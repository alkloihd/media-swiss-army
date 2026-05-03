# Session Handoff v2 — End of 2026-05-03

**From:** Claude Opus 4.7 (1M context) solo lead
**To:** next session at user's Mac
**Branches in play:**
- `main` — TestFlight live; auto-deploys on push
- `feature/phase-3-stitch-ux-and-photos` — phase 3 work, no auto-deploy until merged

---

## Where we are right now

### TestFlight pipeline ✅

GitHub Actions → App Store Connect → TestFlight, fully automated:
- Push to `main` → ~12 min build → TestFlight email
- Builds 9-12 deployed today; Build 12 fixed real bugs from Build 9 testing

| Build | Source | Notable change |
|---|---|---|
| 9 | manual workflow_dispatch | First TestFlight build user installed on phone |
| 10 | PR #2 squash-merge to main | Canonical first auto-deploy |
| 11 | bugfix push to main | Post-flight size guard + UIBackgroundTask |
| 12 | bugfix push to main | Friendlier `-11847` error message |

### Bugs fixed in Build 11 / 12

- **Files getting LARGER on Small preset** (e.g. iPhone HEVC re-encoded to fixed-bitrate H.264 1280x720 ballooning) → post-flight size guard discards output and surfaces `.skipped(reason: "Already optimized — kept original")` if output ≥ 95% of source. Real fix is AVAssetWriter migration (phase 3 commit 1).
- **`-11847 AVErrorOperationInterrupted`** on long videos when app backgrounded → wrapped Compress + Stitch in `UIBackgroundTask` (~30 sec grace from iOS). Friendlier error message tells user to keep app foregrounded.

### Real-world test feedback from user (Build 11/12 on iPhone 17 Pro Max)

User direction (live testing):
1. *"the interface to preview is not good i can't drag and drop the videos from the end like in iMovie and that would be cool to be able to preview the stitch video before rendering"*
2. *"tried to stitch photos and videos still" (failed — photos picker is video-only)*
3. *"why do we have 30 second [bg limit] that should be silly"*
4. *"can we also increase the limit of files to stitch or compress or strip to 50?"*
5. *"add live preview of each clip when we click it to edit and trim so it auto plays from the start after each trim and if trimming the end it auto plays the last 2 seconds of the clip on movement... can we auto compact though after so you work more efficiently"*

All logged in `BACKLOG-stitch-photos-and-share-extension.md` items 5 + 6.

### Already-applied changes on `feature/phase-3-stitch-ux-and-photos` (commit `550eb1a`)

- `maxSelectionCount: 20 → 50` across all 6 PhotosPicker call sites
- Backlog item 6 with full live-preview spec

---

## Phase 3 work plan (in execution order)

Each item is a separate commit on `feature/phase-3-stitch-ux-and-photos`. NO push to main until all green.

### Commit 1 — AVAssetWriter migration with smart bitrate caps (effort: L)

**Why first**: foundational. Makes every subsequent feature better.

