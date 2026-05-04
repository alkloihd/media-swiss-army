# Dependency / Risk Log — 2026-05-04

Purpose: track what changed, what downstream code can be affected, what is not working, and what still needs human or iPhone inspection after each cluster.

Rule: append after every cluster task/PR checkpoint before moving on.

## Cluster Dependency Map

| Cluster                    | Depends on                                        | Affects later work                                                                                              | Human/iPhone gate                                                            |
| -------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 0 — Hotfixes               | PR #9 baseline, planning suite                    | `StillVideoBaker.bake` tuple return, `CompressionService.compress` result shape, compression preset fallback UI | Real-device compression on Max/Balanced/Streaming and photo stitch scale-fit |
| 1 — Cache & Still Bake     | Cluster 0 tuple return must be preserved          | CacheSweeper lifecycle, still baking performance/cancel cleanup                                                 | Confirm no cache bloat, cancel/save cleanup behavior                         |
| 2 — Stitch Correctness     | Cluster 0/1 stitch + bake behavior                | Audio track assignment, HDR passthrough, filename staging, import sort order                                    | Real stitch exports with audio, HDR, photo/video batches                     |
| 3 — UX Polish & Onboarding | Stable Compress/Stitch/MetaClean flows from 0-2   | User-facing copy, onboarding state, MetaClean batch UX, controls                                                | Visual/manual app flow inspection                                            |
| 4 — App Store Hardening    | Final app identity and stable settings/navigation | Privacy manifest, permissions, privacy policy URL, review prompt                                                | App Store Connect/TestFlight policy sanity; GitHub Pages privacy link        |
| 5 — Meta Marker Registry   | Stable MetadataService behavior                   | Async fingerprint APIs across production/tests, bundled marker JSON                                             | Meta/Ray-Ban sample detection on real assets                                 |

## Running Issues / Watchpoints

| Status | Area                      | Issue                                                                                                                     | Evidence                                                                                                                           | Next action                                                                                                                                                                                    |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Open   | TestFlight/manual         | Simulator cannot prove real-device `-11841` fix or photo scale-fit.                                                       | MCP `test_sim` and launch passed, but original bugs were surfaced on iPhone.                                                       | After PR #10 merge/TestFlight, user must run Cluster 0 manual prompts.                                                                                                                         |
| Resolved | Signing/App Store Connect | Cluster 0/1 TestFlight export failed after a bundle-id rename orphaned the App Store Connect app lookup. | PR #12 reverted active identity to `ca.nextclass.VideoCompressor`; TestFlight run `25309299281` succeeded. | Do not touch bundle identity strings or `.github/workflows/testflight.yml`; rebase Cluster 2 onto `main@936cafb` before PR. |
| Open   | Stitch real device        | TestFlight build on iPhone18,2 / iOS 26.3.1 can still throw raw AVFoundation `-11841` in Stitch exports and fail to re-render after save. | Claude relay at 13:04 SAST: Random + Small, no-transition video/photo stitches, and save-then-render repeat failed on device. | Treat as Cluster 2 Task 4.5 gate: root-cause, add simulator-deterministic tests, implement Stitch retry/downshift and re-render safety before PR. |
| Watch  | Historical docs           | Older 2026-05-03 archives still mention `ca.nextclass.VideoCompressor`.                                                   | Active grep only finds old ID in append-only log/archive contexts.                                                                 | Do not rewrite historical logs unless user explicitly asks.                                                                                                                                    |

## Cluster Checkpoints

### Cluster 0 — PR #10

| Field                 | Notes                                                                                                                                                                                                        |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Branch / PR           | `feat/codex-cluster0-hotfixes`, PR #10                                                                                                                                                                       |
| Key changes           | Photo stitch uses baked movie dimensions; compression caps Max bitrate; writer declares SDR BT.709; frame-rate/GOP clamps; `-11841` one-shot downshift; fallback surfaced in UI; bundle identity normalized. |
| APIs changed          | `StillVideoBaker.bake(still:duration:) -> (url: URL, size: CGSize)`; `CompressionService.compress(input:settings:onProgress:) -> CompressionResult`; `CompressedOutput` includes optional fallback note.     |
| Downstream dependency | Cluster 1 must preserve the tuple return from `StillVideoBaker`; UI/model work must preserve visible fallback note rather than silently hiding downshift.                                                    |
| Verification          | `build_sim` passed; `test_sim` passed 152/152; `build_run_sim` launched as `com.alkloihd.videocompressor`; MCP UI snapshot showed Compress empty state; PR CI green.                                         |
| TestFlight status     | Merge commit `f1e08d5` triggered run `25305896821`; archive succeeded; export/upload failed with `Error Downloading App Information` at `xcodebuild -exportArchive`.                                         |
| Not yet proven        | Real-device encoder behavior and photo stitch scale-fit on iPhone/TestFlight.                                                                                                                                |
| Human inspection      | App Store Connect bundle/app/API-key access if TestFlight remains blocked; iPhone manual prompts after a build successfully lands.                                                                           |

