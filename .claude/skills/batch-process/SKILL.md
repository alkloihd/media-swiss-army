---
name: batch-process
description: >
  Handles processing multiple video files efficiently, including scanning directories,
  grouping files by properties, and queuing batch compression jobs. Use when a user
  wants to compress an entire folder, process multiple files with the same settings,
  or manage a large batch queue.
trigger_phrases:
  - 'compress all videos in this folder'
  - 'batch compress these files'
  - 'process multiple videos'
  - 'compress everything in the directory'
  - 'queue up all these files'
  - 'how many files can I process at once'
  - 'compress a folder of videos'
  - 'parallel compression'
negative_triggers:
  - 'compress this one video' # -> compress-video
  - 'why is this file still large' # -> diagnose-compression
  - 'what quality should I use' # -> optimize-quality
  - 'show metadata for this file' # -> metadata-tools
---

## Workflow

### Step 1 -- Scan and Collect Files

Identify all video files to process.

**Input methods:**

1. **Drag-and-drop multiple files** into the drop zone (up to 20 via multer)
2. **Path input** with multiple paths separated by `;` or newlines
3. **Directory path** (requires manual listing -- the app processes individual files)

**Supported video extensions:**

```
.mp4 .mkv .avi .mov .webm .wmv .flv .ts .m4v .mts .m2ts
.mpg .mpeg .3gp .vob .ogv .f4v
```

**For each file discovered:**

1. Upload via `POST /api/upload` (for browser-selected files) or provide path directly
2. Probe via `GET /api/probe?path=<path>` to get metadata
3. Add to the file queue in `appState.files`

**Validation Gate:**

- [ ] All files exist and are accessible
- [ ] All files probe successfully (have video streams)
- [ ] Total count is manageable (check available disk space for outputs)

---

### Step 2 -- Probe All Files and Analyze

Gather metadata for every file to inform grouping decisions.

**Per-file metadata:**

```json
{
  "codec": "h264",
  "width": 1920,
  "height": 1080,
  "fps": 29.97,
  "bitrate": 8500000,
  "duration": 120.5,
  "size": 127893504,
  "format": "mov,mp4,m4a,3gp,3g2,mj2",
  "audioCodec": "aac"
}
```

**Aggregate statistics to compute:**

- Total input size (sum of all file sizes)
- Min/max/average bitrate
- Unique codecs present
- Unique resolutions present
- Total duration
- Estimated total output size

---

### Step 3 -- Group Files by Properties

Grouping helps identify files that need different treatment.

**Recommended groups:**

| Group              | Criteria                           | Suggested Handling                                            |
| ------------------ | ---------------------------------- | ------------------------------------------------------------- |
| ProRes / Raw       | codec = prores, rawvideo           | Compress aggressively; expect 5-20x reduction                 |
| High-bitrate H.264 | codec = h264, bitrate > 15Mbps     | Good compression candidates; H.265 balanced                   |
| Already-compressed | codec = h264/hevc, bitrate < 5Mbps | Skip or use `compact`/`tiny` preset only                      |
| 4K+                | width >= 3840                      | Consider downscaling to 1080p for delivery                    |
| Low-res            | height <= 720                      | Keep original resolution; scaling down further loses too much |
| Long-form          | duration > 3600s                   | Monitor disk space; these produce large outputs               |
| Short clips        | duration < 10s                     | Fixed overhead may limit compression ratio                    |

**Per-file resolution override:**
The UI supports per-file resolution dropdowns via the `file.scale` property on each
file card. Use this to set different resolutions per group:

- 4K files -> scale to 1080p
- 1080p files -> keep original
- 720p files -> keep original

---

### Step 4 -- Configure Per-File Settings

The app applies the same codec/preset/format to all files in a batch, but resolution
can be set per file.

**Global settings (apply to all):**

- Codec: Set via codec selector buttons
- Preset: Set via quality preset buttons
- Format: Set via format selector buttons

**Per-file settings:**

- Resolution: Set via per-file dropdown on each file card
- The `file.scale` property is read during compression

**Recommended batch configurations:**

