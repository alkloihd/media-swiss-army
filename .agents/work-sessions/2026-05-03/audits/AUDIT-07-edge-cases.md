# AUDIT-07 — Edge Cases & Boundary Conditions (iOS)

**Auditor**: subagent / opus
**Date**: 2026-05-03
**Scope**: `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/`
**Mode**: READ-ONLY (no builds, no MCP)

Reviewed all 54 Swift sources with focus on the 20 enumerated edge-case axes. Findings are ordered by severity. Each finding lists the file:line, the boundary that breaks, the user-visible consequence, and a fix sketch. Severity rubric:

- **CRITICAL** — data loss, crash, or wrong-result that ships silently
- **HIGH** — observable user-visible failure, no graceful recovery
- **MEDIUM** — degraded UX or inconsistency, but app stays functional
- **LOW** — cosmetic or edge polish

---

## CRITICAL

### C1 — Mid-export cancel on Stitch passthrough leaks the in-flight output file
**File**: `Services/StitchExporter.swift:925-955` (`runPassthrough`)
**Boundary**: User taps **Cancel Export** during a passthrough stitch.
**What happens**: `withTaskCancellationHandler.onCancel` calls `exporter.cancelExport()`. AVFoundation flips the session status to `.cancelled` and the continuation resumes. The function then enters the switch and falls into `case .cancelled: throw CompressionError.cancelled`. **The partial `outputURL` file written to `StitchOutputs/` is never deleted.**

Compare to the re-encode path (`CompressionService.encode` line 454-457) which explicitly does `try? FileManager.default.removeItem(at: outputURL)` on cancel and on writer-failure. The passthrough branch is missing both cleanup paths (cancelled and `.failed`).

**User impact**: Repeated cancels accumulate orphan `_STITCH.mp4` files in the user's Documents/StitchOutputs that never get reclaimed except by the 7-day CacheSweeper sweep at next launch. On a 4K passthrough stitch a single orphan can be hundreds of MB.

**Fix**: In the `case .cancelled` and `case .failed` arms, `try? FileManager.default.removeItem(at: outputURL)` before throwing. The bakedStillURLs are already cleaned up by `runExport`'s `defer`.

---

### C2 — Stitch export cancel mid-bake leaks already-baked stills if user cancels in the still phase
**File**: `Services/StitchExporter.swift:84-124` (`buildPlan` still bake loop) + `Models/StitchProject.swift:484-490` (`runExport` defer cleanup)
**Boundary**: User has 5 stills, cancels after 2 are baked.
**What happens**: `buildPlan` throws `CancellationError` from `try Task.checkCancellation()` on iteration 3. The two URLs that ARE in `bakedStillURLs` are local to `buildPlan` and **never returned** — `runExport`'s `defer` (line 487) cleans up only the URLs that came back inside the `Plan`. Since the throw happens before `return Plan(...)`, the outer `defer` never sees those two temp `.mov` files.

**User impact**: Each cancelled multi-still stitch leaks N temp `.mov` files into `NSTemporaryDirectory/StillBakes/`. iOS does NOT reliably reap that dir (the comment at line 484 acknowledges this). On a flaky network/Photos environment where stills take a while to bake, this is repeatable.

**Fix**: Catch the cancellation inside the bake loop, clean up `bakedStillURLs` before re-throwing. Or move the bake-tracking array onto an `actor`/class so the defer can reach it on the throw path.

---

### C3 — Empty audio mix when a clip has no audio track silently drops audio for the next clip too
**File**: `Services/StitchExporter.swift:343-434` (`buildAudioMix`) + `:247-251` (`audioT.insertTimeRange`)
**Boundary**: Stitch project has `[clipA(no audio), clipB(audio), clipC(audio)]` with transitions enabled.
**What happens**: At line 248-250, `if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first` returns nil for clipA, so nothing is inserted. But the alternating-track pattern still allocates clipA to trackA and clipB to trackB. clipC alternates back to trackA. Now `buildAudioMix` indexes `audioTracks[i % 2]` (line 359) — for i=0 (clipA) it tries to set volume on trackA which has NO clipA samples, so the `setVolumeRamp(...timeRange: overlap)` at line 392-396 maps to silence. clipB's fade-in (i=1) writes to trackB and is OK. clipC's fade-in (i=2) is `i%2 == 0` so writes to trackA — this is the SAME track that was supposed to carry clipA, so the head-fade ramps from 0→1 starting at clipC's composedRange.start. But trackA's first `insertTimeRange` was clipB's (because clipA had no audio and was skipped). The track now has clipB's audio with a volume ramp meant for clipC starting at clipC's time. **Result**: clipC's audio fade-in actually fades a different clip's audio that happens to overlap that wall-clock time.

