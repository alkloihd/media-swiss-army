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
| iOS native app       | **Live on TestFlight.** Native SwiftUI + AVAssetWriter + VideoToolbox + PhotosUI. 4 tabs: Compress / Stitch / MetaClean / Settings. Auto-deploy from `main` via GitHub Actions. See Part 15 for full pipeline.                          |

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

## Part 15: iOS App + TestFlight Deployment Pipeline

**This section is mandatory reading for any agent touching `VideoCompressor/` or `.github/workflows/`. The pipeline below means a single push to `main` produces a TestFlight build — agents must understand the blast radius before pushing.**

### App identity

| Field                | Value                                              |
| -------------------- | -------------------------------------------------- |
| Bundle ID            | `com.alkloihd.videocompressor`                     |
| Home-screen name     | `Media Swiss Army`                                 |
| In-app title         | `Alkloihd Video Swiss-AK`                          |
| Apple Team ID        | `9577LMA4J5`                                       |
| Xcode project        | `VideoCompressor/VideoCompressor_iOS.xcodeproj`    |
| Scheme               | `VideoCompressor_iOS`                              |
| Source folder        | `VideoCompressor/ios/` (PBXFileSystemSynchronizedRootGroup — files added on disk auto-included) |
| Test target          | `VideoCompressor/VideoCompressorTests/`            |
| Min iOS              | 17.0                                               |
| Encryption export    | `ITSAppUsesNonExemptEncryption=NO`                 |
| Background modes     | `audio` (opt-in via Settings → "Allow encoding in background") |

### iOS architecture (current truth)

- **SwiftUI** for all UI; no UIKit ViewControllers.
- **AVAssetWriter + AVAssetReader** for compression (NOT `AVAssetExportSession` — that produced 1.2 GB outputs from 600 MB sources at fixed bitrate). Smart bitrate caps from `lib/ffmpeg.js` ported to `CompressionSettings.bitrate(forSourceBitrate:)`: `balanced` 70%, `small` 40%, `streaming` 50% of source.
- **HEVC** for max/balanced/small presets; **H.264** for streaming preset.
- **VideoToolbox** hardware encoder via AVAssetWriter `kVTCompressionPropertyKey_*`.
- **PhotosUI** `PhotosPicker` with `matching: .any(of: [.videos, .images])` — Photos library is first-class (HEIC/JPEG compress + metaclean + stitch on still images planned in commit 5).
- **Audio Background Mode** opt-in (`AudioBackgroundKeeper` plays a 1-sec silent AAC at volume 0 with `.mixWithOthers`) bypasses iOS's ~30s background ceiling. Foreground-only by default.
- **CacheSweeper** actor manages 6 working dirs (`Inputs/`, `Outputs/`, `Stitch/`, `Thumbnails/`, `MetaClean/`, `tmp/`); auto-sweeps files >7 days old on launch; manual "Clear cache" in Settings.
- **DeviceCapabilities** classifies device by `hw.machine` sysctl — Pro phones (2× encoder engines) get parallel multi-clip encode via `TaskGroup`; standard phones serialize.
- **MetadataService** uses CGImageSource/CGImageDestination for stills; `AVMetadataItem` + atom-walking for video. Meta-glasses fingerprint detection looks for binary "Comment"/"Description" atoms with `ray-ban`/`meta`/`rayban` markers.
- **`StripRules.autoMetaGlasses`** is intentionally narrow: `{stripCategories: [], stripMetaFingerprintAlways: true}` — only strips the binary fingerprint atom, preserving date/GPS/device info.

### Key iOS files

