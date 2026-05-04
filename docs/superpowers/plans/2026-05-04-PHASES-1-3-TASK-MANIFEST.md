# Phases 1-3 Task Manifest

> Codex: tick each box as you complete each sub-task. Use the **Comments** column to record any deviation from the plan, judgment call, or finding you want the user to see during PR review. Do not delete or rewrite the plan files — log deviations here instead.

## How to use

1. Pick the next un-checked cluster (top-down).
2. Open the corresponding plan file in `docs/superpowers/plans/`.
3. Branch: `git checkout -b feat/codex-cluster<N>-<slug>` off `main`.
4. Walk the plan task-by-task using `superpowers:subagent-driven-development`.
5. Tick boxes here as you commit each sub-task.
6. After PR merges to main and TestFlight green, mark the cluster row done.

---

## Cluster 0 — Hotfixes (Bug 1 -11841 + Bug 4 photo scale-fit)

**Plan:** `docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md`
**Branch:** `feat/codex-cluster0-hotfixes`
**Effort:** ~3-5h | **Commits:** ≤10 (currently planned 7) | **TestFlight cycle:** #0 (lands FIRST)

| ✓   | Sub-task                                                            | Comments                                                                                                                                                                                                                                                                          |
| --- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ☑   | Task 1: StillVideoBaker.bake returns (URL, CGSize)                  | Combined with Task 2 atomically because the signature change intentionally breaks callers until `StitchExporter` consumes the tuple. TDD red: `test_sim` failed on `URL` lacking `url`/`size`; green: `139/139` simulator tests.                                                  |
| ☑   | Task 2: StitchExporter.buildPlan uses bake's CGSize for naturalSize | Completed in the same commit as Task 1; `StitchClip.naturalSize` now uses the baked movie dimensions from `StillVideoBaker`.                                                                                                                                                      |
| ☑   | Task 3: Cap Max preset bitrate to ≤ source bitrate                  | Updated the existing old-contract test plus added plan regressions; TDD red failed three Max-only assertions, then `test_sim` passed `141/141`.                                                                                                                                   |
| ☑   | Task 4: Add SDR AVVideoColorPropertiesKey defensive defaults        | Combined with Task 5 because both modify `CompressionService` writer settings; TDD red compile-failed on missing helper APIs, then `test_sim` passed `144/144`.                                                                                                                   |
| ☑   | Task 5: Clamp framerate / GOP keys for high-bitrate paths           | Completed with Task 4; added helper-shape tests for 120 fps frame-rate clamp and 60-frame GOP clamp. Also cleaned low-severity stale bitrate comments from Task 3 review.                                                                                                         |
| ☑   | Task 6: -11841 retry-with-downshift in CompressionService.encode    | Adapted to return `CompressionResult` so fallback is not silent: `VideoLibrary` stores the actual preset used and `CompressedOutput.note` surfaces the fallback note in the row UI. Added deterministic synthetic `-11841` retry tests after review; `test_sim` passed `152/152`. |
| ☐   | Task 7: Push, PR, CI, merge → TestFlight #0                         | PR #10 merged to `main` as `f1e08d5`, but TestFlight run `25305896821` failed at export/upload with `Error Downloading App Information` after archive succeeded. Phone/manual gate remains blocked.                                                                               |

---

## Cluster 1 — Cache & Still Bake (Phase 1.1 + 1.2 + 1.6)

**Plan:** `docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md`
**Branch:** `feat/codex-cluster1-cache-and-bake`
**Effort:** ~5h | **Commits:** ≤10 | **TestFlight cycle:** #1

