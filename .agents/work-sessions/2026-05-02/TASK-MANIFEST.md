# Task Manifest -- 2026-05-02

## Protocol Hardening + Audit Kickoff

- [x] Read current repo docs, KINWOVEN protocol, app structure, and explorer findings.
- [x] Replace `CLAUDE.md` with pointer-only source-of-truth note.
- [x] Rewrite `AGENTS.md` as canonical protocol with current app truth.
- [x] Add `.agents/work-sessions/PROTOCOL.md`.
- [x] Add `.agents/work-sessions/RUNNING-LIST.md`.
- [x] Add `.agents/work-sessions/DREAMS.jsonl`.
- [x] Add `.agents/work-sessions/2026-05-02/STATUS.md`.
- [x] Add `.agents/work-sessions/2026-05-02/TASK-MANIFEST.md`.
- [x] Add handoff and kickoff prompt files.
- [x] Update stale agent docs.
- [x] Update mirrored skill frontmatter and stale preset/MetaClean language.
- [x] Run verification commands.
- [x] Record final results and known failures.

## XcodeBuildMCP Setup

- [x] Verify `xcodebuildmcp` binary is on PATH.
- [x] Run `npm install -g xcodebuildmcp@latest`.
- [x] Confirm `xcodebuildmcp tools` lists tools.
- [x] Configure Codex TOML to use `xcodebuildmcp mcp`.
- [x] Add Claude Code user-scope MCP server.
- [x] Run final `claude mcp list` check.
- [x] Document restart requirements.

## Verification Results

- [x] `python3 -m json.tool .claude/settings.json`
- [x] `python3 -m json.tool .claude/settings.local.json`
- [x] `cmp -s .claude/settings.json .claude/settings.local.json`
- [x] Scoped Prettier check for changed docs/settings/skills.
- [x] `node --check server.js && for f in lib/*.js; do node --check "$f"; done`
- [x] `npx eslint server.js lib/*.js public/js/*.js`
- [x] `claude mcp list` shows `xcodebuildmcp: xcodebuildmcp mcp - ✓ Connected`
- [x] `xcodebuildmcp tools` lists 72 canonical tools, 104 total tools.

## Known Failures / Warnings

- Broad requested Prettier glob fails because it includes `.claude/worktrees/gifted-mcnulty-1bf71b/` and `.claude/commands/status.md`.
- `npm run check` fails because `eslint .` includes `design-review/review.js`, which has browser globals not configured in ESLint. It also repeats warnings from `.claude/worktrees/`.
- Scoped app ESLint has 0 errors and 13 existing warnings.
- `npm audit --audit-level=moderate` reports 5 advisories: 2 moderate, 3 high.
