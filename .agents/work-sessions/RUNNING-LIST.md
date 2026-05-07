# Video Compressor Running List

## IN PROGRESS

- [2026-05-05] Cluster 3.5 Calm-Cinema visual redo on `feat/cluster-3.5-visual-calm-cinema`. Task 2 components compile in app + test target; runtime simulator tests are deferred until CoreSimulator/MCP stops opening extra iPhone windows. User wants true SwiftUI `.glassEffect()` later, but current Xcode 16 / iOS 18 SDK cannot compile the symbol, so this is blocked until a newer SDK is installed or the branch uses a material-only fallback.
- [2026-05-02] Protocol hardening and audit kickoff prep. Source: current Codex session.
- [2026-05-02] XcodeBuildMCP setup across Claude Code and Codex. Source: current Codex session.

## QUEUED

- [2026-05-07] Stitch UI space follow-up: reduce vertical controls by making Aspect and Transition same-line menus/dropdowns, then add a custom transition entry to the clip long-press menu so preview space is easier to see.
- [2026-05-05] After Codex finishes Cluster 3.5, provide a Claude prompt asking it to launch a 7-8 Opus-agent red-team pass covering visual QA, functional regressions, accessibility, simulator/app-window walkthrough, XCTest/CI, performance, edge cases, and PR/git hygiene.
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
