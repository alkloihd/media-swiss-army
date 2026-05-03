# Work Session Protocol

This file is the quick reference for how AI agents document work in this repository. The full behavioral source of truth is `AGENTS.md`.

## Location

All session files live under:

```text
.agents/work-sessions/
```

Root files:

- `PROTOCOL.md` -- this quick reference.
- `RUNNING-LIST.md` -- persistent priority and idea bucket.
- `DREAMS.jsonl` -- append-only larger ideas log.

Per-session files:

```text
.agents/work-sessions/YYYY-MM-DD/
  AI-CHAT-LOG.md
  STATUS.md
  TASK-MANIFEST.md
  CHANGELOG.md
  CARRYOVER-PROMPT.md
  handoffs/
  status/
```

## Timestamp

Use SAST:

```bash
TZ=Africa/Johannesburg date "+%Y-%m-%d %H:%M SAST"
```

## Entry Format

```markdown
## [YYYY-MM-DD HH:MM SAST] {E-MMDD-HHMM} -- [TAG] Agent (Model): Short title

> **Agent Identity** (first entry only)
> Model: [exact model]
> Platform: [Claude Code / Codex / Gemini CLI / other]
> Working Directory: [absolute path]
> Session Role: [Lead / Subagent / Reviewer / Scribe / Solo]

**In-Reply-To:** {E-MMDD-HHMM} (optional)
**Confidence:** HIGH / MEDIUM / LOW
**Files:** file1, file2

### Context
Why this work happened.

### Evidence
What was read or verified before acting.

### Findings
What was discovered.

### Decisions
What was chosen and why.

### Next Steps
What comes after.

**Result:** Success / Partial / Failed
**Resolves:** {E-MMDD-HHMM} (optional)
```

## Tags

Use: `[SETUP]` `[FEAT]` `[FIX]` `[DEBUG]` `[RESEARCH]` `[DECISION]` `[DOCS]` `[REVIEW]` `[DEPLOY]` `[HANDOFF]` `[ROLLBACK]` `[SEC]` `[PLANNING]` `[INFRA]` `[TEST]`.

## Rules

1. Use real timestamps only.
2. Append established logs; do not rewrite history.
3. Include evidence: files, commands, source docs, or outputs.
4. Create `STATUS.md` every session.
5. Create `TASK-MANIFEST.md` when there are 3+ tasks.
6. Put handoffs in `handoffs/` with descriptive names.
7. Keep `AGENTS.md` canonical and `CLAUDE.md` pointer-only.
