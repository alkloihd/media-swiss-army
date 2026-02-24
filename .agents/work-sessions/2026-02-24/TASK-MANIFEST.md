# Task Manifest -- Video Compressor Build Session 3

**Created:** 2026-02-24 16:45 IST by [lead/opus]
**Status:** DRAFT -- Awaiting user approval before execution
**Branch:** `feature/metaclean-stitch` (off `main` @ `9efab52`)

---

## Agent Identification Protocol (MANDATORY)

Every agent that touches this manifest MUST follow these rules:

1. **Sign your work.** When updating any checkbox, notes column, or status, prepend your identity:
   `[agentName/model]` -- e.g., `[ffmpeg-expert/sonnet]`, `[frontend-builder/sonnet]`, `[lead/opus]`

2. **Log to AI-CHAT-LOG.md.** Every task you start or complete gets a timestamped entry in
   `.agents/work-sessions/2026-02-24/AI-CHAT-LOG.md` with:
   - `[YYYY-MM-DD HH:MM IST]`
   - `[AGENT-TYPE/MODEL]` -- e.g., `[teammate:ffmpeg-expert/sonnet]`
   - `[TAG]` -- `[BUILD]`, `[FIX]`, `[FEATURE]`, `[DOCS]`, `[TEST]`, etc.
   - Task ID reference (e.g., `[TASK 2.1]`)
   - Files created/modified
   - Status: Complete / In Progress / Blocked

3. **Never leave anonymous entries.** If a checkbox is checked, there must be an agent name next to it.

4. **Observations are gold.** Use the Notes column for: gotchas, blockers, decisions, things the next agent needs to know. Don't leave it blank.

5. **File ownership is sacred.** Check the ownership table below. Never edit a file owned by another agent without coordination.

---

## File Ownership (No Two Agents on the Same File)

| File | Owner | Action |
|------|-------|--------|
| `lib/exiftool.js` | ffmpeg-expert | Create |
| `lib/stitch.js` | ffmpeg-expert | Create |
| `lib/ffmpeg.js` | ffmpeg-expert | Modify (bug 0b) |
| `lib/jobQueue.js` | ffmpeg-expert | Modify (new job types) |
| `server.js` | ffmpeg-expert | Modify (new routes) |
| `public/js/tabs.js` | frontend-builder | Create |
| `public/js/metaclean.js` | frontend-builder | Create |
| `public/js/stitch.js` | frontend-builder | Create |
| `public/index.html` | frontend-builder | Modify |
| `public/css/styles.css` | frontend-builder | Modify |
| `public/js/app.js` | frontend-builder | Modify |
| `public/js/compression.js` | frontend-builder | Modify (bug 0a) |
| `public/js/filemanager.js` | frontend-builder | Modify (download buttons) |
| `public/js/progress.js` | frontend-builder | Modify (new WS events) |
| `AI-CHAT-LOG.md` | all agents | Append only |
| `CHANGELOG.md` | scribe | Append |
| `TASK-MANIFEST.md` | all agents | Update own rows only |

---

## Parallel Execution Plan

```
TIME 1 (parallel):
  Track A: [ffmpeg-expert]  -- Phase 0b, 0c (backend bug fixes)
  Track B: [frontend-builder] -- Phase 0a (HW badge fix) + Phase 1 (tabs)
  Track C: [scribe]          -- Initialize AI-CHAT-LOG, CHANGELOG headers

TIME 2 (parallel, after Phase 1 complete):
  Track A: [ffmpeg-expert]   -- Phase 2 (exiftool backend) + Phase 6.1 (download route)
  Track B: [frontend-builder] -- Phase 3 (MetaClean UI) + Phase 6.2 (download buttons)

TIME 3 (parallel):
  Track A: [ffmpeg-expert]   -- Phase 4 (stitch backend)
  Track B: [frontend-builder] -- Phase 5 (stitch UI)

TIME 4 (sequential):
  [compression-diagnostics]  -- Phase 7 (QA)
  [code-reviewer]            -- Final review before PR

TIME 5:
  [scribe]                   -- CHANGELOG, HANDOFF, CARRYOVER-PROMPT
```