- Replace `AVAssetExportSession` curated presets with `AVAssetWriter`-driven encoding
- Per-preset bitrate cap math (mirrors web app's `lib/ffmpeg.js`):
  - Max: source bitrate (no cap)
  - Balanced: `min(target=6 Mbps, source × 0.7)`
  - Small: `min(target=3 Mbps, source × 0.4)`
  - Streaming: `min(target=4 Mbps, source × 0.5)` + faststart metadata
- True smart compression — output is ALWAYS smaller than source unless source is below the floor (in which case skip)
- Removes the "files getting bigger" defect's root cause; the post-flight guard becomes a defense-in-depth backup
- Mirrors the actor + cancellation + 10 Hz progress pattern from CompressionService
- Update `CompressionService` and `StitchExporter` to call this new path
- Run all 22 existing tests + add 3 new tests for smart-cap math

### Commit 2 — Audio Background Mode (opt-in, configurable) (effort: S)

**Why early**: kills the 30-sec ceiling for everything downstream.

- Add Background Modes: Audio capability to pbxproj (Debug + Release configs)
- Add new Settings tab (or add to existing toolbar) with toggle "Allow encoding to continue in background"
- Default OFF (App Store reviewer-friendly default)
- When ON: at start of any encode, configure `AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])` and play a silent looping audio buffer in background. End the session when encode finishes.
- Test on physical device (simulator doesn't enforce background limits)
- User-visible: when enabled and encoding, the iOS Now Playing widget shows "Media Swiss Army" with empty controls. Document.
- Risk note: App Store review may push back on this for non-media apps; we're a media app so should pass, but keep the toggle so it's user-explicit

### Commit 3 — Photos as first-class (HEIC + JPEG) (effort: L)

Per `BACKLOG-stitch-photos-and-share-extension.md` §3.5 — full photo pipeline.

- New `PhotoMedia` model with `PhotoFormat: heic / jpeg / png`
- `PhotoCompressionService` actor using `CGImageSource` + `CGImageDestination`:
  - HEIC re-encode at quality 0.92 (lossless-ish), strip embedded JPEG thumbnails
  - Optional resolution clamp (8MP/5MP/2MP)
  - JPEG → HEIC for ~50% size reduction at perceptual parity
- `PhotoMetadataService` actor for HEIC/JPEG metadata read/strip:
  - Parse EXIF, TIFF, GPS, MakerApple, XMP packets
  - Detect Meta-glasses fingerprints (XMP `meta:` / `RayBan` / `c2pa` markers; MakerApple software string)
  - Strip via `CGImageDestinationAddImageFromSource` with filtered properties dict
- Extend `VideoLibrary` to handle `MediaKind: .video | .still` — branch service calls
- Extend `MetaCleanQueue` and `MetaCleanService` similarly
- Photo support in `StitchProject.append` — convert still to single-frame MOV via `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` so it composes with videos
- `StitchClip.kind: .video | .still` + `ClipEdits.stillDuration: Double?` (default 3.0, range 0.5-10)
- `ClipEditorSheet` shows Duration tab (slider 0.5-10s) when clip is `.still`, Trim tab when video
- All `PhotosPicker` calls switch to `matching: .any(of: [.videos, .images])`
- Auto-strip Meta runs across all paths (Compress, Stitch, MetaClean) for both videos and photos

### Commit 4 — iMovie-style drag-from-end + live trim preview (effort: M)

Per backlog items 5 and 6.

- Replace `List + .onMove` in `StitchTimelineView` with horizontal `LazyHStack` inside `ScrollView(.horizontal)`
- Each clip is `.draggable(StitchClipID)` + `.dropDestination(for: StitchClipID.self)` so user can grab from anywhere and drop anywhere
- `ClipEditorSheet`:
  - Dock `AVPlayerViewController` (or `VideoPlayer`) at the top
  - Drag trim-start handle: `seek(to: newStart)` continuously; on release, `play()` from new in-point
  - Drag trim-end handle: `seek(to: newEnd - 2 sec)` continuously; on release, `play()` for 2 sec then pause
  - Live-apply edits to parent (no Done button modality — drag, see, drag again)
  - Cancel reverts to the snapshot taken on appear
- Drop the dual-Slider for a custom dual-thumb timeline scrubber (single horizontal track with 2 handles)

### Commit 5 — iOS Share Extension + App Group (effort: M)

Per backlog item 2.

- Add new Xcode target `MediaSwissShareExtension` (Share Extension template)
- Add App Group capability `group.ca.nextclass.MediaSwissArmy` to main app + extension entitlements
- Extension UI: 3 buttons (Compress / Stitch / MetaClean) — user taps one
- On tap: copy each shared `NSItemProvider` payload into App Group's `Inbox/<destination>/<uuid>.<ext>`
- Custom URL scheme `mediaswiss://` to deep-link the main app
- Main app on launch + foreground: scan Inbox folders, move items into the right Compress/Stitch/MetaClean queue, switch TabView to that tab
- iOS will surface our app in the Photos share sheet automatically once the extension is registered

### Commit 6 — Multi-clip parallel compression (effort: S)

Mentioned by user, also a phase-3 priority.

- iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro / 17 Pro all have 2 dedicated video encoder engines
- Detect device class via `ProcessInfo.processInfo.thermalState` + a UIDevice model lookup
- Bump `VideoLibrary.compressAll` concurrency to 2 on Pro devices, 1 on non-Pro
- Use `TaskGroup` for the parallel queue with thermal-throttle backoff
- A 10-clip batch finishes in roughly half the wall-clock time on Pro devices

### Commit 7 — Final red team + simulator E2E proof (effort: S)

- Dispatch 4 Opus reviewers (concurrency, security, AVFoundation, App Store readiness — same pattern as Build 11 audit)
- Apply CRITICAL + HIGH findings; defer everything else
- Use XcodeBuildMCP to drive simulator visually:
  - Open each tab, screenshot
  - Tap import, screenshot picker
  - Add fixture videos AND photos via `simctl addmedia`
  - Drive each tab end-to-end, screenshot at each step
  - All screenshots end up in `.agents/work-sessions/<date>/screenshots/`
- Update CHANGELOG.md per phase-3 commit
- Append AI-CHAT-LOG entries

### Final step — merge phase-3 to main → one big TestFlight build with everything

---

## Bootstrap prompt for the next session at your Mac

Open Claude Code in the repo, paste:

```
Continuing the Media Swiss Army project at end of session 2026-05-03.

PR #2 was merged earlier — Build 12 is the latest TestFlight build with
core 3-tab functionality + auto-strip Meta + Build 11/12 bug fixes.

This session picks up phase 3. Read first:
- .agents/work-sessions/2026-05-03/HANDOFF-v2.md  (this file — full context)
- .agents/work-sessions/2026-05-03/BACKLOG-stitch-photos-and-share-extension.md  (all 6 backlog items)
- .agents/work-sessions/2026-05-03/AI-CHAT-LOG.md  (full session paper trail)

Branch: feature/phase-3-stitch-ux-and-photos (already created and pushed)
Commit ordering (7 commits): see HANDOFF-v2 §"Phase 3 work plan".

Use XcodeBuildMCP heavily for visual sim testing. Drive build_run_sim +
screenshot after each significant change so user sees progress live.

Dispatch Opus 4.7 subagents per commit; pr-review-toolkit:code-reviewer
(opus) per review; haiku scribe for AI-CHAT-LOG entries. Keep CHANGELOG.md
current with agent identification on every entry.

DO NOT push to main until phase 3 is fully done and all reviewers green.

Start by booting iPhone 16 Pro simulator, screenshotting current state of
the 3 tabs, then dispatching Opus subagent for Commit 1 (AVAssetWriter
migration).
```

---

## What's already in the repo and ready for phase 3

- TestFlight pipeline (GitHub Actions → App Store Connect, no manual triggers needed)
- `feature/phase-3-stitch-ux-and-photos` branch pushed to GitHub with the 50-file PhotosPicker bump and updated backlog
- All session logs, plans, audits, handoffs are tracked in git (work-sessions/ no longer gitignored)
- Test fixture (8s 720p H.264 from ffmpeg) injected into iPhone 16 Pro simulator's Photos
- XcodeBuildMCP session defaults configured: project + scheme + simulator + bundle ID
- AXE 1.6.0 installed on user's Mac for UI automation

## What user needs to do at the Mac

1. Pull latest: `git fetch && git switch feature/phase-3-stitch-ux-and-photos`
2. Open a fresh Claude Code session in the repo
3. Paste the bootstrap prompt above
4. Plug in iPhone if you want to test physical device deploys mid-flight
5. Otherwise: just watch the simulator + screenshots as we iterate

## Risks queued for the new session

- **Audio Background Mode App Store review risk** — keep it opt-in, default OFF. If reviewer pushes back later, we can add a harder gate.
- **Photo HEIC encoding edge cases** — Live Photos return both HEIC + MOV; v1 ignores the MOV sidecar
- **Multi-clip parallel encode thermal** — on iPhone 13 base / older non-Pros, 2 concurrent encodes can throttle. Default to 1 concurrent on non-Pro models
- **Share Extension App Group setup** — paid Apple Dev account required (already true), entitlements need a one-time tweak

---

End of v2 handoff. Ready for fresh session at home.