### Autopilot Policy — From 09:11 SAST

| Field              | Notes                                                                                                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch cadence     | One clean branch/PR per cluster from current `main`; no direct pushes to `main`; no stale outstanding PRs before starting the next cluster.                                               |
| Review cadence     | Use reviewer agents where they return; if a reviewer hangs, close it, log that fact, and rely on local verification + PR CI rather than blocking indefinitely.                            |
| TestFlight cadence | Watch every `main` merge workflow. If TestFlight fails for external signing/App Store Connect reasons, log it and continue simulator/local feature work without claiming phone readiness. |
| Revert path        | Every cluster lands as a merge commit/PR, so code can be reverted by reverting the merge commit. Older successfully processed TestFlight builds remain selectable in Apple tools.         |

### Cluster 1 — Branch Start

| Field             | Notes                                                                                                                                                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch            | `feat/codex-cluster1-cache-and-bake` from `main` at `f1e08d5`                                                                                                                                                                          |
| Baseline          | `mcp__XcodeBuildMCP__.test_sim` passed 152/152 before production edits.                                                                                                                                                                |
| Agent scan        | No hard blockers. Adapt plan snippets for Cluster 0 tuple return, use >=32px still fixtures, update expected counts from baseline 152, avoid brittle wall-clock tests, and use explicit cleanup around preallocated still-bake output. |
| Known deviation   | `StitchExporter.runReencode` has no local export-session cancel branch; it delegates to `CompressionService.encode`, so cancel cleanup should be verified there.                                                                       |
| Human/iPhone gate | Cluster 1 can be simulator-verified; real cache cleanup after Photos save and TestFlight availability still need a working TestFlight upload or device run.                                                                            |

#### Task 1 — Still Bake O(1)

| Field        | Notes                                                                                                                                                                                                                |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `StillVideoBaker.bake(still:)` emits a fixed 1-second movie; `bake(still:intoPreallocated:)` supports pre-registered cleanup URLs; `StitchExporter` scales baked still segments to the user-selected still duration. |
| Tests        | Added `StillVideoBakerTests` and `StitchExporterScaleTests`; updated `StitchAspectRatioTests` for the new API.                                                                                                       |
| Verification | TDD compile-red on missing `bake(still:)`, then `mcp__XcodeBuildMCP__.test_sim` passed 155/155.                                                                                                                      |
| Watchpoints  | Focused reviewer agent timed out; rely on green tests and later PR review/CI.                                                                                                                                        |

#### Task 2 — CacheSweeper Lifecycle APIs

| Field        | Notes                                                                                                                                                                                                          |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `CacheSweeper` now tracks managed tmp outputs, adds `sweepOnCancel`, delayed `sweepAfterSave`, `sweepOnLaunchTight`, and includes managed tmp in totals/breakdown.                                             |
| Tests        | Added `CacheSweeperTests` for safe Documents deletion, outside-file preservation, cancel cleanup, nil cancel, short-delay save sweep, `StillBakes` cleanup, `PhotoClean-*` wrapper cleanup, and tmp breakdown. |
| Verification | TDD compile-red on missing APIs, then `mcp__XcodeBuildMCP__.test_sim` passed 163/163.                                                                                                                          |
| Watchpoints  | Worker and focused reviewer agents timed out; rely on tests plus later PR review/CI.                                                                                                                           |

#### Task 3 — Cleanup Hook Wiring

| Field        | Notes                                                                                                                                                                                                                                   |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Cancel/failure cleanup now routes through `CacheSweeper.sweepOnCancel` in compression, stitch passthrough, video metadata strip, photo metadata strip, and photo compression paths. Save-success cleanup now uses delayed sweep hooks. |
| Adaptation   | Current code saves MetaClean and Stitch outputs to Photos from `MetaCleanExportSheet` and `StitchExportSheet`, not from `MetaCleanQueue.runClean` or `StitchProject.runExport`. Delayed sweeps were wired at the actual save sites.     |
| Tests        | Existing Cluster 1 cache lifecycle tests plus full simulator suite.                                                                                                                                                                     |
| Verification | `mcp__XcodeBuildMCP__.test_sim` passed 163/163 after integration.                                                                                                                                                                       |
| Watchpoints  | Focused Task 3 review agent timed out and was closed. Static grep/diff pass found hooks at actual save-success sites; rely on green tests plus final PR review/CI.                                                                     |

#### Final Local Verification