---

## Phase 0: Critical Bug Fixes

### 0a. HW Badge Display Bug
- **Assigned:** `frontend-builder/sonnet`
- **Files:** `public/js/compression.js`
- **Priority:** High (display-only, but confuses users)

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 0a.1 | Fix `updateHWBadge()` (~line 117): change `hwInfo.videotoolbox` to `hwInfo.h264_videotoolbox \|\| hwInfo.hevc_videotoolbox \|\| hwInfo.prores_videotoolbox` | [ ] | |
| 0a.2 | Fix `updateHWIndicators()` (~line 145): check each codec against its specific VT key (`h264_videotoolbox`, `hevc_videotoolbox`, `prores_videotoolbox`). AV1 = always `false` (no VT encoder) | [ ] | |
| 0a.3 | Verify badge shows "Hardware acceleration available" in browser | [ ] | |

### 0b. Files Getting Bigger Bug
- **Assigned:** `ffmpeg-expert/sonnet`
- **Files:** `lib/ffmpeg.js`, possibly `server.js`
- **Priority:** Critical

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 0b.1 | Read `lib/ffmpeg.js` `adjustBitrate()` and trace the call path from `POST /api/compress` in `server.js` to confirm source bitrate is being passed | [ ] | Root cause: balanced preset targets 6Mbps on files already at 4-5Mbps |
| 0b.2 | Fix: ensure target bitrate never exceeds `sourceBitrate * presetRatio` for balanced/small/streaming. Max preset exempt | [ ] | |
| 0b.3 | Add pre-flight warning in compress response when source is already well-compressed (source bitrate < target * 0.5) | [ ] | |
| 0b.4 | Verify fix: re-compress a low-bitrate file with balanced preset, confirm output is smaller | [ ] | |

### 0c. Slow 230MB Compression
- **Assigned:** `compression-diagnostics/sonnet`
- **Files:** Analysis only (may lead to UI defaults change)
- **Priority:** Medium (diagnosis first)

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 0c.1 | Probe a 230MB test file: check codec, resolution, bitrate, fps | [ ] | HW accel IS available. Suspect: AV1 or 4K or slow preset |
| 0c.2 | Check what codec/preset the UI defaults to and whether HW encoder is selected | [ ] | |
| 0c.3 | Document findings and recommend fix (if any) | [ ] | |

---

## Phase 1: Tab Navigation
- **Assigned:** `frontend-builder/sonnet`
- **Files:** `public/js/tabs.js` (create), `public/index.html`, `public/css/styles.css`, `public/js/app.js`
- **Depends on:** Nothing (can start immediately)
- **Blocks:** Phase 3, Phase 5

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 1.1 | Create `public/js/tabs.js` with `initTabs()` -- query `[data-tab-button]` and `[data-tab-panel]`, click handler to show/hide | [ ] | Export `initTabs` for app.js |
| 1.2 | Add tab bar to `index.html` header: Compress (default active), Stitch, MetaClean | [ ] | Use `data-tab-button` and `data-tab-panel` attributes |
| 1.3 | Wrap existing compress UI in `<div data-tab-panel="compress">` -- zero visual changes | [ ] | CRITICAL: must not break existing compress flow |
| 1.4 | Add empty `<div data-tab-panel="stitch">` and `<div data-tab-panel="metaclean">` with placeholder content | [ ] | Hidden by default (display:none) |
| 1.5 | Add tab CSS to `styles.css`: `.tab-bar`, `.tab-button`, `.tab-button.active` using CSS custom properties | [ ] | Must work in both dark and light themes |
| 1.6 | Import and call `initTabs()` from `app.js` DOMContentLoaded | [ ] | |
| 1.7 | Test: tabs switch correctly, compress tab still fully functional | [ ] | |

---