**User impact**: When mixing silent + audible clips with transitions, the audio in the stitched output has wrong-clip volume envelopes — sometimes the wrong clip fades in, sometimes a clip plays full-volume during what should be a fade. Subtle but unmistakable on careful listening.

**Fix**: Track which composition audio track each clip's audio actually went into (via the `audioT` reference at line 229) and key the audio mix params off THAT mapping, not the parity of the segment index. Mirror the video segments' explicit `videoTrack` field — add an `audioTrack` field next to it.

---

### C4 — Identical-file ref-counted delete in `StitchProject.remove(at:)` ONLY checks paths in the surviving array — split halves remain safe but DUPLICATES from drag reimport break
**File**: `Models/StitchProject.swift:99-104` (ref-count check) + `Views/StitchTab/StitchTabView.swift:383-406` (`stageToStitchInputs`)
**Boundary**: User imports `clipA.mov`, then re-imports the same Photos asset → stages to a UUID-suffixed copy `clipA-abc123.mov` (line 394-396). Now drag-duplicates clipA via context menu (`StitchTimelineView.swift:210-229`) — the duplicate shares the ORIGINAL `clipA.mov` URL. User deletes the duplicate.
**What happens**: `remove(at:)` runs the path-equality ref count and sees the original is still referenced → does NOT delete. ✅
But: user deletes the ORIGINAL while the DUPLICATE is still in the timeline. The duplicate is in `clips`, scan finds it referenced, does NOT delete. ✅
**However**: When the duplicate is later removed and is the LAST reference, the file IS deleted — but the in-memory `StitchClip` for the duplicate also pointed to that URL so all is fine.

The actual bug is subtler: `Views/StitchTab/StitchTabView.swift:394-396` only collision-suffixes if the destination ALREADY EXISTS on disk. If the user imports `clipA`, exports/uses it, then deletes it (file gone from disk), then imports `clipA` again from Photos — the suffix is NOT applied (no collision), so the new staged URL is `clipA.mov`. If any old `StitchClip` reference to `clipA.mov` survives in another @State or memoized cache (e.g. an undo-history reference inside `EditHistory`), it is now silently aliased to a DIFFERENT file's content.

**User impact**: rare but present — undo/redo into a previously-deleted-then-reimported clip plays the wrong source.

**Fix**: Always suffix import paths with a random short tag, regardless of collision. This makes the URL identity match the import identity even after delete-and-reimport.

---

## HIGH

### H1 — Empty-clip stitch export attempt is guarded but the empty-bake-only stitch crashes via `firstNominalFrameRate` default
**File**: `Services/StitchExporter.swift:78-80` + `:281-298`
**Boundary**: 0 clips → `buildPlan` correctly throws "Stitch export requires at least one clip." ✅
But: 1 clip that is a still-only project. `firstNominalFrameRate` stays nil (no video tracks loaded), so line 284's `firstNominalFrameRate.map { max($0, 1) } ?? 30` returns 30, OK. ✅

