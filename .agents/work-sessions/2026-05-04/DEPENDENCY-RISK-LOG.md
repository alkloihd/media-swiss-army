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
| Open   | Signing/App Store Connect | Cluster 0 TestFlight export failed after merge while Xcode tried to download App Store app information for export/upload. | GitHub run `25305896821`: archive succeeded; `xcodebuild -exportArchive` failed with `Error Downloading App Information`, exit 70. | Treat as external App Store Connect/bundle/API-key gate; continue simulator-verified feature work on PR branches; do not edit `.github/workflows/testflight.yml` unless separately authorized. |
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
