# Red Team — Stills-in-Stitch Hotfix

Reviewer: solo/opus, 2026-05-03
Branch reviewed: `fix/stills-in-stitch-thumbnails-and-discoverability` @ `2bdc5e8`
Files reviewed: StillVideoBaker.swift, StitchExporter.swift, ClipBlockView.swift, ClipEditorInlinePanel.swift, StitchTabView.swift (picker line) plus call-site grep over `kind == .still` and Meta-fingerprint registry.

---

## CRITICAL (must fix before ship)

| # | File | Line | Issue | Suggested fix |
|---|------|------|-------|---------------|
| C1 | StillVideoBaker.swift | 118-167 | **Buffer-unlock race.** `CVPixelBufferLockBaseAddress` is paired with `defer { …Unlock… }` at function-scope (line 119). The pump block at line 150 runs on `DispatchQueue` AFTER the function body completes (`requestMediaDataWhenReady` schedules the closure asynchronously). But the function does NOT return until `withCheckedContinuation` resumes (line 149-167), so the defer fires AFTER the pump finishes — actually safe. **However**: the pump appends `buffer` from inside a background queue while holding nothing keeping the lock semantically valid for IOSurface-backed buffers if the encoder reads later. AVAssetWriterInputPixelBufferAdaptor expects buffers *unlocked* before `append` (locking is for CPU writes only). Drawing finishes on line 140; the lock should be released BEFORE the pump starts appending or before the first `append`. As written, the lock is held across all appends, then released after `finishWriting`. Encoder may copy from a locked surface, but Apple sample code unlocks before append. | Move the unlock to right after `context.draw(...)` on line 140 — drop the `defer`, call `CVPixelBufferUnlockBaseAddress(buffer, [])` explicitly there. The buffer is now read-only from the adaptor's POV. |
| C2 | StillVideoBaker.swift | 149-167 | **Continuation can resume twice.** The pump block contains two early-return paths (`frame >= totalFrames` line 153-156 and append-failure line 159-162). Both `markAsFinished` + `resume` + `return`. But `requestMediaDataWhenReady` re-invokes the closure WHEN THE INPUT WANTS MORE DATA. After `markAsFinished()` the closure should not be invoked again, but if it IS (race between markAsFinished landing and the queue draining), the `while inputRef.isReadyForMoreMediaData` loop runs again → `frame=0` (it's a local `var` reset each closure invocation!) → resumes continuation a second time → **fatal: continuation resumed twice → crash**. | Two fixes: (a) hoist `frame` out of the closure into an `@State`-style box (e.g. capture an `actor` counter or use `var frameRef = 0` outside the closure, captured by reference), AND (b) guard resumption with a `var done = false; if done { return }; done = true` flag inside the closure. |
| C3 | StitchExporter.swift | 80-112 | **No bake cleanup → temp dir grows unboundedly.** Baker writes to `NSTemporaryDirectory()/StillBakes/UUID.mov`. The header comment on line 78-79 claims "iOS reaps them periodically" — **false reassurance**. iOS only reaps NSTemporaryDirectory under memory pressure or rarely on launch; users can accumulate hundreds of MB of orphaned bakes across export sessions. CacheSweeper does not touch this dir. | Add a `defer` block in `buildPlan` (or pass back baked URLs in `Plan` and clean in `runExport`/finalizer): track baked URLs in an array, remove them after `export()` completes (or fails). Alternatively, sweep `StillBakes/` on app launch in CacheSweeper. |

---

## HIGH

| # | File | Line | Issue | Suggested fix |
|---|------|------|-------|---------------|
| H1 | StillVideoBaker.swift | 159-162 | **Append-failure swallows the actual error.** When `adaptor.append` returns false, the pump just markAsFinished + resume — the function then proceeds to `await writer.finishWriting()` and only throws if `writer.status != .completed`. The append failure root cause (often `writer.error` set to a transient I/O issue) is lost; user sees "writer status 3" with no actionable info. | Capture `adaptor.assetWriterInput?.error` or `writer.error` at the failure point, surface via a new `BakeError.appendFailed(String)` and throw it from after the continuation. |
| H2 | StitchExporter.swift | 82-111 | **No progress reporting during bake.** For 5 stills × 3s, bake is ~1-3s wall clock, all happening BEFORE the export progress bar starts moving. User sees a frozen UI. The bake loop also runs sequentially even though stills are independent. | At minimum, surface a "Preparing stills…" message via the `onProgress` channel (BoundedProgress with a tag). Better: bake in parallel with `withThrowingTaskGroup`. |
| H3 | StitchExporter.swift | 82-111 | **No `Task.checkCancellation()` in bake loop.** The clip-insertion loop at line 168 has it; the bake loop doesn't. If the user taps Cancel during a 10-still bake, the bakes complete pointlessly and the user waits. | Add `try Task.checkCancellation()` at the top of the `for clip in clips` bake loop. |
| H4 | StillVideoBaker.swift | 81-83 | **`AVVideoMaxKeyFrameIntervalKey: frameRate`** — frameRate is `Int32(30)` which is correct as keyframe interval (1 IDR/sec). But the comment "I-frame each second" is right for 30fps; if `frameRate` were ever changed, the comment lies. Cosmetic but mismatch is a real foot-gun. | Use `AVVideoMaxKeyFrameIntervalDurationKey: 1.0` instead — it's seconds-based and self-documenting. |
| H5 | StillVideoBaker.swift | 65-66, 75-92 | **Odd-dimension still input** (e.g. an iPhone screenshot at 1170×2532) → after thumbnail resize at maxEdge=1920, the smaller axis can be odd. H.264 encoders reject odd dimensions and `writer.startWriting()` returns false with a cryptic error. | After computing `width`/`height` (line 64-65), round each to the nearest even value: `let width = (cgImage.width / 2) * 2`. |
| H6 | ClipEditorInlinePanel.swift | 78-103 | **Stills still instantiate AVPlayer + time observer.** The `init` (line 48-57) always creates an AVPlayer from `clip.sourceURL`, even for stills. `onAppearWithClip()` then calls `attachTimeObserver()` which sets a 30Hz callback on a player that's never rendered. Result: ~30 main-thread callbacks/sec for a still clip, plus the observer leaks if the panel never disappears (tab swap doesn't fire `.onDisappear` reliably on iPad split). | Wrap `attachTimeObserver()`/`seekTo()` in `if clip?.kind != .still` guards. Better, only create the AVPlayer for non-stills (use `AVPlayer()` placeholder for stills). |