| Path                                                        | Responsibility                                                       |
| ----------------------------------------------------------- | -------------------------------------------------------------------- |
| `VideoCompressor/ios/ContentView.swift`                     | TabView host: Compress / Stitch / MetaClean / Settings.              |
| `VideoCompressor/ios/Models/CompressionSettings.swift`      | Resolution × QualityLevel; smart bitrate cap math.                   |
| `VideoCompressor/ios/Models/VideoFile.swift`                | Per-file state: pickedAt, metadata, jobState, saveStatus, kind.      |
| `VideoCompressor/ios/Services/CompressionService.swift`     | AVAssetWriter pipeline, cancellation, cleanup-on-cancel.             |
| `VideoCompressor/ios/Services/VideoLibrary.swift`           | @MainActor ObservableObject; UIBackgroundTask + AudioBackgroundKeeper wrap. |
| `VideoCompressor/ios/Services/AudioBackgroundKeeper.swift`  | Refcounted AVAudioSession singleton; gated on `allowBackgroundEncoding` UserDefaults. |
| `VideoCompressor/ios/Services/CacheSweeper.swift`           | Actor managing working dirs; sweep / clear / breakdown.              |
| `VideoCompressor/ios/Services/MetadataService.swift`        | Read/strip metadata; Meta fingerprint detection.                     |
| `VideoCompressor/ios/Services/StitchExporter.swift`         | AVMutableComposition concat with per-clip trim.                      |
| `VideoCompressor/ios/Views/SettingsTabView.swift`           | Background-encode toggle + cache breakdown + clear button.           |
| `VideoCompressor/ios/Views/StitchTab/`                      | Timeline, ClipEditor, TrimEditor (live preview, drag reorder).       |
| `VideoCompressor/VideoCompressorTests/`                     | XCTest target. `MetadataTagTests`, `CompressionSettingsTests`, `CompressionServiceTests` (uses `/tmp/sample_test_video.mp4` fixture, XCTSkip if missing). |

### Auto-deploy: push to `main` → TestFlight

Pipeline file: **`.github/workflows/testflight.yml`**.

```text
push to main
  └─> GitHub Actions (macos-26 runner)
       ├─ checkout
       ├─ xcodebuild archive (-allowProvisioningUpdates, no manual signing)
       ├─ xcodebuild -exportArchive (ExportOptions.plist destination=upload)
       │     ↳ uses App Store Connect API key from repo secret
       └─> IPA delivered directly to App Store Connect
            └─> TestFlight processing (~3-8 min more)
                 └─> available on iPhone TestFlight app
```

**End-to-end ~12 min from commit to "available to testers."**

### Triggering builds

| Method              | When                                                              |
| ------------------- | ----------------------------------------------------------------- |
| Push to `main`      | Automatic. Every commit on `main` triggers TestFlight.            |
| `workflow_dispatch` | Manual trigger from GitHub UI (Actions tab → TestFlight → Run workflow). Workflow file must already exist on `main`. |

**Cherry-pick gotcha:** if you create the workflow on a feature branch, `workflow_dispatch` will not appear in the Actions tab until the workflow file lands on `main`. Always cherry-pick CI changes to `main` before relying on manual dispatch.

### Repo secrets (GitHub Actions)

These are configured in **GitHub → Repo → Settings → Secrets and variables → Actions**. Never commit any of these to the tree.

| Secret                                | Purpose                                          |
| ------------------------------------- | ------------------------------------------------ |
| `APP_STORE_CONNECT_API_KEY_ID`        | Key ID from App Store Connect (e.g. `APSFBYWUZJ`). |
| `APP_STORE_CONNECT_API_ISSUER_ID`     | Issuer UUID from App Store Connect.              |
| `APP_STORE_CONNECT_API_KEY_BASE64`    | Base64-encoded `.p8` private key.                |

**Required role: `Admin`.** "App Manager" is insufficient for `destination=upload` — uploads will fail with a permissions error. If a key was created with the wrong role, regenerate it as Admin.

### Confidence-gate: when to push to `main`

The user's standing direction (2026-05-03):

> *"Don't trigger a bunch of builds separately — fix everything via teams of agents, and only when confidence is above 90% across all dimensions, merge to main and trigger the canonical TestFlight build."*

Practical protocol:

1. **All multi-commit work happens on a feature branch** — current is `feature/phase-3-stitch-ux-and-photos`.
2. **Each commit must build green and pass tests locally** before landing on the feature branch.
3. **Red team before merging:** dispatch ≥4 Opus reviewers across orthogonal dimensions (security, encoding correctness, UI/UX, performance). Resolve all CRITICAL + most HIGH findings.
4. **Simulator E2E walkthrough:** boot iPhone Pro sim, exercise each tab, verify output sizes match expectations, confirm no crashes/leaks.
5. **Only after confidence ≥ 90% on all dimensions:** open PR feature → main, merge, single TestFlight build kicks off.