| Field        | Notes                                                                                           |
| ------------ | ----------------------------------------------------------------------------------------------- |
| Verification | `mcp__XcodeBuildMCP__.test_sim` passed 164/164 after the pre-merge review follow-up; `mcp__XcodeBuildMCP__.build_sim` succeeded. |
| PR readiness | CHANGELOG, task manifest, dependency/risk log, and AI chat log updated before push/PR creation.                                   |
| Review       | Pre-merge reviewer approved PR #11 with no blockers. The one residual still-bake orphan risk was fixed before merge with a regression test. |

### Cluster 1 — PR #11

| Field                 | Notes                                                                                                                                                                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch / PR           | `feat/codex-cluster1-cache-and-bake`, PR #11                                                                                                                                                                                       |
| Merge                 | Merged to `main` as `5e57fa9` after PR CI passed and read-only pre-merge review approved with no blockers.                                                                                                                         |
| Key changes           | Still bakes are O(1), baked URLs are pre-registered and cleaned on build-plan failure, CacheSweeper tracks managed tmp wrappers, and cancel/save/launch cleanup hooks are wired through app flows.                                  |
| APIs changed          | `StillVideoBaker.bake(still:)` is the duration-free convenience API; `bake(still:intoPreallocated:)` supports caller-registered cleanup; `CacheSweeper` adds `sweepOnCancel`, `sweepAfterSave`, and `sweepOnLaunchTight`.          |
| Downstream dependency | Cluster 2 must preserve still-bake tuple/cleanup behavior and avoid re-architecting the existing A/B stitch track model.                                                                                                           |
| Verification          | Local `test_sim` passed 164/164; local `build_sim` succeeded; PR CI green; main CI green.                                                                                                                                          |
| TestFlight status     | Run `25307940461` failed after archive during export/upload with `Error Downloading App Information`, exit 70, matching Cluster 0's external App Store Connect/app-information gate.                                               |
| Not yet proven        | Real-device cache cleanup and still-bake speed after Photos save/cancel because no new TestFlight build has landed since the App Store Connect export gate appeared.                                                               |
| Human inspection      | App Store Connect app/bundle/API-key access must be checked outside code. Once TestFlight export works, user should run Cluster 0 and Cluster 1 manual iPhone prompts before those clusters are marked fully done.                 |

### Cluster 2 — Branch Start

| Field             | Notes                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Branch            | `feat/codex-cluster2-stitch-correctness` from `main` at `5e57fa9`.                                                            |
| Baseline          | Fresh `mcp__XcodeBuildMCP__.test_sim` passed 164/164 before production edits.                                                  |
| Known dependency  | Preserve Cluster 1 `StillVideoBaker` tuple/preallocation cleanup and Cluster 0 visible compression fallback behavior.          |
| Human/iPhone gate | Real stitch exports with audio/HDR/photo-video batches still need a successful TestFlight/device install after the export gate. |

#### Task 1 — HDR Pixel Format + Color Properties

| Field        | Notes                                                                                                                                                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Key changes  | `CompressionService` now loads source format descriptions before writer setup, detects 10-bit sources, requests 10-bit reader pixel buffers, preserves HDR color properties with BT.2020/HLG defaults, and uses HEVC Main10 for 10-bit HEVC. |
| Adaptation   | Plan snippets were stale because Cluster 0 already added SDR color properties and the writer settings moved. Detection was moved before `profileLevel`/writer settings, and the existing `AVVideoProfileLevelKey` path is reused.          |
| Tests        | Added helper tests for 10-bit/8-bit reader pixel formats, HDR BT.2020/HLG color defaults, and HEVC Main10 profile selection.                                                                                                                |
| Verification | Initial TDD red compile failed on missing `pixelBufferDict`; `mcp__XcodeBuildMCP__.build_sim` succeeded; XcodeBuildMCP CLI `simulator test` passed 168/168 after MCP `test_sim` timed out at 120s.                                           |
| Watchpoints  | HDR remains simulator/unit verified only. Real HDR visual round-trip on iPhone is pending because TestFlight/device verification is gated.                                                                                                  |

#### Task 2 — Audio Mix Track Parity

| Field        | Notes                                                                                                                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `StitchExporter` segment records now carry the actual inserted `audioTrack`; audio mix construction skips silent segments and groups input parameters by composition track ID instead of recomputing `i % 2` parity.       |
| Adaptation   | The plan's previous/next-audible rewrite was not used because audio should still fade out into a still and fade in out of a still. Immediate timeline neighbors are kept for overlap windows while silent params are skipped. |
| Tests        | Added `[video, still, video]` crossfade fixture coverage with generated silent-audio video and still PNG fixtures.                                                                                                         |
| Verification | TDD red: new test failed with 3 params on the old parity code. Green: `mcp__XcodeBuildMCP__.test_sim` passed 169/169.                                                                                                     |
| Watchpoints  | Real-device audio perception remains pending until TestFlight/device gate clears.                                                                                                                                         |