| ✓   | Sub-task                                                              | Comments                                                                                                                                                                                                                                                                        |
| --- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ☑   | Task 1: Still-bake O(1) (incl. bake-cancel reg order)                 | Added future-API tests first; red compile failed on missing `bake(still:)`, then green `test_sim` passed `155/155`. Preserved tuple return, added preallocated URL registration, and stretched 1s baked stills via `scaleTimeRange`. Reviewer agent timed out and was closed.   |
| ☑   | Task 2: Extend CacheSweeper — tmp dirs, sweepOnCancel, sweepAfterSave | Added red tests for missing APIs, then implemented managed tmp support for `StillBakes`, `Picks-*`, and `PhotoClean-*`; `test_sim` passed `163/163`. Production `sweepAfterSave` keeps 30s delay with a testable short-delay overload. Reviewer agent timed out and was closed. |
| ☑   | Task 3: Wire sweepOnCancel/sweepAfterSave into all cancel/save sites  | Integrated cancel/failure cleanup in compression, stitch passthrough, video metadata strip, photo metadata strip, and photo compression paths. `VideoLibrary` save now uses delayed output sweep. Adapted MetaClean/Stitch save hooks to the actual Photos save-success views instead of export/clean completion so sandbox outputs are not removed before the user saves them. `test_sim` passed `163/163`. |
| ☐   | Task 4: Push, PR, CI, merge → TestFlight #1                           | PR #11 merged to `main` as `5e57fa9`; PR CI and main CI passed. TestFlight run `25307940461` failed at export/upload with `Error Downloading App Information`, exit 70, after archive succeeded. Manual iPhone gate remains blocked.                                          |

---

## Cluster 2 — Stitch Correctness (Phase 1.3 + 1.4 + 1.5)

**Plan:** `docs/superpowers/plans/2026-05-04-phase1-cluster2-stitch-correctness.md`
**Branch:** `feat/codex-cluster2-stitch-correctness`
**Effort:** ~5h | **Commits:** ≤8 (currently planned 7) | **TestFlight cycle:** #2

| ✓   | Sub-task                                                             | Comments |
| --- | -------------------------------------------------------------------- | -------- |
| ☑   | Task 1: HDR passthrough (detect 10-bit + color properties)           | Adapted stale snippets: writer already had SDR color properties from Cluster 0, so 10-bit detection was moved before writer settings and `AVVideoProfileLevelKey` now selects HEVC Main10 for 10-bit sources. TDD red compile-failed on missing `pixelBufferDict`; green: XcodeBuildMCP CLI `simulator test` passed `168/168` after MCP `test_sim` timed out at 120s. |
| ☑   | Task 2: Audio mix track parity (per-segment audioTrack)              | Adapted plan per scout: kept immediate timeline-neighbor fade windows so audio fades into/out of stills, but skipped silent segments and grouped input parameters by composition track ID. TDD red failed with 3 audio-mix params for `[video, still, video]`; green `test_sim` passed `169/169`. |
| ☑   | Task 3: Stage filename collision (always UUID-prefix)                | Added a static staging test hook and changed staging to always lowercased 6-char UUID prefix. Test adapted to use `.mov` source files so suggested `clip.mov` stages as `xxxxxx-clip.mov`. TDD red compile-failed on missing hook; green XcodeBuildMCP CLI `simulator test` passed `170/170` after MCP timeout. |
| ☑   | Task 4: Auto-sort imports oldest-first (Bug 3 / DIAG-sort-direction) | Added a tested `finalizeImportOrdering` seam and called it after `importClips` completes, instead of only testing `sortByCreationDateAsync()` directly. TDD red compile-failed on missing hook; green XcodeBuildMCP CLI `simulator test` passed `171/171` after MCP timeout. |
| ☐   | Task 4.5: Device Stitch -11841 + re-render gate                      | Added after TestFlight real-device report on `main@936cafb`: Stitch `Small` exports can still throw raw AVFoundation `-11841`, and re-render after Photos save can fail. Must root-cause, test, fix, and verify before Cluster 2 PR. |
| ☐   | Task 5: Push, PR, CI, merge → TestFlight #2                          |          |

---

## Cluster 3 — UX Polish & Onboarding (Phase 2.1 — 2.7)

**Plan:** `docs/superpowers/plans/2026-05-04-phase2-cluster3-ux-polish-and-onboarding.md` _(in progress)_
**Branch:** `feat/codex-cluster3-ux-polish`
**Effort:** ~12h | **Commits:** ≤10 | **TestFlight cycle:** #3

