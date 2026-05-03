# Phases 1-3 Cluster Plans — Index

> **For agentic workers:** Execute one cluster at a time, one PR per cluster, in the order listed below. Each merge to `main` produces one TestFlight build (per `AGENTS.md` Part 15). Total budget = 6 cycles, this index = 6 PRs. Use `superpowers:executing-plans` to walk each plan.

**Author:** lead session (Claude Opus 4.7), 2026-05-04
**Goal:** Decompose Phases 1-3 of `.agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md` into 6 cluster PRs (including Cluster 0 hotfixes).
**Starting point:** `main` at `4dd7525` (post-PR-9 merge + kickstarter/pbxproj chore).

---

## Cluster → Task mapping

| # | Cluster | MASTER-PLAN tasks | Branch | Effort | Plan file |
|---|---|---|---|---|---|
| 0 | **Hotfixes** | Bug 1 (compression -11841) + Bug 4 (photo scale-fit) — both real-device blockers | `feat/codex-cluster0-hotfixes` | ~3-5h | `2026-05-04-cluster0-hotfixes.md` |
| 1 | Cache & still-bake | 1.1 (TASK-01) + 1.2 (TASK-99) + 1.6 (TASK-31) | `feat/phase1-cluster1-cache-and-bake` | ~5h | `2026-05-04-phase1-cluster1-cache-and-still-bake.md` |
| 2 | Stitch correctness | 1.3 (TASK-39) + 1.4 (TASK-32) + 1.5 (TASK-33) + Bug 3 (auto-sort on import) | `feat/phase1-cluster2-stitch-correctness` | ~5h | `2026-05-04-phase1-cluster2-stitch-correctness.md` |
| 3 | UX polish & onboarding | 2.1 → 2.7 (full Phase 2) | `feat/phase2-cluster3-ux-polish` | ~12h | `2026-05-04-phase2-cluster3-ux-polish-and-onboarding.md` |
| 4 | App Store hardening | 3.1 → 3.5 | `feat/phase3-cluster4-appstore-hardening` | ~5h | `2026-05-04-phase3-cluster4-app-store-hardening.md` |
| 5 | Meta-marker registry | 3.6 (TASK-02) | `feat/phase3-cluster5-meta-marker-registry` | ~5h | `2026-05-04-phase3-cluster5-meta-marker-registry.md` |

**Phase 1-3 grand total: ~35-37h** (includes Cluster 0 hotfixes)

---

## TestFlight budget tracker

| TestFlight # | After cluster | What testers see |
|---|---|---|
| 0 | 0 (hotfixes) | Compression succeeds on all 4 presets. Photos in stitched output render full-canvas-pillarboxed instead of tiny insets. |
| 1 | 1 (cache + bake) | Stills bake instantly. Cache no longer grows after cancel/save. |
| 2 | 2 (stitch correctness — now also auto-sorts on import) | HDR videos no longer wash to SDR. Audio mix correct on mixed clips. No alias bugs after delete-reimport. Clips auto-sort oldest-first on import. |
| 3 | 3 (UX polish) | Onboarding shows on first launch. Settings explainer present. Friendlier copy. Hidden advanced presets. |
| 4 | 4 (App Store hardening) | PrivacyInfo manifest landed. Cloud CI green. Privacy policy linked from Settings. Review prompt after 3 cleans. |
| 5 | 5 (marker registry) | New devices (Oakley Meta) detected. False-positive guard prevents user-text triggers. |

**6 cycles consumed. User has relaxed the ≤5 cap — TestFlight has no hard limit. Cluster 0 ships first as a hotfix because real-device compression is broken on 3 of 4 presets.**

---

## Locked decisions (provenance)

These were locked by the user in the kickoff prompt 2026-05-04. Captured here for traceability.

1. **App Store name:** `MetaClean: AI Glasses Data` (provisional; finalize in Phase 4)
2. **Pricing:** `$4.99` one-time base. Pro IAP design deferred to Phase 6.
3. **Apple Small Business Program:** skip for now (user task, not in code plans).
4. **Long-press preview:** keep `.contextMenu(preview:)` overlay (per AUDIT-05 M2). Phase 2 task adds `Preview` as first menu item for discoverability.
5. **Compress presets:** show `Balanced` + `Small` by default. `Max` + `Streaming` + `Custom` under "Advanced" disclosure.
6. **CropEditor sliders:** hide entirely. Replace with aspect-ratio presets only (Square / 9:16 / 16:9 / Free).
7. **Adaptive Meta-marker registry:** Phase 3 cluster 5. **Bundled JSON only — no remote refresh in v1.0.**
8. **iOS Share Extension:** defer to Phase 6.
9. **Pro tier IAP:** defer all monetization to Phase 6.
10. **Local-device iteration setup (Phase 5):** not before Phase 1.
11. **TestFlight cadence:** 6 cycles total — relaxed from ≤5 because Cluster 0 hotfixes are a launch blocker. TestFlight has no per-period limit per the user's clarification 2026-05-04.
12. **Real-device testing:** TestFlight per-PR until Phase 5 `dev-iterate.sh` lands.
13. **iPhone tethered now:** no — will plug in for Phase 5.