#### Task 3 — Stage Filename Collision

| Field        | Notes                                                                                                                                                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `StitchTabView` staging now always prefixes staged filenames with a lowercased 6-character UUID and exposes a static test hook for staging logic.                                                                       |
| Adaptation   | The test uses `.mov` source fixture names so suggested `clip.mov` produces `xxxxxx-clip.mov`, avoiding the plan's `.tmp` extension pitfall.                                                                             |
| Tests        | Added `StitchProjectStageTests` for delete-then-reimport of `clip.mov`, asserting distinct UUID-prefixed staged paths even when the first staged file was deleted.                                                       |
| Verification | TDD red: compile failed on missing `testHook_stageToStitchInputs`. Green: XcodeBuildMCP CLI `simulator test` passed 170/170 after MCP `test_sim` timed out at 120s.                                                     |
| Watchpoints  | None beyond real-device import behavior pending behind the external device/TestFlight gate.                                                                                                                            |

#### Task 4 — Import Auto-Sort Oldest First

| Field        | Notes                                                                                                                                                                                            |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Key changes  | `StitchTabView.importClips` now calls `finalizeImportOrdering(project:)` after the import loop, which runs `sortByCreationDateAsync()` so PhotosPicker newest-first delivery becomes oldest-first. |
| Adaptation   | Added a small tested import-finalization seam instead of only testing `sortByCreationDateAsync()` directly; this proves the production import path calls the sorter.                              |
| Tests        | Added `StitchProjectSortTests.testImportFinalizationAutoSortsOldestFirst` using newest-first clips with explicit dates.                                                                           |
| Verification | TDD red: compile failed on missing `testHook_finalizeImportOrdering`. Green: XcodeBuildMCP CLI `simulator test` passed 171/171 after MCP `test_sim` timed out at 120s.                            |
| Watchpoints  | Real PhotosPicker import ordering remains simulator-unit verified; real-device timeline inspection is pending behind the external device/TestFlight gate.                                         |

#### Task 4.5 — Real-Device Stitch Export Gate

| Field        | Notes                                                                                                                                                                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Trigger      | TestFlight build from `main@936cafb` restored the pipeline, and user testing on iPhone18,2 / iOS 26.3.1 found Stitch `Small` exports still throwing raw AVFoundation `-11841` plus a save-then-re-render failure.                                             |
| Key changes  | `StitchExporter` now returns `StitchExportResult`, retries stitch re-encodes on `-11841`, adds a stitch floor of `Small -> Streaming`, catches raw AVFoundation `NSError` `-11841`, and rebuilds rejected transition plans without transitions before retrying another preset or surfacing a failure. `StitchExportSheet` now shows fallback notes, offers `Export Again` after a finished export, and hides Save when the finished sandbox output was already swept. |
| Agent scan   | Dispatched read-only explorer agents for (1) Stitch `-11841` fallback architecture and (2) CacheSweeper/Stitch save/re-render data flow.                                                                                                                     |
| Tests        | Added stitch retry/downshift tests for `Small -> Streaming`, raw `NSError` `-11841`, non-retry `-11847`, transition-drop-before-preset-retry ordering, transition fallback messaging, Random+Small synthetic timeline coverage, Stitch output sweep preserving inputs, and finished-sheet export-again/stale-output helpers. |
| Verification | `mcp__XcodeBuildMCP__.build_sim` succeeded. `mcp__XcodeBuildMCP__.test_sim` passed `182` total: `181` passed, `1` skipped. The skip is documented in-test because simulator AVFoundation rejects the synthetic Random+Small composition after the `-11841` fallback path with a generic error; deterministic retry tests cover the production branch. |
| Watchpoints  | Real iPhone verification is still required for the original hardware encoder bug. Do not touch active bundle identity or TestFlight workflow.                                                                                                                |

### Cluster 2 — PR #13

| Field                 | Notes                                                                                                                                                                                                                                                            |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch / PR           | `feat/codex-cluster2-stitch-correctness`, PR #13                                                                                                                                                                                                                 |
| Merge                 | Merged to `main` as `1d886cc` after PR checks passed.                                                                                                                                                                                                            |
| Key changes           | HDR encode metadata preservation, audio-mix track correctness, UUID import staging, oldest-first import finalization, and real-device Stitch `-11841` fallback/re-export guard.                                                                                  |
| Verification          | Local `build_sim` succeeded; local `test_sim` passed `182` total (`181` passed, `1` documented simulator-fixture skip); PR checks passed; TestFlight workflow run `25317235711` succeeded in 2m59s.                                                               |
| Not yet proven        | Original iPhone18,2 / iOS 26.3.1 Stitch repro must be retested from TestFlight: Random + Small, no-transition video/photo-only stitches, mixed photo/video stitch, save to Photos, then Export Again on the same project.                                        |
| Downstream dependency | Cluster 3 UI work must preserve the visible fallback note and `Export Again` action in `StitchExportSheet`; Cluster 4 app-review work must not alter the restored `ca.nextclass.VideoCompressor` bundle identity.                                                |

