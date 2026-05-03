---
name: diagnose-compression
description: >
  Diagnoses why video compression results are poor -- file is too large, quality
  is degraded, artifacts visible, or output is bigger than input. Use when a user
  is unhappy with compression results or confused by unexpected output sizes.
trigger_phrases:
  - 'why is the compressed file so large'
  - 'output is bigger than the original'
  - "compression didn't reduce the size"
  - 'video quality looks terrible after compression'
  - 'I see artifacts after compressing'
  - 'why did the file get larger'
  - "compression isn't working"
  - 'the file barely got smaller'
negative_triggers:
  - 'compress this video' # -> compress-video
  - 'what settings should I use' # -> optimize-quality
  - 'process multiple files' # -> batch-process
  - 'show me the metadata' # -> metadata-tools
---

## Workflow

### Step 1 -- Probe the Input File

Gather complete metadata about the source file.

**API Call:**

```http
GET /api/probe?path=<encoded_input_path>
```

**Key metrics to capture:**

- `codec`: Source codec name (e.g., `h264`, `hevc`, `prores`, `mjpeg`)
- `bitrate`: Source bitrate in bits/second
- `width` x `height`: Source resolution
- `duration`: Length in seconds
- `size`: File size in bytes
- `format`: Container format (e.g., `mov,mp4,m4a,3gp,3g2,mj2`)

**Calculate derived metrics:**

```
bitrateKbps = bitrate / 1000
bitsPerPixelPerFrame = bitrate / (width * height * fps)
```

**Validation Gate:**

- [ ] Probe data retrieved successfully
- [ ] Bitrate value is present and > 0
- [ ] Codec name is identified

---

### Step 2 -- Probe the Output File

If the compressed file exists, probe it for comparison.

**Comparison table to build:**

| Metric     | Input        | Output       | Change |
| ---------- | ------------ | ------------ | ------ |
| Size       | X MB         | Y MB         | -Z%    |
| Bitrate    | X kbps       | Y kbps       | -Z%    |
| Resolution | WxH          | WxH          | same/? |
| Codec      | source_codec | target_codec |        |
| Duration   | X sec        | Y sec        | same/? |

---

### Step 3 -- Identify the Root Cause

Run through this diagnostic decision tree:

#### 3a. Output is LARGER than input

**Most common cause: Already-compressed input with low bitrate**

When the source is already H.264 at (for example) 2500 kbps, and you compress to
H.265 with `balanced` preset targeting 6000 kbps, the output will be LARGER.

The smart bitrate capping system mitigates this:

- `balanced` caps at 70% of input bitrate
- `balanced` caps at 50%
- `compact` caps at 30%
- `tiny` caps at 15%
- `lossless` has no cap by design

**Check:** Is `sourceBitrate / 1000` < target bitrate for the chosen encoder/preset?

| Encoder           | maximum | high   | balanced | compact | tiny  |
| ----------------- | ------- | ------ | -------- | ------- | ----- |
| h264_videotoolbox | 20000k  | 12000k | 8000k    | 4000k   | 1500k |
| hevc_videotoolbox | 15000k  | 8000k  | 5000k    | 2500k   | 1000k |

If the source bitrate is already below the target, even after capping, the HW encoder
may produce a larger file because VideoToolbox bitrate targeting is approximate and
tends to overshoot on simple content.

**Other causes of size increase:**

