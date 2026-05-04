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
| ☑   | Task 4.5: Device Stitch -11841 + re-render gate                      | Added after TestFlight real-device report on `main@936cafb`. Stitch re-encode now retries `-11841` with stitch-specific downshift, `Small -> Streaming`, and transition exports rebuild without transitions before preset retry if the transition composition is rejected. Finished Stitch exports now expose `Export Again`, stale swept outputs no longer offer Save, and fallback notes surface in the sheet. Verification: `build_sim` succeeded; `test_sim` passed `182` total (`181` passed, `1` documented simulator-fixture skip). |
| ☑   | Task 5: Push, PR, CI, merge → TestFlight #2                          | PR #13 merged to `main` as `1d886cc`; PR checks passed. TestFlight workflow run `25317235711` succeeded in 2m59s. Real iPhone confirmation for the original Stitch encoder/report remains pending after the user installs the TestFlight build. |

---

## Cluster 3 — UX Polish & Onboarding (Phase 2.1 — 2.7)

**Plan:** `docs/superpowers/plans/2026-05-04-phase2-cluster3-ux-polish-and-onboarding.md` _(in progress)_
**Branch:** `feat/codex-cluster3-ux-polish`
**Effort:** ~12h | **Commits:** ≤10 | **TestFlight cycle:** #3

| ✓   | Sub-task                                                          | Comments |
| --- | ----------------------------------------------------------------- | -------- |
| ☑   | Task 1: Dev-y copy polish (TASK-04)                               | Added `BatchCleanProgress.userFacingLabel(kind:)`, wired friendlier MetaClean batch/export copy, wrapped the stale-clip debug print in `#if DEBUG`, and removed the duplicate header scissors action. TDD red: missing helper compile failure; green `test_sim` passed 186 total, 185 passed, 1 documented skip. |
| ☑   | Task 2: Onboarding screen — 3-card paged (TASK-05)                | Added `OnboardingGate` pure logic and first-launch `OnboardingView`, wired `ContentView` via `@AppStorage("hasSeenOnboarding_v1")`, and routes Get started to MetaClean. TDD red: missing `OnboardingGate`; green `test_sim` passed 190 total, 189 passed, 1 documented skip. |
| ☑   | Task 3: Settings "What MetaClean does" explainer (TASK-10)        | Inserted the MetaClean explainer as the first Settings section with three disclosure groups and accessibility identifier. Verification: `test_sim` passed 190 total, 189 passed, 1 documented skip; `build_sim` succeeded. |
| ☑   | Task 4: Long-press preview decision (TASK-12)                     | Added Preview as the first Stitch clip context-menu item and a sheet that reuses `ClipLongPressPreview`. Adapted plan by keeping `ClipLongPressPreview` private because the sheet is in the same file. Verification: `test_sim` passed 190 total, 189 passed, 1 documented skip; `build_sim` succeeded. |
| ☑   | Task 5: Drop indicator polish (TASK-45)                           | Updated Stitch timeline drop target affordance to 8pt accent bar, soft accent shadow, and 12pt animated gutter on the target clip. Verification: `test_sim` passed 190 total, 189 passed, 1 documented skip; `build_sim` succeeded. |
| ☑   | Task 6: Faster batch MetaClean + single-toast (TASK-03 + TASK-06) | Added `MetaCleanQueue.batchConcurrency`, completed-count batch progress, `SaveBatchResult`, `VideoLibrary.lastSaveBatch`, and a MetaClean batch-save toast. Adapted the plan by using a callback from `MetaCleanTabView` instead of a static global sink, and by keeping Photos save/delete serial while metadata stripping is bounded-concurrent. TDD red: missing helper/result compile failure; green focused MetaClean tests passed 12/12 after a small label-start red/green; full `test_sim` passed 198 total, 197 passed, 1 documented skip; `build_sim` succeeded. |
| ☑   | Task 7: Frontend simplifications — presets + sliders (TASK-46)    | Replaced CropEditor XYWH sliders with tested aspect presets, added the same crop preset grid to the live `ClipEditorInlinePanel`, moved Max/Streaming under PresetPicker Advanced, and collapsed Settings performance under Advanced. Adapted crop math to use display size for rotated portrait identity collapse and preserved crop identity as `nil`. TDD red: missing `cropRect`/preset enum; green focused crop tests passed 7/7, `clean` succeeded, full `test_sim` passed 205 total, 204 passed, 1 documented skip; `build_sim` succeeded. |
| ☐   | Task 8: Push, PR, CI, merge → TestFlight #3                       |          |

