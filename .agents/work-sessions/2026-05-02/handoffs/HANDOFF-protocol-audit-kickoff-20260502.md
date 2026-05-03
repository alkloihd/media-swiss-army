# Handoff -- Protocol Hardening and Audit Kickoff

## State

Protocol hardening is underway on `feature/metaclean-stitch`.

Completed:

- `AGENTS.md` rewritten as canonical source of truth.
- `CLAUDE.md` reduced to pointer-only.
- `.agents/work-sessions/PROTOCOL.md` added.
- `.agents/work-sessions/RUNNING-LIST.md` added.
- `.agents/work-sessions/DREAMS.jsonl` added.
- `STATUS.md` and `TASK-MANIFEST.md` added for 2026-05-02.
- Explorer-agent findings captured in `status/explorer-findings.md`.
- XcodeBuildMCP status captured in `status/xcodebuildmcp-status.md`.
- Global `xcodebuildmcp@latest` install refreshed.
- Codex TOML updated to use `xcodebuildmcp mcp`.
- Claude Code user MCP server `xcodebuildmcp` added.

Pending:

- Finish stale agent doc updates.
- Finish mirrored skill frontmatter and wording updates.
- Run verification commands.
- Update final logs and changelog.

## Important Context

The worktree had unrelated changes before this pass:

- `lib/jobQueue.js`
- `lib/probe.js`
- untracked `.claude/worktrees/`
- untracked `design-review/`

Do not revert or overwrite those unless Rishaal explicitly asks.

## Key Findings to Preserve

- MetaClean, Stitch, and Download are built, not future work.
- Current presets are `lossless`, `maximum`, `high`, `balanced`, `compact`, `tiny`.
- `lib/presets.js` does not exist; preset logic is in `lib/ffmpeg.js`.
- Job queue has separate HW and SW queues.
- Local checks are polluted by untracked folders.
- `npm audit` currently reports high/moderate advisories.
- No Xcode project exists yet, so XcodeBuildMCP can be configured but not used for app builds yet.

## Next Agent

Read:

1. `AGENTS.md`
2. `.agents/work-sessions/PROTOCOL.md`
3. `.agents/work-sessions/2026-05-02/STATUS.md`
4. `.agents/work-sessions/2026-05-02/TASK-MANIFEST.md`
5. `.agents/work-sessions/2026-05-02/status/explorer-findings.md`
6. `.agents/work-sessions/2026-05-02/status/xcodebuildmcp-status.md`
7. `.agents/work-sessions/2026-05-02/handoffs/KICKSTARTER-7-8-agent-audit-dashboard-ios-port.md`

Then continue verification or start the next audit chat.
