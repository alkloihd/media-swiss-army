# AGENTS.md -- Video Compressor Unified Protocol

<!-- Open Standard | Claude Code + Codex | v2.1 | 2026-05-02 -->

This is the single source of truth for all agents working on Video Compressor. Every AI assistant, including Claude Code, Codex, Gemini CLI, and future tools, MUST read this file at session start.

`CLAUDE.md` is only a pointer to this file. Do not duplicate project context there.

---

## Part 1: The 7 Principles

These are non-negotiable for this repo.

1. **Start with what is unfinished** before accepting new directions. Show the current priority.
2. **Capture every idea, finish current work first.** When Rishaal mentions something new mid-task, add it to the running list and keep the current work moving.
3. **Push back gently on scope creep.** One task completed is better than five tasks started.
4. **Match response to need.** Do not spin up a large team when one direct edit will do.
5. **End every session with a clear handoff.** Session logs are Rishaal's external memory and are not optional.
6. **Channel excitement into priority.** Capture the big ideas, then execute in the order that reduces risk fastest.
7. **Do not silently drop earlier asks.** If something was requested earlier and remains unaddressed, surface it.

---

## Part 2: Running Bucket

Session memory lives in `.agents/work-sessions/`.

Root files:

- `.agents/work-sessions/RUNNING-LIST.md` tracks `DONE`, `IN PROGRESS`, `QUEUED`, and `BACKBURNER`.
- `.agents/work-sessions/DREAMS.jsonl` is an append-only idea log for larger future work.
- `.agents/work-sessions/PROTOCOL.md` is the quick-reference session protocol.

Per-day folders:

```text
.agents/work-sessions/YYYY-MM-DD/
  ai-chat-log.md or AI-CHAT-LOG.md
  STATUS.md
  TASK-MANIFEST.md
  CHANGELOG.md
  handoffs/
```

When Rishaal mentions something new:

1. Capture it in `RUNNING-LIST.md` or the current `TASK-MANIFEST.md`.
2. Say it was captured in one short line.
3. Continue the active task unless he explicitly switches priorities.

When there are 3+ tasks, create or update `TASK-MANIFEST.md`.

---

## Part 3: Project Overview

Video Compressor is a local-first media utility with a web UI. It uses Node.js, Express, WebSocket progress updates, FFmpeg, FFprobe, ExifTool, and Apple Silicon hardware acceleration through VideoToolbox.

Primary local URL:

```bash
node server.js
# http://localhost:3000

PORT=4000 node server.js
# http://localhost:4000
```

Prerequisites:

- Node.js >= 18
- FFmpeg at `/opt/homebrew/bin/ffmpeg`
- FFprobe at `/opt/homebrew/bin/ffprobe`
- ExifTool for MetaClean at `/opt/homebrew/bin/exiftool` or on PATH
- macOS with Apple Silicon for best hardware acceleration; software fallback works where FFmpeg supports it

No cloud dependency exists in the current app. For the planned iOS port, Firebase is optional and only needed if future requirements include accounts, cloud sync, analytics, crash reporting, Remote Config, app distribution support, shared storage, or remote AI workflows.

Recommended iOS direction: native SwiftUI + AVFoundation + VideoToolbox + Photos/Files APIs. Keep processing on device unless a future product decision explicitly requires cloud features.

---

## Part 4: Current App Truth

### Built Features

| Area                 | Current state                                                                                                                                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compress             | Built. Drag/drop, file picker, path input, upload/probe, thumbnails, Plyr preview, trim, crop, matrix settings, target-size helper, codec/format/audio/FPS/two-pass/metadata/fast-start controls, WebSocket progress, download links. |
| Stitch               | Built. Clip upload/probe, thumbnail timeline, SortableJS reorder, interact.js trim handles, optional compression, result download. Known risk: trim shape drift between frontend and backend needs audit.                             |
| MetaClean            | Built. ExifTool detection, image/video upload, attribution/privacy modes, surgical tag removal, removed/preserved report UI, clean download. Known risk: uploaded clean files live in temp output unless downloaded.                  |
| Download             | Built. `GET /api/download?path=` streams output as attachment.                                                                                                                                                                        |
| Design Review        | Built as a local no-build static review tool under `design-review/`; not currently served by the main Express app.                                                                                                                    |
| iOS/macOS native app | Planned. Draft specs and plans exist under `Docs/superpowers/` and `docs/superpowers/`.                                                                                                                                               |