- ProRes output (always larger than H.264/H.265 -- by design, it's a mastering codec)
- Adding audio re-encoding overhead to short clips
- Upscaling resolution (should be blocked by UI, but check)

#### 3b. Output looks BAD (quality loss, artifacts)

**Common causes:**

1. **CRF too high** (SW encoder): CRF 32+ for H.265 or CRF 28+ for H.264 on complex content
2. **Bitrate too low** (HW encoder): For 4K content, even 8000k may be insufficient
3. **Resolution downscale**: Scaling 4K to 720p loses detail
4. **Codec mismatch**: Re-encoding ProRes source to H.264 at "compact" preset strips mastering quality
5. **Double compression**: Re-encoding already-compressed H.264 to H.264 accumulates generational loss

**Bits-per-pixel diagnostic:**

```
bpp = bitrate / (width * height * fps)
```

- bpp < 0.05: Likely visible quality loss
- bpp 0.05-0.1: Acceptable for most content
- bpp 0.1-0.2: Good quality
- bpp > 0.2: Excellent quality

#### 3c. Compression barely reduces size

**Common causes:**

1. **Source already well-compressed**: H.264 at CRF ~23 won't compress much further
2. **"maximum" preset selected**: Designed for quality, not size reduction
3. **ProRes source -> H.264 balanced**: This SHOULD compress well (5-10x reduction typical)
4. **Short clip**: Fixed overhead (headers, keyframes) as percentage of tiny file

---

### Step 4 -- Recommend a Fix

Based on the diagnosis, suggest specific actions:

| Diagnosis                             | Recommendation                                                                            |
| ------------------------------------- | ----------------------------------------------------------------------------------------- |
| Already-compressed H.264, low bitrate | Skip compression or use `compact` preset with H.265                                       |
| ProRes source, output too large       | Expected -- ProRes is mastering format. Use H.265 balanced for delivery                   |
| HW encoder overshooting bitrate       | Switch to SW encoder (libx264/libx265) which uses CRF for consistent quality              |
| Quality too low                       | Increase preset from `compact` to `balanced` or `maximum`; or use higher resolution       |
| Double compression artifacts          | Avoid re-encoding; if needed, use `maximum` preset to minimize generational loss          |
| Bitrate cap not reducing enough       | The cap uses six-tier ratios: maximum 0.9, high 0.7, balanced 0.5, compact 0.3, tiny 0.15 |

---

### Step 5 -- Verify the Fix

After applying the recommended change, verify:

- [ ] Re-compress with adjusted settings
- [ ] Compare new output size to both original and previous attempt
- [ ] Spot-check quality (playback in preview player)
- [ ] Confirm size reduction meets user expectations

---

## Deep Knowledge: Why Already-Compressed Files Don't Compress Well

### The Fundamental Problem

Video compression is lossy. Each encode pass:

1. Analyzes motion vectors and spatial frequency
2. Quantizes coefficients (irreversible quality loss)
3. Entropy codes the result

Re-encoding an already-compressed file means:

- The encoder sees the DECODED output (with artifacts baked in)
- It must re-analyze and re-quantize, adding MORE loss
- The "information content" after decode is often higher than the compressed size suggests
  because decoded frames fill in quantized blocks, creating data the encoder must handle

### ProRes vs H.264 Behavior

**ProRes source -> H.264/H.265:**

- Excellent compression expected (5-20x reduction)
- ProRes preserves near-raw quality at very high bitrates (60-300 Mbps)
- Re-encoding to delivery codecs works perfectly

**H.264 source -> H.265:**

- Moderate compression expected (20-40% reduction typical)
- H.265 is more efficient, so re-encoding has genuine benefit
- But if source H.264 is already very low bitrate, gains disappear

**H.264 source -> H.264:**

- Minimal benefit (0-15% at best)
- Risk of quality loss from double compression
- Generally not recommended unless changing resolution or trimming

### VideoToolbox Bitrate Targeting

Apple's VideoToolbox hardware encoder uses a different bitrate control strategy
than software encoders:

- SW encoders (libx264/libx265): Use CRF (Constant Rate Factor) which adapts
  bitrate to content complexity. Simple scenes get low bitrate, complex scenes get high.
- HW encoders (VideoToolbox): Use target bitrate (`-b:v`). The encoder aims for this
  average but overshoots on complex content and undershoots on simple content.

This means VideoToolbox may produce files LARGER than expected for:

- Simple, static content (talking head, slides)
- Already-compressed content with low information density
- Short clips where ramp-up overhead is significant

---

## Error Reference Table

| FFmpeg Error                               | Meaning                              | Fix                                                        |
| ------------------------------------------ | ------------------------------------ | ---------------------------------------------------------- |
| `Invalid data found when processing input` | Corrupt file or unsupported codec    | Re-download file; try different container                  |
| `Discarded X frame(s)`                     | Timestamp discontinuities            | Add `-fflags +genpts` before input                         |
| `Error while opening encoder`              | Codec not available or misconfigured | Check `ffmpeg -encoders`; verify VideoToolbox availability |
| `height not divisible by 2`                | Odd resolution with certain codecs   | Scale filter uses `-2:H` to ensure even dimensions         |
| `Avi duration discrepancy`                 | AVI container issues                 | Convert to MP4 first, then compress                        |
| `Too many packets buffered`                | Memory pressure during encode        | Reduce concurrency from 4 to 2                             |
| `Unknown encoder`                          | FFmpeg built without that codec      | Reinstall FFmpeg: `brew reinstall ffmpeg`                  |
| `Output file is empty`                     | Encoding failed silently             | Check full stderr; likely codec/format incompatibility     |
