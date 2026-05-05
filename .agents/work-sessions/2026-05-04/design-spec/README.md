# Design Spec — 2026-05-04 user handoff folder

This folder holds three implementation specs that the user (Rishaal) approved at 17:32 SAST on 2026-05-04. They are ordered by priority. Any agent picking up this work — restarted Codex / a fresh Claude session / a subagent — should walk them in this order.

| Order | File | Scope | Priority | Effort |
|---|---|---|---|---|
| 1 | `1-cluster-2.5-stitch-hotfix.md` | Three small UX/correctness fixes for the Stitch flow that real-device testing surfaced after Cluster 2 merged | **P0** — user-blocking | 1–2h |
| 2 | `2-cluster-3.5-visual-calm-cinema.md` | Re-do of Cluster 3 visual polish — applies the "calm glass + cinematic accent" direction the user picked over Codex's initial microcopy-only Cluster 3 ship | P1 — pre-launch polish | 6–10h |
| 3 | `3-cluster-6-snap-mode-multicam.md` | New flagship feature: in-app multi-camera capture session with pause/resume across app-background, modeled on the LG G6 "Snap" mode — destined to be the premium-tier hook | P2 — squeeze before launch if possible, otherwise v1.1 | 16–24h |

## Context for the agent

- All seven PRs from 2026-05-04 (#10–#16) are MERGED to `main`. Current `main` HEAD: `6d7941e`.
- Codex's autopilot session ended at 16:51 SAST (`[SESSION-COMPLETE]`); its conversation context is gone, only on-disk artifacts and AI-CHAT-LOG entries remain.
- An independent code review (logged at 17:25 SAST) confirmed:
  - Cluster 2 stitch fix is **partial** for `-11841`-on-transitions (only Max → Balanced → Small downshift, no Streaming/Custom coverage, no usable error message when the table runs out)
  - Cluster 2 `sweepAfterSave` scope is **correct** (re-render after save works)
  - "Clear all clips / start over" affordance is **entirely missing** in `StitchTabView` and `StitchProject`
  - Cluster 3 shipped microcopy + onboarding + simplified preset picker, **not** the calm-glass visual direction
  - Future stitch-pipeline PRs MUST require a real-device smoke test (sim is meaningless for encoder envelope rejection on iPhone 18 hardware)

## Branching guidance

- Each spec ships as its own branch + PR off the latest `main`. Do NOT stack PRs.
- Hotfix (#1) lands first; Visual redo (#2) and Snap-mode (#3) can be parallelised after #1 merges.
- Bundle id is locked to `ca.nextclass.VideoCompressor` per AGENTS.md banner — do NOT touch `PRODUCT_BUNDLE_IDENTIFIER` or any signing-related string.
- Every PR that touches `StitchExporter.swift` / `CompressionService.swift` / `CaptureSession` / capture pipelines MUST request real-device verification from the user via a `[BLOCKED]` line in AI-CHAT-LOG before merging. Sim green is necessary but not sufficient for these.

## Author

Spec drafted by Claude Opus 4.7 (1M ctx) at 2026-05-04 17:33 SAST while Rishaal was mobile and Codex was idle. User explicitly approved each scope in chat and chose direct-spec (no mockup round-trip) as the build path.