### API Surface

| Method   | Path                                | Purpose                                   |
| -------- | ----------------------------------- | ----------------------------------------- |
| `POST`   | `/api/upload`                       | Upload up to 20 files with Multer.        |
| `GET`    | `/api/probe?path=`                  | Return flat FFprobe metadata.             |
| `GET`    | `/api/stream?path=`                 | Stream media with range request support.  |
| `GET`    | `/api/thumbnail?path=&time=&width=` | Generate JPEG thumbnail with FFmpeg.      |
| `POST`   | `/api/compress`                     | Queue compression job(s).                 |
| `GET`    | `/api/jobs`                         | List job status and progress.             |
| `DELETE` | `/api/jobs/:id`                     | Cancel queued or running job.             |
| `GET`    | `/api/hwaccel`                      | Return VideoToolbox capability detection. |
| `GET`    | `/api/exiftool`                     | Return ExifTool detection status.         |
| `GET`    | `/api/metadata?path=`               | Return ExifTool JSON metadata.            |
| `POST`   | `/api/metaclean`                    | Clean metadata from one or more files.    |
| `POST`   | `/api/stitch/probe`                 | Probe stitch compatibility.               |
| `POST`   | `/api/stitch`                       | Stitch clips with optional compression.   |
| `GET`    | `/api/download?path=`               | Download a local output file.             |

### WebSocket Events

Compression:

- `progress`
- `complete`
- `error`

Workflow-specific events:

- `metaclean-complete`
- `metaclean-error`
- `stitch-complete`
- `stitch-error`

MetaClean currently emits per-file WebSocket events from the backend, but the frontend does not consume all of them. Treat that as a P1 audit item.

---

## Part 5: Architecture

```text
Browser
  -> POST /api/upload       -> Multer temp upload
  -> GET /api/probe         -> lib/probe.js via ffprobe
  -> POST /api/compress     -> lib/ffmpeg.js builds args
                              -> lib/jobQueue.js queues FFmpeg
                              -> WebSocket progress
  -> POST /api/metaclean    -> lib/exiftool.js
  -> POST /api/stitch       -> lib/stitch.js
```

Important files:

| Path                         | Responsibility                                                                                            |
| ---------------------------- | --------------------------------------------------------------------------------------------------------- |
| `server.js`                  | Express server, static files, all API routes, WebSocket broadcast, path guards.                           |
| `lib/ffmpeg.js`              | FFmpeg command builder, six-tier presets, bitrate capping, scaling, trim/crop/FPS/audio/metadata options. |
| `lib/probe.js`               | FFprobe metadata extraction.                                                                              |
| `lib/hwaccel.js`             | VideoToolbox capability detection and encoder fallback mapping.                                           |
| `lib/jobQueue.js`            | Job queue with separate HW/SW lanes, progress parsing, EventEmitter events.                               |
| `lib/exiftool.js`            | ExifTool detection, metadata reads, surgical tag removal, clean-copy report generation.                   |
| `lib/stitch.js`              | Lossless concat and re-encode stitch logic.                                                               |
| `public/index.html`          | Single-page app shell with Compress, Stitch, and MetaClean tabs.                                          |
| `public/css/styles.css`      | CSS variable theme, layout, components, responsive behavior.                                              |
| `public/js/app.js`           | Frontend orchestrator and central `appState`.                                                             |
| `public/js/compression.js`   | Compression controls and estimate logic.                                                                  |
| `public/js/matrix.js`        | Interactive compression matrix.                                                                           |
| `public/js/filemanager.js`   | File cards, thumbnails, status, per-file resolution, download link.                                       |
| `public/js/progress.js`      | WebSocket client and progress handling.                                                                   |
| `public/js/stitch.js`        | Stitch workflow UI and client requests.                                                                   |
| `public/js/metaclean.js`     | MetaClean workflow UI and client requests.                                                                |
| `public/js/tabs.js`          | Compress/Stitch/MetaClean tab navigation.                                                                 |
| `public/js/timeline-deps.js` | Third-party timeline dependency helpers.                                                                  |
| `public/js/trim.js`          | Compress trim controls.                                                                                   |
| `public/js/crop.js`          | Compress crop controls.                                                                                   |
| `public/js/player.js`        | Plyr preview integration.                                                                                 |
| `public/js/dragdrop.js`      | Compress drag/drop, file input, and path input.                                                           |