| ✓   | Sub-task                                                          | Comments |
| --- | ----------------------------------------------------------------- | -------- |
| ☐   | Task 1: Dev-y copy polish (TASK-04)                               |          |
| ☐   | Task 2: Onboarding screen — 3-card paged (TASK-05)                |          |
| ☐   | Task 3: Settings "What MetaClean does" explainer (TASK-10)        |          |
| ☐   | Task 4: Long-press preview decision (TASK-12)                     |          |
| ☐   | Task 5: Drop indicator polish (TASK-45)                           |          |
| ☐   | Task 6: Faster batch MetaClean + single-toast (TASK-03 + TASK-06) |          |
| ☐   | Task 7: Frontend simplifications — presets + sliders (TASK-46)    |          |
| ☐   | Task 8: Push, PR, CI, merge → TestFlight #3                       |          |

---

## Cluster 4 — App Store Hardening (Phase 3.1 — 3.5)

**Plan:** `docs/superpowers/plans/2026-05-04-phase3-cluster4-app-store-hardening.md` _(in progress)_
**Branch:** `feat/codex-cluster4-appstore-hardening`
**Effort:** ~5h | **Commits:** ≤7 | **TestFlight cycle:** #4

| ✓   | Sub-task                                         | Comments |
| --- | ------------------------------------------------ | -------- |
| ☐   | Task 1: Privacy manifest (TASK-34)               |          |
| ☐   | Task 2: Photos auth gate (TASK-35)               |          |
| ☐   | Task 3: Apple-specific CI checks (TASK-18)       |          |
| ☐   | Task 4: Privacy policy on GitHub Pages (TASK-07) |          |
| ☐   | Task 5: SKStoreReviewController prompt (TASK-09) |          |
| ☐   | Task 6: Push, PR, CI, merge → TestFlight #4      |          |

---

## Cluster 5 — Meta-Marker Registry (Phase 3.6 / TASK-02)

**Plan:** `docs/superpowers/plans/2026-05-04-phase3-cluster5-meta-marker-registry.md` _(in progress)_
**Branch:** `feat/codex-cluster5-meta-marker-registry`
**Effort:** ~5h | **Commits:** ≤8 | **TestFlight cycle:** #5

| ✓   | Sub-task                                                     | Comments |
| --- | ------------------------------------------------------------ | -------- |
| ☐   | Task 1: Resource JSON schema + bundled MetaMarkers.json      |          |
| ☐   | Task 2: Registry actor + binaryAtomMarkers / xmpFingerprints |          |
| ☐   | Task 3: MetadataService wire-in + false-positive guards      |          |
| ☐   | Task 4: PhotoMetadataService wire-in                         |          |
| ☐   | Task 5: Registry tests (unit + integration)                  |          |
| ☐   | Task 6: Push, PR, CI, merge → TestFlight #5                  |          |

---

## Completion checklist (final)

- [ ] All 6 cluster PRs merged to main
- [ ] All 6 TestFlight cycles consumed (cap relaxed per user 2026-05-04)
- [ ] 138+ baseline tests still pass on every PR
- [ ] No CRITICAL audit findings introduced (verified by red-team review on each PR)
- [ ] Codex appended a session log entry for each merge to `.agents/work-sessions/<date>/AI-CHAT-LOG.md`
- [ ] CHANGELOG.md updated with Phase 1-3 summary

---

## Deviation log