The actual H1 case is `canExport == clips.count >= 2` (`Models/StitchProject.swift:56`) which gates the EXPORT button — but the **draggable timeline** lets you populate clips one at a time and the editor functions on a single clip. If the user navigates away mid-import and only one clip lands, the export button stays disabled (correct), but the **aspectMode auto-vote** on a single clip works fine (lands on that clip's orientation).

**However**: `StitchProject.export()` at line 425 has NO guard on `canExport`. If a programmatic path (or future Share Extension) calls export with 0 clips, `buildPlan` throws but the `exportState` transitions to `.building` first (line 427) before the throw flips it to `.failed`. Brief flash of "Building composition…" UI for an empty project.

**User impact**: cosmetic on the current UI; latent bug for any future caller that reaches export programmatically.

**Fix**: Add `guard canExport else { exportState = .failed(error: ...); return }` at the top of `export(settings:)`.

---

### H2 — Single-clip stitch + transition selected → `needsAB == false` correctly bypasses the dual-track path, but the user can SET transition on a 1-clip project and it has no effect with no UI feedback
**File**: `Models/StitchProject.swift:30` (`@Published var transition`) + `Services/StitchExporter.swift:141` (`needsAB = transition != .none && clips.count >= 2`)
**Boundary**: User adds 1 clip, picks "Crossfade" transition, then `canExport == false` so they can't export — but if they later add a 2nd clip the transition silently kicks in.
**What happens**: nothing breaks (correct fallback), but the transition picker offers selections that are no-ops for 1-clip projects. No tooltip / disabled state explains this.

**User impact**: minor confusion during onboarding ("why doesn't my Crossfade do anything?").

**Fix**: Disable the transition picker (or grey out non-`.none` rows) when `clips.count < 2`. Cosmetic but worth a session.

---

### H3 — Very-short clip + 1.0 s transition (transition longer than clip) silently produces broken output
**File**: `Services/StitchExporter.swift:227-258` + `:155-156` (`transitionDuration = 1.0s`) + `Models/StitchClip.swift:63` (`durationSeconds = 1.0`)
**Boundary**: User imports a 0.3 s clip + a 5 s clip + Crossfade. Transition wants 1.0 s overlap.
**What happens**: At line 237, `insertAt = CMTimeMaximum(.zero, CMTimeSubtract(cursor, transitionDuration))`. For clip 2, `cursor` is 0.3 s (clip 1's duration). `0.3 - 1.0 = -0.7`, clamped to 0. **clip 2 inserts at composition time 0**, fully overlapping clip 1, and the visible result is a 1.0 s window where opacity ramps but only 0.3 s of clip 1 ever exists. The remaining 0.7 s of "fade-out" is fading from a paused last-frame on a track with no samples.

The same math at the audio-mix layer (line 369-398) computes `overlap = [0..0.3]`, which is the sane value, but the video-instruction layer at `:644-678` computes `gapRange = [n.composedRange.start..seg.composedRange.end]`. With `n.composedRange.start = 0` and `seg.composedRange.end = 0.3`, the gap is 0.3 s but `setOpacityRamp` was given `gapRange.duration = 0.3` while `transitionDuration` was 1.0 s. The crossfade visually completes in 0.3 s instead of 1.0 s — not a crash, but the transition feels "snipped". Worse: if there's a 3rd clip after the 0.3 s, ITS overlap calculation also reads `cursor` which has been advanced by `cursor = CMTimeAdd(insertAt, timeRange.duration)` = `0 + 0.3 = 0.3`. So clip 3 inserts at `max(0, 0.3 - 1.0) = 0` again, fully overlapping clips 1 AND 2. Compounding chaos.

**User impact**: short B-roll inserted between two longer clips becomes unwatchable: visible content out of order, transitions snap, audio crossfades clamp to 0.

**Fix**: Either reject sub-`transitionDuration` clips with a UI warning before export, or scale the per-gap transitionDuration to `min(prevClipDuration, nextClipDuration, 1.0) / 2`. The latter is what professional editors do.

---

### H4 — Repeated rapid splits can produce sub-`minSliverSeconds` clips through the second-split path of `removeRange`
**File**: `Models/StitchProject.swift:343-379` (`removeRange`) + `:286-289` (split guard)
**Boundary**: User calls `removeRange(clipID, fromSeconds: 0.05, toSeconds: 0.06)` — the gap is 0.01 s.
**What happens**: First `split(at: 0.05)` succeeds if `0.05 > currentStart + 0.1` is FALSE (assuming clip starts at 0). So `0.05 > 0 + 0.1` = FALSE → split returns false → `removeRange` returns false. ✅
But: `removeRange(clipID, fromSeconds: 0.5, toSeconds: 0.55)` on a 5 s clip:
1. Split at 0.5 — `0.5 > 0+0.1 && 0.5 < 5-0.1` = TRUE. Split happens. Now clip has trim [0..0.5] and [0.5..5]
2. Find second half, split at 0.55 — second half's `currentStart=0.5`, `currentEnd=5`. `0.55 > 0.5+0.1 = 0.6`? FALSE. Second split returns false.
3. `restoreFromPartialSplit` runs (line 367) and re-merges. ✅

Still safe. **However**: rapid 10x split presses on the same clip in 1 second (item 15 in the audit list). Each split is `@MainActor`-isolated, so they serialize. But they all share `playheadSeconds` which is updated on a 30 Hz time observer. If the user holds the split button, each tap reads the CURRENT `playheadSeconds`. But after a split, line 377-378 updates `playheadSeconds = currentEnd` (which is now the FIRST half's end). The next tap re-evaluates `canSplitAtPlayhead = playheadSeconds > currentStart + 0.1 && < currentEnd - 0.1`. If the playhead is exactly AT `currentEnd`, `canSplitAtPlayhead` is FALSE because `playheadSeconds < currentEnd - 0.1` is FALSE. So the button disables itself. ✅

The real issue is that **history is wiped on split** (line 331-332 — both halves get fresh empty `EditHistory()`). So a user who taps Split, realizes it was wrong, and presses Undo — **nothing happens**. The split has destroyed undo for that clip. This is documented at line 328-330 ("Future enhancement: project-level structural undo") but the user has no warning.

**User impact**: lost work on accidental split. Common given the Split button is prominent in the inline editor.

**Fix**: Snapshot pre-split state to a project-level structural undo stack, OR (cheaper) commit pre-split state to the first-half's history so per-clip undo can recover.

---

### H5 — `iCloud Photos` originals-not-on-device case never triggers a download
**File**: `Services/VideoLibrary.swift:84-95` (video import) + `Views/StitchTab/StitchTabView.swift:253-258` (stitch import)
**Boundary**: User has iCloud Photos with "Optimize iPhone Storage" — the picked HEIC/MOV is a placeholder, real bytes live in iCloud.
**What happens**: `PhotosPickerItem.loadTransferable(type: VideoTransferable.self)` is supposed to handle this — under the hood it calls `requestContentEditingInput` which downloads on demand. **But**: if the network is offline, or the item has been evicted past iCloud's download window, `loadTransferable` fails with a transient error. The catch arms at lines 96-98 (and stitch's 259) silently `// fall through` without surfacing the cause — the user just sees nothing happen.

For stills the fall-through becomes a `nil` photo, then `continue` (line 275) and the import is skipped silently.

**User impact**: User imports 5 clips from Photos in a low-connectivity scenario; only 2 land. No alert, no progress indication. Looks like the picker forgot.

**Fix**: Surface the error — don't swallow with `// fall through`. At minimum, set `lastImportError` on the second-attempt failure too (currently only the still-attempt failure is reported in stitch's `:268-273`). Consider showing per-item progress for slow downloads.

---

### H6 — Mid-export device interruption (phone call, Siri) interrupts the AVAssetReader cycle silently with no retry path
**File**: `Services/CompressionService.swift:469-477` (writer error -11847 handling) + `Services/StitchExporter.swift:946-950` (passthrough -11847)
**Boundary**: User starts a 5-min compress, gets a phone call halfway through.
**What happens**: AVFoundation surfaces NSError code -11847 (`AVErrorOperationInterrupted`). The error message ("Export was interrupted because the app went to the background…") is correct. But: the temp output file at `outputURL` is removed (line 470, 951), and `videos[i].jobState = .failed`. **No "Retry" button surfaces**. The user has to find the row, swipe, re-add, and start again — or use the per-row UI which has no obvious retry affordance.

**User impact**: 5-min job → phone call → user has to do everything from scratch. Particularly painful for batch compresses.

**Fix**: Add a retry button on `.failed` rows in `VideoRowView` that re-runs `compress(id)`. The source URL is still on disk (Inputs/) so retry is essentially free.

---

### H7 — Disk full mid-export produces an opaque error, with the orphan partial output left behind in cancel/error paths in some code paths
**File**: `Services/CompressionService.swift:454-466` + `Services/MetadataService.swift:285-296` + `Services/PhotoCompressionService.swift:148-154`
**Boundary**: Encoding 4K HDR 60 fps 30-min clip on a device with only 2 GB free.
**What happens**: AVAssetWriter fails late in the encode with NSError 28 (`ENOSPC`). The catch path at `CompressionService:469-479` removes the partial output but the message ("Encode failed: [NSCocoaErrorDomain 28] No space left on device") is technical. No suggestion to free space. No proactive estimate-vs-free check at the start.

`CompressionEstimator` exists (referenced from `Services/CompressionEstimator.swift`) — its output is in `compress`'s pre-flight estimate (line 490-508 of CompressionService) but **the estimate is never compared against `volumeAvailableCapacityForImportantUsage`**. iOS exposes that key via `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`.

**User impact**: cryptic failure mode. The user doesn't know to clear space.

**Fix**: At the start of `runJob` (or in `CompressionService.encode`), read free space, compare against estimate × 1.2, and if insufficient surface a friendly error before kicking off the encode. Save an hour of encode time on a guaranteed-to-fail run.

---

## MEDIUM

### M1 — `Photos library asset deleted between import and use` — sourceURL stale → playback shows black, export throws generic
**File**: `Services/VideoLibrary.swift:118-139` (`copyToWorkingDir`) — does a MOVE, not a COPY
**Boundary**: User imports clipA from Photos. Some other app or a sync deletes the Photos asset. User then opens VideoCompressor, taps Compress.
**What happens**: `copyToWorkingDir` already MOVEs the picker's temp file into `Inputs/` at import time, so the working copy is independent of the Photos asset. ✅ Compress works fine.

The PHAsset-deleted case is only a problem in the **MetaClean replace-original flow**: `Services/PhotosSaver.swift:111-112` does `PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)`, then `guard assets.count > 0 else { return }`. Silent no-op if the original was deleted between import and replace. The user expected the original gone; the cleaned copy is in Photos. Net effect: their Photos library has BOTH the (now-deleted) original AND the cleaned copy. Not catastrophic.

**However**: limited Photos auth (item 9) means `itemIdentifier` returns nil at picker time, so `originalAssetID` is nil, so `saveAndOptionallyDeleteOriginal` skips the delete (line 110). The Replace toggle becomes a "Save and keep original" silently. No UI feedback that the toggle is inert.

**User impact**: privacy-conscious users in limited-Photos mode believe their original was deleted when it wasn't.

**Fix**: When `originalAssetID == nil` for an item, surface a per-row warning ("Original retained — re-import with full Photos access to enable replace").

---

### M2 — App relaunch with in-flight export — no resume / recovery, partial files orphaned only by 7-day sweep
**File**: `Services/CacheSweeper.swift` (referenced) + `VideoCompressorApp.swift:14-18`
**Boundary**: Encode 30-min 4K. App killed by iOS jetsam mid-encode (out of memory).
**What happens**: Next launch, `CacheSweeper.shared.sweepOnLaunch(daysOld: 7)` runs. The orphan file in `Outputs/` is YOUNG (just made) so it survives the sweep. Source is still in `Inputs/`. **No state about pending jobs survives the relaunch** — the @StateObject `VideoLibrary` is recreated empty, so the user re-adds files via picker. Their old import sits in `Inputs/` as an orphan for ≤7 days.

**User impact**: cluttered Files.app folder for power users. Loss of work on long-running batches if app is jetsamed.

**Fix**: Persist `videos` array (as JSON of metadata + URLs) on `applicationWillResignActive`, restore on `init`. Mark in-flight jobs as `.failed` with a "Resume?" button. SwiftData would do this naturally; current code is in-memory only.

---

### M3 — Mixed-orientation aspect-mode `.auto` ties — landscape wins
**File**: `Services/StitchExporter.swift:854-881` (`computeRenderSize`)
**Boundary**: 2 portrait + 2 landscape clips, no explicit aspect mode chosen.
**What happens**: `if landscape >= portrait` (line 871) → landscape wins. Documented behaviour (line 870 comment "Landscape wins ties"). With 50/50 split, half the user's content gets pillarboxed.

**User impact**: surprising for users who shoot more portrait (most Gen Z + iPhone defaults). The comment acknowledges "most common phone-shot videos" but iPhone Photos is more often portrait now.

**Fix**: Either bias to portrait on ties, or — better — surface a UI hint when `.auto` ends in a tie ("4 clips: 2 landscape, 2 portrait — choosing 16:9. Pick 9:16 to flip.").

---

### M4 — Dark mode + light mode — `Color.white` and `Color.black` are used as literals in StitchTab views
**File**: `Views/StitchTab/StitchTimelineView.swift:272`, `:91` + `Views/StitchTab/RotateEditorView.swift:38` + `Views/StitchTab/TrimEditorView.swift:233`
**Boundary**: Dark mode rendering.
**What happens**: `Color.black` as a video preview backdrop is fine (videos look right on black in either mode). `Color.white` in `RotateEditorView.swift:38` (used for selected-state text) and in `TrimEditorView.swift:233` (slider thumb fill) is hardcoded — these stay white in both modes. White slider thumbs against light backgrounds in light mode are low-contrast.

`UIColor.black.cgColor` at `StitchExporter.swift:575,691` is the videoComposition background — that's the rendered output's letterbox color, correctly black regardless of UI mode.

**User impact**: low-contrast edits in light mode for the trim slider thumb and rotate-editor selected-state text.

**Fix**: Use `Color.primary` / `.secondary` / `.background` semantic colors instead.

---

### M5 — Concurrent user actions: drag a clip while export running — state churn risk
**File**: `Models/StitchProject.swift:425-437` (`export` snapshots `clips`) + `:108-110` (`move`)
**Boundary**: User taps Export, sheet appears, exporter runs `buildPlan`. While that's loading asset tracks, user drags-reorders clips in the timeline (the sheet is over-presented but the timeline is still visible behind it — actually `interactiveDismissDisabled(project.isExporting)` is set on line 45 of StitchExportSheet, so the sheet is modal and locks out timeline manipulation… mostly).

But the timeline is RENDERED behind the sheet. iOS sheets at default detent show the timeline at the top. **Drag-to-reorder still works on a non-modally-overlapped view if the touch target is exposed** — `presentationDetents([.medium])` could still leak touches.

**What happens**: Export already snapshotted `clips` at line 428 (`let snapshot = clips`). The export uses the snapshot. The user's reorder mutates `clips`. ✅ Export is data-isolated.

**However**: the `bakedStillURLs` returned from buildPlan are tied to the snapshot's clip IDs at the time the bake ran. If the user removed a still mid-bake (via a path that bypasses the modal — e.g. swipe-to-delete from a different view), the bake's `try Task.checkCancellation()` doesn't fire because the export Task is unaware. The bake completes and writes a temp .mov. Then the export finishes and the defer cleans it up. ✅

**Fix**: This is mostly safe due to the snapshot. Consider adding `interactiveDismissDisabled` to the timeline ScrollView when `project.isExporting` to be belt-and-suspenders.

---

### M6 — HEIC with multiple representations (Live Photo, burst) — only one gets imported
**File**: `Services/VideoLibrary.swift:99-115` + `Models/PhotoMedia.swift` (referenced)
**Boundary**: User picks a Live Photo from Photos.
**What happens**: `PhotoTransferable` has `transferRepresentation` for `.image` (line 533 of VideoLibrary). Live Photos consist of an HEIC still + a paired MOV. The picker's transfer to `.image` returns ONLY the HEIC. The user expected the motion component too. No warning that the Live Photo's motion is dropped.

Similar for burst — only the "selected" frame is delivered.

**User impact**: cleaning a Live Photo's metadata only sanitizes the still; the paired MOV remains untouched in the user's library with its original metadata.

**Fix**: Detect Live Photos via `PhotosPickerFilter.livePhotos` or `PHAsset.mediaSubtypes`. Add a flow that imports both halves OR a UI warning "Live Photo: motion clip will not be cleaned."

---

### M7 — iPad split view & multi-window — no obvious breakage but `@StateObject private var queue = MetaCleanQueue()` is per-scene
**File**: `VideoCompressorApp.swift:9-26` + per-tab `@StateObject` declarations
**Boundary**: User opens two windows of the app on iPad.
**What happens**: `library` is a `@StateObject` on the App. Each WindowGroup scene gets its OWN instance (default WindowGroup behavior is per-scene), so two windows = two separate VideoLibraries. Imports in one window don't appear in the other. Same for `StitchProject` and `MetaCleanQueue` — they're per-tab `@StateObject` instances and don't cross windows.

**User impact**: confusing on iPad — drag-and-drop between two windows of the SAME app is a natural multitasking pattern, but each window operates on its own state.

**Fix**: Move libraries to a singleton or scene-bridging mechanism (tricky given @StateObject lifecycle). Lower priority — most users won't multi-window this app.

---

## LOW

### L1 — Empty timeline export: `aspectMode .auto` with no clips returns hardcoded 1920×1080 fallback
**File**: `Services/StitchExporter.swift:268-271`
**Boundary**: 0 clips reaches `computeRenderSize`. (Should be unreachable due to guard at line 78, but noted for defense.)
**What happens**: `maxNaturalSize == .zero` → fallback 1920×1080. Combined with empty clip list, render canvas is set but no instructions emit. The earlier guard prevents this from running.

**Fix**: nothing required — guard is sufficient.

---

### L2 — `Haptics` calls during export progress can chatter on slow devices
**File**: `Models/StitchProject.swift:497-499` (encoding state update)
**Boundary**: 4K HEVC encode at 0.5x realtime on iPhone 12.
**What happens**: progress poller fires at 10 Hz. `exportState = .encoding(progress)` republishes; the SwiftUI re-render churn is noted but no haptic is fired here.

**Fix**: nothing required — progress is throttled by the 10 Hz poller already.

---

### L3 — `StitchTimelineView` zoom doesn't persist
**File**: `Views/StitchTab/StitchTimelineView.swift:55-58`
**Boundary**: User pinches to a comfortable zoom, switches tabs, comes back.
**What happens**: `@State private var zoom = 1.0` resets to default on view recreation. Documented as intentional (line 56 comment).

**Fix**: low priority. If users complain, add `@AppStorage("stitchTimelineZoom")`.

---

## Counts

- **CRITICAL**: 4 (C1, C2, C3, C4)
- **HIGH**: 7 (H1, H2, H3, H4, H5, H6, H7)
- **MEDIUM**: 7 (M1, M2, M3, M4, M5, M6, M7)
- **LOW**: 3 (L1, L2, L3)
- **Total**: 21 findings

## Top-3 fix priority for ship-readiness

1. **C1** (passthrough cancel/fail leaks output file) — one-line fix, prevents disk waste.
2. **H6** (no retry on AVErrorOperationInterrupted) — single button addition, recovers from common phone-call interruption.
3. **H3** (transition longer than clip) — needs UI rejection or transition-duration scaling. User-facing breakage that the test suite won't catch.

## Methodology

- Read `StitchExporter.swift` (957 lines), `StitchProject.swift` (553 lines), `CompressionService.swift` (680 lines), `VideoLibrary.swift` (548 lines), `MetaCleanQueue.swift` (278 lines), `MetadataService.swift` (587 lines), `PhotosSaver.swift` (126 lines), `StillVideoBaker.swift` (288 lines) end-to-end.
- Spot-checked `StitchTabView.swift`, `MetaCleanTabView.swift`, `ClipEditorInlinePanel.swift`, `StitchTimelineView.swift`, `StitchExportSheet.swift`, `VideoListView.swift`, `PhotoCompressionService.swift`, `CompressionSettings.swift`.
- Searched for: cancel coverage (`Task.isCancelled` / `checkCancellation`), iCloud / Photos network handling (`PHCachingImageManager`, `requestContentEditingInput`), color literals, disk-space checks (`volumeAvailableCapacityForImportantUsage`).
- Did NOT run builds or simulators (read-only mandate).
