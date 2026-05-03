---
name: compress-video
description: >
  Compresses one or more video files using FFmpeg with optimal settings for the
  target quality/size tradeoff. Use when a user wants to reduce video file size,
  re-encode a video, change codec/format, or apply trim/crop during compression.
trigger_phrases:
  - 'compress this video'
  - 'make this file smaller'
  - 're-encode to H.265'
  - 'convert video to mp4'
  - 'reduce video file size'
  - 'encode with hardware acceleration'
  - 'compress with VideoToolbox'
  - 'shrink this recording'
negative_triggers:
  - 'why is the file still large' # -> diagnose-compression
  - 'compare quality settings' # -> optimize-quality
  - 'process all files in folder' # -> batch-process
  - 'strip metadata' # -> metadata-tools
  - 'inspect video metadata' # -> metadata-tools
  - 'find best CRF value' # -> optimize-quality
---

## Workflow

### Step 1 -- Validate Input File

Confirm the input file exists and is a supported video format.

```
Supported extensions:
  .mp4 .mkv .avi .mov .webm .wmv .flv .ts .m4v .mts .m2ts
  .mpg .mpeg .3gp .vob .ogv .f4v
```

**Actions:**

1. Check file exists at the given path
2. Call `GET /api/probe?path=<encoded_path>` to retrieve metadata
3. Verify the response contains a video stream

**Validation Gate:**

- [ ] File exists on disk
- [ ] Probe returns valid JSON with `width`, `height`, `duration`, `codec`, `bitrate`
- [ ] Duration > 0 (not a still image or corrupt file)

If probe fails, check:

- Is the path URL-encoded correctly?
- Does the file have a video stream (not audio-only)?
- Is FFprobe accessible at `/opt/homebrew/bin/ffprobe`?

---

### Step 2 -- Select Compression Settings

Choose codec, quality preset, output format, and resolution scale.

#### Available Codecs

| Codec  | HW Encoder (VideoToolbox) | SW Encoder  | Best For                     |
| ------ | ------------------------- | ----------- | ---------------------------- |
| H.264  | `h264_videotoolbox`       | `libx264`   | Maximum compatibility        |
| H.265  | `hevc_videotoolbox`       | `libx265`   | Best size/quality balance    |
| AV1    | (none -- SW only)         | `libsvtav1` | Future-proof, smallest files |
| ProRes | `prores_videotoolbox`     | `prores_ks` | Editing / mastering          |

#### Quality Presets

Current presets are six-tier. Legacy names are accepted by the backend only as aliases.

| Preset   | Intent                       | H.264 HW | H.264 SW        | H.265 HW | H.265 SW        | AV1 SW     |
| -------- | ---------------------------- | -------- | --------------- | -------- | --------------- | ---------- |
| lossless | Preserve as much as possible | 40000k   | CRF 0/slow      | 30000k   | CRF 0/slow      | CRF 0/p4   |
| maximum  | Highest practical quality    | 20000k   | CRF 15/medium   | 15000k   | CRF 18/medium   | CRF 20/p6  |
| high     | High quality                 | 12000k   | CRF 20/fast     | 8000k    | CRF 23/fast     | CRF 27/p6  |
| balanced | Default balance              | 8000k    | CRF 23/fast     | 5000k    | CRF 28/fast     | CRF 32/p6  |
| compact  | Smaller file                 | 4000k    | CRF 30/fast     | 2500k    | CRF 34/fast     | CRF 40/p8  |
| tiny     | Maximum reduction            | 1500k    | CRF 38/veryfast | 1000k    | CRF 42/veryfast | CRF 50/p12 |

Legacy aliases: `max` -> `maximum`, `small` -> `compact`, `streaming` -> `balanced`.

#### Codec-Format Compatibility

| Codec  | MP4 | MOV | MKV |
| ------ | --- | --- | --- |
| H.264  | yes | yes | yes |
| H.265  | yes | yes | yes |
| AV1    | yes | no  | yes |
| ProRes | no  | yes | no  |

#### Resolution Scaling

| Scale    | Target Height | Notes                   |
| -------- | ------------- | ----------------------- |
| original | (unchanged)   | Default                 |
| 1080p    | 1080          | Full HD                 |
| 720p     | 720           | HD, good for streaming  |
| 480p     | 480           | SD, maximum compression |
| 360p     | 360           | Mobile / low-bandwidth  |

Width is calculated automatically to preserve aspect ratio (even dimensions via `-2`).
Upscaling is blocked -- options larger than source are disabled.

**Validation Gate:**

- [ ] Codec is one of: h264, h265, av1, prores
- [ ] Format is compatible with chosen codec
- [ ] Scale does not exceed source resolution
- [ ] If HW encoder is unavailable, confirm SW fallback is acceptable

---

### Step 3 -- Estimate Output Size

Before compressing, estimate the output to set user expectations.

**For HW encoders (bitrate-based):**