| Date       | Cluster    | Sub-task      | What I deviated and why                                                                                                                                                                                                                                                                                                                                          | Outcome                                                                                          |
| ---------- | ---------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| 2026-05-04 | (planning) | (n/a)         | Added Cluster 0 hotfix PR after real-device testing surfaced -11841 + photo scale-fit bugs. TestFlight cap raised from ≤5 to 6 (user clarified TestFlight has no hard limit).                                                                                                                                                                                    | Pending Codex execution                                                                          |
| 2026-05-04 | 0          | preflight     | Read-only plan-vs-code scan found current-code drift. Codex will preserve the Cluster 0 behavioral contract but adapt snippets: combine baker tuple + StitchExporter use atomically, use valid >=32px fixtures, update existing Max-bitrate test contract, use Swift-valid retry structure, and surface fallback/downshift state rather than DEBUG-only logging. | Captured before implementation                                                                   |
| 2026-05-04 | 0          | Task 6        | Plan returned only `URL` and relied on DEBUG logs for fallback visibility. Codex changed `CompressionService.compress` to return `CompressionResult(url, settings, fallbackMessage)` and threaded that through `VideoLibrary`, `CompressedOutput`, and `VideoRowView` so the actual preset and fallback note are user-visible.                                   | `test_sim` passed 150/150                                                                        |
| 2026-05-04 | 0          | Task 6 review | Reviewer found retry result shape was not deterministic under synthetic `-11841`. Codex extracted `runWithOneShotDownshift` as a test seam and added tests for fallback result settings/message plus one-shot double-failure behavior.                                                                                                                           | `test_sim` passed 152/152                                                                        |
| 2026-05-04 | 0          | PR pre-merge  | User flagged bundle identity mismatch after verification. Codex normalized active project/docs to `com.alkloihd.videocompressor` instead of leaving the project on historical `ca.nextclass.VideoCompressor`. Historical 2026-05-03 logs/archives were not rewritten.                                                                                            | `build_sim` succeeded; `test_sim` passed 152/152; app launched as `com.alkloihd.videocompressor` |
| 2026-05-04 | 1          | preflight     | Read-only agents found plan snippets were stale against current code. Codex adapted by using >=32px test fixtures, counting from the 152-test Cluster 0 baseline, avoiding brittle wall-clock assertions, and using explicit cleanup around preallocated still-bake output.                                                                                      | Captured before implementation                                                                   |
| 2026-05-04 | 1          | Task 1 review | Focused reviewer agent timed out after the implementation. Codex closed the reviewer and proceeded based on TDD evidence: compile-red on future API, then green `test_sim` with 155/155.                                                                                                                                                                         | `test_sim` passed 155/155                                                                        |
| 2026-05-04 | 1          | Task 2 review | CacheSweeper worker and focused reviewer agents timed out. Codex closed both and implemented locally with TDD evidence: compile-red on missing cache lifecycle APIs, then green `test_sim` with 163/163.                                                                                                                                                         | `test_sim` passed 163/163                                                                        |
| 2026-05-04 | 1          | Task 3        | The plan named `MetaCleanQueue.runClean` and `StitchProject.runExport` as save sites, but current code saves those outputs to Photos in `MetaCleanExportSheet` and `StitchExportSheet`. Codex wired `sweepAfterSave` at the actual Photos save-success sites and left clean/export completion as file-production states to avoid deleting outputs before a user saves them.                     | `test_sim` passed 163/163                                                                        |
| 2026-05-04 | 2          | Task 1        | HDR plan snippets assumed writer color properties were absent and `is10Bit` could be introduced near the reader block. Current code already had SDR color defaults from Cluster 0, so Codex loaded format descriptions before writer setup, reused `AVVideoProfileLevelKey` for Main10 selection, and used XcodeBuildMCP CLI for the full test because the MCP tool timed out at 120s. | XcodeBuildMCP CLI `simulator test` passed 168/168                                                 |
| 2026-05-04 | 2          | Task 2        | Audio plan suggested computing fades against previous/next audible segments. Scout review showed that would remove fade windows around stills, so Codex kept immediate timeline-neighbor overlap calculations and changed only track ownership/parameter grouping.                                                                                         | `test_sim` passed 169/169                                                                        |
| 2026-05-04 | 2          | Task 3        | Stage-collision test was adapted from the plan to use `.mov` source fixture names; using `.tmp` sources would correctly preserve the source extension and fail the planned `clip.mov` filename assertion for the wrong reason.                                                                                                                             | XcodeBuildMCP CLI `simulator test` passed 170/170                                                |
| 2026-05-04 | 2          | Task 4        | The plan's proposed auto-sort test would call `sortByCreationDateAsync()` directly and pass before production changed. Codex added a small `StitchTabView.finalizeImportOrdering` seam, calls it from `importClips`, and tests that seam with newest-first clips.                                                                                         | XcodeBuildMCP CLI `simulator test` passed 171/171                                                |
| 2026-05-04 | 2          | Task 4.5      | Real-device TestFlight feedback on `main@936cafb` exposed Stitch failures that the simulator suite missed. Codex added an explicit Cluster 2 gate instead of opening the PR on simulator-only evidence.                                                                                                                                            | In progress                                                                                     |
