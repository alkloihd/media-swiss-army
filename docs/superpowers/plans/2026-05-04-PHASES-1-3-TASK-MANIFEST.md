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

| ✓ | Sub-task | Comments |
|---|---|---|
| ☑ | Task 1: StillVideoBaker.bake returns (URL, CGSize) | Combined with Task 2 atomically because the signature change intentionally breaks callers until `StitchExporter` consumes the tuple. TDD red: `test_sim` failed on `URL` lacking `url`/`size`; green: `139/139` simulator tests. |
| ☑ | Task 2: StitchExporter.buildPlan uses bake's CGSize for naturalSize | Completed in the same commit as Task 1; `StitchClip.naturalSize` now uses the baked movie dimensions from `StillVideoBaker`. |
| ☑ | Task 3: Cap Max preset bitrate to ≤ source bitrate | Updated the existing old-contract test plus added plan regressions; TDD red failed three Max-only assertions, then `test_sim` passed `141/141`. |
| ☐ | Task 4: Add SDR AVVideoColorPropertiesKey defensive defaults | |
| ☐ | Task 5: Clamp framerate / GOP keys for high-bitrate paths | |
| ☐ | Task 6: -11841 retry-with-downshift in CompressionService.encode | |
| ☐ | Task 7: Push, PR, CI, merge → TestFlight #0 | |

---

## Cluster 1 — Cache & Still Bake (Phase 1.1 + 1.2 + 1.6)

**Plan:** `docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md`
**Branch:** `feat/codex-cluster1-cache-and-bake`
**Effort:** ~5h | **Commits:** ≤10 | **TestFlight cycle:** #1

| ✓ | Sub-task | Comments |
|---|---|---|
| ☐ | Task 1: Still-bake O(1) (incl. bake-cancel reg order) | |
| ☐ | Task 2: Extend CacheSweeper — tmp dirs, sweepOnCancel, sweepAfterSave | |
| ☐ | Task 3: Wire sweepOnCancel/sweepAfterSave into all cancel/save sites | |
| ☐ | Task 4: Push, PR, CI, merge → TestFlight #1 | |

---

## Cluster 2 — Stitch Correctness (Phase 1.3 + 1.4 + 1.5)

**Plan:** `docs/superpowers/plans/2026-05-04-phase1-cluster2-stitch-correctness.md`
**Branch:** `feat/codex-cluster2-stitch-correctness`
**Effort:** ~5h | **Commits:** ≤8 (currently planned 7) | **TestFlight cycle:** #2

| ✓ | Sub-task | Comments |
|---|---|---|
| ☐ | Task 1: HDR passthrough (detect 10-bit + color properties) | |
| ☐ | Task 2: Audio mix track parity (per-segment audioTrack) | |
| ☐ | Task 3: Stage filename collision (always UUID-prefix) | |
| ☐ | Task 4: Auto-sort imports oldest-first (Bug 3 / DIAG-sort-direction) | |
| ☐ | Task 5: Push, PR, CI, merge → TestFlight #2 | |

---

## Cluster 3 — UX Polish & Onboarding (Phase 2.1 — 2.7)

**Plan:** `docs/superpowers/plans/2026-05-04-phase2-cluster3-ux-polish-and-onboarding.md` *(in progress)*
**Branch:** `feat/codex-cluster3-ux-polish`
**Effort:** ~12h | **Commits:** ≤10 | **TestFlight cycle:** #3

| ✓ | Sub-task | Comments |
|---|---|---|
| ☐ | Task 1: Dev-y copy polish (TASK-04) | |
| ☐ | Task 2: Onboarding screen — 3-card paged (TASK-05) | |
| ☐ | Task 3: Settings "What MetaClean does" explainer (TASK-10) | |
| ☐ | Task 4: Long-press preview decision (TASK-12) | |
| ☐ | Task 5: Drop indicator polish (TASK-45) | |
| ☐ | Task 6: Faster batch MetaClean + single-toast (TASK-03 + TASK-06) | |
| ☐ | Task 7: Frontend simplifications — presets + sliders (TASK-46) | |
| ☐ | Task 8: Push, PR, CI, merge → TestFlight #3 | |

---

## Cluster 4 — App Store Hardening (Phase 3.1 — 3.5)

**Plan:** `docs/superpowers/plans/2026-05-04-phase3-cluster4-app-store-hardening.md` *(in progress)*
**Branch:** `feat/codex-cluster4-appstore-hardening`
**Effort:** ~5h | **Commits:** ≤7 | **TestFlight cycle:** #4

| ✓ | Sub-task | Comments |
|---|---|---|
| ☐ | Task 1: Privacy manifest (TASK-34) | |
| ☐ | Task 2: Photos auth gate (TASK-35) | |
| ☐ | Task 3: Apple-specific CI checks (TASK-18) | |
| ☐ | Task 4: Privacy policy on GitHub Pages (TASK-07) | |
| ☐ | Task 5: SKStoreReviewController prompt (TASK-09) | |
| ☐ | Task 6: Push, PR, CI, merge → TestFlight #4 | |

---

## Cluster 5 — Meta-Marker Registry (Phase 3.6 / TASK-02)

**Plan:** `docs/superpowers/plans/2026-05-04-phase3-cluster5-meta-marker-registry.md` *(in progress)*
**Branch:** `feat/codex-cluster5-meta-marker-registry`
**Effort:** ~5h | **Commits:** ≤8 | **TestFlight cycle:** #5

| ✓ | Sub-task | Comments |
|---|---|---|
| ☐ | Task 1: Resource JSON schema + bundled MetaMarkers.json | |
| ☐ | Task 2: Registry actor + binaryAtomMarkers / xmpFingerprints | |
| ☐ | Task 3: MetadataService wire-in + false-positive guards | |
| ☐ | Task 4: PhotoMetadataService wire-in | |
| ☐ | Task 5: Registry tests (unit + integration) | |
| ☐ | Task 6: Push, PR, CI, merge → TestFlight #5 | |

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

| Date | Cluster | Sub-task | What I deviated and why | Outcome |
|---|---|---|---|---|
| 2026-05-04 | (planning) | (n/a) | Added Cluster 0 hotfix PR after real-device testing surfaced -11841 + photo scale-fit bugs. TestFlight cap raised from ≤5 to 6 (user clarified TestFlight has no hard limit). | Pending Codex execution |
| 2026-05-04 | 0 | preflight | Read-only plan-vs-code scan found current-code drift. Codex will preserve the Cluster 0 behavioral contract but adapt snippets: combine baker tuple + StitchExporter use atomically, use valid >=32px fixtures, update existing Max-bitrate test contract, use Swift-valid retry structure, and surface fallback/downshift state rather than DEBUG-only logging. | Captured before implementation |