### Cluster 3 — Branch Start

| Field             | Notes                                                                                                                                                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch            | `feat/codex-cluster3-ux-polish` from `main@1d886cc`, with append-only Cluster 2 merge/TestFlight log commits carried on the branch rather than pushed directly to `main`.                                                              |
| Baseline          | `mcp__XcodeBuildMCP__.test_sim` passed `182` total: `181` passed, `1` documented simulator-fixture skip.                                                                                                                               |
| Scope             | Phase 2 UX polish: copy cleanup, first-launch onboarding, Settings explainer, Stitch preview/drop affordances, MetaClean batch concurrency/toast, crop/preset/settings simplification.                                                  |
| Agent scan        | Read-only agents dispatched for UI/onboarding tasks, MetaClean batch concurrency, and crop/preset/settings simplification.                                                                                                             |
| Watchpoints       | Preserve Cluster 2 Stitch fallback note and `Export Again`; do not alter bundle identity or TestFlight workflow; validate SwiftUI copy/interaction changes with build/test evidence plus TestFlight/manual prompts after merge.          |

#### Task 1 — Dev-y Copy Polish

| Field        | Notes                                                                                                                                                                                                                 |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added `BatchCleanProgress.userFacingLabel(kind:)`; MetaClean batch/export labels now use friendlier copy; `ClipEditorSheet` print is DEBUG-only; duplicate header scissors icon removed from `ClipEditorInlinePanel`.                  |
| Adaptation   | Kept ASCII ellipses in user-facing strings/tests while preserving the plan's middle-dot batch label. Did not expand into broader MetaClean empty-state copy despite scout noting it, to keep Task 1 scoped.                             |
| Verification | TDD red compile failed on missing `userFacingLabel(kind:)`; green `mcp__XcodeBuildMCP__.test_sim` passed `186` total: `185` passed, `1` documented simulator-fixture skip.                                           |
| Watchpoints  | The remaining `print(` grep hit is inside `#if DEBUG`; acceptance allows DEBUG-only print sites.                                                                                                                      |

#### Task 2 — First-Launch Onboarding

| Field        | Notes                                                                                                                                                                                                                 |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added pure `OnboardingGate`, 3-card paged `OnboardingView`, and `ContentView` first-launch `.fullScreenCover` gated by `@AppStorage("hasSeenOnboarding_v1")`; final button routes to MetaClean.                       |
| Adaptation   | Updated stale `ContentView` header comments that still described Stitch/MetaClean as placeholders. Kept onboarding copy concise and app-utility focused.                                                               |
| Verification | TDD red compile failed on missing `OnboardingGate`; green `mcp__XcodeBuildMCP__.test_sim` passed `190` total: `189` passed, `1` documented simulator-fixture skip.                                                     |
| Watchpoints  | Fresh-install presentation and persistence still require manual simulator/device walkthrough after the full Cluster 3 PR lands.                                                                                       |

#### Task 3 — Settings MetaClean Explainer

| Field        | Notes                                                                                                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Settings now starts with a "What MetaClean does" section, including disclosure groups for what gets removed, what stays, and what MetaClean never does.                     |
| Adaptation   | Kept the section first and updated the Settings file header.                                                                                                                |
| Verification | `mcp__XcodeBuildMCP__.test_sim` passed `190` total: `189` passed, `1` documented simulator-fixture skip; `mcp__XcodeBuildMCP__.build_sim` succeeded.                       |
| Watchpoints  | Manual UI inspection should confirm this is visually first above the background-encoding toggle.                                                                            |

#### Task 4 — Stitch Preview Menu Item

| Field        | Notes                                                                                                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Stitch clip context menus now start with `Preview`, and tapping it presents the existing `ClipLongPressPreview` in a medium/large sheet with a Done button.                |
| Adaptation   | Kept `ClipLongPressPreview` file-private because the new sheet lives in the same file; the plan's promotion note was unnecessary.                                           |
| Verification | `mcp__XcodeBuildMCP__.test_sim` passed `190` total: `189` passed, `1` documented simulator-fixture skip; `mcp__XcodeBuildMCP__.build_sim` succeeded.                       |
| Watchpoints  | Manual UI inspection should confirm Preview appears first and the existing long-press preview overlay still works.                                                          |

