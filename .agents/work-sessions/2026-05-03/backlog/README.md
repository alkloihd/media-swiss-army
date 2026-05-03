# Backlog — Codex / next-agent task list

**Purpose:** This folder contains structured, ready-to-pick-up tasks for the next agent (Codex, Claude, or human). Each task lives in its own file with: scope, success criteria, the exact files to touch, code sketches where helpful, and any prereqs.

**Order of operations** (read top-to-bottom):

1. Read `AGENTS.md` Part 16 (Codex Onboarding) at the repo root for environment setup.
2. Read `.agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md` Part 7 for the v1.0 launch roadmap.
3. Read each `TASK-*.md` in this folder, in priority order (numeric prefix = priority).
4. Pick a task, branch off `main`, ship it, open a PR.

**Each task is self-contained** — you don't need session history to start.

---

## Task index

### 🚨 Pre-launch must-haves (block a polished v1.0 launch)

| File | Title | Estimated effort |
|---|---|---|
| `TASK-01-still-bake-constant-time.md` | Optimise still-image bake to be O(1) regardless of duration | 1-2h |
| `TASK-02-adaptive-meta-marker-registry.md` | Data-driven Meta-glasses fingerprint detection | 4-6h |
| `TASK-03-faster-batch-metaclean.md` | Concurrent batch with single completion toast | 3-4h |
| `TASK-04-dev-y-copy-polish.md` | Strip engineering-flavored UI copy | 2h |
| `TASK-05-onboarding-screen.md` | First-launch 3-card explainer | 2-3h |
| `TASK-06-app-icon-and-svgs.md` | App icon (1024×1024) + tab/menu SVGs | 2-4h (designer) |
| `TASK-07-privacy-policy-page.md` | GitHub Pages privacy policy | 1h |
| `TASK-08-screenshots-and-preview-video.md` | App Store assets | 2-3h |
| `TASK-09-store-review-prompt.md` | SKStoreReviewController after 3 cleans | 30min |
| `TASK-10-settings-explainer.md` | "What MetaClean does" Settings section | 1h |
| `TASK-11-apple-small-business-program.md` | Enrol in 15% commission tier | 5min (user) |

### 🔧 Polish + UX upgrades (post-MVP, pre-paid-launch)

| File | Title | Estimated effort |
|---|---|---|
| `TASK-12-long-press-preview-bottom.md` | (Optional) Move long-press preview to bottom editor area | 1-2h |
| `TASK-13-centroid-pinch-zoom.md` | iMovie-style content-stays-under-fingers zoom | 2-3h |
| `TASK-14-share-extension.md` | iOS Share Extension target | 4-6h |
| `TASK-15-photo-bake-progress-detail.md` | Per-still progress sub-bar (already partial in PR #8) | 1h |
| `TASK-16-error-message-polish.md` | User-actionable error copy | 1h |

### 🛠 Developer experience

| File | Title | Estimated effort |
|---|---|---|
| `TASK-17-dev-iterate-script.md` | scripts/dev-iterate.sh + pre-push hook for wireless device push | 1-2h |
| `TASK-18-apple-ci-checks.md` | Cloud CI: xcodebuild test on macos-26, privacy manifest validation | 2-3h |
| `TASK-19-codex-mcp-setup.md` | Codex local config to mirror Claude Code's xcodebuildmcp setup | 30min |

### 🎯 Pro-tier IAP candidates (after v1.0 ships)

| File | Title | Estimated effort |
|---|---|---|
| `TASK-20-pro-tier-iap.md` | $9.99 IAP — unlock advanced features | 1-2 days |
| `TASK-21-mac-app-catalyst.md` | Mac via Mac Catalyst | 1 day |
| `TASK-22-apple-watch-quick-clean.md` | Watch app: clean last AirDropped photo | 1 day |
| `TASK-23-auto-clean-on-import.md` | BLE-paired Meta device → auto-clean trigger | 2-3 days |

---

## Working contract for the next agent

- Always branch off `main`, never push to `main` directly
- One PR per task. CI must pass (4 checks) before merge
- Local sim test (`mcp__xcodebuildmcp__test_sim`) must pass — every task with a code change
- Never edit `.git/`, `.claude/`, or `.codex/` config without confirmation
- Every PR description ends with: `🤖 Generated with [Claude Code or Codex](URL)` so attribution is clear
- After every task: append a 1-line summary to `.agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md`

## Audit reports already on disk

Read these before starting — they list known issues with file:line references:

- `../audits/RED-TEAM-PRE-SHIP.md` — pre-ship review of the Phase 3 PR
- `../audits/RED-TEAM-HOTFIX-2.md` — stills-in-stitch hotfix audit
- `../audits/RED-TEAM-CHRONO-SORT.md` — sort feature audit
- `../audits/AUDIT-01-concurrency.md` through `../audits/AUDIT-08-feature-gaps.md` — comprehensive 8-agent audit launched 2026-05-03 (in progress)

Synthesised audit findings will be appended to each task file as they complete.