| Source Type                         | Codec | Preset   | Format | Scale    |
| ----------------------------------- | ----- | -------- | ------ | -------- |
| ProRes masters                      | H.265 | balanced | MP4    | 1080p    |
| Camera footage (H.264 high-bitrate) | H.265 | balanced | MP4    | original |
| Screen recordings                   | H.265 | compact  | MP4    | original |
| Already-compressed delivery files   | Skip  | --       | --     | --       |
| Mixed for archival                  | AV1   | balanced | MKV    | original |

---

### Step 5 -- Queue and Execute

Send the compression request for all pending files.

**How the batch is processed:**

1. The "Compress All" button iterates over all files with `status === 'pending'`
2. Each file sends an individual `POST /api/compress` request
3. Server adds each job to JobQueue
4. JobQueue routes VideoToolbox jobs to the HW queue with concurrency 2 and software jobs to the SW queue with concurrency 3

**API request per file:**

```http
POST /api/compress
{
  "files": [{ "path": "<serverPath>", "name": "<filename>" }],
  "preset": "balanced",
  "codec": "h265",
  "format": "mp4",
  "scale": "original"
}
```

**Concurrency considerations for M2 Max:**

- HW queue concurrency is 2 to match the VideoToolbox encode-engine assumption on M2 Max
- SW queue concurrency is 3 so CPU-bound libx264/libx265 work can proceed without blocking HW jobs
- Mixed HW/SW batches may run up to both queue limits at once; watch thermals and memory on long batches
- Mixing HW and SW encoding works well; HW uses encode engines while SW uses CPU cores
- For AV1 (libsvtav1), consider reducing SW queue concurrency because it is very CPU-intensive

**Validation Gate:**

- [ ] All files have `status === 'pending'`
- [ ] Disk space sufficient for estimated total output
- [ ] Compress button is enabled and shows correct count

---

### Step 6 -- Monitor Batch Progress

Track all jobs via WebSocket updates.

**Progress tracking per job:**

```
WebSocket message: { type: "progress", jobId, percent, speed, fps, eta }
```

**Batch-level monitoring:**

- Count of completed / total jobs
- Files transition: `pending` -> `queued` -> `compressing` -> `done` / `error`
- Each file card shows individual progress bar with percentage, speed, and ETA
- Compress button shows spinner with count: "Compressing (N)..."

**Post-completion verification:**

- [ ] All jobs completed (no errors)
- [ ] Each output file exists
- [ ] Size comparison shown on each file card (original -> compressed, -X%)
- [ ] Total batch savings computed

---

## Error Handling for Batches

| Scenario                       | Behavior                                                       | Recovery                                       |
| ------------------------------ | -------------------------------------------------------------- | ---------------------------------------------- |
| One file fails, others succeed | Failed file shows error badge; others continue                 | Fix the failing file and re-add it             |
| Disk space runs out mid-batch  | Current job may fail; queued jobs will fail on start           | Free space, remove partial outputs, re-queue   |
| All files fail with same error | Likely a codec/format misconfiguration                         | Check compression settings and re-try          |
| Server crashes mid-batch       | WebSocket disconnects; auto-reconnect with exponential backoff | Restart server; re-add incomplete files        |
| Browser tab closed             | Jobs continue on server; progress lost in UI                   | Refresh page; check `GET /api/jobs` for status |
| Upload fails for some files    | Those files show error status                                  | Re-upload failed files individually            |

---

## Reference: Queue Architecture

```
                 +------------------+
                 |   Express API    |
                 | POST /api/compress|
                 +--------+---------+
                          |
                          v
                 +------------------+
                 |    JobQueue      |
                 |  (EventEmitter)  |
                 +--------+---------+
                          |
                          v
                 +------------------+
                 |     JobQueue     |
                 | HW:2 / SW:3   |
                 +--+--+--+--+-----+
                    |  |  |  |
                    v  v  v  v
                 [FFmpeg processes]
                    |  |  |  |
                    v  v  v  v
                 [WebSocket broadcast]
                    |
                    v
                 [Browser UI updates]
```

**Job lifecycle:**
`queued` -> `running` -> `complete` | `error` | `cancelled`

**Throttling:**
Progress events are throttled to 1 per second per job via a custom throttle function
to prevent WebSocket flooding during batch processing.
