---
name: metadata-tools
description: >
  Inspects, preserves, or strips metadata from video files using ffprobe and ffmpeg.
  Use when a user wants to see what metadata is embedded in a video, preserve metadata
  during compression, strip sensitive metadata before sharing, or use the built-in
  MetaClean metadata stripping workflow for Meta/Ray-Ban attribution and privacy cleanup.
trigger_phrases:
  - 'show video metadata'
  - 'what metadata does this file have'
  - 'strip metadata from video'
  - 'preserve metadata during compression'
  - 'inspect video tags'
  - 'remove GPS data from video'
  - 'check video properties'
  - 'ffprobe this file'
negative_triggers:
  - 'compress this video' # -> compress-video
  - 'why is the compressed file large' # -> diagnose-compression
  - 'process multiple files' # -> batch-process
  - 'what quality should I use' # -> optimize-quality
---

## Workflow

### Step 1 -- Probe Full Metadata

Use the probe API to get the standard metadata, then optionally use ffprobe directly
for extended metadata inspection.

**Basic probe (via API):**

```http
GET /api/probe?path=<encoded_path>
```

Returns:

```json
{
  "duration": 120.5,
  "width": 1920,
  "height": 1080,
  "fps": 29.97,
  "codec": "h264",
  "bitrate": 8500000,
  "size": 127893504,
  "format": "mov,mp4,m4a,3gp,3g2,mj2",
  "audioCodec": "aac"
}
```

**Extended probe (via ffprobe CLI):**
For full metadata including tags, chapters, and embedded data:

```bash
# Show ALL metadata tags
/opt/homebrew/bin/ffprobe -v quiet -print_format json \
  -show_format -show_streams -show_chapters \
  "/path/to/video.mp4"
```

**Common metadata fields found in video files:**

| Category           | Fields                                         | Source           |
| ------------------ | ---------------------------------------------- | ---------------- |
| **Technical**      | codec, bitrate, resolution, fps, duration      | Stream headers   |
| **Container**      | format_name, format_long_name, nb_streams      | Format section   |
| **Creation**       | creation_time, date                            | Format tags      |
| **Camera**         | make, model, software                          | Format tags      |
| **Location**       | location, com.apple.quicktime.location.ISO6709 | Format tags      |
| **Content**        | title, artist, album, comment, description     | Format tags      |
| **Encoding**       | encoder, handler_name                          | Stream tags      |
| **Apple-specific** | com.apple.quicktime.\* (many fields)           | Format tags      |
| **Chapters**       | start_time, end_time, title per chapter        | Chapters section |
| **Subtitles**      | subtitle streams (codec, language, title)      | Stream section   |

**Validation Gate:**

- [ ] Probe returns valid data
- [ ] Format tags section identified (may be empty for some files)
- [ ] Stream count matches expectations (video + audio + optional subtitle)

---

### Step 2 -- Display Metadata Summary

Present metadata in organized categories for the user.

**Display format:**

```
=== File Information ===
Name:       video.mp4
Size:       121.9 MB
Duration:   2:00.5
Format:     mov,mp4,m4a,3gp,3g2,mj2

=== Video Stream ===
Codec:      H.264 (High Profile)
Resolution: 1920x1080
Frame Rate: 29.97 fps
Bitrate:    8.5 Mbps

=== Audio Stream ===
Codec:      AAC
Sample Rate: 48000 Hz
Channels:   2 (stereo)
Bitrate:    192 kbps

=== Metadata Tags ===
creation_time: 2026-02-20T14:30:00.000000Z
encoder:       Lavf60.3.100
handler_name:  VideoHandler

=== Location Data ===
[PRESENT / NOT FOUND]
location: +40.7128-074.0060/

=== Chapters ===
[N chapters / No chapters]
```

---

### Step 3 -- Choose Action

Based on the user's needs, select one of three actions:

#### Action A: Preserve Metadata During Compression

The app already preserves metadata by default using these FFmpeg flags:

- `-map_metadata 0` -- copies all global metadata from input to output
- `-movflags +faststart+use_metadata_tags` -- for MP4/MOV with H.264/H.265

**What is preserved:**

- Container-level tags (title, artist, comment, creation_time)
- Stream-level tags (language, handler_name)
- Chapter markers (when container supports them)

**What is NOT preserved by default:**

- Subtitle streams (not mapped unless explicitly added)
- Attachment streams (fonts, images)
- All data streams

**To also preserve subtitles and all streams:**

```
-map 0                    # map ALL streams from input
-c:s copy                 # copy subtitle streams without re-encoding
```

Note: Task #22 (stream mapping for metadata/subtitle preservation) is in progress.
Current implementation uses `-map_metadata 0` but does not map all streams.

#### Action B: Strip All Metadata

Remove all metadata before sharing, useful for privacy (removes GPS, camera info, etc.).

**FFmpeg command to strip metadata:**