## Phase 2: ExifTool Backend
- **Assigned:** `ffmpeg-expert/sonnet`
- **Files:** `lib/exiftool.js` (create), `server.js` (add routes), `lib/jobQueue.js` (extend)
- **Depends on:** Nothing (can start in parallel with Phase 1)
- **Blocks:** Phase 3

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 2.1 | Create `lib/exiftool.js` with `detectExifTool()` -- check `/opt/homebrew/bin/exiftool`, cache result | [ ] | Follow `lib/hwaccel.js` pattern. Uses `execFile` (promisified) |
| 2.2 | Implement `readMetadataJson(filePath)` -- runs `exiftool -json -G1 -a -s` | [ ] | Returns parsed JSON array |
| 2.3 | Implement `computeRemovals(metadata, mode)` -- attribution vs privacy rulesets | [ ] | Attribution: EXIF:Make/Model (HEIC), Keys:Comment/Model/Copyright (MOV). Privacy: + UUID/Serial/SubSecTime/AndroidVersion |
| 2.4 | Implement `writeCleanCopy(inputPath, outputPath, removals)` -- builds exiftool args with `-TAG=` format | [ ] | NEVER uses blanket `-all=`. Uses `execFile` for safety |
| 2.5 | Implement `generateReport(inputMeta, outputMeta, removals)` -- before/after diff | [ ] | Returns `{ removed: [{tag, oldValue}], preserved: count }` |
| 2.6 | Add `GET /api/exiftool` route to `server.js` -- returns `{ installed, version, path }` | [ ] | |
| 2.7 | Add `GET /api/metadata?path=` route to `server.js` -- returns full exiftool JSON | [ ] | Validate path exists before calling exiftool |
| 2.8 | Add `POST /api/metaclean` route to `server.js` -- accepts `{ files, mode }`, creates jobs | [ ] | Output naming: `{name}_CLEAN.{ext}` next to source |
| 2.9 | Extend `jobQueue.js` to support `metaclean` job type -- ExifTool process instead of FFmpeg | [ ] | WebSocket events: `metaclean-start`, `metaclean-complete`, `metaclean-error` |
| 2.10 | Test backend: call `/api/metaclean` on sample HEIC and MOV, verify `_CLEAN` output created | [ ] | Sample files at `/Users/rishaal/CODING/MagFieldsWarRoom/assets/meta/` |

---

## Phase 3: MetaClean UI
- **Assigned:** `frontend-builder/sonnet`
- **Files:** `public/js/metaclean.js` (create), `public/index.html`, `public/js/app.js`, `public/js/progress.js`
- **Depends on:** Phase 1 (tabs), Phase 2 (backend)

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 3.1 | Create `public/js/metaclean.js` with `initMetaClean()` | [ ] | Adds `appState.metaclean = { files, mode, results, exiftoolStatus }` |
| 3.2 | Implement ExifTool status badge -- fetch `/api/exiftool` on init, show installed/version or warning | [ ] | |
| 3.3 | Implement mode toggle: Attribution Only (default) / Privacy Mode | [ ] | Two buttons, active state styling |
| 3.4 | Add MetaClean drop zone and file list to `index.html` metaclean tab panel | [ ] | Reuse `.glass-card` and file card patterns |
| 3.5 | Wire drag-drop for MetaClean tab -- reuse `dragdrop.js` pattern or extend it | [ ] | |
| 3.6 | Implement "Clean Files" button -- `POST /api/metaclean` with files + mode | [ ] | |
| 3.7 | Add WebSocket handlers in `progress.js` for `metaclean-start`, `metaclean-complete`, `metaclean-error` | [ ] | |
| 3.8 | Render per-file report cards after cleaning: removed tags list with old values | [ ] | |
| 3.9 | Add download button per cleaned output (uses `/api/download` from Phase 6) | [ ] | |
| 3.10 | Import and call `initMetaClean()` from `app.js` | [ ] | |
| 3.11 | Test full flow in browser: upload HEIC, clean, verify report, download | [ ] | |

---