#### Task 5 — Drop Indicator Polish

| Field        | Notes                                                                                                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Stitch timeline drop target now uses an 8pt accent bar, soft accent shadow, and a 12pt animated leading gutter on the target clip.                                         |
| Verification | `mcp__XcodeBuildMCP__.test_sim` passed `190` total: `189` passed, `1` documented simulator-fixture skip; `mcp__XcodeBuildMCP__.build_sim` succeeded.                       |
| Watchpoints  | Manual UI inspection should confirm the wider bar and neighbor push read clearly at low zoom.                                                                              |

#### Task 6 — Faster Batch MetaClean + Single Save Toast

| Field        | Notes                                                                                                                                                                                                 |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | MetaClean batch clean now uses `MetaCleanQueue.batchConcurrency` for bounded metadata-strip concurrency, publishes a single `SaveBatchResult` through `VideoLibrary`, and shows one bottom toast after batch save completion. |
| Adaptation   | Kept Photos save/delete serial in the TaskGroup result drain instead of running `PHPhotoLibrary.performChanges` in child tasks; routed completion through a `cleanAll` callback instead of a static weak global sink. |
| Tests        | Added `MetaCleanQueueConcurrencyTests` for concurrency policy, completed-count progress fraction, and save-batch display copy.                                                                          |
| Verification | TDD red compile failed on missing `MetaCleanQueue.batchConcurrency` and `SaveBatchResult`; focused label-start red/green then passed 12/12; full `mcp__XcodeBuildMCP__.test_sim` passed `198` total: `197` passed, `1` skip; `build_sim` succeeded. |
| Watchpoints  | Real-device MetaClean batch timing and Photos delete-confirmation UX still need TestFlight/iPhone inspection; current confidence is simulator/build plus static diff review until device testing is available. |

#### Task 7 — Frontend Simplifications

| Field        | Notes                                                                                                                                                                                                 |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Compress picker now shows Balanced + Small by default with Max + Streaming under Advanced; crop controls are four aspect presets; Settings performance lives behind an Advanced disclosure.            |
| Adaptation   | The active Stitch editor is `ClipEditorInlinePanel`, not just `ClipEditorSheet`, so the crop preset grid is wired into the inline editor as well. Crop math uses `displaySize` to avoid rotated iPhone portrait false crops and collapses identity crops to `nil`. |
| Tests        | Added `CropEditorPresetTests` for free/invalid clears, square landscape crop, native 16:9/rotated 9:16 identity collapse, and portrait/landscape cross-crops.                                             |
| Verification | TDD red compile failed on missing `CropEditorView.cropRect`/preset enum; focused crop tests passed 7/7; `mcp__XcodeBuildMCP__.clean` succeeded; full `test_sim` passed `205` total: `204` passed, `1` skip; `build_sim` succeeded. |
| UI evidence  | Simulator launched, onboarding completed, Settings Advanced collapsed/expanded correctly in `snapshot_ui`; screenshot saved at `/var/folders/4v/3fctbw5j65gcbzcbhrsg33y40000gq/T/screenshot_optimized_de88d7dd-a934-48de-a5aa-2bfe202f5d14.jpg`. |
| Watchpoints  | Need real media loaded in Stitch to visually confirm inline crop preset placement with video/still previews; simulator shut down before further tap-through, but build/test coverage is green.           |

### Cluster 4 — Branch Start

| Field       | Notes                                                                                                                                                                              |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch      | `feat/codex-cluster4-appstore-hardening` from `main@d5c108d`, with append-only Cluster 3 merge/TestFlight log commits carried locally on the feature branch.                      |
| Baseline    | `mcp__XcodeBuildMCP__.test_sim` passed `205` total: `204` passed, `1` documented simulator-fixture skip.                                                                           |
| Scope       | App Store hardening: privacy manifest, Photos read auth gate, review prompt, privacy policy/settings link, and PR-side iOS XCTest CI.                                               |
| Agent scan  | Read-only scouts dispatched for privacy manifest/policy/CI, Photos auth gate, and review prompt integration.                                                                       |
| Watchpoints | Do not edit TestFlight workflow or bundle identity. Review prompt should count user-visible clean/save success, not metadata-strip-only success. CI job must avoid masking failures. |

#### Task 1 — Privacy Manifest

| Field        | Notes                                                                                                                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Key changes  | Added `VideoCompressor/ios/PrivacyInfo.xcprivacy` with UserDefaults `CA92.1`, FileTimestamp `C617.1`, DiskSpace `E174.1`, `NSPrivacyTracking=false`, empty tracking domains, and empty collected data. |
| Tests        | Added `PrivacyManifestTests` to load the hosted app bundle manifest, parse the plist, assert no tracking, and pin all three required-reason API categories.                                             |
| Verification | TDD red failed 3/3 because the manifest was missing from the app bundle; `plutil -lint` passed; `clean` succeeded; focused tests passed 3/3; full `test_sim` passed `208` total: `207` passed, `1` skip. |
| Watchpoints  | Simulator app-bundle test proves local bundling, but App Store Connect privacy-manifest acceptance is still verified by the next TestFlight/App Store Connect build details.                           |