Hotfixes that are unambiguously safe (small, well-tested, blocking testers) MAY go direct to `main` — but ask first.

### Local iOS dev

Configured via `.xcodebuildmcp/config.yaml`. Default workflows: `simulator, simulator-management, ui-automation, debugging, logging, device, project-discovery, project-scaffolding, coverage, utilities`.

```bash
# Session start (Claude Code agents)
mcp__xcodebuildmcp__session_show_defaults

# Build + run on default sim
mcp__xcodebuildmcp__build_run_sim

# Run tests
mcp__xcodebuildmcp__test_sim

# Screenshot for verification
mcp__xcodebuildmcp__screenshot
```

For physical-device builds, the user must complete one-time signing in Xcode (Signing & Capabilities → Automatically manage signing → Team: 9577LMA4J5). After that, MCP-driven device builds work.

### Tracked Claude Code config (auto-inherited by branches)

These ARE in git on `main`, so every feature branch inherits the same agent permissions, MCPs, hooks, skills:

```text
.claude/settings.json          ← team-shared permissions + env flags
.claude/agents/                ← role definitions (ffmpeg-expert, frontend-builder, scribe, ...)
.claude/commands/              ← slash commands (/compress, /diagnose, /status)
.claude/hooks/                 ← Pre/PostToolUse + session hooks
.claude/skills/                ← progressive-disclosure skills
.github/workflows/testflight.yml  ← deploy pipeline
.github/workflows/ci.yml          ← lint/format/syntax/audit
.xcodebuildmcp/config.yaml     ← XcodeBuildMCP workflow gate
AGENTS.md, CLAUDE.md           ← canonical protocol
```

Per-user-only (gitignored, never tracked):

```text
.claude/settings.local.json    ← personal MCP servers, machine-specific keys
.claude/plans/                 ← scratch plan-mode output
.claude/worktrees/             ← agent-spawned worktrees
.agents/work-sessions/**/session-activity.log  ← raw shell history
```

If a new agent picks up this repo cold:
1. `git clone` from `main` → all of the above lands automatically.
2. `npm install` for the web app.
3. `xcodebuildmcp setup` (Codex) or `claude mcp add --scope user xcodebuildmcp -- xcodebuildmcp mcp` (Claude Code) for iOS work.
4. A push to `main` will deploy to TestFlight without further wiring — the secrets live on GitHub, not locally.

---

## Part 16: Codex / next-agent onboarding

If you are Codex (or any new agent) picking this repo up cold, this is your runway.

### 16.1 First five minutes

```bash
cd "/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR"
git fetch origin && git status
ls .agents/work-sessions/2026-05-03/backlog/
cat .agents/work-sessions/2026-05-03/backlog/README.md
cat .agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md
```

The backlog folder is your task list. `AUDIT-CONSOLIDATED-FINDINGS.md` is the synthesis of nine simultaneous audits and tells you what's already fixed vs deferred.

### 16.2 Identifiers + signing

| Field | Value |
|---|---|
| Apple Team ID | `9577LMA4J5` |
| Bundle ID | `com.alkloihd.videocompressor` |
| Home-screen name | `Media Swiss Army` |
| App Store name (planned) | `MetaClean: AI Glasses Data` |
| GitHub repo | `alkloihd/video-compressor-FUCKMETA` |
| Default branch | `main` |
| Min iOS | 17.0 |
| Xcode project | `VideoCompressor/VideoCompressor_iOS.xcodeproj` |
| Scheme | `VideoCompressor_iOS` |
| Test target | `VideoCompressorTests` (138 tests as of 2026-05-03) |
| Source folder (auto-synced) | `VideoCompressor/ios/` (`PBXFileSystemSynchronizedRootGroup`) |

Physical-device signing is already wired (Automatic) under the user's Apple ID. Re-using that team ID will pick up the same provisioning profile.

### 16.3 XcodeBuildMCP (REQUIRED)

The lead has been driving builds + tests through the XcodeBuildMCP server. To get the same toolset:

```bash
# 1. Install
npm install -g xcodebuildmcp@latest

# 2. Verify
xcodebuildmcp --help
xcodebuildmcp tools

# 3. Wire into Codex
# In ~/.codex/config.toml:
[mcp_servers.XcodeBuildMCP]
command = "xcodebuildmcp"
args    = ["mcp"]

# 4. Restart Codex so the MCP tools are loaded
```

