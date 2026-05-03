# Paste-ready prompt for Claude in Terminal

Open Claude Code in your terminal in the repo root (`/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/`). Paste the prompt below as your first message. Claude will read the handoff docs, ask you a focused set of decision questions, then invoke `/ultraplan` for you.

---

## STAGE 1 — Onboard prompt (paste this first)

```text
You're picking up an iOS app project called "Media Swiss Army" (App Store name will be "MetaClean: AI Glasses Data"). The previous session — Claude Opus running in Claude Code on this Mac — left a comprehensive handoff. Before doing anything else:

1. Read these files in order:
   - HANDOFF-TO-CLAUDE-TERMINAL.md (root) — full session story, what's tested, what's not, what's left
   - AGENTS.md Part 16 — your full onboarding (signing IDs, MCP setup, working contract)
   - .agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md — phased roadmap to App Store
   - .agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md — what's known broken vs fixed
   - docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md — day-1 prompt template
   - .agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md — launch + ASO strategy
   - .agents/work-sessions/2026-05-03/audits/ — 9 audit reports + 3 red-team reports

2. Verify your XcodeBuildMCP setup is working. Run `mcp__xcodebuildmcp__session_show_defaults` and confirm projectPath ends in `VideoCompressor/VideoCompressor_iOS.xcodeproj`. If your Codex/Claude doesn't have xcodebuildmcp installed, follow AGENTS.md Part 16 §16.3.

3. Once you've finished reading, ask me ALL THIRTEEN questions from "Open questions for the user" in HANDOFF-TO-CLAUDE-TERMINAL.md. Don't paraphrase — keep the exact numbering 1-13. Ask them as a numbered list and let me answer them in one batch.

4. After I answer, summarise my answers back to me in one short paragraph so I can confirm you understood. Wait for my "yes, plan it" before invoking ultraplan.

5. Once I confirm, run /ultraplan with a prompt that synthesizes:
   - The MASTER-PLAN.md phase breakdown
   - My answers to the 13 questions  
   - Any decisions about scope cuts (some things in MASTER-PLAN may get deferred based on my answers)

   The ultraplan invocation should ask the cloud session to produce TDD-format implementation plans for Phases 1, 2, and 3 of MASTER-PLAN.md, with one plan file per task following the template at docs/superpowers/plans/2026-05-03-still-bake-constant-time.md. Save the plans to docs/superpowers/plans/ with a date-prefixed slug per file.

Don't write any code yet. Don't open any PRs. The goal of this conversation is to UNDERSTAND the project and PRODUCE plans. Code-execution comes later via subagent-driven-development.

Working directory: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/
GitHub repo: https://github.com/alkloihd/video-compressor-FUCKMETA
Default branch: main
Latest merged PR: #9 (will be 10+ if I've merged the docs follow-up before you read this)

Now read the docs and ask me the 13 questions.
```

---

## STAGE 2 — `/ultraplan` invocation (Claude builds this for you)

After you've answered the 13 questions and Claude has summarised your answers back to you, Claude will invoke `/ultraplan` with a prompt similar to the template below. You don't paste this yourself — Claude will compose it from your answers and run it.

```text
/ultraplan Produce TDD implementation plans for Phases 1, 2, and 3 of the MASTER-PLAN.md at .agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md.

Each plan should follow the template at docs/superpowers/plans/2026-05-03-still-bake-constant-time.md (writing-plans skill format — bite-sized TDD steps, exact file paths, complete code, expected commands and outputs, no placeholders).

User decisions from the kickoff conversation:
- App Store name: <user's answer>
- Pricing: <user's answer>  
- Small Business Program: <user's answer>
- Long-press preview placement: <user's answer>
- Compress presets to hide behind Advanced: <user's answer>
- CropEditor sliders: <user's answer>
- Adaptive Meta-marker registry priority: <user's answer>
- Share Extension scope: <user's answer>
- Pro tier IAP candidates: <user's answer>
- Local-device iteration setup priority: <user's answer>
- TestFlight cadence target: <user's answer>
- Real-device testing workflow: <user's answer>
- iPhone tethered? <user's answer>

Constraints:
- Each plan = one PR = one TestFlight cycle
- Total TestFlight cycles ≤ <user's cadence answer> across Phases 1-3
- All plans must respect AGENTS.md Part 14 non-negotiables and Part 16 working contract
- 138 unit tests must continue to pass after each plan executes
- The 7 already-fixed audit CRITICALs (in PR #9) must NOT regress
- Privacy-first: no network calls, no analytics, no third-party SDKs

Output format:
- One plan file per task in MASTER-PLAN.md Phases 1-3
- Filename pattern: docs/superpowers/plans/2026-05-XX-<phase>.<task>-<slug>.md  
- Each plan includes the standard writing-plans header, file structure table, and bite-sized tasks with TDD test-first ordering
- Include rough effort estimates per task (in hours)

Audit reports for context (cloud session should read these):
.agents/work-sessions/2026-05-03/audits/AUDIT-01-concurrency.md
.agents/work-sessions/2026-05-03/audits/AUDIT-02-memory-leaks.md
.agents/work-sessions/2026-05-03/audits/AUDIT-03-privacy-security.md
.agents/work-sessions/2026-05-03/audits/AUDIT-04-performance.md
.agents/work-sessions/2026-05-03/audits/AUDIT-05-ux.md
.agents/work-sessions/2026-05-03/audits/AUDIT-06-codecs.md
.agents/work-sessions/2026-05-03/audits/AUDIT-07-edge-cases.md
.agents/work-sessions/2026-05-03/audits/AUDIT-08-feature-gaps.md
.agents/work-sessions/2026-05-03/audits/AUDIT-09-cache-cleanup-on-cancel-and-export.md

Existing TASK files (cloud session should reference):
.agents/work-sessions/2026-05-03/backlog/TASK-01-still-bake-constant-time.md
.agents/work-sessions/2026-05-03/backlog/TASK-02-adaptive-meta-marker-registry.md
.agents/work-sessions/2026-05-03/backlog/TASK-99-cache-cleanup-on-cancel-and-save.md

Existing complete plan to use as template:
docs/superpowers/plans/2026-05-03-still-bake-constant-time.md
```

---

## What you do next

1. Open Claude Code in your terminal at this repo root (or run `claude` from anywhere if it's globally installed; navigate it to this dir if needed).
2. Paste **Stage 1** (the prompt above) as your first message.
3. Wait for Claude to finish reading + ask the 13 questions.
4. Answer the 13 questions in one message.
5. Confirm Claude's summary by saying "yes, plan it."
6. Claude invokes `/ultraplan`.
7. The plan opens in your browser. Review, comment, iterate.
8. Approve the plan.
9. Choose execution destination: cloud (it codes in the browser session), local terminal (teleport back to your terminal — best for the iOS work where you need MCP + sim access), or save-to-file.

For this app's iOS work, **execute locally**. The cloud sessions can't drive XcodeBuildMCP for sim builds or device installs.

---

## Sources

- [Plan in the cloud with ultraplan — Claude Code Docs](https://code.claude.com/docs/en/ultraplan)
- [GitHub: 6missedcalls/ultraplan — Deep multi-phase implementation planning skill for Claude Code](https://github.com/6missedcalls/ultraplan)
- [Claude Code Ultraplan: Cloud Planning to Free Your Terminal — claudefa.st](https://claudefa.st/blog/guide/mechanics/ultraplan)
