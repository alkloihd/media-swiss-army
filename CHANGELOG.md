# Changelog

All notable iOS app changes are documented here. Web-app changes live on `main`'s history. This file tracks the iOS Video Compressor only.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) with one twist: every entry names the agent that made the change for full agent paper trail.

Agent identifier format: `[type/model]` — e.g. `[Claude Opus 4.7 / 1M ctx]`, `[subagent:sonnet]`, `[subagent:haiku/scribe]`, `[subagent:opus/code-reviewer]`. Match the format used in `.agents/work-sessions/<DATE>/AI-CHAT-LOG.md`.

## [Unreleased] — `feature/metaclean-stitch`

### Reviewed

- 2026-05-03 [subagent:opus/code-reviewer] Audit of 3f69f2b (per-clip editor sheet, commit 3): 1 HIGH (`CropEditorView` identity-rect FP comparison), 3 MEDIUM (modal-on-modal `.onAppear`, accent-color a11y contrast, missing accessibility labels), 4 LOW — see AI-CHAT-LOG {E-0503-1101}.
- 2026-05-03 [subagent:opus/code-reviewer] Audit of d03d4bc (Stitch UI, commit 2): 1 HIGH (silent overwrite in `stageToStitchInputs`), 3 MEDIUM, 3 LOW — see AI-CHAT-LOG {E-0503-1050}.

### Added

- 2026-05-03 [subagent:opus via Opus 4.7 lead] (44057d3) MetaClean model + remux strip service (commit 5 of 6). `MetadataTag` + `MetadataCategory` + `StripRules` (autoMetaGlasses / stripAll / identity factories) + `MetadataCleanResult` value types. `MetadataService` actor reads metadata across `.metadata` / `.quickTimeMetadata` / `.quickTimeUserData` / `.iTunesMetadata` keyspaces; classifies by category; flags Meta Ray-Ban fingerprint atoms. `strip(url:rules:onProgress:)` uses `AVAssetReader → AVAssetWriter` passthrough pump (`outputSettings: nil`) — pure remux, bit-identical pixels, no re-encode. Output as `_CLEAN.mp4` in `Documents/Cleaned/`.
- 2026-05-03 [subagent:opus via Opus 4.7 lead] (79fc296) StitchExporter + export sheet (commit 4 of 6). Actor builds `AVMutableComposition` from clips, detects passthrough vs re-encode, applies per-clip `AVMutableVideoCompositionLayerInstruction` for crop/rotate. `CompressionService.encode(asset:videoComposition:settings:outputURL:onProgress:)` overload — single export pipeline shared by Compress and Stitch. `StitchExportSheet` settings picker + live progress + Save to Photos. `StitchProject.export(settings:)` replaces commit-1 stub.
- 2026-05-03 [subagent:sonnet via Opus 4.7 lead] (3f69f2b) Per-clip editor sheet with trim/crop/rotate (commit 3 of 6).
- 2026-05-03 [subagent:sonnet via Opus 4.7 lead] (d03d4bc) Stitch tab shell + timeline reorder + thumbnails (commit 2 of 6).
- 2026-05-03 [subagent:sonnet] (8147e22) Stitch model + StitchProject state (commit 1 of 6).
- 2026-05-03 [subagent:sonnet] (4a9cbc9) Task 0 type refactors: BoundedProgress + CompressedOutput + CompressionSettings + LibraryError. Closes type-design-analyzer top-3 from {E-0503-0936}.
- 2026-05-03 [Claude Opus 4.7 / 1M ctx] (8d88990) Phase 1 iOS MVP: SwiftUI app with VideoLibrary, CompressionService (AVAssetExportSession), 4 presets (Max / Balanced / Small / Streaming), PhotosPicker import, save-to-Photos. 11 Swift files under `VideoCompressor/ios/`.
- 2026-05-03 [Claude Opus 4.7 / 1M ctx] (9a54f68) Phase 2 commit 1: 3-tab `TabView` shell with Stitch / MetaClean placeholders.
- 2026-05-03 [Claude Opus 4.7 / 1M ctx] (edc9546) `TESTFLIGHT.md` deployment guide at project root.

### Fixed

- 2026-05-03 [subagent:sonnet] (5db2187) 12 critical findings from 4-Opus-reviewer audit:
  - `AVAssetExportSession.cancelExport()` now wired through `withTaskCancellationHandler`
  - Polling task cancelled before final 1.0 progress emit
  - Zero-byte output detected and surfaced as `.failed`
  - Picker tmp leak: `moveItem` instead of `copyItem`; `Picks-*` parent cleanup
  - Alert binding: real two-way `Binding(get:set:)` (was `.constant`)
  - `compressAll` predicate: `isActive` instead of `!= .running(progress: 0)`
  - Single shared `CompressionService` instance instead of per-job
  - `compress(_:)` funneled through `activeTask` to prevent batch+per-row races
  - NSError `code/domain/userInfo` + `NSUnderlyingError` preserved on export failure
  - `Documents/Inputs` + `Documents/Outputs` marked `isExcludedFromBackup`
  - Orphan output cleanup when row removed mid-compression
  - `@Sendable` on `onProgress` parameter

### Reviewed

- 2026-05-03 [subagent:opus/code-reviewer] Concurrency + lifecycle audit — 2 CRIT, 4 HIGH, 4 MEDIUM, 1 LOW
- 2026-05-03 [subagent:opus/silent-failure-hunter] Error-path audit — 2 CRIT, 5 HIGH, 6 MEDIUM, 4 LOW
- 2026-05-03 [subagent:opus/type-design-analyzer] 12 types scored on encapsulation/invariant/usefulness/enforcement (1-5). Recommended: `BoundedProgress`, `CompressedOutput`, `CompressionSettings`, `LibraryError` refactors.
- 2026-05-03 [subagent:opus/spec-gap-analyst] Phase-1 (~25% of spec) → spec migration plan; 5-commit phase-2 ordering.
- 2026-05-03 [subagent:opus/code-reviewer] T0 type-refactor audit — 0 CRIT, 3 HIGH, 4 MEDIUM, 2 LOW
- 2026-05-03 [subagent:opus/code-reviewer] Commit 1 audit (StitchClip + StitchProject) — 0 CRIT, 2 HIGH, 3 MEDIUM, 2 LOW

### Documented

- 2026-05-03 [subagent:opus/general-purpose] (gitignored) `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` — 5007-word implementation plan for Stitch + MetaClean tabs (12 tasks, 6 commits, 7-row risk register).

### Infra / Tooling

- 2026-05-03 [Claude Opus 4.7 / 1M ctx] (dd6c1b6) `XcodeBuildMCP@2.3.2` skills installed (`.agents/skills/xcodebuildmcp-mcp/`, `.agents/skills/xcodebuildmcp-cli/`) + symlinks in `.claude/skills/`. `.xcodebuildmcp/config.yaml` enables 10 workflow groups for full iOS dev. `AGENTS.md` §9 documents the integration.
- 2026-05-03 [Claude Opus 4.7 / 1M ctx] (eafa27e) Xcode iOS project scaffolded as `VideoCompressor_iOS.xcodeproj` (SwiftUI template).