---

## Cluster 4 — App Store Hardening (Phase 3.1 — 3.5)

**Plan:** `docs/superpowers/plans/2026-05-04-phase3-cluster4-app-store-hardening.md` _(in progress)_
**Branch:** `feat/codex-cluster4-appstore-hardening`
**Effort:** ~5h | **Commits:** ≤7 | **TestFlight cycle:** #4

| ✓   | Sub-task                                         | Comments |
| --- | ------------------------------------------------ | -------- |
| ☑   | Task 1: Privacy manifest (TASK-34)               | Added bundled `PrivacyInfo.xcprivacy` with UserDefaults `CA92.1`, FileTimestamp `C617.1`, DiskSpace `E174.1`, no tracking, no domains, and no collected data. Added manifest parser tests. TDD red: manifest missing from app bundle; green after `clean`, `plutil -lint` OK, focused tests passed 3/3, full `test_sim` passed 208 total, 207 passed, 1 documented skip. |
| ☑   | Task 2: Photos auth gate (TASK-35)               | Added passive `PHPhotoLibrary.authorizationStatus(for: .readWrite)` gating to both `StitchClipFetcher` fetch paths with defaulted auth/fetch test injection. Added 8 auth tests covering denied-state no-fetch short-circuiting plus authorized/limited fetch continuation. TDD red: missing `authStatusProvider`, then missing fetch provider seam after review; green focused tests passed 8/8, full `test_sim` passed 216 total, 215 passed, 1 documented skip. |
| ☑   | Task 3: SKStoreReviewController prompt (TASK-09) | Added `ReviewPrompter` with UserDefaults-backed count/version gating and iOS 18 `AppStore.requestReview(in:)` plus `SKStoreReviewController` fallback. Integrated after successful single Photos save and once per batch using actual saved count. Adapted plan away from strip-only success. TDD red: missing `ReviewPrompter`, then actor-isolated default closure compile failure; green focused tests passed 9/9, full `test_sim` passed 225 total, 224 passed, 1 documented skip. |
| ☑   | Task 4: Privacy policy on GitHub Pages (TASK-07) | Added `docs/privacy/index.html` for the locked GitHub Pages URL and a Settings About section linking to it. Adapted the SwiftUI section initializer after TDD compile-red on `Section("About") { } footer:` in the current SDK. Verification: `npx prettier --check docs/privacy/index.html` passed after formatting; focused tests passed 9/9; full `test_sim` passed 225 total, 224 passed, 1 documented skip. |
| ☑   | Task 5: Apple-specific CI checks (TASK-18)       | Added `iOS XCTest` PR job to `.github/workflows/ci.yml` only. Adapted plan to actual target `VideoCompressor_iOSTests`, avoided `xcbeautify` dependency, used `set -euo pipefail`, and selected iPhone 17 Pro / 16 Pro / first available iPhone Pro at runtime for runner drift. Verification: YAML parse passed, Prettier check passed, `xcodebuild -list` confirmed target/scheme, CI-style `test_sim -only-testing:VideoCompressor_iOSTests CODE_SIGNING_ALLOWED=NO` passed 225 total, 224 passed, 1 documented skip. |
| ☐   | Task 6: Push, PR, CI, merge → TestFlight #4      |          |

---

## Cluster 5 — Meta-Marker Registry (Phase 3.6 / TASK-02)

