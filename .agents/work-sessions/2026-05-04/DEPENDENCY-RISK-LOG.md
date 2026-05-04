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

| Status | Area                      | Issue                                                                                                                          | Evidence                                                                     | Next action                                                                                           |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Open   | TestFlight/manual         | Simulator cannot prove real-device `-11841` fix or photo scale-fit.                                                            | MCP `test_sim` and launch passed, but original bugs were surfaced on iPhone. | After PR #10 merge/TestFlight, user must run Cluster 0 manual prompts.                                |
| Watch  | Signing/App Store Connect | Bundle ID is now normalized to `com.alkloihd.videocompressor`; TestFlight upload requires this ID to exist/provision in Apple. | `build_run_sim` launched as `com.alkloihd.videocompressor`; PR CI is green.  | Watch TestFlight upload after merge; if signing fails, inspect Actions logs without editing workflow. |
| Watch  | Historical docs           | Older 2026-05-03 archives still mention `ca.nextclass.VideoCompressor`.                                                        | Active grep only finds old ID in append-only log/archive contexts.           | Do not rewrite historical logs unless user explicitly asks.                                           |

## Cluster Checkpoints

### Cluster 0 — PR #10

| Field                 | Notes                                                                                                                                                                                                        |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Branch / PR           | `feat/codex-cluster0-hotfixes`, PR #10                                                                                                                                                                       |
| Key changes           | Photo stitch uses baked movie dimensions; compression caps Max bitrate; writer declares SDR BT.709; frame-rate/GOP clamps; `-11841` one-shot downshift; fallback surfaced in UI; bundle identity normalized. |
| APIs changed          | `StillVideoBaker.bake(still:duration:) -> (url: URL, size: CGSize)`; `CompressionService.compress(input:settings:onProgress:) -> CompressionResult`; `CompressedOutput` includes optional fallback note.     |
| Downstream dependency | Cluster 1 must preserve the tuple return from `StillVideoBaker`; UI/model work must preserve visible fallback note rather than silently hiding downshift.                                                    |
| Verification          | `build_sim` passed; `test_sim` passed 152/152; `build_run_sim` launched as `com.alkloihd.videocompressor`; MCP UI snapshot showed Compress empty state; PR CI green.                                         |
| Not yet proven        | Real-device encoder behavior and photo stitch scale-fit on iPhone/TestFlight.                                                                                                                                |
| Human inspection      | PR #10 diff if available; App Store Connect Bundle ID/provisioning if TestFlight fails; iPhone manual prompts after TestFlight lands.                                                                        |