```bash
/opt/homebrew/bin/ffmpeg -i input.mp4 \
  -map_metadata -1 \
  -map 0:v -map 0:a \
  -c copy \
  output_clean.mp4
```

Flags explained:

- `-map_metadata -1`: Discard all metadata
- `-map 0:v -map 0:a`: Only copy video and audio streams (no subtitles, data, attachments)
- `-c copy`: Stream copy (no re-encoding, instant, no quality loss)

**Selective metadata removal:**

```bash
# Remove only location data, keep everything else
/opt/homebrew/bin/ffmpeg -i input.mp4 \
  -map_metadata 0 \
  -metadata location="" \
  -metadata "com.apple.quicktime.location.ISO6709"="" \
  -c copy \
  output.mp4
```

#### Action C: Edit Specific Metadata

Add or modify specific tags without re-encoding.

```bash
# Set title and artist
/opt/homebrew/bin/ffmpeg -i input.mp4 \
  -map_metadata 0 \
  -metadata title="My Video Title" \
  -metadata artist="Author Name" \
  -metadata comment="Compressed with Video Compressor" \
  -c copy \
  output.mp4
```

**Common editable tags:**

- `title` -- Video title
- `artist` -- Creator name
- `album` -- Collection name
- `comment` -- Freeform comment
- `date` -- Creation date
- `description` -- Longer description
- `genre` -- Content genre
- `copyright` -- Copyright notice

---

### Step 4 -- Execute the Action

Run the appropriate command based on the chosen action.

**For preservation (default during compression):**
No additional action needed -- the compress-video workflow already includes
`-map_metadata 0` and `-movflags +faststart+use_metadata_tags`.

**For stripping or editing:**
These operations use `-c copy` (stream copy) and complete nearly instantly,
as no re-encoding occurs.

Execution via:

```bash
/opt/homebrew/bin/ffmpeg -y [flags] -i input.mp4 [metadata_flags] -c copy output.mp4
```

---

### Step 5 -- Verify Result

Confirm the metadata action was applied correctly.

**Verification steps:**

- [ ] Output file exists and size is approximately equal to input (stream copy preserves size)
- [ ] Probe output file to verify metadata state
- [ ] For strip: confirm no tags remain in format section
- [ ] For preserve: confirm tags carried over from input
- [ ] For edit: confirm modified tags have new values
- [ ] Playback works correctly (stream copy should never break playback)

---

## Future: Meta Glasses Metadata Stripping Mode

A planned feature for automated metadata stripping specifically for Meta Ray-Ban
smart glasses videos and similar wearable camera footage.

**Why this is needed:**

- Meta glasses embed extensive metadata: GPS coordinates, device info, capture settings
- Users sharing glasses footage may not realize it contains location data
- Automated "clean for sharing" mode strips privacy-sensitive fields while preserving
  technical metadata needed for playback

**Planned implementation:**

1. Detect Meta glasses footage by checking `make` / `model` tags
2. Auto-strip: location, GPS, device identifiers, user account info
3. Preserve: codec info, timestamps, chapter markers
4. Zero re-encoding (stream copy only)

**Fields to strip for Meta glasses:**

```
com.apple.quicktime.location.ISO6709
location
com.apple.quicktime.make
com.apple.quicktime.model
com.apple.quicktime.software
com.apple.quicktime.creationdate
```

---

## Reference: ffprobe Command Cheatsheet

```bash
# Full metadata dump (JSON)
ffprobe -v quiet -print_format json -show_format -show_streams -show_chapters input.mp4

# Stream info only
ffprobe -v quiet -print_format json -show_streams input.mp4

# Format/container info only
ffprobe -v quiet -print_format json -show_format input.mp4

# Chapters only
ffprobe -v quiet -print_format json -show_chapters input.mp4

# Specific stream info
ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate input.mp4

# Show all tags (human readable)
ffprobe -v quiet -show_entries format_tags input.mp4

# Frame-level info (first 10 frames)
ffprobe -v quiet -print_format json -show_frames -read_intervals "%+#10" input.mp4

# Packet info (useful for debugging timestamps)
ffprobe -v quiet -print_format json -show_packets -read_intervals "%+#10" input.mp4
```

---

## Error Handling

| Error                                      | Cause                                                | Fix                                                    |
| ------------------------------------------ | ---------------------------------------------------- | ------------------------------------------------------ |
| `No such file or directory`                | Path incorrect or file moved                         | Verify path; check for special characters              |
| `Invalid data found when processing input` | Corrupt file header                                  | Try `-fflags +genpts` or re-download file              |
| `Could not write header`                   | Output format doesn't support the metadata type      | Use a different container (MKV supports most metadata) |
| `Operation not permitted` on output        | File permissions or SIP protection                   | Check write permissions on output directory            |
| Tags not appearing after edit              | Some players cache metadata                          | Try a different player or clear cache                  |
| GPS data still present after strip         | Apple-specific location fields use non-standard keys | Strip ALL `com.apple.quicktime.*` fields explicitly    |