Once attached, the tools you'll use most:

- `mcp__xcodebuildmcp__session_show_defaults` — confirm project/scheme/sim are set (call once per session before first build)
- `mcp__xcodebuildmcp__build_sim` — compile-only build for the iPhone 16 Pro sim
- `mcp__xcodebuildmcp__test_sim` — run the 138-test target on the sim
- `mcp__xcodebuildmcp__build_run_sim` — build + install + launch in sim
- `mcp__xcodebuildmcp__build_run_device` — **wireless install on a USB-tethered iPhone, no Apple build minutes consumed**
- `mcp__xcodebuildmcp__screenshot` — capture sim screenshots for visual review

**IMPORTANT — never call `session_set_defaults`** unless you know the lead isn't running in parallel. Multiple agents touching session defaults swap each other's project paths and break their builds. The current defaults are correct.

### 16.4 Simulator hygiene

If the user reports "iPhone clones popping up", every run accumulates a sim instance. Reset:

```bash
xcrun simctl shutdown all
killall Simulator
```

Always quit the sim when handing off / pausing.

### 16.5 GitHub CLI

```bash
# Authenticated already as the user. If gh status fails:
gh auth status
gh auth login --web

# Day-to-day:
gh pr create --base main --head <branch> --title "..." --body-file /tmp/pr_body.md
gh pr checks <num> --watch   # poll CI
gh pr merge <num> --merge    # standard merge commit
gh pr view <num> --json state,mergeCommit
gh run list --workflow testflight.yml --limit 5
gh run view <run-id>
```

Each merge to `main` triggers `.github/workflows/testflight.yml` which builds + uploads to App Store Connect. Build cycle ≈ 60–90s, costs Apple build minutes.

### 16.6 CI guards (already on every PR)

- ESLint
- Prettier
- Security Audit (`npm audit`)
- Syntax Check

These run on Node files (the legacy web compressor under `lib/`, `server.js`). They do NOT yet run iOS unit tests in cloud. Backlog: `TASK-18-apple-ci-checks.md` would add `xcodebuild test` on `macos-26`.

### 16.7 Working contract

1. Always branch off `main`. Never push to `main` directly. Use `gh pr merge` to produce the merge commit.
2. Every code-touching PR must pass `mcp__xcodebuildmcp__test_sim` locally before push (pre-push hook coming via `TASK-17-dev-iterate-script.md`).
3. PR descriptions end with the agent attribution line: `🤖 Generated with [Codex](URL)` or similar.
4. Append a 1-line summary to `.agents/work-sessions/<date>/AI-CHAT-LOG.md` after each merge.
5. Don't run more than 2 background agents in parallel — sim resource contention causes intermittent test failures.
6. Don't introduce CoreHaptics for tick feedback; UISelectionFeedbackGenerator already covers it (see `Haptics.swift`).
7. Don't introduce a custom `AVVideoCompositing` class without sign-off; built-in opacity/crop ramps cover today's transitions.

### 16.8 Wireless device push (when set up)

Once `TASK-17-dev-iterate-script.md` lands, the iteration loop will be:

```bash
# From any branch:
./scripts/dev-iterate.sh
# = lint + xcodebuild test + build_run_device → ~60s, no Apple build minutes
```

Until then, use `mcp__xcodebuildmcp__build_run_device` with the iPhone tethered.

### 16.9 What NOT to touch without confirmation

- `.git/` config
- `.github/workflows/testflight.yml` (App Store Connect API key wiring)
- `.claude/`, `.codex/`, `~/.codex/config.toml`
- The Apple Developer portal (signing certs, provisioning profiles)
- `App Store Connect` (the app entry, pricing, privacy details — handled via the user's browser, not via code)

### 16.10 Quick "is this app what they say it is" sanity check

Read these in order:
1. `AGENTS.md` Part 4 (current app truth) + Part 15 (deployment pipeline)
2. `.agents/work-sessions/2026-05-03/PUBLISHING-AND-MONETIZATION.md` (where this is heading)
3. `.agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md` (what's known broken)
4. `git log --oneline -20` (recent direction)

That's enough context to start picking tasks.

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