## Phase 4: Stitch Backend
- **Assigned:** `ffmpeg-expert/sonnet`
- **Files:** `lib/stitch.js` (create), `server.js` (add route), `lib/jobQueue.js` (extend)
- **Depends on:** Phase 2 (for auto-metaclean on output)

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 4.1 | Create `lib/stitch.js` with `probeClips(clips)` -- ffprobe all clips, check compatibility | [ ] | Compatible = same codec + resolution + fps + no trims |
| 4.2 | Implement `stitchLossless(clips, outputPath)` (Path A) -- write list.txt, `ffmpeg -f concat -safe 0 -c copy` | [ ] | Fast, no quality loss. Only when compatible |
| 4.3 | Implement `stitchReencode(clips, outputPath, options)` (Path B) -- filter_complex concat with per-input trim | [ ] | Uses `-ss`/`-to` per input, normalizes codec/resolution |
| 4.4 | Implement `stitch(clips, options)` -- auto-choose Path A or B, return ChildProcess | [ ] | Returns `{ process, outputPath, method }` |
| 4.5 | Add `POST /api/stitch` route to `server.js` | [ ] | Body: `{ clips, order, compress, preset?, codec?, format? }` |
| 4.6 | Extend `jobQueue.js` for `stitch` job type with progress parsing | [ ] | WebSocket: `stitch-progress`, `stitch-complete`, `stitch-error` |
| 4.7 | Implement auto-MetaClean chain: on stitch complete, run metaclean on output | [ ] | Chain pattern: stitch job complete event -> create metaclean job |
| 4.8 | Optional compression: if `compress=true`, run existing compress pipeline on stitched output | [ ] | Two-step MVP (stitch then compress). Single-pass = future optimization |
| 4.9 | Output naming: `{firstClip}_STITCH_1-2-3.{ext}` or `_STITCH_1-2-3_COMP.{ext}` | [ ] | |
| 4.10 | Test backend: stitch 2 compatible clips losslessly, verify output plays | [ ] | |

---

## Phase 5: Stitch UI
- **Assigned:** `frontend-builder/sonnet`
- **Files:** `public/js/stitch.js` (create), `public/index.html`, `public/js/app.js`, `public/js/progress.js`
- **Depends on:** Phase 1 (tabs), Phase 4 (backend)

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 5.1 | Add SortableJS CDN script tag to `index.html` | [ ] | `<script src="https://cdn.jsdelivr.net/npm/sortablejs@1.15.6/Sortable.min.js"></script>` |
| 5.2 | Create `public/js/stitch.js` with `initStitch()` | [ ] | Adds `appState.stitch = { clips, compress, preset, codec, format }` |
| 5.3 | Add Stitch tab content to `index.html`: drop zone, clip list container, controls | [ ] | |
| 5.4 | Implement clip cards with drag handle (SortableJS), thumbnail, filename, duration | [ ] | |
| 5.5 | Implement per-clip Preview button -- loads clip into existing Plyr player via `/api/stream` | [ ] | |
| 5.6 | Implement per-clip Set In / Set Out buttons -- capture `player.currentTime` | [ ] | MVP: no slider, just buttons + editable timecode fields |
| 5.7 | Implement editable timecode input fields (HH:MM:SS.ms) next to Set In/Out | [ ] | |
| 5.8 | Implement "Compress output" toggle -- shows/hides preset/codec/format selectors | [ ] | Mirror compression.js UI pattern |
| 5.9 | Implement "Stitch" button -- `POST /api/stitch` with clips + order + trim + compress options | [ ] | |
| 5.10 | Add WebSocket handlers in `progress.js` for `stitch-progress`, `stitch-complete`, `stitch-error` | [ ] | |
| 5.11 | Import and call `initStitch()` from `app.js` | [ ] | |
| 5.12 | Test full flow in browser: add clips, reorder, set trims, stitch, verify output | [ ] | |

---

## Phase 6: Download Endpoint
- **Assigned:** `ffmpeg-expert/sonnet` (6.1) + `frontend-builder/sonnet` (6.2)
- **Files:** `server.js` (route), `public/js/filemanager.js` (buttons)
- **Depends on:** Nothing (can run any time)

