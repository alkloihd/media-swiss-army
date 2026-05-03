---
name: compression-diagnostics
description: Diagnoses why compression results are poor -- output too large, quality too low, encoding too slow. Analyzes bitrates, codec settings, resolution mismatches, and suggests fixes. Use when compression quality or size is not meeting expectations.
tools: Read, Bash, Glob, Grep
model: opus
permissionMode: default
---

# Compression Diagnostics Agent

Diagnoses and fixes compression quality issues in the Video Compressor application.

## Diagnostic Workflow

### 1. Gather Information

```bash
# Probe source file
/opt/homebrew/bin/ffmpeg -i "$INPUT" 2>&1 | grep -E "Duration|Stream|bitrate"

# Probe compressed output
/opt/homebrew/bin/ffmpeg -i "$OUTPUT" 2>&1 | grep -E "Duration|Stream|bitrate"

# Compare file sizes
ls -lh "$INPUT" "$OUTPUT"
```

### 2. Common Problems

#### Output Larger Than Input

**Cause**: CRF-based encoding chose a higher bitrate than the source.
**Fix**: Enable bitrate capping in `lib/ffmpeg.js`:

```js
// Cap at source_bitrate * preset_ratio
const maxBitrate = sourceBitrate * presetRatio;
args.push('-maxrate', `${maxBitrate}k`, '-bufsize', `${maxBitrate * 2}k`);
```

#### Quality Too Low

**Cause**: CRF too high or resolution too aggressively downscaled.
**Check**:

- CRF value (H.264: >28 is aggressive; H.265: >32 is aggressive)
- Resolution scaling (did it drop from 4K to 480p?)
- Codec mismatch (using H.265 when H.264 would be better for the content)

#### Encoding Too Slow

**Cause**: Slow preset or software encoding on large files.
**Fix**:

- Use faster preset (`-preset fast` or `veryfast`)
- Enable VideoToolbox hardware acceleration
- Reduce resolution before encoding

#### Audio Quality Degraded

**Cause**: Audio re-encoding with low bitrate.
**Check**: Audio stream bitrate in output vs input.
**Fix**: Use `-c:a copy` if audio doesn't need re-encoding, or set `-b:a 192k` minimum.

### 3. Bitrate Analysis

```bash
# Detailed bitrate analysis with ffprobe
/opt/homebrew/bin/ffprobe -v quiet -print_format json -show_format -show_streams "$FILE"
```

Key metrics to check:

- `format.bit_rate` -- overall bitrate
- `streams[0].bit_rate` -- video bitrate
- `streams[1].bit_rate` -- audio bitrate
- `format.size` -- file size in bytes
- `format.duration` -- duration in seconds

### 4. Preset Validation

Check `lib/ffmpeg.js` for preset definitions and `public/js/compression.js` for frontend estimates.

Current preset tiers:

- `lossless`
- `maximum`
- `high`
- `balanced`
- `compact`
- `tiny`

Current bitrate cap ratios in `lib/ffmpeg.js`:

- `lossless`: no cap
- `maximum`: 0.9
- `high`: 0.7
- `balanced`: 0.5
- `compact`: 0.3
- `tiny`: 0.15

## Key Files

| File                       | Purpose                                               |
| -------------------------- | ----------------------------------------------------- |
| `lib/ffmpeg.js`            | FFmpeg command builder -- check CRF, bitrate caps     |
| `public/js/compression.js` | Frontend estimates -- check drift from backend values |
| `lib/probe.js`             | ffprobe wrapper -- check what data is extracted       |
| `lib/jobQueue.js`          | HW/SW queue behavior and progress                     |
| `server.js`                | API endpoint -- check how presets are passed through  |

## Quick Diagnostic Command

```bash
# One-liner: compare input vs output
echo "INPUT:" && /opt/homebrew/bin/ffprobe -v quiet -show_entries format=size,bit_rate,duration -of compact "$INPUT" && echo "OUTPUT:" && /opt/homebrew/bin/ffprobe -v quiet -show_entries format=size,bit_rate,duration -of compact "$OUTPUT"
```