#### Task 2 — Photos Auth Gate

| Field        | Notes                                                                                                                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `StitchClipFetcher.creationDate` and `creationDates` now gate Photos metadata lookup on passive `.readWrite` authorization and return `nil` / `[:]` unless status is `.authorized` or `.limited`. |
| Adaptation   | Added the missing batch `.restricted` test so all three denied-status states are covered across both fetch paths. Used `authorizationStatus`, not `requestAuthorization`, to avoid any Stitch prompt. |
| Review fix   | A reviewer noted fake asset IDs did not prove denied states skip fetch. Added defaulted fetch-provider seams plus tests proving denied no-fetch and authorized/limited fetch continuation.             |
| Verification | TDD red compile failed on missing `authStatusProvider`, then missing fetch provider seam; focused auth tests passed `8/8`; full `test_sim` passed `216` total: `215` passed, `1` documented skip. |
| Watchpoints  | Real Photos authorized/limited behavior still depends on the device library, but tests now prove the gate calls or skips the fetch seam before Photos API access.                                  |

#### Task 3 — Review Prompt

| Field        | Notes                                                                                                                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added `ReviewPrompter` with UserDefaults-backed success count, per-version lock, iOS 18 `AppStore.requestReview(in:)`, and `SKStoreReviewController` fallback for older SDK paths.                            |
| Adaptation   | Prompt credit is recorded after actual Photos save success, not metadata-strip success. Single saves count after `MetaCleanExportSheet` save succeeds; batch replace counts `savedCount` once after the batch. |
| Tests        | Added pure eligibility and injected recorder tests for threshold, same-version lock, new-version re-prompt, non-positive count ignore, and count persistence.                                                   |
| Verification | TDD red failed on missing `ReviewPrompter`, then actor-isolated default closures; focused ReviewPrompter tests passed `9/9`; full `test_sim` passed `225` total: `224` passed, `1` documented skip.            |
| Watchpoints  | Actual system review UI cannot be forced by unit tests and may be rate-limited by iOS; tests cover the app-side eligibility and request trigger path.                                                           |

#### Task 4 — Privacy Policy And Settings Link

| Field        | Notes                                                                                                                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added `docs/privacy/index.html` for `https://alkloihd.github.io/media-swiss-army/privacy/` and a Settings `About` section with a Safari-opening Privacy Policy row.                                           |
| Adaptation   | Used the locked repo URL and current Media Swiss Army branding. The plan's `Section("About") { } footer:` initializer did not compile under this SDK, so the Settings row uses explicit header/footer closures. |
| Verification | `npx prettier --check docs/privacy/index.html` passed after formatting; TDD compile-red caught the Section initializer issue; focused ReviewPrompter tests passed `9/9`; full `test_sim` passed `225/224/1`.  |
| Watchpoints  | GitHub Pages still requires manual repo setting: Settings → Pages → Source `main` branch, `/docs` folder. Until then the in-app link opens Safari to a parseable URL that may 404.                              |

#### Task 5 — PR-Side iOS CI

| Field        | Notes                                                                                                                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added an `iOS XCTest` job to `.github/workflows/ci.yml` so pull requests run the iOS unit test target before merge. No TestFlight workflow, signing, or bundle ID files changed.                                           |
| Adaptation   | The plan's `VideoCompressorTests` selector and hard-coded iPhone 16 Pro runner assumption were stale. CI now uses `VideoCompressor_iOSTests` and selects iPhone 17 Pro, iPhone 16 Pro, or first available iPhone Pro.       |
| Dependencies | Avoided `xcbeautify` so the job does not depend on weekly runner image packages. Uses raw `xcodebuild` with `set -euo pipefail`, `CODE_SIGNING_ALLOWED=NO`, DerivedData cache, and failed-result artifact upload.             |
| Verification | `ruby` YAML parse passed; `npx prettier --check .github/workflows/ci.yml docs/privacy/index.html` passed; `xcodebuild -list` confirmed scheme/target; CI-style `test_sim` passed `225` total: `224` passed, `1` skipped. |
| Watchpoints  | Cloud runner availability still needs PR CI proof. After the job appears green, `iOS XCTest` should be added manually as a required status check on `main` branch protection.                                               |

### Cluster 5 — Branch Start