```
estimatedSize = (targetBitrate_bps / 8) * duration_seconds
```

Note: Smart bitrate capping adjusts the target:

- `lossless`: no cap
- `maximum`: min(target, inputBitrate \* 0.9)
- `high`: min(target, inputBitrate \* 0.7)
- `balanced`: min(target, inputBitrate \* 0.5)
- `compact`: min(target, inputBitrate \* 0.3)
- `tiny`: min(target, inputBitrate \* 0.15)

**For SW/CRF encoders (ratio-based):**

| Encoder   | maximum | high | balanced | compact | tiny |
| --------- | ------- | ---- | -------- | ------- | ---- |
| libx264   | 0.90    | 0.70 | 0.60     | 0.35    | 0.15 |
| libx265   | 0.80    | 0.60 | 0.50     | 0.25    | 0.12 |
| libsvtav1 | 0.70    | 0.50 | 0.40     | 0.20    | 0.10 |
| prores_ks | 2.00    | 1.50 | 1.20     | 0.80    | 0.50 |

**Resolution adjustment:**

```
pixelRatio = (scaledWidth * scaledHeight) / (originalWidth * originalHeight)
estimatedSize *= pixelRatio
```

**Verification Step:**

- Display estimated output size and percentage change to user
- If estimated size is LARGER than input (common with ProRes or already-compressed files), warn the user

---

### Step 4 -- Execute Compression

Send the compression request to the API.

**API Call:**

```http
POST /api/compress
Content-Type: application/json

{
  "files": [{ "path": "/path/to/video.mp4", "name": "video.mp4" }],
  "preset": "balanced",
  "codec": "h265",
  "format": "mp4",
  "scale": "original"
}
```

Optional fields: `trim` (`{ start, end }`), `crop` (`{ width, height, x, y }`)

**What happens internally:**

1. Server probes the input file for metadata
2. `buildCommand()` constructs FFmpeg arguments
3. Job is added to JobQueue (HW concurrency 2, SW concurrency 3)
4. FFmpeg process spawns with `stdio: ['ignore', 'pipe', 'pipe']`
5. Progress parsed from stderr (`time=`, `speed=`, `fps=`)
6. WebSocket broadcasts progress/complete/error events

**Output naming:**

- File: `{originalName}_COMP.{ext}`
- If exists: `{originalName}_COMP_2.{ext}`, `_COMP_3`, etc.
- Output goes to the SAME directory as the input file

---

### Step 5 -- Monitor and Verify

Track compression progress via WebSocket and verify output.

**WebSocket events:**

- `progress`: `{ type, jobId, percent, speed, fps, eta }`
- `complete`: `{ type, jobId, outputPath, outputSize, compressedSize }`
- `error`: `{ type, jobId, error }`

**Verification Steps:**

- [ ] Output file exists at the expected path
- [ ] Output file size > 0
- [ ] Compression ratio is reasonable (not 1:1 or larger than input without explanation)
- [ ] Output is playable (probe returns valid metadata)

---

## Error Handling

| Error                           | Cause                                            | Fix                                                                 |
| ------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------- |
| `FFmpeg exited with code 1`     | Invalid arguments, codec mismatch, corrupt input | Check stderr output, verify codec/format compatibility              |
| `Failed to start FFmpeg`        | FFmpeg binary not found or not executable        | Verify `/opt/homebrew/bin/ffmpeg` exists; run `brew install ffmpeg` |
| `File not found`                | Path doesn't exist or has special characters     | URL-encode the path; check for spaces/quotes                        |
| `No streams found`              | File is not a valid media file                   | Verify file isn't corrupt; try re-downloading                       |
| `ffprobe returned invalid JSON` | Corrupt file or incompatible format              | Try a different file; check format support                          |
| Output larger than input        | Already-compressed H.264/H.265 input             | Use `diagnose-compression` skill; consider lower preset or skip     |
| Disk space error                | Insufficient space for output                    | Check available space; output goes next to source file              |
| `SIGTERM` / process killed      | User cancelled or system pressure                | Job marked as cancelled; retry if desired                           |

---

## Reference: Complete FFmpeg Flag Construction

The `buildCommand()` function in `lib/ffmpeg.js` builds args in this order:

```
ffmpeg -threads 0 -y
  -i <input>
  -map_metadata 0
  [-ss <start> -to <end>]          # if trim
  -c:v <encoder>
  <quality_flags>                   # preset-specific
  [-vf crop=W:H:X:Y,scale=-2:H]   # if crop/scale
  -c:a <audio_codec> -b:a <rate>   # audio
  [-movflags +faststart+use_metadata_tags]  # if mp4/mov + h264/h265
  <output>
```

Audio codecs per video codec:

- H.264/H.265: AAC (256k for maximum, 192k otherwise)
- ProRes: PCM S16LE (uncompressed)
- AV1: libopus (128k)
