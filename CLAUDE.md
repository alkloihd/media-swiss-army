# Video Compressor

## 1. Project Overview

A local video compression application with a web-based UI that leverages FFmpeg and Apple Silicon hardware acceleration (VideoToolbox). Designed for macOS with M-series chips, it provides drag-and-drop batch video compression with real-time progress monitoring via WebSocket.

**URL:** `http://localhost:3000` (or use `PORT=4000 node server.js`)

### How to Run

```bash
npm install        # first time only
node server.js     # start on port 3000
# or
PORT=4000 node server.js
# or double-click start.command in Finder
```

### Prerequisites

- **Node.js** >= 18 (ES modules required)
- **FFmpeg** >= 7.x at `/opt/homebrew/bin/ffmpeg`
- **FFprobe** at `/opt/homebrew/bin/ffprobe`
- macOS with Apple Silicon (M1/M2/M3) for hardware acceleration (software fallback works anywhere)

---

## 2. Architecture

### File Structure

```
VIDEO COMPRESSOR/
  server.js                  # Express server, WebSocket, all API routes
  package.json               # Dependencies, scripts, ES module config
  start.command              # macOS double-click launcher
  CLAUDE.md                  # This file
  eslint.config.js           # Flat ESLint config (ES2024, browser+node globals)
  .prettierrc                # Single quotes, trailing commas, 100 char width
  lib/
    ffmpeg.js                # FFmpeg command builder, quality presets, bitrate capping
    probe.js                 # ffprobe metadata extraction (flat format)
    hwaccel.js               # VideoToolbox detection + encoder fallback mapping
    jobQueue.js              # p-queue wrapper (concurrency:4), progress parsing, events
  public/
    index.html               # Single-page app (Tailwind CDN, Plyr CDN)
    css/styles.css           # Theme system (CSS custom properties, light/dark, glassmorphism)
    js/
      app.js                 # Main orchestrator: state, upload, compression dispatch
      compression.js         # Settings: codec/preset/format/resolution/estimation/custom
      filemanager.js         # File cards, per-video resolution, progress bars
      progress.js            # WebSocket client, auto-reconnect
      player.js              # Plyr video player (preview, playback)
      trim.js                # Trim start/end time controls
      crop.js                # Crop presets (aspect ratio, even dimensions)
      dragdrop.js            # Drag-and-drop, file input, path input
      theme.js               # Theme toggle (light/system/dark), localStorage
  .claude/
    settings.local.json      # Permissions (allow/deny/ask), hooks, env vars
    agents/                  # Agent team definitions (YAML frontmatter)
      ffmpeg-expert.md       # FFmpeg, codec selection, HW accel specialist
      frontend-builder.md    # UI/UX, vanilla JS, Tailwind, Plyr
      compression-diagnostics.md  # Diagnose poor compression, bitrate analysis
      scribe.md              # Lightweight docs agent (haiku model)
      code-reviewer.md       # Code review, ESLint, security (plan mode)
    commands/                # Slash commands
      compress.md            # /compress — quick compression workflow
      diagnose.md            # /diagnose — compression quality diagnostics
      status.md              # /status — server/project status check
    hooks/                   # Hook shell scripts (PreToolUse, PostToolUse, etc.)
      block-node-modules.sh  # Block editing node_modules/
      block-package-lock.sh  # Block editing package-lock.json
      block-destructive-git.sh  # Block force push, reset --hard, etc.
      auto-prettier.sh       # Auto-format on edit (.js/.css/.html/.json)
      auto-eslint.sh         # Auto-lint on edit (.js)
      syntax-check.sh        # node --check on backend files
      backend-restart-notice.sh  # Remind to restart server
      session-log-prompt.sh  # Log user prompts to session activity
      session-log-stop.sh    # Log session end
    skills/                  # Progressive Disclosure skills (3-level)
      compress-video/SKILL.md
      diagnose-compression/SKILL.md
      batch-process/SKILL.md
      optimize-quality/SKILL.md
      metadata-tools/SKILL.md
    plans/                   # Plan mode output directory
  .agents/
    work-sessions/           # Per-day session logs and handoffs
    plans/                   # Agent team plans
```

### Data Flow

```
[Browser] --> POST /api/upload --> [Multer] --> temp file with extension
          --> GET /api/probe   --> [ffprobe] --> JSON metadata (flat format)
          --> POST /api/compress --> [buildCommand] --> [JobQueue.addJob]
                                                         |
                                    [PQueue concurrency:4] --> [FFmpeg spawn]
                                                                    |
                                    [stderr progress parsing] --> [throttle 1s]
                                                                    |
                                    [WebSocket broadcast] --> [Browser UI update]
```

