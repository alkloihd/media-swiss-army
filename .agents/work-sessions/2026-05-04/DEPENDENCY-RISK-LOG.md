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