---

## MEDIUM

| # | File | Line | Issue | Suggested fix |
|---|------|------|-------|---------------|
| M1 | StitchExporter.swift | 95-106 | **Pre-bake/post-bake clip swap preserves `id` but loses metadata.** The new `StitchClip` constructor (line 97-106) sets `naturalSize: clip.naturalSize` (the still's image size, often a different aspect than `displaySize` of the baked .mov), `preferredTransform: .identity`, and trim becomes `[0, clamped]`. But user may have set `cropNormalized` or `rotationDegrees` on the still in the inline editor — those edits ARE preserved (`bakedEdits = clip.edits`), but they were authored against the still's pre-bake displaySize. After bake the displaySize changes (now matches naturalSize because preferredTransform is identity). Crop rectangle in normalized coords still maps correctly, but rotation behavior may differ subtly. | Verify with a manual test: rotate a still 90°, set a crop, then export. If output looks wrong, force-clear `cropNormalized` and `rotationDegrees` during bake-swap and surface a console warning. For now, ship as-is and note as a known issue. |
| M2 | ClipEditorInlinePanel.swift | 130-150 | **Slider undo snapshot is stale.** `startSnapshotForUndo` is captured inside the closure body at line 135-137: `if startSnapshotForUndo == nil { startSnapshotForUndo = clip.edits }`. But `clip` here is the `let duration = clip.edits.stillDuration ?? 3.0` parameter from the enclosing function — captured at the slider construction time. By the time the slider's setter fires (on first drag), `project.clips` may have changed (e.g. a parallel append). Then `clip.edits` is stale. Low likelihood in practice but a real correctness gap. | Replace `clip.edits` with `self.clip?.edits ?? .identity` (uses the computed property, fresh lookup). |
| M3 | StitchTabView.swift | 39, 81 | **Picker `.any(of: [.videos, .images])`** — re-enables Live Photos as well. Live Photo selection returns the still component but a Live Photo's NSItemProvider may surface as either UTType.image or UTType.heif. If the user picks a Live Photo, only the still is imported (movie component dropped silently). Acceptable for v1 but worth a banner. | Acceptable risk for ship; document in HANDOFF that Live Photo motion is dropped. |
| M4 | StillVideoBaker.swift | 144 | **`max(1, Int(duration * 30))` — duration of 0.05s yields 1 frame** which the writer accepts but produces a sub-1s movie that AVMutableComposition may reject during `insertTimeRange`. The clamp upstream (line 86) clamps to [1, 10] so this is currently unreachable, but if anyone later loosens the clamp without updating here, we crash. | Add `guard duration >= 0.5 else { throw BakeError.invalidDuration }` at top, OR document the [1,10] contract on the bake() docstring. |
| M5 | MetadataService.swift / PhotoMetadataService.swift | 467-472 / 322-330 | **Meta fingerprint registry is still a string-literal blocklist** (`ray-ban`, `rayban`, `meta`, `xmp.metaai`, `c2pa`, `manifeststore`). Confirms task brief (F): NOT in this PR — still pending P8 from PUBLISHING-AND-MONETIZATION. **Not a hotfix concern**, but flagging per ask. | Out of scope for this PR. Track in P8 backlog item. |

---

## LOW

| # | File | Line | Issue | Suggested fix |
|---|------|------|-------|---------------|
| L1 | ClipEditorSheet.swift | 40 | **`print("[ClipEditorSheet] clip \(clipID) not found — dismissing")`** — debug print ships in release. | Remove or wrap in `#if DEBUG`. |
| L2 | MetaCleanTabView.swift | 201 | **"Cleaning \(current) of \(total)"** — engineering-flavored copy noted in task brief (G). It reads acceptable; not "dev-y" enough to block ship. | Optional polish: "Cleaning photo 3 of 8". |
| L3 | MetaCleanQueue.swift | 32, 150-194 | **`BatchCleanProgress` exposed to UI** — type name only appears in code, not user-visible. | No fix needed. |
| L4 | StillVideoBaker.swift | 119 | **Unused** `defer` if C1 fix lands — remove. | Tracked under C1. |
| L5 | StillVideoBaker.swift | 24 | **`actor StillVideoBaker`** with no instance state means the actor isolation buys nothing — could be a `struct` or a free function. | Cosmetic; leave for later. |
| L6 | ClipBlockView.swift | 99-115 | **`Task.detached` not stored** — fires and forgets. If the view is dismissed mid-decode, the work continues. Not a leak (returns to no one), but wastes CPU. | Acceptable for thumbnails. |

---

## OK / non-issues (audited and clean)

- **ClipBlockView.swift `task(id: clip.sourceURL)`** — properly cancels and re-runs on URL change. The `thumbnails` array isn't a stale-state risk because `kind` doesn't change for a clip's lifetime.
- **`StillPreview.task(id: url)`** — correctly cancels on URL change.
- **DispatchQueue label** uses `outURL.lastPathComponent` — UUID-based, unique per bake. No collisions.
- **`writer.finishWriting()` then status check** — proper async completion path; no missing `await`.
- **Pixel buffer pool nil case** (line 110-112) — handled with `BakeError.writerSetupFailed`.
- **buildPlan cancellation between clips** (line 168) — present and correctly placed.
- **Audio mix construction** unaffected by stills — baked .mov has no audio track, audio mix loop guards on `audioTracks.isEmpty`.
- **Picker re-enabled** is consistent across the codebase: VideoLibrary.swift:236, VideoRowView.swift:26, PresetPickerView.swift:24 all already handle `.kind == .still` (these were already in tree from earlier work). No call site assumes "no stills".
- **`makeAspectFitLayer`** uses `clip.displaySize` derived from preferredTransform; baked clips have `.identity` transform so displaySize == naturalSize. Aspect-fit math holds.
- **Cancellation through `withTaskCancellationHandler`** in passthrough path — correct shape.

---

## Recommended ship triage

- **Must-fix before TestFlight**: C1, C2, C3.
- **Strongly recommended**: H1 (better error messages), H3 (cancellation), H6 (still-clip player leak).
- **Defer post-ship**: H2 (progress UI for bake), H4 (cosmetic), H5 (odd-dim guard — only bites on rare aspect ratios), all M-items, all L-items, and F (Meta registry adaptive — separate P8 ticket).

If C2 is hard to verify in 30 min, the safest bet is: change the pump to use a one-shot semaphore-style boolean flag and remove the inner-loop `frame` reset by hoisting it out of the closure. ~5 lines of code.
