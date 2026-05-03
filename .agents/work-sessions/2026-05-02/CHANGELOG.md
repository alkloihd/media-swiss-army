# Changelog

[2026-05-02 16:38 IST] [codex/gpt-5] [INFRA] Started Claude settings consolidation
  Actions: Comparing shared and local Claude Code settings and preparing a merged configuration.
  Files: .claude/settings.json, .claude/settings.local.json
  Status: In progress

[2026-05-02 16:39 IST] [codex/gpt-5] [INFRA] Consolidated Claude settings and expanded Playwright MCP permissions
  Actions: Both Claude settings files now contain the same merged valid JSON. Added Playwright MCP server-level approval plus common browser automation tools.
  Files: .claude/settings.json, .claude/settings.local.json
  Status: Complete

[2026-05-02 13:39 SAST] [codex/gpt-5] [INFRA] Hardened protocol, prepared audit kickoff, and configured XcodeBuildMCP
  Actions: Made `AGENTS.md` canonical, reduced `CLAUDE.md` to a pointer, added work-session protocol/status/handoff files, saved the Claude 8-lane audit prompt, aligned agent/skill docs, and configured XcodeBuildMCP for Codex and Claude Code.
  Files: AGENTS.md, CLAUDE.md, .claude/agents/*.md, .claude/skills/*/SKILL.md, .codex/skills/*/SKILL.md, .agents/skills/*/SKILL.md, .agents/work-sessions/**, .claude/settings.json, .claude/settings.local.json, /Users/rishaal/.codex/config.toml, /Users/rishaal/.claude.json
  Status: Complete
