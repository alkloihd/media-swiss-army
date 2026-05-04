# Codex Kickstarter — Day 1

> **For agentic workers:** This document is your starting prompt. Read it top-to-bottom before doing anything. It assumes nothing about prior session state.

**Goal:** Bring you (Codex) up to functional parity with the lead Claude session that built this app, then hand you the remaining work via task plans you author yourself using the `/writing-plans` skill.

**You will:** verify your MCP setup, read the canonical onboarding docs, then execute the existing detailed plan as a warm-up, then produce + execute plans for the rest of Phase 1 (and onward) using `/writing-plans`.

---

## Step 1 — Verify the XcodeBuildMCP server works for you

The lead Claude session drove all builds + tests through `xcodebuildmcp`. You need the same.

- [ ] **1.1** Check installation:

```bash
which xcodebuildmcp
xcodebuildmcp --help
```

If `command not found`:

```bash
npm install -g xcodebuildmcp@latest
```

- [ ] **1.2** Confirm the MCP server is registered with Codex. Check `~/.codex/config.toml` contains:

```toml
[mcp_servers.XcodeBuildMCP]
command = "xcodebuildmcp"
args = ["mcp"]
```

If missing, add it and restart Codex so the MCP tools load.

- [ ] **1.3** From Codex, list available MCP tools and confirm the `mcp__xcodebuildmcp__*` family is present. You should see at minimum:

```
mcp__xcodebuildmcp__session_show_defaults
mcp__xcodebuildmcp__build_sim
mcp__xcodebuildmcp__test_sim
mcp__xcodebuildmcp__build_run_sim
mcp__xcodebuildmcp__build_run_device
mcp__xcodebuildmcp__screenshot
mcp__xcodebuildmcp__clean
```

- [ ] **1.4** Verify you can talk to the project. Call:

```
mcp__xcodebuildmcp__session_show_defaults
```

Expected output (the lead's session left these set; confirm they're correct):

```json
{
  "projectPath": "/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/VideoCompressor_iOS.xcodeproj",
  "scheme": "VideoCompressor_iOS",
  "configuration": "Debug",
  "simulatorName": "iPhone 16 Pro",
  "simulatorId": "996226E2-F957-4730-93D5-4F10BFD916C3",
  "platform": "iOS",
  "bundleId": "ca.nextclass.VideoCompressor"
}
```

If the values differ — DO NOT call `session_set_defaults` to fix them yet. Verify with the user first; the lead session may still be running in parallel and changing defaults will break their builds.

