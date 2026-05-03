# Video Compressor Running List

## IN PROGRESS

- [2026-05-02] Protocol hardening and audit kickoff prep. Source: current Codex session.
- [2026-05-02] XcodeBuildMCP setup across Claude Code and Codex. Source: current Codex session.

## QUEUED

- Run 7-8 lane audit and generate `public/audit/` dashboard plus `public/audit/data/audit.json`.
- Fix local verification pollution from `.claude/worktrees/` and `design-review/`.
- Address `npm audit` advisories.
- Add automated tests for path safety, probe, compression command building, stream ranges, job cancellation, MetaClean, Stitch, and WebSocket progress.
- Audit and fix Stitch trim request shape drift.
- Harden frontend rendering of user-controlled filenames, metadata, and errors.
- Decide native iOS implementation plan: SwiftUI + AVFoundation/VideoToolbox first; Firebase optional only for cloud features.

## BACKBURNER

- Serve or replace `design-review/` with `public/audit/`.
- Move MetaClean outputs for uploaded files into `~/Movies/Video Compressor Output`.
- Add a live `/api/audit` endpoint only if static audit JSON is insufficient.
- Create native Xcode project after audit and iOS strategy decision.

## DONE

- [2026-05-02] Consolidated `.claude/settings.json` and `.claude/settings.local.json`.
- [2026-05-02] Expanded Playwright MCP auto-allow settings.