---

## Phase 6 candidates (deferred — capture only)

These are ideas to revisit AFTER Phase 1-3 ships. Not part of the 6 cluster PRs.

### Freemium gating sketch (decision deferred to post-launch)

- Free tier: 5–10 MetaClean uses (`@AppStorage("metaCleanUsesRemaining")` decremented per save).
- Pro IAP `$9.99` one-time unlocks: unlimited MetaClean, auto-overwrite original on save, batch >10.
- Compression + Stitch stay **free at all tiers** (these are the loss-leader hooks).
- Implementation reference: `AUDIT-08` Part D and `PUBLISHING-AND-MONETIZATION.md` Part 6.

### App Store name finalization (Phase 4)

`MetaClean: AI Glasses Data` is the working name. Confirm availability in App Store Connect before submission. Backup: `MetaClean: Glasses Privacy`.

### iOS Share Extension (Phase 6)

Backlog: `.agents/work-sessions/2026-05-03/backlog-archive/BACKLOG-share-extension.md`. Adds "Share to MetaClean" from any app — ~30% conversion lift on similar utilities (AUDIT-08).

### Mac Catalyst, Apple Watch quick-clean

Per `MASTER-PLAN` Phase 6.3 + 6.4. Universal Purchase keeps the $4.99 promise across platforms.

### Auto-clean on `PHPhotoLibraryChangeObserver`

Per `MASTER-PLAN` Phase 6.5. Battery + UX needs care; defer until users ask.

---

## Non-goals for Phase 1-3