- [ ] **1.5** Confirm you can run the test target end-to-end:

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 138, Passed: 138` (this is the baseline as of the lead session's PR #9 merge). If the count is different, run `mcp__xcodebuildmcp__clean` first then re-run.

If tests fail, **STOP** — something has regressed and you should not start writing new code on a broken main. Surface the failures to the user.

- [ ] **1.6** Confirm sim hygiene. The lead session may have left zombie iOS Simulator instances:

```bash
xcrun simctl list booted
```

If more than one sim is booted:

```bash
xcrun simctl shutdown all
killall Simulator
```

- [ ] **1.7** Confirm you can install on the user's physical iPhone (this saves Apple build minutes). Ask the user to plug in their iPhone via USB and trust this Mac. Then:

```
mcp__xcodebuildmcp__build_run_device
```

Expected: build succeeds and the app appears on the device. If the device list is empty, the user hasn't paired yet — pause and ask.

---

## Step 2 — Read the canonical context

In this order:

- [ ] **2.1** `AGENTS.md` (the whole file, ~700 lines) — this is the project's source of truth. Pay particular attention to:
  - Part 4 (Current App Truth)
  - Part 7 (Agent Roles + File Ownership)
  - Part 15 (iOS App + TestFlight Deployment Pipeline)
  - **Part 16 (Codex / next-agent onboarding)** — written specifically for you

- [ ] **2.2** `.agents/work-sessions/2026-05-03/PUBLISHING-AND-MONETIZATION.md` — the launch plan, $4.99 pricing strategy, App Review notes, ASO playbook.

- [ ] **2.3** `.agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md` — what's broken (already fixed inline + deferred). 9 audit reports synthesized.

- [ ] **2.4** `.agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md` — the phased roadmap. This is the ORDERING; the per-task TDD plans are written separately.

- [ ] **2.5** `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` — a complete, ready-to-execute TDD plan for Phase 1.1 written by the lead session using the `/writing-plans` skill. Use this as the TEMPLATE for the plans you will write yourself.

- [ ] **2.6** `git log --oneline -30` — recent direction.

After this you should know: what the app does, what's broken, what's planned, what conventions to follow.

---

## Step 3 — Execute the warm-up plan

Phase 1.1 (Still bake O(1)) has a complete plan already. Execute it to (a) prove your toolchain works on a real change, (b) fix a real critical-priority bug, (c) ship one PR before you start writing your own plans.

- [ ] **3.1** Branch off main:

```bash
git checkout main && git pull
git checkout -b feat/still-bake-constant-time
```

- [ ] **3.2** Use the `superpowers:subagent-driven-development` skill (or `superpowers:executing-plans` if you prefer inline) to walk through `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` task by task.

- [ ] **3.3** When the plan's Task 6 says to push + open a PR, ASK THE USER FIRST — they may want to review your changes before any TestFlight cycle is consumed.

- [ ] **3.4** Wait for CI green, merge, smoke-test on the user's device.

- [ ] **3.5** Append to `.agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md`:

```
[YYYY-MM-DD HH:MM IST] [solo/codex/<model>] [PERF] Phase 1.1 — Still bake O(1) merged (PR #N)
```

---

## Step 4 — Author the remaining Phase 1 plans

Phase 1 has 6 critical fixes total. Plan 1.1 is done (above). The remaining 5 need plans you write yourself.

For each task in `MASTER-PLAN.md` Phase 1, do this dance:

- [ ] **4.1** Run the `/writing-plans` skill (announce: "I'm using the writing-plans skill to create the implementation plan for <task>"). Follow the skill's template — bite-sized TDD steps, exact file paths, complete code, expected commands + outputs. Use `2026-05-03-still-bake-constant-time.md` as the reference layout.

- [ ] **4.2** Save each plan to `docs/superpowers/plans/<date>-<slug>.md`.

- [ ] **4.3** Pause for the user to review the plan if they want to. Auto mode is OFF — don't barrel ahead without checks.

- [ ] **4.4** Execute the plan via subagent-driven-development.

The 5 remaining Phase 1 plans, in order:

1. **Phase 1.2 — Aggressive cache cleanup on cancel + save** (TASK-99 spec exists in `backlog/`; this should have been a plan already, write it)
2. **Phase 1.3 — HDR passthrough** (read `AUDIT-06-codecs.md` H1 first; spec is "preserve 10-bit BT.2020 HEIC source through the pipeline")
3. **Phase 1.4 — Audio mix track parity** (spec: replace index-parity assumption with explicit per-segment audio track tracking)
4. **Phase 1.5 — Stage filename collision** (spec: UUID prefix on staged input filenames so delete-then-reimport doesn't alias undo history)
5. **Phase 1.6 — Bake cancellation cleanup** (spec: append the bakedURL to `bakedStillURLs` BEFORE the bake call so a thrown bake is still cleaned up)

---

## Step 5 — Phases 2 onward

After Phase 1 ships and the user does a real-device smoke test, repeat the same dance for Phases 2 (UX polish), 3 (App Store hardening), and onward per `MASTER-PLAN.md`.

Pace yourself: one plan, one PR, one merge. The user has limited Apple build minutes — `gh pr merge` to main triggers a TestFlight build every time. Aim for ≤ 2 TestFlight cycles per phase.

---

## Working contract recap (extracted from `AGENTS.md` Part 16)

- **Always branch off `main`.** Never push to `main` directly.
- **One PR per task / plan.** CI must pass (4 checks) before merge.
- **Local sim test passes before push.** `mcp__xcodebuildmcp__test_sim` is your gate.
- **Don't call `session_set_defaults`.** Multiple agents touching session defaults swap each other's project paths.
- **Don't run more than 2 background sub-agents in parallel.** Sim resource contention causes flaky test failures.
- **Don't introduce CoreHaptics.** `UISelectionFeedbackGenerator` covers tick feedback. See `Haptics.swift`.
- **Don't introduce a custom `AVVideoCompositing` class** without the user's explicit go-ahead. Built-in opacity/crop ramps cover today's transitions.
- **PR descriptions end with the agent attribution line** (`🤖 Generated with [Codex]...`).
- **Append to `AI-CHAT-LOG.md`** after every merge.
- **Sim hygiene:** quit Simulator after each session.

---

## What NOT to touch without confirmation

- `.git/` config
- `.github/workflows/testflight.yml` (App Store Connect API key wiring)
- `.claude/`, `.codex/`, `~/.codex/config.toml`
- The Apple Developer portal (signing certs, provisioning profiles)
- App Store Connect (the app entry, pricing, privacy details)
- The user's Xcode keychain or signing identities

---

## When you're stuck

- Re-read `AGENTS.md` Part 16 — most onboarding gotchas are documented there.
- Look for the audit reports in `.agents/work-sessions/2026-05-03/AUDIT-0*.md` — the issue you're hitting may be flagged.
- Use `git log --oneline -30` to see what the lead session was doing recently.
- Ask the user. They have full context and a real device.

---

## Acceptance: you're ready to take over when

- [ ] Step 1 (MCP verification) is fully checked off.
- [ ] You can run `mcp__xcodebuildmcp__test_sim` and get 138/138.
- [ ] You've read all of Step 2.
- [ ] You can install the app on the user's physical iPhone via `build_run_device`.
- [ ] You've executed Phase 1.1 successfully and merged the PR.

After that, the user can release the lead Claude session and you own the project until launch.

---

## One thing the lead session never did and you should

**Visually walk the app on the simulator or a real device.** The lead session ran 138 unit tests on every fix but never opened the simulator window and clicked through the tabs. Pinned-down logic is necessary but not sufficient — the user surfaced HEIC thumbnails / 3302 errors / "compression failed" dialogs that no unit test could catch.

Before declaring any phase done, do this:

1. `mcp__xcodebuildmcp__build_run_sim` (boots the sim and installs)
2. Walk through Compress, Stitch, MetaClean, Settings tabs
3. Try the user-reported flows: import a HEIC, stitch with a still, drag-reorder a clip, long-press a clip, hit Sort by Date
4. Take screenshots with `mcp__xcodebuildmcp__screenshot` and review

That visual check catches what tests miss.

---

**End of Kickstarter.** Welcome to the project.
