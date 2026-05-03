# Requirements Document -- MetaClean + Stitch + Bug Fixes

**Version:** 1.0 DRAFT
**Date:** 2026-02-24
**Author:** lead/opus
**Status:** Awaiting user approval

---

## 1. Scope

Add two new workflow modes (MetaClean, Stitch) and a download endpoint to the existing Video Compressor app, plus fix three critical bugs. The existing Compress workflow must remain identical.

---

## 2. Critical Bug Fixes (Phase 0)

### BUG-0a: HW Badge Shows Wrong State

- **Severity:** Display-only (encoding works correctly)
- **Location:** `public/js/compression.js:117` (`updateHWBadge()`) and `:145` (`updateHWIndicators()`)
- **Root Cause:** Frontend checks `hwInfo.videotoolbox` but API returns `h264_videotoolbox`, `hevc_videotoolbox`, `prores_videotoolbox`
- **Acceptance Criteria:**
  - Badge shows "Hardware acceleration available" when any VT encoder is detected
  - Each codec button shows green HW dot when its specific VT encoder is available
  - Badge shows "Software encoding only" only when no VT encoders are detected

### BUG-0b: Compression Makes Files Bigger

- **Severity:** Critical (defeats purpose of the tool)
- **Root Cause:** VideoToolbox fixed-bitrate targets can exceed source bitrate for already-compressed files. `adjustBitrate()` caps at preset ratios but still allows targets above source bitrate.
- **Acceptance Criteria:**
  - If source bitrate is already at or below the target bitrate, reduce target to source * preset_ratio
  - Never produce output larger than input for balanced/small/streaming presets
  - Show a warning to the user when source is already well-compressed
  - Max preset is exempt (user explicitly wants quality)

### BUG-0c: Slow 230MB File Compression

- **Severity:** Medium (performance, not correctness)
- **Diagnostic Steps:** Check selected codec (AV1 is 0.3-0.8x realtime), check if 4K without downscale, check preset speed
- **Acceptance Criteria:**
  - Diagnose root cause and document findings
  - If codec/preset is suboptimal, suggest or default to faster options
  - H.264/H.265 with VideoToolbox should compress at >= 2x realtime for 1080p content

---

## 3. Feature: Tab Navigation (Phase 1)

### User Story
As a user, I want to switch between Compress, Stitch, and MetaClean modes without leaving the page.

### Requirements
- R1.1: Three tab buttons in header area: Compress (default), Stitch, MetaClean
- R1.2: Clicking a tab shows its content section and hides others
- R1.3: Existing Compress UI wrapped in a tab panel -- zero visual or functional changes
- R1.4: Empty tab panels for Stitch and MetaClean (populated in later phases)
- R1.5: Tab state is visual only (no URL routing, no localStorage)
- R1.6: Tabs use existing CSS custom properties for theme compatibility

### Acceptance Criteria
- [ ] Compress tab active by default, works identically to current app
- [ ] Switching tabs shows/hides content instantly
- [ ] Dark and light themes apply correctly to tab buttons
- [ ] No JavaScript errors in console when switching tabs

---

## 4. Feature: MetaClean (Phases 2-3)

### User Story
As a user with Meta Ray-Ban Smart Glasses footage, I want to surgically remove Meta/Ray-Ban attribution metadata while preserving all other metadata (GPS, dates, camera settings).

### Requirements

#### Backend (Phase 2)
- R2.1: `lib/exiftool.js` module with: `detectExifTool()`, `readMetadataJson()`, `computeRemovals()`, `writeCleanCopy()`, `generateReport()`
- R2.2: ExifTool detection cached (same pattern as `lib/hwaccel.js`)
- R2.3: `GET /api/exiftool` returns `{ installed: bool, version: string }`
- R2.4: `GET /api/metadata?path=<encoded_path>` returns full exiftool JSON
- R2.5: `POST /api/metaclean` accepts `{ files: [{path, name}], mode: "attribution"|"privacy" }`
- R2.6: Job type `metaclean` in job queue with WebSocket status events
- R2.7: Output naming: `{original}_CLEAN.{ext}` next to source

#### Stripping Rules
- R2.8: **Attribution mode** (default):
  - HEIC: Remove `EXIF:Make` (when "Meta AI"), `EXIF:Model` (when "Ray-Ban Meta Smart Glasses")
  - MOV: Remove `Keys:Comment` (contains Meta AI string), `Keys:Model`, `Keys:Copyright`
- R2.9: **Privacy mode** (superset of attribution):
  - HEIC: Additionally remove `EXIF:UserComment` (UUID), `EXIF:SerialNumber`, `SubSecTime*`
  - MOV: Additionally remove `Keys:Description`, `Keys:AndroidVersion`
