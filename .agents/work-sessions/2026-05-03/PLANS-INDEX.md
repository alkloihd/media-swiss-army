# Plans Index — docs/superpowers/plans/

All graduated plan documents that have been promoted out of session folders into the
durable `docs/superpowers/plans/` directory. These are the canonical long-lived references;
session-specific plans live in `.agents/work-sessions/<date>/plans/`.

---

| File | Summary |
|---|---|
| `docs/superpowers/plans/2026-04-10-ios-app-phase1-2.md` | Phase 1 & 2 implementation plan for the VideoCompressor iOS/macOS universal app — Compress tab with VideoToolbox hardware encoders and the 2D compression-matrix UI. The plan that stood up the original iOS scaffold. |
| `docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md` | Codex Day-1 onboarding plan — brings Codex to functional parity with the lead Claude session and hands off remaining work via task plans. Read this before picking up any backlog task. |
| `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` | O(1) still-image bake plan — eliminates the N-frame encoding loop in `StillVideoBaker` and replaces it with a single-second baked `.mov` stretched via `AVMutableCompositionTrack.scaleTimeRange`. Corresponds to `backlog/TASK-01-still-bake-constant-time.md`. |
