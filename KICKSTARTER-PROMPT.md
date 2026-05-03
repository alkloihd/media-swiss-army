# Kickstarter prompts for Claude in Terminal

Two paste-ready prompts. Open `claude` in this repo root. Paste **Prompt 1** first, wait for "I've read everything", then fill in your answers in **Prompt 2** and paste it.

---

## Prompt 1 — Orient + read

Paste this verbatim. Claude reads, confirms, doesn't do anything else.

```text
You're picking up an iOS app project called "Media Swiss Army" (App Store name will be "MetaClean: AI Glasses Data"). The previous session left a comprehensive handoff. Your ONLY job in this turn is to read the following files in order — no questions, no plans, no code. Read each one fully, then reply with a single sentence: "I've read everything; ready for the ultraplan invocation."

Read these in this order:

1. HANDOFF-TO-CLAUDE-TERMINAL.md (repo root) — full session story
2. AGENTS.md — Parts 1, 2, 4, 15, 16 in particular
3. docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md — onboarding template
4. docs/superpowers/plans/2026-05-03-still-bake-constant-time.md — example of a complete writing-plans plan
5. .agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md — phased roadmap to App Store
6. .agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md — known broken vs fixed
7. .agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md — launch + ASO strategy
8. All 9 audit reports under .agents/work-sessions/2026-05-03/audits/AUDIT-0*.md (skim — focus on the headline findings)
9. The 3 red-team reports under .agents/work-sessions/2026-05-03/audits/RED-TEAM-*.md (skim)
10. The 3 active TASK files: .agents/work-sessions/2026-05-03/backlog/TASK-01-still-bake-constant-time.md, TASK-02-adaptive-meta-marker-registry.md, TASK-99-cache-cleanup-on-cancel-and-save.md

After reading, also confirm your XcodeBuildMCP setup is working — run mcp__xcodebuildmcp__session_show_defaults and confirm projectPath ends in "VideoCompressor/VideoCompressor_iOS.xcodeproj". If MCP is missing, follow AGENTS.md Part 16 §16.3 to install.

Don't ask questions. Don't write code. Don't open PRs. Just read, verify MCP, and reply with the confirmation sentence.

Repo: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/
Default branch: main
Latest merged PR is #9 (the day's audit-criticals + Codex handoff).
```

---

## Prompt 2 — `/ultraplan` invocation

Once Claude confirms "I've read everything; ready for the ultraplan invocation," fill in YOUR answers below (replace each `<your answer>`), then paste the whole thing.