- R2.10: Value matching: `/(meta|ray-?ban|meta ai|meta view)/i`
- R2.11: UUID matching (privacy): `/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i`
- R2.12: **NEVER** run `exiftool -all=` -- surgical removal only
- R2.13: All non-targeted metadata preserved (GPS, dates, camera info, thumbnails)

#### Frontend (Phase 3)
- R3.1: MetaClean tab content with mode toggle (Attribution / Privacy)
- R3.2: Reuse existing drag-drop and file upload for adding files
- R3.3: Per-file card showing: filename, type, size
- R3.4: After cleaning: per-file report showing removed tags with old values
- R3.5: Download button per cleaned output
- R3.6: ExifTool status badge (installed/not installed, version)

### Acceptance Criteria
- [ ] Sample HEIC: Make/Model removed, all dates/GPS preserved
- [ ] Sample MOV: Keys:Comment/Model/Copyright removed, timestamps preserved
- [ ] Privacy mode removes additional UUID/serial/version fields
- [ ] Output file created next to source with `_CLEAN` suffix
- [ ] Report accurately lists removed tags and their old values
- [ ] Non-Meta files processed without error (no tags matched = no changes)

### Test Files
- `/Users/rishaal/CODING/MagFieldsWarRoom/assets/meta/sample meta photo.heic` (618 KB)
- `/Users/rishaal/CODING/MagFieldsWarRoom/assets/meta/sample meta.MOV` (42 MB)

---

## 5. Feature: Stitch (Phases 4-5)

### User Story
As a user, I want to concatenate multiple video clips into a single file, optionally trimming each clip and compressing the output.

### Requirements

#### Backend (Phase 4)
- R4.1: `lib/stitch.js` module with lossless concat (Path A) and re-encode fallback (Path B)
- R4.2: **Path A (lossless):** When all clips share codec/resolution/audio and no trims -- use `ffmpeg -f concat -safe 0 -i list.txt -c copy`
- R4.3: **Path B (re-encode):** When clips differ or trims applied -- normalize all clips, concat via filter complex
- R4.4: `POST /api/stitch` accepts `{ clips: [{path, name, trim?: {start, end}}], order: [0,1,2], compress: bool, preset?, codec?, format? }`
- R4.5: Job type `stitch` in job queue with WebSocket progress
- R4.6: Output naming: `{firstClip}_STITCH_1-2-3.{ext}` (or `_STITCH_1-2-3_COMP.{ext}` if compress enabled)
- R4.7: MetaClean auto-runs on stitched output (chain: stitch complete -> metaclean)
- R4.8: Optional compression uses existing preset/codec infrastructure (two-step MVP)

#### Frontend (Phase 5)
- R5.1: Stitch tab content with clip list
- R5.2: Drag-and-drop reorder of clips (SortableJS CDN)
- R5.3: Per-clip: Preview button (loads into existing Plyr player)
- R5.4: Per-clip: Set In / Set Out buttons (capture `player.currentTime`)
- R5.5: Editable timecode fields next to Set In/Out for precision
- R5.6: "Compress output" toggle with existing preset/codec/format selectors
- R5.7: Stitch button starts the job
- R5.8: WebSocket progress for stitch jobs

### Acceptance Criteria
- [ ] 2+ clips with same codec stitch losslessly (fast, no quality loss)
- [ ] Mixed-codec clips fall back to re-encode and produce playable output
- [ ] Per-clip trims respected in output
- [ ] Clip reorder reflected in final output
- [ ] "Compress output" applies compression presets to stitched result
- [ ] MetaClean runs on final output automatically
- [ ] Output file created next to first source clip

---

## 6. Feature: Download Endpoint (Phase 6)

### User Story
As a user accessing the app from my phone, I want to download processed files since they're saved in /tmp which I can't access.

### Requirements
- R6.1: `GET /api/download?path=<encoded_path>` streams file with `Content-Disposition: attachment`
- R6.2: Download buttons on completed job cards (compress, metaclean, stitch)
- R6.3: Correct filename in Content-Disposition header

### Acceptance Criteria
- [ ] Clicking download saves file to browser's download location
- [ ] File has correct original name (not temp UUID)
- [ ] Works from phone browser (iOS Safari, Chrome)

---

## 7. Constraints (Non-Negotiable)

1. No frameworks -- vanilla JS ES modules only
2. No build step -- CDN for Tailwind, Plyr, SortableJS
3. Local only -- no cloud, no external API calls
4. Don't break Compress -- existing tab must work identically
5. ES modules only -- import/export, never require()
6. FFmpeg via spawn -- never exec() (shell injection prevention)
7. ExifTool via execFile -- same pattern as ffprobe in probe.js
8. Preserve metadata by default -- only strip targeted fields
9. Output next to source -- _CLEAN, _STITCH, _COMP suffixes
10. Theme compatible -- all new UI uses CSS custom properties
