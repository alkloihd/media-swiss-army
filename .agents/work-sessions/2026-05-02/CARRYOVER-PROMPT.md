# Carryover Prompt

[2026-05-02 16:39 IST] [codex/gpt-5] [INFRA] Claude Code settings consolidation completed.

User asked to merge .claude/settings.json and .claude/settings.local.json, preserving settings from both files, keeping both files, making both identical, and validating JSON. This is done. User also asked about installing a global MCP server; ask for the server name/package/command, then use `claude mcp add --scope user ...`.

[2026-05-02 13:39 SAST] [codex/gpt-5] [INFRA] Continue from protocol hardening completion.

Read `AGENTS.md` first. It is the source of truth. Then read `.agents/work-sessions/2026-05-02/STATUS.md`, `TASK-MANIFEST.md`, `status/explorer-findings.md`, and `status/xcodebuildmcp-status.md`.

The Claude kickoff prompt for the 8-lane audit/dashboard/iOS port strategy is saved at `.agents/work-sessions/2026-05-02/handoffs/KICKSTARTER-7-8-agent-audit-dashboard-ios-port.md`.

XcodeBuildMCP is installed globally and configured for both Codex and Claude Code. Restart Codex/Claude to refresh active MCP tools. No Xcode project exists yet.
