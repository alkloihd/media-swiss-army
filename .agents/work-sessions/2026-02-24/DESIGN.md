# Design Document -- MetaClean + Stitch + Bug Fixes

**Version:** 1.0 DRAFT
**Date:** 2026-02-24
**Author:** lead/opus
**Status:** Awaiting user approval

---

## 1. Architecture Overview

All new features are **additive**. No existing modules are replaced. The core pattern is:
- New `lib/` modules for backend logic (same patterns as `hwaccel.js`, `probe.js`, `ffmpeg.js`)
- New API routes in `server.js` (same patterns as existing routes)
- New `public/js/` modules for frontend (same `init*()` + `appState` pattern)
- Existing job queue + WebSocket for progress (extended, not replaced)

### Extended Data Flow

```
[Browser]
  |-- Tab Navigation (tabs.js) --> show/hide content sections
  |
  |-- Compress Tab (existing, unchanged)
  |     POST /api/compress --> buildCommand --> JobQueue --> FFmpeg spawn
  |
  |-- MetaClean Tab (new)
  |     GET /api/exiftool --> detectExifTool() cached result
  |     GET /api/metadata?path= --> readMetadataJson() via exiftool -json
  |     POST /api/metaclean --> computeRemovals() --> writeCleanCopy() via execFile
  |                              |
  |                              --> WebSocket: metaclean-progress / metaclean-complete
  |
  |-- Stitch Tab (new)
  |     POST /api/stitch --> probeAll clips --> choosePath(A or B)
  |       Path A: buildConcatList() --> ffmpeg -f concat -c copy
  |       Path B: buildReencodeCmd() --> ffmpeg filter_complex concat
  |                              |
  |                              --> WebSocket: stitch-progress / stitch-complete
  |                              --> auto-chain: metaclean on output
  |
  |-- GET /api/download?path= --> Content-Disposition: attachment stream
```

---

## 2. Module Design

### 2.1 lib/exiftool.js (new)

Follows the same detection-and-cache pattern as `lib/hwaccel.js`.

```
Exports:
  detectExifTool()      -> { installed: bool, version: string, path: string }
  readMetadataJson(filePath)  -> Object[] (exiftool -json -G1 -a -s output)
  computeRemovals(metadata, mode)  -> { tags: [{group, tag, oldValue}], count: number }
  writeCleanCopy(inputPath, outputPath, removals)  -> { success: bool, outputPath }
  generateReport(inputMeta, outputMeta, removals)  -> { removed: [], preserved: number }
```

**Key decisions:**
- Uses `execFile` (promisified), NOT `exec` -- safe from injection
- ExifTool binary at `/opt/homebrew/bin/exiftool` (hardcoded like ffmpeg path)
- Detection result cached in module-level variable (same as hwaccel.js)
- `computeRemovals()` uses two rulesets:
  - **Attribution:** tag-name + value-regex match against `/(meta|ray-?ban|meta ai|meta view)/i`
  - **Privacy:** attribution rules + UUID regex + known serial/version tags
- `writeCleanCopy()` builds args array: `['-o', outputPath, '-overwrite_original', ...tagArgs, inputPath]`
  where each tag removal is `-TAG=` format
- **Never** uses `-all=` (blanket strip)

### 2.2 lib/stitch.js (new)

```
Exports:
  probeClips(clips)     -> { compatible: bool, codec, resolution, reasons: string[] }
  buildConcatList(clips) -> string (file content for list.txt)
  stitchLossless(clips, outputPath)  -> child_process.ChildProcess
  stitchReencode(clips, outputPath, options)  -> child_process.ChildProcess
  stitch(clips, options) -> { process, outputPath, method: 'copy'|'reencode' }
```

