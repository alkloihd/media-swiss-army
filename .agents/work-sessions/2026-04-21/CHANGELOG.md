# Changelog — 2026-04-21 Session

Reverse chronological. Agent identity: `[AGENT-TYPE/MODEL]`.

---

## 2026-04-22 (IST, session extends past midnight)

### 03:05 — [solo/opus] [PERF] Applied easy perf wins from audit

- `lib/probe.js` — added mtime-keyed in-memory cache (`Map<filePath, {mtimeMs, data}>`) to avoid redundant ffprobe spawns when the same file is probed multiple times in a session
- `lib/jobQueue.js` — split the single `PQueue({concurrency: 2})` into two lanes: `_hwQueue` (concurrency 2, for VideoToolbox jobs — capped at M2 Max's 2 encode engines) and `_swQueue` (concurrency 3, for software encoders — runs concurrently with HW lane instead of blocking behind it)
- `addJob()` detects HW by scanning `pass1Args + ffmpegArgs` for `videotoolbox`; routes to the correct lane
- `CLAUDE.md` — fixed stale concurrency line (was `Concurrency: 4`, now reflects actual 2-lane shape)
- Verification: `node --check` clean on both files, `npx eslint` 0 errors (1 pre-existing warning unchanged)
- Skipped: SVT-AV1 `-svtav1-params lp=8` (low-impact, only helps AV1 jobs, not worth the risk before iOS migration)

### 03:00 — [team:design-pipeline-port/lead=opus] [INFRA] Team created + 2 teammates spawned

- `TeamCreate design-pipeline-port` — persistent team with shared task list
- Spawned `skills-porter` (general-purpose/sonnet) — owns `.agents/skills/design-pipeline/**`
- Spawned `review-ui-builder` (frontend-builder/sonnet) — owns `design-review/**`
- Dropped `scribe` from initial plan — lead (me) handles session logs directly
- Team members spawn via Agent tool with `team_name` + `name` params; they work independently with non-overlapping file ownership

### 02:50 — [teammate:ffmpeg-expert/sonnet] [AUDIT] Performance audit of web app

Verdict: **YES — app is fast enough to use productively during iOS migration**

- `lib/jobQueue.js:50` uses concurrency 2 (not 4 as docs claimed) — actually correct for 2 VT engines
- `lib/ffmpeg.js:177-179` correctly sets `-threads 0` for SW encoders only
- `lib/ffmpeg.js:170-172` zero-copy VT pipeline correct (`-hwaccel videotoolbox -hwaccel_output_format videotoolbox_vld` when no filters)
- Both VT engines exploited when queue has 2+ VT jobs
- Easy wins surfaced: HW/SW queue split (EASY), probe cache (EASY), SVT-AV1 lp param (EASY)
- Not worth changing: worker threads, server-side thumbnail cache, `execFile` for ffprobe

### 02:35 — [solo/opus] [INFRA] Opened work session folder `.agents/work-sessions/2026-04-21/`

- Created `AI-CHAT-LOG.md`, `CHANGELOG.md`
- Will create `HANDOFF.md` at end of session

### 02:20 — [solo/opus] [DECISION] Design pipeline port plan approved

- Target: `.agents/skills/design-pipeline/` (shared with Codex)
- Firebase dropped entirely — local-only review UI
- Team shape: 3 named teammates (`skills-porter`, `review-ui-builder`, `scribe`)
- Authoring via `skill-creator` skill

### 01:30 — [3x subagent:Explore/sonnet] [RESEARCH] Surveyed 3 design-pipeline source repos

- KinWoven `.claude/skills/` — harness patterns (AGENTS.md protocol, session logging)
- milo-design-pipeline — **the real pipeline** (Python + Gemini 3.1 Pro/Flash Image)
- MILO-APP-CLEAN — production Next.js consumer (reference)

### 01:00 — [solo/opus] [DECISION] iOS pivot confirmed; Firebase dropped

- Native Swift/SwiftUI + VideoToolbox + AVFoundation + PhotoKit
- No WebView wrappers
- iOS dev moves to new chat after this session's handoff

## 2026-04-21

### 20:30 — [solo/opus] [INFRA] Merged `feature/metaclean-stitch` → `main`

- Commit `28e914d` on `origin/main`
- Public repo default branch now reflects v1.2

### 20:15 — [solo/opus] [FEATURE+FIX] v1.2 bundle commit + push

- Commit `e2fdd26` on `feature/metaclean-stitch`
- 28 files changed, 3,085 insertions / 11,227 deletions
- New features: 2D preset matrix, visual stitch timeline, two-pass software encoding, cosmic theme
- Fixes: dead `buildCommand` branch, `/api/stitch/probe` GET→POST, ESLint globals, theme dedup
- Hygiene: untracked 14 already-tracked `Docs/` and 2026-02-24 session files
- Smoke test: server boots, VideoToolbox detected, endpoints respond

### 20:00 — [solo/opus] [FIX] ESLint flat-config ignore + untrack public-repo-unfriendly docs

- `eslint.config.js` — moved `ignores` to its own root-level config object; added `node_modules.nosync/**`
- `git rm --cached -r Docs/ .agents/work-sessions/2026-02-24/` — 14 files untracked

### 19:30 — [teammate:general-purpose/sonnet] [INFRA] `.gitignore` hygiene updates

- Added: `.playwright-mcp/`, `.superpowers/`, `Docs/`, `screenshots/`, `.claude/plans/`, `.claude/settings*.json`, `.agents/work-sessions/`
- Flagged: 14 already-tracked files that would leak unless untracked (handled in next step)

### 19:30 — [teammate:frontend-builder/sonnet] [FIX] Frontend blockers resolved

- `matrix.js` + `stitch.js` — added per-file `/* global ... */` for undefined browser globals
- `theme.js` **deleted** (dead code duplicating inline `data-theme="dark"`)
- `index.html` — removed orphaned `theme.js` import

### 19:30 — [teammate:ffmpeg-expert/sonnet] [FIX] Backend blockers resolved

- `lib/ffmpeg.js` — removed unused destructure, deleted dead `buildCommand` two-pass branch
- `server.js` — removed unused `readdirSync` import, converted `/api/stitch/probe` GET→POST

### 19:00 — [solo/opus] [REVIEW] Triage of unpushed + uncommitted v1.2 work

- 3 parallel reviewers (backend/frontend/security) identified 4 code blockers + repo hygiene issues
- All verdicts: FIX FIRST (nothing catastrophic, nothing shippable as-is)