| Item | Why deferred |
|---|---|
| Pro tier IAP | Phase 6 only — base ships free at all tiers |
| Share Extension | Phase 6 |
| Remote MetaMarkers refresh | v1.0 ships bundled JSON only (decision #7) |
| Mac Catalyst | Phase 6 |
| Apple Watch app | Phase 6 |
| Phase 5 `dev-iterate.sh` | Tracked separately in MASTER-PLAN |
| Phase 4 assets (icon, screenshots, App Preview video) | Designer + manual work |
| Wipe transition rewrite (TASK-30) | Defer until users complain (per MASTER-PLAN 6.6) |
| Centroid-anchored pinch zoom (TASK-13) | Phase 6.7 |

---

## Coordination notes (cross-cluster API changes)

### Cluster 0 ↔ Cluster 1: `StillVideoBaker.bake` signature

Cluster 0 changes the bake API to return `(URL, CGSize)` instead of `URL` (so the post-bake StitchClip can use the actual baked dimensions, fixing the photo-scale-fit bug).

Cluster 1's still-bake-O(1) refactor (which drops the `duration` parameter) must preserve this `(URL, CGSize)` return type. The Cluster 1 plan currently expects a `URL` return — when Cluster 0 lands first, Cluster 1's branch will need to be rebased or the plan updated. The reviewer agent will flag this; the Codex executor should rebase Cluster 1 against post-Cluster-0 main before starting.

### Cluster 0 ↔ Cluster 2: `CompressionService.encode` retry path

Cluster 0 adds a -11841 retry-with-downshift path to `CompressionService.encode`. Cluster 2 (HDR passthrough) also touches this function. Both should land cleanly — Cluster 2 modifies the pixel format selection; Cluster 0 adds an outer retry wrapper. They don't conflict but Codex should verify by running the full test suite after each merge.

### Cluster 2 added task: auto-sort on import

The chronological-sort comparator was already correct (oldest-first); auto-sort just wasn't called on PhotosPicker import. Cluster 2 now adds this as a small Task 4 (~30 min, 1 commit). Renumbers the existing PR/merge task to Task 5.

---

## Cross-references

- `AGENTS.md` — canonical protocol (Parts 14, 15, 16 mandatory reading)
- `.agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md` — source of truth for phase scope
- `.agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md` — what audits flagged
- `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` — canonical TDD plan template (Cluster 1 inherits from this)
- `.agents/work-sessions/2026-05-03/audits/RED-TEAM-CHRONO-SORT.md` — original PR #8 chrono-sort review (referenced by Cluster 2's added task)
- `docs/superpowers/plans/2026-05-04-DIAG-compression-presets.md` — Cluster 0's bug 1 diagnosis
- `docs/superpowers/plans/2026-05-04-DIAG-photo-scale-fit.md` — Cluster 0's bug 4 diagnosis
- `docs/superpowers/plans/2026-05-04-DIAG-sort-direction.md` — Cluster 2's added task diagnosis

---

## Codex Execution Playbook

This is the runbook for the executing agent (Codex / GPT-5). Follow it in order.

### One-time setup (first time you pick up this project)

1. Read `AGENTS.md` Part 16 (Codex onboarding) end-to-end.
2. Read `docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md` for MCP verification + sim hygiene.
3. Run `mcp__xcodebuildmcp__session_show_defaults` — confirm project + scheme + simulator are set.
4. Run `mcp__xcodebuildmcp__test_sim` — confirm `Total: 138, Passed: 138`.

### Per-cluster execution loop

For each cluster (0 → 1 → 2 → 3 → 4 → 5, in order):

1. **Pick** the next unchecked cluster from `2026-05-04-PHASES-1-3-TASK-MANIFEST.md`.
2. **Sync:** `git checkout main && git pull`.
3. **Branch:** `git checkout -b feat/codex-cluster<N>-<slug>` (slug is in the manifest).
4. **Open the plan** — `docs/superpowers/plans/2026-05-04-phaseN-clusterX-<slug>.md`.
5. **Use `superpowers:subagent-driven-development`** to walk the plan task-by-task. Test first, code second, commit third — never deviate.
6. **After each commit** — append a one-line entry to `.agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md` in the format:
   ```
   [YYYY-MM-DD HH:MM IST] [solo/codex/<model>] [TAG] short summary (commit <sha>)
   ```
7. **After last commit, before PR:**
   - Tick the corresponding box in `2026-05-04-PHASES-1-3-TASK-MANIFEST.md`.
   - Update `CHANGELOG.md` with a one-paragraph summary of the cluster (group with the existing format).
   - Run `mcp__xcodebuildmcp__test_sim` one final time — expect baseline+new count.
8. **Push + PR:** `git push -u origin feat/codex-cluster<N>-<slug>` then `gh pr create --base main --head feat/codex-cluster<N>-<slug>`.
9. **Watch CI:** `gh pr checks <num> --watch`. Resolve any failures before merging.
10. **Red-team checkpoint:** before clicking merge, dispatch one read-only Opus agent to review the PR diff for: (a) any CRITICAL audit finding regression, (b) test coverage gaps, (c) silent fallbacks. Pass = merge. Fail = fix and re-push.
11. **Merge:** `gh pr merge <num> --merge`. This triggers TestFlight cycle <N>.
12. **Cleanup:** `git checkout main && git branch -d feat/codex-cluster<N>-<slug>` and `xcrun simctl shutdown all && killall Simulator`.
13. **Wait for TestFlight green** — ~12 min cycle. Then ask the user to install on their iPhone and walk the cluster's "Manual iPhone test prompts" section.
14. Only after user confirms the manual test passes, mark the cluster row "done" in the manifest. Then proceed to next cluster.

### When you encounter friction

- Plan is wrong / line numbers don't match: log it in the manifest's Deviation Log column. Use your best judgment, fix locally, surface in the PR description.
- A test you wrote (per the plan) is genuinely impossible to make pass: flag it as XCTSkip with a comment, log in deviation log, do not silently delete.
- An audit-flagged regression resurfaces: STOP, do not merge. Surface to the user.
- TestFlight build fails: check `.github/workflows/testflight.yml` (do NOT edit it). Most likely cause: signing changed or App Store Connect API key rotated.

### Logging conventions

- `AI-CHAT-LOG.md` entries: every commit, one line, IST timestamp.
- `CHANGELOG.md` entries: every PR merge, one paragraph, group by cluster.
- Manifest Deviation Log: every judgment call you make outside the plan's letter.

### Hard rules (from AGENTS.md Parts 10 + 14 + 16)

- Never push to `main` directly. Always PR.
- Never call `mcp__xcodebuildmcp__session_set_defaults`.
- Don't introduce CoreHaptics or custom AVVideoCompositing.
- Don't touch `.github/workflows/testflight.yml`.
- 6 TestFlight cycles total across all 6 clusters (= 1 per cluster). Cluster 0 ships first as a launch-blocker hotfix.
- Quit Simulator after every session (sim hygiene).
- Don't run more than 2 background agents in parallel.