---

## 3. Tech Stack

| Layer | Technology | Details |
|-------|-----------|---------|
| Backend Runtime | Node.js | ES modules (`"type": "module"`), top-level await |
| HTTP Framework | Express 4.21 | JSON body parser, static file serving |
| WebSocket | ws 8.18 | Real-time progress, auto-reconnect on client |
| File Upload | multer 1.4.5 | Multipart form data, 50GB limit, temp dir |
| Job Queue | p-queue 8.0 | Two lanes: HW queue concurrency 2 (M2 Max has 2 VideoToolbox encode engines), SW queue concurrency 3 |
| Unique IDs | uuid 10.0 | UUIDv4 for job identifiers |
| Video Engine | FFmpeg 7.1.1 | System-installed at `/opt/homebrew/bin/ffmpeg` |
| Frontend CSS | Tailwind CSS (CDN) | No build step, utility classes |
| Video Player | Plyr (CDN) | Custom-themed video player |
| Linting | ESLint 10.x | `npm run lint` |
| Formatting | Prettier 3.8 | `npm run format` |

### npm Scripts

```bash
npm start           # node server.js
npm run dev          # node --watch server.js
npm run lint         # ESLint check
npm run lint:fix     # ESLint auto-fix
npm run format       # Prettier write
npm run format:check # Prettier check
npm run check        # lint + format:check
npm run security     # npm audit
```

---

## 4. Agent Team Structure

### Agents (`.claude/agents/`)

Each agent has YAML frontmatter with `name`, `description`, `tools`, `model`, `permissionMode`.

| Agent | Model | Purpose |
|-------|-------|---------|
| `ffmpeg-expert` | sonnet | FFmpeg commands, codec selection, VideoToolbox HW accel, CRF tuning |
| `frontend-builder` | sonnet | Vanilla JS, CSS custom properties, Plyr, drag-and-drop, WebSocket |
| `compression-diagnostics` | sonnet | Diagnose poor results, bitrate analysis, preset validation |
| `scribe` | haiku | Lightweight: AI-CHAT-LOG, CHANGELOG, HANDOFF, session summaries |
| `code-reviewer` | sonnet | Bug review, security (XSS, path traversal), ESLint, plan mode |

### Commands (`.claude/commands/`)

| Command | Trigger | Description |
|---------|---------|-------------|
| `/compress` | Quick compress | Check server, pick file/preset/resolution, run, report |
| `/diagnose` | Diagnose quality | Probe input/output, compare bitrates, suggest fixes |
| `/status` | Project status | Server status, FFmpeg version, deps, disk, lint check |

### Skills (`.claude/skills/`)

Progressive Disclosure framework (3 levels: YAML frontmatter, workflow steps, deep knowledge).

| Skill | Trigger | Description |
|-------|---------|-------------|
| `compress-video` | "compress this video" | Full compression workflow |
| `diagnose-compression` | "output is bigger" | Diagnose poor compression |
| `batch-process` | "compress all files" | Multi-file batch workflow |
| `optimize-quality` | "best quality setting" | Quality/size tradeoff optimization |
| `metadata-tools` | "show metadata" | Inspect/preserve/strip metadata |

### Hooks (`.claude/hooks/`)

All hooks are external `.sh` scripts referenced from `settings.local.json`.

**PreToolUse (blocking):**
- `block-node-modules.sh` — Blocks Edit/Write to `node_modules/`
- `block-package-lock.sh` — Blocks Edit/Write to `package-lock.json`
- `block-destructive-git.sh` — Blocks `push --force`, `reset --hard`, `clean -f`, `branch -D`

**PostToolUse (auto-fix):**
- `auto-prettier.sh` — Formats `.js/.css/.html/.json` after edit
- `auto-eslint.sh` — Lints `.js` after edit, reports errors
- `syntax-check.sh` — `node --check` on `server.js` and `lib/*.js`
- `backend-restart-notice.sh` — "Server restart needed" after backend edits

**Session tracking:**
- `session-log-prompt.sh` — Logs each user prompt to daily activity log
- `session-log-stop.sh` — Logs session end

### Permissions (`.claude/settings.local.json`)

- **allow**: All standard Bash commands, git read/write ops, npm/npx, ffmpeg/ffprobe, exiftool, file tools (Read, Edit, Write, Grep, Glob)
- **deny**: `.env` files, secrets, credentials, PEM/key files, destructive git commands
- **ask**: `kill`/`pkill`/`killall`, `git push`, `git rebase`, `npm publish`