Queue truth:

- Hardware jobs use `PQueue({ concurrency: 2 })`.
- Software jobs use `PQueue({ concurrency: 3 })`.
- The old docs that say single `PQueue concurrency: 4` are stale.

Theme truth:

- The CSS includes dark and light variables.
- `public/index.html` currently forces dark mode.
- The old docs that describe a Light/System/Dark localStorage toggle are stale.

---

## Part 6: Compression Settings Truth

The current preset names are:

- `lossless`
- `maximum`
- `high`
- `balanced`
- `compact`
- `tiny`

Legacy aliases are accepted by `lib/ffmpeg.js`:

| Legacy      | Current    |
| ----------- | ---------- |
| `max`       | `maximum`  |
| `small`     | `compact`  |
| `streaming` | `balanced` |

Current codecs:

| Friendly codec | Hardware encoder      | Software encoder | Containers    |
| -------------- | --------------------- | ---------------- | ------------- |
| `h264`         | `h264_videotoolbox`   | `libx264`        | MP4, MOV, MKV |
| `h265`         | `hevc_videotoolbox`   | `libx265`        | MP4, MOV, MKV |
| `av1`          | none                  | `libsvtav1`      | MP4, MKV      |
| `prores`       | `prores_videotoolbox` | `prores_ks`      | MOV           |

Current resolution targets include:

- original
- 2160p / 4K
- 1440p / 2K
- 1080p
- 720p
- 480p
- 360p

Important audit risks:

- Backend skips scaling only when source height equals target height, not when target is larger than source. Verify no-upscale behavior end to end.
- Frontend HW/SW selection influences estimates, but backend still selects hardware when available. Verify or fix before calling the toggle production-ready.
- Two-pass is disabled for hardware encoders and ProRes.
- `buildArgs()` currently adds VideoToolbox hardware decode args broadly; verify software/non-mac behavior.

---

## Part 7: Agent Roles and File Ownership

Never edit the same file from two parallel workers.

| Domain                         | Owner role                       | Files                                                                                |
| ------------------------------ | -------------------------------- | ------------------------------------------------------------------------------------ |
| Lead and synthesis             | `lead`                           | Task manifest, final synthesis, file ownership decisions.                            |
| Backend API and safety         | `backend-api` or `ffmpeg-expert` | `server.js`, route contracts, path validation.                                       |
| FFmpeg and compression         | `ffmpeg-expert`                  | `lib/ffmpeg.js`, `lib/hwaccel.js`, `lib/probe.js`, `lib/jobQueue.js`.                |
| Stitch and MetaClean internals | `workflow-specialist`            | `lib/stitch.js`, `lib/exiftool.js`, `public/js/stitch.js`, `public/js/metaclean.js`. |
| Frontend UI                    | `frontend-builder`               | `public/**/*`.                                                                       |
| Compression diagnostics        | `compression-diagnostics`        | Analysis and recommendations, no ownership unless assigned.                          |
| Documentation and sessions     | `scribe` or `docs-auditor`       | `AGENTS.md`, `CLAUDE.md`, `.agents/**/*.md`, `.claude/**/*.md`, `.codex/**/*.md`.    |
| Code review                    | `code-reviewer`                  | Review only unless explicitly assigned a fix.                                        |

Existing Claude agent files live in `.claude/agents/`.

Current model labels may include:

- Claude: `opus`, `sonnet`, `haiku`, or exact version when known.
- Codex: `gpt-5`, `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex`, or exact runtime model when known.
- Other tools: record the tool and model exactly as reported.

---

## Part 8: Skills

Shared project skills exist in three mirrored locations:

- `.agents/skills/`
- `.claude/skills/`
- `.codex/skills/`

Current domain skills:

| Skill                  | Use when                                                                    |
| ---------------------- | --------------------------------------------------------------------------- |
| `compress-video`       | Compressing one or more videos.                                             |
| `diagnose-compression` | Output is too large, quality is poor, or compression behavior is confusing. |
| `batch-process`        | Multi-file or folder workflows.                                             |
| `optimize-quality`     | Choosing best quality/size settings for specific content.                   |
| `metadata-tools`       | Inspecting, preserving, or stripping metadata, including MetaClean.         |

Rules:

- Keep mirrored skill files byte-identical unless a tool-specific difference is intentional and documented.
- Skill frontmatter should begin at byte 0 with `---`.
- Do not reference nonexistent files such as `lib/presets.js`; presets live in `lib/ffmpeg.js` and frontend estimates live in `public/js/compression.js`.

---

## Part 9: Tooling and MCP

### Claude Code

Project settings:

- `.claude/settings.json`
- `.claude/settings.local.json`

MCP servers should be configured with official Claude Code commands, using user scope for personal cross-project tools:

```bash
claude mcp add --scope user xcodebuildmcp -- xcodebuildmcp mcp
```

### Codex

Codex user config:

- `/Users/rishaal/.codex/config.toml`

Recommended XcodeBuildMCP entry:

```toml
[mcp_servers.XcodeBuildMCP]
command = "xcodebuildmcp"
args = ["mcp"]
```

Restart Codex after editing TOML so the MCP server is loaded into the tool list.

### XcodeBuildMCP

Install or refresh:

```bash
npm install -g xcodebuildmcp@latest
xcodebuildmcp --help
xcodebuildmcp tools
```

Requirements from upstream docs:

- macOS 14.5+
- Xcode 16.x+
- Node.js 18+ for npm installation

This repo currently has Xcode 16.0 installed at `/Applications/Xcode.app/Contents/Developer`.
AXE 1.6.0 installed at `/opt/homebrew/bin/axe` for simulator UI automation.

#### Project skills (mandatory read before tool use)

Before calling any `xcodebuildmcp` tool — `mcp__xcodebuildmcp__*` (Claude Code) or shelling out via `xcodebuildmcp <workflow> <tool>` (Codex) — read the matching skill file:

- **Claude Code (MCP tools path)**: `.agents/skills/xcodebuildmcp-mcp/SKILL.md`
- **Codex (CLI path)**: `.agents/skills/xcodebuildmcp-cli/SKILL.md`

Codex does not auto-load skill files; agents must `cat` the relevant SKILL.md before the first XcodeBuildMCP call in a session. Symlinks at `.claude/skills/xcodebuildmcp-{mcp,cli}` are for Claude Code skill discovery only.

#### Workflow groups

Configured in `.xcodebuildmcp/config.yaml` at the repo root. Default profile enables: `simulator, simulator-management, ui-automation, debugging, logging, device, project-discovery, project-scaffolding, coverage, utilities`. Edit the YAML to add/remove. CLI usage (`xcodebuildmcp <workflow> ...`) ignores the gate — all workflows are reachable from the binary regardless.

#### Session start protocol

1. Call `mcp__xcodebuildmcp__session_show_defaults` (or `xcodebuildmcp setup`) once per session to confirm project/scheme/simulator.
2. Use `discover_projs` only if step 1 reports missing context.
3. Prefer combined commands (`build_run_sim`) over chained separate calls.
4. For physical-device work, the user must complete one-time signing via Xcode "Signing & Capabilities → Automatically manage signing → Team". After that, all device builds are MCP-driven.

---

## Part 10: Safety Rules

Always follow these rules:

- Never edit `node_modules/` or `node_modules.nosync/`.
- Never edit `package-lock.json` directly; use npm commands.
- Never force push.
- Never run `git reset --hard`, `git clean -f`, `git branch -D`, or destructive equivalents unless the user explicitly requests that exact operation.
- Never commit `.env`, secrets, credentials, PEM/key files, private keys, or API tokens.
- Use `spawn()` or `execFile()` for media commands; never shell-concatenate user paths into `exec()`.
- Treat local path access as sensitive. `isSafePath()` is broad by design for a local tool, but changes to it require security review.
- For frontend rendering, avoid inserting user-controlled filenames, metadata, or errors via `innerHTML`; use DOM text nodes when practical.
- Run formatting and validation after edits.

Required validation after editing JS/CSS/HTML/JSON:

```bash
npx prettier --write <changed-files>
npx eslint <changed-js-files>
node --check server.js
for f in lib/*.js; do node --check "$f"; done
```

For docs-only work:

```bash
npx prettier --check AGENTS.md CLAUDE.md ".agents/**/*.md" ".agents/**/*.jsonl" ".claude/**/*.md" ".codex/**/*.md"
```

Known current verification state:

- App-only backend syntax checks pass.
- App-only Prettier checks pass.
- App-only ESLint currently has warnings but no errors.
- `npm run check` can fail because broad globs include untracked `.claude/worktrees/` and `design-review/`.
- `npm audit` currently reports high/moderate advisories that need follow-up.

---

## Part 11: Work Session Protocol

Timezone standard: SAST.

Use:

```bash
TZ=Africa/Johannesburg date "+%Y-%m-%d %H:%M SAST"
```

Log format:

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

Tags:

- `[SETUP]`
- `[FEAT]`
- `[FIX]`
- `[DEBUG]`
- `[RESEARCH]`
- `[DECISION]`
- `[DOCS]`
- `[REVIEW]`
- `[DEPLOY]`
- `[HANDOFF]`
- `[ROLLBACK]`
- `[SEC]`
- `[PLANNING]`
- `[INFRA]`
- `[TEST]`

Rules:

- Use real timestamps only.
- Append-only for established log entries.
- Include evidence: file paths, commands, outputs, source links, or commit hashes.
- Do not fabricate verification.
- Create `STATUS.md` every session.
- Create `TASK-MANIFEST.md` when there are 3+ tasks.
- Put handoffs in `handoffs/` with descriptive names.

---

## Part 12: Current Backlog Priority

P0/P1 next items:

1. Protocol and docs drift cleanup. In progress on 2026-05-02.
2. Configure XcodeBuildMCP across Claude Code and Codex, then restart sessions to expose tools.
3. Create the 7-8 lane audit and dashboard in a fresh Claude Code session.
4. Fix local verification pollution from `.claude/worktrees/` and `design-review/`.
5. Address `npm audit` advisories.
6. Add real automated tests for path safety, probe, compression command building, stream ranges, job cancellation, MetaClean, Stitch, and WebSocket progress.
7. Audit and fix Stitch trim request shape drift.
8. Harden frontend XSS surfaces that render filenames/metadata/errors.
9. Decide native iOS plan: SwiftUI + AVFoundation/VideoToolbox first, Firebase optional only for cloud features.

Backburner:

- Serve `design-review/` or replace it with `public/audit/`.
- Move MetaClean outputs for uploaded files into `~/Movies/Video Compressor Output`.
- Add a live `/api/audit` endpoint only if static audit JSON is insufficient.
- Add Xcode project scaffold after audit and native app decision.

---

## Part 13: Future 8-Lane Audit Charter

The next major audit should dispatch these lanes:

1. `lead/synthesis`: manifest, ownership, final report.
2. `backend/API/security`: routes, path access, stream/range, upload limits, download safety.
3. `FFmpeg/compression`: presets, scaling, HW/SW, two-pass, progress, output naming.
4. `frontend/UI`: usability, responsive layout, visual polish, accessibility, XSS.
5. `Stitch/MetaClean`: trim correctness, silent audio, sync/async behavior, output paths, reports.
6. `docs/skills/protocol`: AGENTS/CLAUDE/skills/session logs/backlogs.
7. `QA/stress/performance`: reproducible stress commands, queue behavior, long files, failure modes.
8. `iOS port strategy`: SwiftUI/AVFoundation/VideoToolbox plan, Firebase optionality, XcodeBuildMCP setup.

Deliverables:

- `public/audit/` multi-page static dashboard.
- `public/audit/data/audit.json` checklist and findings data.
- Built vs left-to-build report.
- Stress-test matrix.
- iOS port recommendation.

---

## Part 14: Non-Negotiables

1. Local-first and privacy-first unless the user explicitly chooses cloud features.
2. Evidence before completion claims.
3. AGENTS.md is canonical.
4. Finish current task before expanding scope.
5. Log meaningful work.
6. Prefer existing patterns over new abstractions.
7. Keep frontend no-build unless there is a clear reason to add a build step.
8. Keep iOS port native-first unless there is a product reason to preserve the web stack.