| # | Task | Done | Agent Notes |
|---|------|------|-------------|
| 6.1 | Add `GET /api/download?path=` route to `server.js` -- stream file with `Content-Disposition: attachment` | [ ] | [ffmpeg-expert] Correct filename in header, not temp UUID |
| 6.2 | Add Download buttons to completed job cards in `filemanager.js` -- all job types (compress, metaclean, stitch) | [ ] | [frontend-builder] Essential for phone workflows |

---

## Phase 7: QA and Verification
- **Assigned:** `compression-diagnostics/sonnet` (7.1-7.8), `code-reviewer/sonnet` (7.9-7.15)
- **Depends on:** All previous phases complete

### Functional Tests (compression-diagnostics)

| # | Test | Pass | Agent Notes |
|---|------|------|-------------|
| 7.1 | Compression tab works identically -- upload, compress, download. No regressions | [ ] | |
| 7.2 | HW badge shows "Hardware acceleration available" with green codec dots | [ ] | |
| 7.3 | MetaClean on `sample meta photo.heic`: EXIF:Make + EXIF:Model removed, dates/GPS preserved | [ ] | |
| 7.4 | MetaClean on `sample meta.MOV`: Keys:Comment + Keys:Model + Keys:Copyright removed, timestamps preserved | [ ] | |
| 7.5 | Privacy mode: additionally removes UserComment UUID, SerialNumber, Description, AndroidVersion | [ ] | |
| 7.6 | Stitch 2+ clips with same codec: lossless concat, continuous playback | [ ] | |
| 7.7 | Stitch with per-clip trims: in/out points respected in output | [ ] | |
| 7.8 | MetaClean auto-runs on stitched output | [ ] | |

### Code Quality (code-reviewer)

| # | Check | Pass | Agent Notes |
|---|-------|------|-------------|
| 7.9 | Download button saves file with correct name from all three modes | [ ] | |
| 7.10 | Dark/light theme works on all new UI (tabs, MetaClean, Stitch) | [ ] | |
| 7.11 | `npx eslint .` passes with 0 errors on all new/modified files | [ ] | |
| 7.12 | `npx prettier --check` passes on all files | [ ] | |
| 7.13 | `node --check server.js` and `node --check lib/*.js` all pass | [ ] | |
| 7.14 | Server starts without errors: `node server.js` | [ ] | |
| 7.15 | No injection vulnerabilities in new routes (path validation, safe process spawning) | [ ] | |

---

## Agent Roster

| Agent | Model | Role | Phases |
|-------|-------|------|--------|
| `ffmpeg-expert` | sonnet | Backend: FFmpeg, ExifTool, stitch engine, server routes | 0b, 2, 4, 6.1 |
| `frontend-builder` | sonnet | Frontend: tabs, MetaClean UI, Stitch UI, download buttons | 0a, 1, 3, 5, 6.2 |
| `compression-diagnostics` | sonnet | Diagnosis: slow compression, QA functional tests | 0c, 7.1-7.8 |
| `code-reviewer` | sonnet | Review: security, lint, format, syntax, theme compliance | 7.9-7.15 |
| `scribe` | haiku | Docs: AI-CHAT-LOG, CHANGELOG, HANDOFF, manifest annotations | Continuous |
| `lead` | opus | Coordination: planning, task assignment, conflict resolution | Oversight |

---

## Summary

- **Total tasks:** 68 checkboxes across 8 phases
- **New files:** 5 (`lib/exiftool.js`, `lib/stitch.js`, `public/js/tabs.js`, `public/js/metaclean.js`, `public/js/stitch.js`)
- **Modified files:** 9 (`server.js`, `lib/ffmpeg.js`, `lib/jobQueue.js`, `public/index.html`, `public/css/styles.css`, `public/js/app.js`, `public/js/compression.js`, `public/js/filemanager.js`, `public/js/progress.js`)
- **Estimated parallel tracks:** 3 concurrent at peak (ffmpeg-expert + frontend-builder + scribe)
- **Critical path:** Phase 1 (tabs) -> Phase 3 (MetaClean UI) + Phase 5 (Stitch UI)