```text
/ultraplan Produce TDD implementation plans for Phases 1, 2, and 3 of MASTER-PLAN.md (.agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md). Each plan follows the writing-plans skill format — bite-sized TDD steps, exact file paths, complete code, expected commands and outputs, no placeholders. Use docs/superpowers/plans/2026-05-03-still-bake-constant-time.md as the canonical template.

Save plans to docs/superpowers/plans/ with filename pattern <YYYY-MM-DD>-phase<N>.<task>-<slug>.md.

My decisions on the 13 open questions from HANDOFF-TO-CLAUDE-TERMINAL.md:

1. App Store name: <your answer — e.g. "MetaClean: AI Glasses Data" or alternative>
2. Pricing: <e.g. "$4.99 one-time" or "$2.99" or "freemium with $9.99 Pro IAP">
3. Apple Small Business Program: <"already enrolled" or "will enrol now" or "skip for now">
4. Long-press preview placement: <"keep contextMenu overlay (default)" or "move to bottom inline editor area">
5. Compress presets to hide behind Advanced: <e.g. "show only Balanced + Small by default" or "show all">
6. CropEditor sliders: <"hide entirely (use aspect-ratio presets only)" or "move to Advanced" or "keep visible">
7. Adaptive Meta-marker registry priority: <"Phase 1.7 — before App Store" or "Phase 6 — post-launch">
8. iOS Share Extension: <"Phase 6 (post-launch)" or "Phase 3 (pre-launch)" or "skip for v1.0">
9. Pro tier IAP candidates for v1.1: <e.g. "batch >50 + custom marker rules" or "Mac Catalyst Universal Purchase only" or "skip Pro tier for now">
10. Local-device iteration setup priority: <"Phase 0 — before any other work, save build minutes" or "Phase 5 (when MASTER-PLAN says)" or "skip">
11. TestFlight cadence target: <e.g. "≤ 5 cycles total" or "≤ 3 per phase" or "no limit">
12. Real-device testing workflow: <"USB-tethered after dev-iterate.sh lands" or "TestFlight per-PR" or "real device only at Phase 0 confirmation">
13. iPhone tethered now: <"yes, currently plugged in" or "no, will plug in for Phase 5">

Constraints (NON-NEGOTIABLE):
- Each plan = one PR = one TestFlight cycle (when merged to main)
- Total TestFlight cycles ≤ my answer to question 11 above
- All plans must respect AGENTS.md Part 14 non-negotiables and Part 16 working contract
- 138 unit tests must continue to pass after each plan executes
- The 7 already-fixed audit CRITICALs (in PR #9) must NOT regress
- Privacy-first: no network calls, no analytics, no third-party SDKs
- iOS 17.0 minimum
- Bundle: com.alkloihd.videocompressor; Team: 9577LMA4J5

Output requirements:
- One plan file per task across MASTER-PLAN.md Phases 1, 2, 3
- File naming: docs/superpowers/plans/<YYYY-MM-DD>-phase<N>.<task-num>-<short-slug>.md (e.g. 2026-05-04-phase1.2-aggressive-cache-cleanup.md)
- Each plan includes: writing-plans header, file structure table, bite-sized steps with TDD test-first ordering, expected MCP tool commands + outputs, hourly effort estimate
- A consolidated PHASES-1-3-INDEX.md at the same path that links every plan in execution order, with effort estimates summed per phase
- Group commits per logical unit; don't split into more than ~10 commits per plan

Audit reports (cloud session should fetch these from the GitHub repo):
- .agents/work-sessions/2026-05-03/audits/AUDIT-01..09 + RED-TEAM-*

Ask me clarifying questions ONLY if my answers above contradict each other or contradict MASTER-PLAN.md. Otherwise produce the plans.
```

---

## What happens after Prompt 2

Claude in terminal hands the planning task to Claude Code on the web (a cloud session running in plan mode). It opens in your browser. You can:

1. Comment + iterate on the plans inline (browser UI)
2. When happy, choose execution destination:
   - **Local terminal (RECOMMENDED for this app)** — teleports back to your machine. Required for iOS work since the cloud session can't drive XcodeBuildMCP / sim / tethered iPhone.
   - **Cloud (Claude codes in browser)** — only for non-iOS portions if any (none here)
   - **Cancel** — saves plans to disk only, you execute manually later

3. After teleport, terminal Claude reads the approved plans and uses superpowers:subagent-driven-development to walk through them.

---

## If Prompt 2 fails

If `/ultraplan` doesn't appear in your terminal Claude (e.g. you're not on Claude Code on the web tier, or the GitHub repo isn't connected), fall back to local plan generation:

```text
Use the superpowers:writing-plans skill to produce TDD plans for MASTER-PLAN.md Phase 1 (six tasks). Save each plan to docs/superpowers/plans/. Use docs/superpowers/plans/2026-05-03-still-bake-constant-time.md as the template. My answers to the 13 questions from HANDOFF-TO-CLAUDE-TERMINAL.md are: [paste your filled-in answers from Prompt 2 above].
```

This produces the same plans without the cloud round-trip. Slower but works on any tier.

---

## Sources

- [Plan in the cloud with ultraplan — Claude Code Docs](https://code.claude.com/docs/en/ultraplan)
- [GitHub: 6missedcalls/ultraplan](https://github.com/6missedcalls/ultraplan)
- [Claude Code Ultraplan: Cloud Planning to Free Your Terminal — claudefa.st](https://claudefa.st/blog/guide/mechanics/ultraplan)