**Plan:** `docs/superpowers/plans/2026-05-04-phase3-cluster5-meta-marker-registry.md` _(in progress)_
**Branch:** `feat/codex-cluster5-meta-marker-registry`
**Effort:** ~5h | **Commits:** ≤8 | **TestFlight cycle:** #5

| ✓   | Sub-task                                                     | Comments |
| --- | ------------------------------------------------------------ | -------- |
| ☑   | Task 1: Resource JSON schema + bundled MetaMarkers.json      | Added bundled `VideoCompressor/ios/Resources/MetaMarkers.json` and resource-presence test. Adapted the plan JSON to preserve current binary video atom and MakerApple legacy bare-`meta` detection while keeping bare `meta` out of XMP. TDD red: resource missing; green after `clean`, focused bundle test passed 1/1; Prettier check passed. |
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
| 2026-05-04 | 2          | Task 4.5      | Real-device TestFlight feedback on `main@936cafb` exposed Stitch failures that the simulator suite missed. Codex added an explicit Cluster 2 gate instead of opening the PR on simulator-only evidence. The synthetic Random+Small full encode test can enter the fallback path on simulator but then AVFoundation rejects the synthetic composition with a generic error after `-11841`; Codex left that test as `XCTSkip` with a comment and covered retry/downshift deterministically with synthetic `CompressionError`, raw `NSError` `-11841`, and transition-drop ordering tests. | `build_sim` succeeded; `test_sim` passed 182 total, 181 passed, 1 skipped                      |
| 2026-05-04 | 3          | Task 6        | The plan proposed a static weak `VideoLibrary` sink and concurrent Photos saves inside TaskGroup children. Scout review found preview/test lifetime risk and `PHPhotoLibrary.performChanges` contention risk, so Codex routed save completion through an injected callback from `MetaCleanTabView`, kept Photos save/delete serial in the result drain, preserved cache cleanup after successful saves, and tracked save failures separately from strip failures for toast copy. | `test_sim` passed 198 total, 197 passed, 1 skipped; `build_sim` succeeded                      |
| 2026-05-04 | 3          | Task 7        | The plan rewrote `CropEditorView`, but the current live Stitch surface uses `ClipEditorInlinePanel`; Codex reused the new preset grid in both places so the simplification is reachable. Crop math was adapted to account for `displaySize`/rotated portrait clips and collapse identity crops to `nil`; Settings uses a plain `Advanced` disclosure per plan, though scout noted `Advanced Performance` would be clearer. | `clean` succeeded; `test_sim` passed 205 total, 204 passed, 1 skipped; `build_sim` succeeded                      |
| 2026-05-04 | 4          | Task 2        | The plan text wanted all three denied-status states across both fetch paths, but its snippet omitted the batch `.restricted` case and referenced `PhotosSaver`'s prompting pattern. Codex added the sixth batch `.restricted` test and used only passive `authorizationStatus(for: .readWrite)`, never `requestAuthorization`, so Stitch sorting cannot trigger a Photos prompt. A reviewer then noted fake IDs alone did not prove fetch short-circuiting, so Codex added injectable fetch seams and authorized/limited continuation tests. | Focused auth tests passed 8/8; full `test_sim` passed 216 total, 215 passed, 1 skipped |
| 2026-05-04 | 4          | Task 3        | The manifest row labels had ReviewPrompter and CI swapped relative to the canonical Cluster 4 plan, so Codex normalized the row labels to the plan order while preserving task IDs. The plan also wired prompts at metadata-strip success and used `@AppStorage`; scout review showed the safer product/App Review point is after actual Photos save success, so Codex used a service-layer UserDefaults prompter and counted single saves plus batch savedCount only. The plan's iOS 17 note is stale because the project targets iOS 18, so production uses `AppStore.requestReview(in:)` with SKStore fallback. | Focused ReviewPrompter tests passed 9/9; full `test_sim` passed 225 total, 224 passed, 1 skipped |