**Key decisions:**
- `probeClips()` calls `probe()` from `lib/probe.js` for each clip, compares codec + resolution + fps
- Compatible = same video codec, same resolution, same fps, no trims requested
- Path A (lossless): writes temp `list.txt`, runs `ffmpeg -f concat -safe 0 -i list.txt -c copy -map_metadata 0`
- Path B (re-encode): uses filter_complex `[0:v][0:a][1:v][1:a]concat=n=N:v=1:a=1` with per-input trim via `-ss`/`-to`
- For Path B with compression: uses existing `buildCommand()` from `lib/ffmpeg.js` on stitched intermediate, OR single-pass encode (future optimization)
- Output path: built from first clip name + `_STITCH_` + clip indices
- Returns a ChildProcess so jobQueue.js can attach progress parsing

### 2.3 public/js/tabs.js (new)

```
Exports:
  initTabs()  -- called from app.js DOMContentLoaded
```

**Implementation:**
- Queries `[data-tab-button]` elements and `[data-tab-panel]` elements
- Click handler: add `active` class to clicked button, remove from siblings
- Show matching `[data-tab-panel="name"]`, hide others
- Default: "compress" tab active

### 2.4 public/js/metaclean.js (new)

```
Exports:
  initMetaClean()  -- called from app.js DOMContentLoaded

Internal state (added to appState):
  appState.metaclean = {
    files: [],           // uploaded files [{path, name, size, type}]
    mode: 'attribution', // or 'privacy'
    results: [],         // per-file cleaning results
    exiftoolStatus: null // { installed, version }
  }
```

**Implementation:**
- Mode toggle (two buttons: Attribution / Privacy) updates `appState.metaclean.mode`
- File drop zone reuses `initDragDrop()` pattern but targets MetaClean panel
- "Clean" button → `POST /api/metaclean` with files + mode
- WebSocket `metaclean-complete` event populates per-file report cards
- Report card shows: filename, tags removed (name + old value), download button

### 2.5 public/js/stitch.js (new)

```
Exports:
  initStitch()  -- called from app.js DOMContentLoaded

Internal state (added to appState):
  appState.stitch = {
    clips: [],           // ordered clips [{path, name, size, trim: {start, end}}]
    compress: false,      // compress toggle
    preset: 'balanced',
    codec: 'h265',
    format: 'mp4'
  }
```

**Implementation:**
- Clip list rendered as sortable cards (SortableJS CDN)
- Each card: thumbnail, filename, duration, Preview button, Set In/Set Out, timecode fields
- Preview button → loads clip into existing Plyr player via `/api/stream?path=`
- Set In/Out → captures `player.currentTime`, stores in clip's trim object
- "Compress output" toggle shows/hides preset/codec/format selectors (reuse compression.js UI pattern)
- "Stitch" button → `POST /api/stitch` with clips + order + compress options
- WebSocket `stitch-progress` updates progress bar, `stitch-complete` shows result + download

---

## 3. API Contracts

### GET /api/exiftool

```json
Response: {
  "installed": true,
  "version": "13.50",
  "path": "/opt/homebrew/bin/exiftool"
}
```

### GET /api/metadata?path=<encoded_path>

```json
Response: [
  {
    "SourceFile": "/path/to/file.heic",
    "EXIF:Make": "Meta AI",
    "EXIF:Model": "Ray-Ban Meta Smart Glasses",
    "EXIF:DateTimeOriginal": "2026:02:20 14:30:00",
    ...
  }
]
```

### POST /api/metaclean

```json
Request: {
  "files": [{ "path": "/tmp/.../abc.heic", "name": "photo.heic" }],
  "mode": "attribution"
}

Response: {
  "jobs": [{
    "id": "uuid",
    "status": "queued",
    "inputPath": "/tmp/.../abc.heic",
    "outputPath": "/tmp/.../abc_CLEAN.heic",
    "fileName": "photo.heic",
    "mode": "attribution"
  }]
}
```

### POST /api/stitch

