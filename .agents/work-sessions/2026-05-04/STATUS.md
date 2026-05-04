# Status — 2026-05-04

## Current Priority

Cluster 0 hotfixes on branch `feat/codex-cluster0-hotfixes`.

## Verified Starting State

- Branch source: `feat/phase-2-features-may3`, up to date with origin before branching.
- XcodeBuildMCP defaults: `VideoCompressor/VideoCompressor_iOS.xcodeproj`, scheme `VideoCompressor_iOS`, simulator `iPhone 16 Pro`.
- Baseline simulator tests: `Total: 138, Passed: 138`.
- Booted simulator check: installed `simctl` rejects `xcrun simctl list booted`; `xcrun simctl list devices booted` showed no booted devices.

## Execution Contract

- Follow `docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md` for scope and acceptance criteria.
- Adapt plan snippets when current code disagrees, preserving the intended behavior.
- Use TDD for code changes and verify red/green rather than writing tests after implementation.
- Keep commits scoped and log each commit in this folder.
- Do not touch `.github/workflows/testflight.yml`.
- Do not push to `main` directly.

## Known Adaptations Before Coding

- Combine Cluster 0 Tasks 1 and 2 atomically because changing `StillVideoBaker.bake` return type breaks `StitchExporter` until both sides change.
- Use still-image fixtures at least `32x32`; current `StillVideoBaker` rejects images smaller than `16x16`.
- Update existing Max-bitrate tests to the new cap contract.
- Use Swift-valid retry structure; do not rely on the plan's suspect catch syntax.
- Surface fallback/downshift behavior instead of DEBUG-only logging.