### Multi-Agent Coordination Rules

For tasks with 2+ independent workstreams, **always prefer creating an agent team** over sequential execution. Use `TeamCreate` when:
- Multiple files/modules can be worked on in parallel
- Cross-layer changes span frontend + backend + lib/ independently
- Research + implementation can happen concurrently
- Any task with parallelizable parts that would take >5 minutes sequentially

Use subagents (Task tool) for focused fire-and-forget tasks where only the result matters.

**File ownership** (prevents merge conflicts):
- `server.js`, `lib/*.js` — ffmpeg-expert or backend teammate
- `public/**/*` — frontend-builder teammate
- `.agents/**/*.md`, `CLAUDE.md` — scribe teammate

**Task sizing**: 3-6 tasks per teammate, self-contained, never two teammates on the same file.

**Skills are shared automatically** — all teammates load `.claude/skills/` on startup along with CLAUDE.md and MCP servers. No extra config needed.

See `AGENTS.md` for the full agent coordination protocol that all teammates read.

### Work Sessions (`.agents/work-sessions/`)

Per-day folders at `.agents/work-sessions/YYYY-MM-DD/`:
- `AI-CHAT-LOG.md` — Timestamped log of every action
- `CHANGELOG.md` — Reverse-chronological feature/fix log
- `HANDOFF.md` — Session handoff for next agent
- `CARRYOVER-PROMPT.md` — Paste into new chat to resume
- `session-activity.log` — Auto-generated by hooks

**Agent Identification Protocol** — Every entry in AI-CHAT-LOG.md and CHANGELOG.md or even the task-manifests in the work sessions folders MUST include:

```
[YYYY-MM-DD HH:MM IST] [AGENT-TYPE/MODEL] [TAG] Description
```

- **AGENT-TYPE**: `solo` (single session), `lead` (team lead), `teammate:NAME` (team member), `subagent` (Task tool)
- **MODEL**: `opus`, `sonnet`, `haiku` — whichever model is running
- **TAG** (required here are some options/examples):
 `[BUILD]`, `[FIX]`, `[FEATURE]`, `[DOCS]`, `[REFACTOR]`, `[PERF]`, `[TEST]`, `[INFRA]`

Example entries:
```
[2026-02-24 14:30 IST] [lead/opus] [FEATURE] Added MetaClean tab navigation
  Actions: Created public/js/tabs.js, modified index.html
  Files: public/js/tabs.js (new), public/index.html (modified)
  Status: Complete

[2026-02-24 14:32 IST] [teammate:ffmpeg-expert/sonnet] [BUILD] Created lib/exiftool.js
  Actions: Implemented detectExifTool(), readMetadataJson(), writeCleanCopy()
  Files: lib/exiftool.js (new)
  Status: Complete
```

When editing AI-CHAT-LOG.md or CHANGELOG.md, **always identify yourself** with agent type + model. Never leave anonymous entries.

---

## 5. API Reference

### POST /api/upload

Upload video files. `multipart/form-data` with field `file` (up to 20 files).

```json
{ "files": [{ "path": "/tmp/.../abc123.mp4", "name": "original.mp4", "size": 52428800 }] }
```

### GET /api/probe?path=`<encoded_path>`

Video metadata via ffprobe. Returns flat format:

```json
{ "duration": 120.5, "width": 1920, "height": 1080, "fps": 29.97, "codec": "h264", "bitrate": 8500000, "size": 127893504, "format": "mov,mp4,m4a,3gp,3g2,mj2", "audioCodec": "aac" }
```

### POST /api/compress

Start compression job(s). Required: `files`, `preset`, `codec`, `format`. Optional: `scale`, `trim`, `crop`, `crf`, `speed`.

```json
{
  "files": [{ "path": "/path/to/video.mp4", "name": "video.mp4" }],
  "preset": "balanced", "codec": "h265", "format": "mp4",
  "scale": "720p", "crf": 28, "speed": "medium"
}
```

### GET /api/stream?path=`<encoded_path>`

Video streaming with HTTP range request support.

### GET /api/thumbnail?path=`<path>`&time=`<timecode>`&width=`<px>`

JPEG thumbnail. Defaults: `time=00:00:02`, `width=320`.

### GET /api/jobs / DELETE /api/jobs/:id

List all jobs / cancel a job (409 if already complete).

### GET /api/hwaccel

Hardware acceleration capabilities:
```json
{ "h264_videotoolbox": true, "hevc_videotoolbox": true, "prores_videotoolbox": true }
```

### WebSocket (same port)