```json
Request: {
  "clips": [
    { "path": "/tmp/.../a.mp4", "name": "clip1.mp4", "trim": { "start": 2.5, "end": 10.0 } },
    { "path": "/tmp/.../b.mp4", "name": "clip2.mp4" }
  ],
  "order": [0, 1],
  "compress": true,
  "preset": "balanced",
  "codec": "h265",
  "format": "mp4"
}

Response: {
  "job": {
    "id": "uuid",
    "status": "queued",
    "clips": 2,
    "method": "reencode",
    "outputPath": "/tmp/.../clip1_STITCH_1-2_COMP.mp4"
  }
}
```

### GET /api/download?path=<encoded_path>

```
Response: Binary stream
Headers:
  Content-Type: application/octet-stream
  Content-Disposition: attachment; filename="photo_CLEAN.heic"
  Content-Length: <file_size>
```

### WebSocket Events (new)

| Event | Payload |
|-------|---------|
| `metaclean-start` | `{ type, jobId, fileName, mode }` |
| `metaclean-complete` | `{ type, jobId, outputPath, report: { removed: [], preserved: number } }` |
| `metaclean-error` | `{ type, jobId, error }` |
| `stitch-progress` | `{ type, jobId, percent, speed, fps, eta, method }` |
| `stitch-complete` | `{ type, jobId, outputPath, outputSize, method }` |
| `stitch-error` | `{ type, jobId, error }` |

---

## 4. HTML Structure (index.html additions)

```html
<!-- Tab bar (new, in header area) -->
<div class="tab-bar">
  <button data-tab-button="compress" class="tab-button active">Compress</button>
  <button data-tab-button="stitch" class="tab-button">Stitch</button>
  <button data-tab-button="metaclean" class="tab-button">MetaClean</button>
</div>

<!-- Compress panel (wrap existing content) -->
<div data-tab-panel="compress" class="tab-panel active">
  <!-- existing compress UI, unchanged -->
</div>

<!-- Stitch panel (new) -->
<div data-tab-panel="stitch" class="tab-panel" style="display:none">
  <div class="stitch-drop-zone"><!-- drag-drop for clips --></div>
  <div class="stitch-clip-list" id="stitchClipList"><!-- sortable clip cards --></div>
  <div class="stitch-controls">
    <label><input type="checkbox" id="stitchCompress"> Compress output</label>
    <div id="stitchCompressOptions" style="display:none">
      <!-- preset/codec/format selectors (mirrors compression.js pattern) -->
    </div>
    <button id="stitchBtn" class="btn-primary">Stitch</button>
  </div>
</div>

<!-- MetaClean panel (new) -->
<div data-tab-panel="metaclean" class="tab-panel" style="display:none">
  <div class="metaclean-status"><!-- exiftool status badge --></div>
  <div class="metaclean-mode-toggle">
    <button data-mode="attribution" class="active">Attribution Only</button>
    <button data-mode="privacy">Privacy Mode</button>
  </div>
  <div class="metaclean-drop-zone"><!-- drag-drop for files --></div>
  <div class="metaclean-file-list"><!-- file cards with reports --></div>
  <button id="cleanBtn" class="btn-primary">Clean Files</button>
</div>
```

---

## 5. CSS Additions (styles.css)

New component styles using existing CSS custom properties:

- `.tab-bar` -- flex row, gap, border-bottom, uses `--border-primary`
- `.tab-button` -- padding, border-radius top, uses `--bg-secondary`, `--text-primary`
- `.tab-button.active` -- uses `--accent-primary`, `--text-on-accent`
- `.tab-panel` -- display block/none based on active state
- `.clip-card` -- similar to existing file cards, with drag handle
- `.clip-card .drag-handle` -- cursor: grab, uses `--text-tertiary`
- `.mode-toggle` -- button group, uses `--bg-tertiary`
- `.report-card` -- tag removal report, uses `--bg-secondary`
- `.report-tag` -- individual removed tag entry

All colors reference CSS variables -- zero hardcoded values.

---

## 6. Bug Fix Designs

### BUG-0a: HW Badge (compression.js)

**Current (broken):**
```js
// updateHWBadge()
if (hwInfo.videotoolbox) { ... }

// updateHWIndicators()
if (hwInfo.videotoolbox) { ... }
```

