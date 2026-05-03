# Kickstarter Prompt -- 7-8 Agent Audit, Dashboard, and iOS Port Strategy

Use this prompt in a fresh Claude Code chat after restarting Claude Code/Codex so XcodeBuildMCP is loaded.

```markdown
Read `AGENTS.md` first. It is the single source of truth for Video Compressor.

We need a full read-only-then-build audit of the Video Compressor repo at:

`/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR`

Before editing:

1. Read `.agents/work-sessions/PROTOCOL.md`.
2. Read `.agents/work-sessions/RUNNING-LIST.md`.
3. Read `.agents/work-sessions/2026-05-02/STATUS.md`.
4. Read `.agents/work-sessions/2026-05-02/TASK-MANIFEST.md`.
5. Read `.agents/work-sessions/2026-05-02/status/explorer-findings.md`.
6. Read `.agents/work-sessions/2026-05-02/status/xcodebuildmcp-status.md`.
7. Create a fresh session log entry using SAST.

Goal:

Dispatch an 8-lane agent audit, synthesize what is built and what remains, stress-test quality and efficiency, then create an interactive multi-page static dashboard served by the existing Express app at `http://localhost:3000/audit/`.

Agent lanes:

1. `lead/synthesis`: Own task manifest, file ownership, final synthesis, and dashboard data schema.
2. `backend/API/security`: Audit `server.js`, upload/probe/stream/download/jobs/metaclean/stitch routes, path safety, range validation, thumbnail bounds, and concurrency risks.
3. `FFmpeg/compression`: Audit `lib/ffmpeg.js`, `lib/hwaccel.js`, `lib/probe.js`, `lib/jobQueue.js`, presets, bitrate caps, HW/SW behavior, two-pass, scaling, output naming.
4. `frontend/UI`: Audit `public/index.html`, `public/css/styles.css`, `public/js/app.js`, `compression.js`, `matrix.js`, `filemanager.js`, `progress.js`, `player.js`, `trim.js`, `crop.js`, `dragdrop.js`.
5. `Stitch/MetaClean workflows`: Audit `lib/stitch.js`, `lib/exiftool.js`, `public/js/stitch.js`, `public/js/metaclean.js`, silent audio, trim shape drift, output paths, per-file progress.
6. `docs/skills/protocol`: Audit `AGENTS.md`, `CLAUDE.md`, `.claude/agents`, `.agents/skills`, `.claude/skills`, `.codex/skills`, work sessions, and backlog state.
7. `QA/stress/performance`: Design and run safe local stress tests, document commands, expected results, bottlenecks, and failures.
8. `iOS port strategy`: Research official Apple docs as needed and produce native SwiftUI + AVFoundation/VideoToolbox recommendation. Treat Firebase as optional only for cloud accounts/sync/analytics/crash/distribution features.

Rules:

- First pass is read-only. Do not edit until each lane returns findings.
- Assign file ownership before edits.
- Do not edit `lib/jobQueue.js` or `lib/probe.js` unless you first inspect existing uncommitted changes and confirm they are relevant.
- Never edit `node_modules/`, `node_modules.nosync/`, or `package-lock.json` manually.
- Log every meaningful action using `.agents/work-sessions/PROTOCOL.md`.
- Use SAST timestamps.
- Cite official docs for iOS/Firebase/XcodeBuildMCP decisions.

Dashboard deliverables:

- `public/audit/index.html` -- overview and built-vs-left summary.
- `public/audit/routes.html` -- API/WebSocket inventory.
- `public/audit/frontend.html` -- frontend module map and UI checklist.
- `public/audit/compression.html` -- presets, codecs, queue behavior, estimate drift.
- `public/audit/findings.html` -- prioritized recommendations.
- `public/audit/css/audit.css` -- responsive styling using existing CSS variables.
- `public/audit/js/audit-data.js` -- fetch/load JSON.
- `public/audit/js/audit-ui.js` -- shared rendering helpers.
- `public/audit/js/pages/*.js` -- page-specific rendering.
- `public/audit/data/audit.json` -- canonical checklist/findings data.

Dashboard requirements:

- No build step.
- Vanilla JS modules.
- Responsive desktop/mobile.
- Search/filter by severity, subsystem, status, and owner.
- Checklist items can be toggled in localStorage without mutating `audit.json`.
- Include links to app routes, source files, and stress-test commands.
- Include a "Run locally" page section explaining:
  - `npm install`
  - `node server.js`
  - `PORT=4000 node server.js`
  - open `http://localhost:3000`
  - open `http://localhost:3000/audit/`

Required output:

1. Update session logs and status.
2. Create the dashboard files.
3. Start the app locally if needed and provide the local URL.
4. Run:
   - `python3 -m json.tool public/audit/data/audit.json`
   - `node --check server.js`
   - `for f in lib/*.js; do node --check "$f"; done`
   - `npx eslint server.js lib/*.js public/js/*.js public/audit/js/*.js`
   - `npx prettier --check public/audit/**/*.html public/audit/**/*.css public/audit/**/*.js public/audit/**/*.json`
5. Report known failures separately.

XcodeBuildMCP status:

- Global binary installed: `xcodebuildmcp`.
- Codex TOML entry should be:

```toml
[mcp_servers.XcodeBuildMCP]
command = "xcodebuildmcp"
args = ["mcp"]
```

- Claude Code user MCP server should exist:

```bash
claude mcp add --scope user xcodebuildmcp -- xcodebuildmcp mcp
```

- There is no Xcode project in this repo yet, so use XcodeBuildMCP for discovery/readiness until an Xcode scaffold is created.
```