| Field       | Notes                                                                                                                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch      | `feat/codex-cluster5-meta-marker-registry` from `main@96f420f`.                                                                                                                      |
| Baseline    | `mcp__XcodeBuildMCP__.test_sim` passed `225` total: `224` passed, `1` documented simulator-fixture skip.                                                                              |
| Scope       | Replace hard-coded Meta-glasses markers with a bundled JSON registry and async detector lookups while preserving legacy detection, no network, and no strip-path changes.              |
| Agent scan  | Read-only scouts dispatched for resource bundling/async cascade, detector semantics, and implementation-quality risks.                                                                |
| Watchpoints | Preserve current bare `meta` behavior for binary video atoms and MakerApple Software; do not add bare `meta` to XMP; do not touch `strip(...)`, networking, analytics, or TestFlight. |

#### Task 1 — Bundled MetaMarkers JSON

| Field        | Notes                                                                                                                                                                                        |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added `VideoCompressor/ios/Resources/MetaMarkers.json` and `MetaMarkerRegistryTests.testBundleContainsMetaMarkersJSON` to prove the resource is copied into the hosted app bundle.          |
| Adaptation   | Scout review found the plan JSON would regress current detection by omitting bare `meta` from binary atoms/MakerApple. JSON preserves that legacy behavior but still excludes bare `meta` from XMP. |
| Verification | TDD red failed 1/1 because resource was absent; `clean` succeeded; focused bundle test passed `1/1`; `npx prettier --check VideoCompressor/ios/Resources/MetaMarkers.json` passed after formatting. |
| Watchpoints  | Bundle auto-inclusion is currently proven by the focused hosted test. If future resource tests fail on CI, inspect filesystem-synchronized group behavior before editing `project.pbxproj`.  |

#### Task 2 — MetaMarkerRegistry Actor

| Field        | Notes                                                                                                                                                                                                    |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | Added `MetaMarkerRegistry` actor with `shared`, bundled JSON load, actor memoization, `parseOrFallback(data:)`, strict legacy fallback, and helper accessors for binary atoms, XMP, MakerApple, guards. |
| Adaptation   | Fallback preserves current legacy `meta` / Ray-Ban detection semantics while excluding new Oakley/device-hint literals so JSON-vs-fallback remains observable in tests.                                  |
| Verification | TDD red compile failed on missing `MetaMarkerRegistry`; focused registry tests passed `6/6`; full `test_sim` passed `231` total: `230` passed, `1` documented simulator-fixture skip.                 |
| Watchpoints  | `MetaMarkerRegistry.shared` caches the first load; tests that exercise parse failures use static `parseOrFallback(data:)` rather than mutating shared actor state. No network or strip paths touched.      |

#### Task 3 — MetadataService Registry Wire-In

| Field        | Notes                                                                                                                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `MetadataService.isMetaGlassesFingerprint` is now async, loads binary atom markers from `MetaMarkerRegistry`, and applies source-type plus min-length guards. `classify` passes `isBinarySource` and byte count. |
| Adaptation   | Because legacy detection included bare `meta`, Task 3 tests intentionally prove binary bare `meta` still triggers only when the source is binary and the payload is large enough.                                |
| Tests        | Added false-positive/user-typed rejection, large binary bare-`meta`, short-payload min-length, user-typed real marker rejection, legacy Ray-Ban, and non-comment key rejection tests.                              |
| Verification | TDD red failed on old detector signature; focused registry + metadata tag tests passed `26/26`; full `test_sim` passed `237` total: `236` passed, `1` documented simulator-fixture skip.                         |
| Watchpoints  | Only video detection/classification changed; `MetadataService.strip` and stripping predicates were not edited.                                                                                                    |

#### Task 4 — PhotoMetadataService Registry Wire-In

| Field        | Notes                                                                                                                                                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key changes  | `PhotoMetadataService.xmpContainsFingerprint` and `isFingerprintTag` now read XMP/MakerApple markers from `MetaMarkerRegistry`; `makeTag` and its callers became async; XMP uses the min-length guard.                 |
| Adaptation   | Used explicit `let hit = await ...` test style instead of async autoclosure helpers to avoid XCTest autoclosure/async compile issues. Preserved all existing PhotoMedia assertions.                                    |
| Tests        | Added XMP registry marker, XMP min-length rejection, Oakley Meta MakerApple detection, and iPhone MakerApple rejection. Upgraded 7 XMP + 4 MakerApple existing calls to async.                                           |
| Verification | TDD red failed on old XMP signature; async cascade grep was completed; focused registry + photo classification tests passed `18/18`; full `test_sim` passed `241` total: `240` passed, `1` documented simulator skip. |
| Watchpoints  | Only still-photo detection/classification changed; `PhotoMetadataService.strip`, `buildRemoveDict`, and ImageIO write/remove logic were not edited.                                                                     |
