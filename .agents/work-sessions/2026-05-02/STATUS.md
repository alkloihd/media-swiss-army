# Status -- 2026-05-02

## Current Focus

Protocol hardening, audit kickoff prep, and XcodeBuildMCP setup.

## Branch / Workspace

- Branch: `feature/metaclean-stitch`
- Existing unrelated changes before this pass: `lib/jobQueue.js`, `lib/probe.js`
- Existing untracked folders before this pass: `.claude/worktrees/`, `design-review/`

## Completed This Session

- Consolidated Claude settings earlier in the session.
- Added broader Playwright MCP permissions earlier in the session.
- Drafted and started implementing the protocol hardening plan.
- Replaced `CLAUDE.md` with a pointer to `AGENTS.md`.
- Rewrote `AGENTS.md` as the source of truth for Claude Code, Codex, XcodeBuildMCP, work sessions, app truth, and audit lanes.
- Added root work-session protocol files and 2026-05-02 status, manifest, status findings, and handoff files.
- Saved the full Claude kickoff prompt at `.agents/work-sessions/2026-05-02/handoffs/KICKSTARTER-7-8-agent-audit-dashboard-ios-port.md`.
- Updated `.claude/agents` and mirrored `.claude/.codex/.agents` skills for current preset names, MetaClean/Stitch/Download reality, frontmatter placement, and HW/SW queue language.
- Verified `xcodebuildmcp` exists on PATH.
- Refreshed global `xcodebuildmcp@latest` install with npm.
- Updated Codex MCP TOML to use the global `xcodebuildmcp mcp` command.
- Added Claude Code user-scope MCP server `xcodebuildmcp`.
- Confirmed `claude mcp list` reports `xcodebuildmcp` connected.
- Confirmed `xcodebuildmcp tools` reports 72 canonical tools and 104 total tools.

## Verification

- Settings JSON valid and identical.
- Scoped changed-file Prettier check passes.
- Backend syntax checks pass.
- Scoped app ESLint has 0 errors and 13 existing warnings.
- `npm run check` still fails because broad `eslint .` includes `design-review/` and `.claude/worktrees/`.
- `npm audit --audit-level=moderate` reports 5 advisories: 2 moderate and 3 high.

## Open Risks

- Codex must be restarted before the newly configured XcodeBuildMCP server appears as active tools in this chat.
- Claude Code may need a restart or `/mcp` refresh to expose the new user-scope XcodeBuildMCP server inside an active Claude session, although `claude mcp list` shows the server connected.
- There is no Xcode project in this repo yet, so XcodeBuildMCP can be tested for server/tool availability but not app build/run.
- The audit dashboard at `public/audit/` has not been built in this pass; it is delegated through the saved Claude kickoff prompt.