| Event | Payload |
|-------|---------|
| `progress` | `{ type, jobId, percent, speed, fps, eta }` |
| `complete` | `{ type, jobId, outputPath, outputSize, compressedSize }` |
| `error` | `{ type, jobId, error }` |

---

## 6. FFmpeg Presets

### Quality Presets

**Hardware (VideoToolbox) — bitrate-based:**

| Encoder | max | balanced | small | streaming |
|---------|-----|----------|-------|-----------|
| h264_videotoolbox | 20000k | 8000k | 4000k | 5000k |
| hevc_videotoolbox | 12000k | 6000k | 3000k | 4000k |
| prores_videotoolbox | Profile 3 | Profile 2 | Profile 1 | Profile 2 |

**Software — CRF-based:**

| Encoder | max | balanced | small | streaming |
|---------|-----|----------|-------|-----------|
| libx264 | CRF 18/slow | CRF 23/medium | CRF 28/medium | CRF 23/fast |
| libx265 | CRF 22/slow | CRF 28/medium | CRF 32/medium | CRF 28/fast |
| libsvtav1 | CRF 25/4 | CRF 30/6 | CRF 38/8 | CRF 35/6 |

### Custom Preset

When `preset=custom`, CRF and speed are passed directly. For VideoToolbox encoders, CRF is mapped to bitrate (CRF 0 = ~30Mbps, CRF 51 = ~500kbps) and capped at 90% of source bitrate.

### Smart Bitrate Capping

Prevents HW encoder output from exceeding input size:

| Preset | Cap | Effect |
|--------|-----|--------|
| max | None | Full target bitrate |
| balanced | 70% of source | min(target, source * 0.7) |
| streaming | 50% of source | min(target, source * 0.5) |
| small | 40% of source | min(target, source * 0.4) |

### Audio / Format / Resolution

- H.264/H.265: AAC 192k (256k for max)
- ProRes: PCM S16LE (uncompressed)
- AV1: libopus 128k
- Scaling: `scale=-2:HEIGHT` (uses `-2` for even dimensions)
- Metadata: `-map_metadata 0`, `-map 0`, `-movflags +faststart+use_metadata_tags`

---

## 7. Conventions

### Code Style

- **ES Modules everywhere** — `import/export`, never `require()`. `"type": "module"` in package.json.
- **No frontend frameworks** — Vanilla JS + DOM APIs. No React/Vue.
- **Tailwind via CDN** — No build step.
- **FFmpeg via spawn** — Always `child_process.spawn()`, never `exec()`. Prevents shell injection.
- **Async/await** throughout. Top-level await in server.js.

### Module Patterns

- Each frontend JS file exports an `init*()` called from `app.js` DOMContentLoaded
- `app.js` owns central `appState`; other modules import from it
- Backend modules are pure functions (except `JobQueue` class extending `EventEmitter`)
- `probe.js` uses `execFile` (bounded output); `jobQueue.js` uses `spawn` (streaming)

### Naming

- CSS: `--category-name` custom properties, `themed-*` utility classes
- JS: camelCase for vars/functions, PascalCase for classes
- Files: lowercase with hyphens
- API: RESTful `/api/resource` with JSON responses
- Output files: `{original}_COMP.{ext}` next to source (no subfolder)

### Theme System

- CSS custom properties on `:root`/`[data-theme='dark']`/`[data-theme='light']`
- 3-way toggle (Light/System/Dark) with localStorage persistence
- All colors via CSS variables — no hardcoded colors in components

### Error Handling

- Backend: `{ error: "message" }` with HTTP status codes
- Frontend: `showNotification(message, type)` for user alerts
- WebSocket: Auto-reconnect with exponential backoff (1s to 30s)
- FFmpeg: Exit code + stderr for error diagnosis

---

## 8. Known Issues

- **Already-compressed files**: VideoToolbox fixed-bitrate may produce same/larger files for low-bitrate sources. Smart bitrate capping mitigates but doesn't eliminate this. Use software encoders (CRF mode) for already-compressed content.
- **Estimation accuracy**: HW encoder estimates based on target bitrate; CRF estimates use fixed ratios. Can be off by 20-40%.
- **Read-only source dirs**: Output goes next to source as `_COMP` suffix. Fails if source dir is read-only.
- **No upload progress**: FormData upload is fire-and-forget. Could add XHR with progress events.

---

## 9. Future Plans

- **Meta AI metadata stripping** — New tab for stripping Meta glasses metadata (separate agent has spec)
- **Video stitching** — Drag-and-drop concatenation with per-clip trim/crop
- **Output directory config** — User-selectable output location
- **Compression comparison** — Sample multiple settings and compare quality/size side-by-side