**Fixed:**
```js
// updateHWBadge()
const hasHW = hwInfo.h264_videotoolbox || hwInfo.hevc_videotoolbox || hwInfo.prores_videotoolbox;
if (hasHW) { ... }

// updateHWIndicators() -- per-codec checks
h264Button: hwInfo.h264_videotoolbox
h265Button: hwInfo.hevc_videotoolbox
proresButton: hwInfo.prores_videotoolbox
av1Button: false (no VT encoder for AV1)
```

### BUG-0b: Files Getting Bigger (lib/ffmpeg.js)

**Current (broken):** `adjustBitrate()` caps target at preset ratio of source, but if source is 4Mbps and balanced target is 6Mbps, the cap allows min(6000, 4000*0.7) = 2800, which actually works. The real issue may be that `adjustBitrate()` isn't being called, or the source bitrate isn't being passed correctly.

**Investigation needed:** Read the actual compress route in server.js and trace where `adjustBitrate()` is called to confirm the bug path. The fix will be one of:
1. Ensure `adjustBitrate()` is always called with actual source bitrate
2. Add a pre-flight check: if source bitrate < target bitrate, warn user and auto-reduce
3. Add a post-build validation: if estimated output > input, flag it

### BUG-0c: Slow 230MB Compression

**Diagnostic plan:**
1. Check which codec is selected when user compresses (AV1/libsvtav1 is 0.3-0.8x realtime)
2. Check if input is 4K (scale=-2:1080 would help)
3. Check if software fallback is being used instead of VideoToolbox
4. Check preset speed setting (slow/veryslow vs medium/fast)

This is a diagnosis task -- fix depends on findings.

---

## 7. File Ownership (No Conflicts)

| File | Owner Agent | Action |
|------|-------------|--------|
| `lib/exiftool.js` | ffmpeg-expert | Create |
| `lib/stitch.js` | ffmpeg-expert | Create |
| `server.js` | ffmpeg-expert | Modify (add routes) |
| `lib/jobQueue.js` | ffmpeg-expert | Modify (new job types) |
| `lib/ffmpeg.js` | ffmpeg-expert | Modify (bug 0b fix) |
| `public/js/tabs.js` | frontend-builder | Create |
| `public/js/metaclean.js` | frontend-builder | Create |
| `public/js/stitch.js` | frontend-builder | Create |
| `public/index.html` | frontend-builder | Modify |
| `public/css/styles.css` | frontend-builder | Modify |
| `public/js/app.js` | frontend-builder | Modify |
| `public/js/compression.js` | frontend-builder | Modify (bug 0a) |
| `public/js/filemanager.js` | frontend-builder | Modify (download buttons) |
| `public/js/progress.js` | frontend-builder | Modify (new events) |

No two agents touch the same file. Zero merge conflict risk.

---

## 8. Dependencies Between Phases

```
Phase 0 (bugs) -----> independent, can run in parallel with Phase 1
Phase 1 (tabs) -----> BLOCKS Phase 3 (MetaClean UI) and Phase 5 (Stitch UI)
Phase 2 (exiftool backend) -----> BLOCKS Phase 3 (MetaClean UI)
Phase 3 (metaclean UI) -----> requires Phase 1 + Phase 2
Phase 4 (stitch backend) -----> BLOCKS Phase 5 (Stitch UI)
                           -----> depends on Phase 2 (auto-metaclean on output)
Phase 5 (stitch UI) -----> requires Phase 1 + Phase 4
Phase 6 (download) -----> independent, can run any time after Phase 1
Phase 7 (QA) -----> requires all above complete
```

**Optimal parallel execution:**
```
Time 1: [Phase 0 bugs] + [Phase 1 tabs] + [Phase 2 exiftool backend]
Time 2: [Phase 3 metaclean UI] + [Phase 4 stitch backend] + [Phase 6 download]
Time 3: [Phase 5 stitch UI]
Time 4: [Phase 7 QA]
```
