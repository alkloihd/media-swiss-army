# KICKSTARTER — paste this into next session

## When you open Claude Code at your Mac

Open a fresh Claude Code session in this repo:
```
/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR
```

## The prompt to paste

```
Continuing the Media Swiss Army iOS app project from session 2026-05-03.

Branch: feature/phase-3-stitch-ux-and-photos (already pushed to GitHub)
Latest TestFlight build (Build 12) is live on main with core 3-tab functionality.

Read these in order before doing anything:
1. .agents/work-sessions/2026-05-03/handoffs/HANDOFF-v2.md  (full context + 7-commit phase-3 plan)
2. .agents/work-sessions/2026-05-03/backlog-archive/BACKLOG-stitch-photos-and-share-extension.md  (6 backlog items with user spec)
3. AGENTS.md §9 (XcodeBuildMCP integration)

After reading, verify state:
- git branch --show-current   (should be feature/phase-3-stitch-ux-and-photos)
- gh auth status              (should be alkloihd, with repo + workflow scopes)
- xcodebuildmcp session_show_defaults  (project + scheme + simulator preconfigured)

Phase 3 plan (HANDOFF-v2 §"Phase 3 work plan") — 7 commits in order:
1. AVAssetWriter migration with smart bitrate caps (foundational)
2. Audio Background Mode (opt-in toggle, kills 30-sec ceiling)
3. Photos as first-class media (HEIC/JPEG everywhere)
4. iMovie-style drag-from-end + live trim preview with auto-play
5. iOS Share Extension + App Group
6. Multi-clip parallel encoding on Pro phones
7. Final red team + simulator E2E walkthrough

Workflow:
- Each commit: dispatch Opus 4.7 subagent to implement, then pr-review-toolkit:code-reviewer (opus) to red team, apply findings, build green via XcodeBuildMCP, screenshot proof, AI-CHAT-LOG entry by haiku scribe, then move on
- Use XcodeBuildMCP build_run_sim + screenshot heavily so I can see UI changes live before each commit lands
- DO NOT push to main until all 7 commits done and reviewers green — final merge triggers ONE TestFlight build with everything

Start: build_run_sim to confirm current state on simulator. Screenshot all 3 tabs. Then propose Commit 1 task list using superpowers:writing-plans skill, dispatch Opus subagent for it.
```

## What you'll see when the session starts

- The repo is on `feature/phase-3-stitch-ux-and-photos`. Latest commit `6df0184` (HANDOFF-v2)
- Main branch has Build 12 deployed. Do NOT push to main during phase 3 — only at the end
- Test fixture mp4 at `/tmp/sample_test_video.mp4` is in iPhone 16 Pro sim Photos library (survives reboot)
- All review findings from Build 11/12 testing are logged in BACKLOG items 5 + 6 with user-verbatim direction

## TestFlight notes

- Auto-deploys on push to main only — phase 3 work on the feature branch will NOT trigger TestFlight uploads
- When phase 3 is fully done + merged → one final big TestFlight build (Build 13+) with all features
- API keys + secrets already configured in GitHub repo settings; no setup needed

## If gh auth fails

If a fresh session can't reach github via `gh`:
```
gh auth login --web
# pick: github.com → HTTPS → yes (use git creds) → web browser → authenticate
```

But it shouldn't fail on the same Mac — auth is in macOS Keychain.

## What user (you) does during phase 3

Just watch + course-correct. I'll drive the simulator visually so you see every change. If you see something off, tell me. Otherwise it auto-pilots through all 7 commits.

End of kickstarter.
