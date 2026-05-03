---
name: optimize-quality
description: >
  Finds the best quality-to-size tradeoff for a specific video by analyzing content
  complexity, comparing codec/preset options, and recommending optimal settings.
  Use when a user wants to understand which settings give the best result for their
  specific content, or needs to compare CRF vs bitrate approaches.
trigger_phrases:
  - "what's the best quality setting"
  - 'find optimal compression settings'
  - 'compare quality presets'
  - 'CRF vs bitrate which is better'
  - 'should I use hardware or software encoding'
  - 'best settings for this type of video'
  - 'quality comparison'
  - 'what CRF should I use'
negative_triggers:
  - 'just compress this video' # -> compress-video
  - 'why is the output so large' # -> diagnose-compression
  - 'compress all files in folder' # -> batch-process
  - 'strip metadata from video' # -> metadata-tools
---

## Workflow

### Step 1 -- Probe and Analyze Input

Gather detailed metadata about the source video to understand its characteristics.

**API Call:**

```http
GET /api/probe?path=<encoded_path>
```

**Key analysis points:**

| Property           | What It Tells Us                                |
| ------------------ | ----------------------------------------------- |
| `codec`            | Source encoding; affects re-encoding strategy   |
| `bitrate`          | Current quality level; baseline for improvement |
| `width` x `height` | Resolution determines bitrate needs             |
| `fps`              | Higher FPS = more data needed                   |
| `duration`         | Affects total file size                         |

**Content complexity classification:**

| Content Type           | Characteristics                   | Compression Friendliness                         |
| ---------------------- | --------------------------------- | ------------------------------------------------ |
| Talking head / podcast | Low motion, simple background     | Very friendly (2-4 Mbps sufficient for 1080p)    |
| Screen recording       | Large static areas, sharp text    | Friendly (3-5 Mbps; avoid blur-inducing presets) |
| Action/sports          | High motion, fast scene changes   | Needs high bitrate (8-15 Mbps for 1080p)         |
| Nature/landscapes      | High detail, gradual motion       | Moderate (5-8 Mbps)                              |
| Animation              | Flat colors, sharp edges          | Very friendly (2-4 Mbps)                         |
| Grain-heavy film       | Dense random noise in every frame | Needs high bitrate or denoising (10-20 Mbps)     |

**Derived metric -- Bits per pixel per frame (BPP):**

```
bpp = bitrate / (width * height * fps)
```

| BPP Range   | Quality Level                             |
| ----------- | ----------------------------------------- |
| < 0.03      | Very low -- visible artifacts likely      |
| 0.03 - 0.06 | Low -- acceptable for simple content      |
| 0.06 - 0.10 | Medium -- good for most content           |
| 0.10 - 0.15 | High -- good for complex content          |
| 0.15 - 0.25 | Very high -- excellent quality            |
| > 0.25      | Overkill for delivery; fine for mastering |

**Validation Gate:**

- [ ] Probe data retrieved with all fields populated
- [ ] BPP calculated and content type estimated
- [ ] Source codec identified for re-encoding strategy

---

### Step 2 -- Content-Specific Recommendations

Based on the content analysis, recommend optimal settings.

#### CRF vs Bitrate: When to Use Which

| Approach                       | Method                 | Best For                         | Behavior                                                                                       |
| ------------------------------ | ---------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------- |
| **CRF** (Constant Rate Factor) | SW encoders: `-crf N`  | Consistent quality across scenes | Adapts bitrate to content complexity; simple scenes get small files, complex scenes get larger |
| **Target Bitrate**             | HW encoders: `-b:v Nk` | Predictable file sizes           | Fixed average bitrate; may under/over-allocate for varying complexity                          |

**When to prefer CRF (software encoding):**

- You care about consistent quality more than exact file size
- Content has varying complexity (mix of static and action)
- You have time to wait (SW encoding is 2-5x slower than HW)
- You need fine-grained quality control

**When to prefer HW encoding (VideoToolbox):**

- Speed matters (4-10x faster than SW)
- You're doing batch processing and need throughput
- File size predictability is acceptable
- Content complexity is relatively uniform

---

### Step 3 -- Preset Comparison Chart

For the user's specific video, compute estimated outputs for each combination.

#### H.264 Options

| Preset   | SW (libx264)     | HW (VideoToolbox) | Est. Size (for reference file) |
| -------- | ---------------- | ----------------- | ------------------------------ |
| maximum  | CRF 15, medium   | 20000k target     | ~90% of original (SW)          |
| balanced | CRF 23, medium   | 8000k target      | ~60% of original (SW)          |
| compact  | CRF 30, fast     | 4000k target      | ~35% of original (SW)          |
| tiny     | CRF 38, veryfast | 1500k target      | ~15% of original (SW)          |

#### H.265 Options (Recommended for most use cases)

| Preset   | SW (libx265)     | HW (VideoToolbox) | Est. Size (for reference file) |
| -------- | ---------------- | ----------------- | ------------------------------ |
| maximum  | CRF 18, medium   | 15000k target     | ~80% of original (SW)          |
| balanced | CRF 28, medium   | 6000k target      | ~50% of original (SW)          |
| compact  | CRF 34, fast     | 2500k target      | ~25% of original (SW)          |
| tiny     | CRF 42, veryfast | 1000k target      | ~12% of original (SW)          |

#### AV1 Options (Best compression ratio, slowest encoding)

| Preset   | SW (libsvtav1)    | HW  | Est. Size (for reference file) |
| -------- | ----------------- | --- | ------------------------------ |
| maximum  | CRF 20, preset 6  | N/A | ~70% of original               |
| balanced | CRF 30, preset 6  | N/A | ~40% of original               |
| compact  | CRF 40, preset 8  | N/A | ~20% of original               |
| tiny     | CRF 50, preset 12 | N/A | ~10% of original               |

#### ProRes (Mastering only -- files will be LARGER)

| Preset   | SW (prores_ks)       | HW (VideoToolbox) | Est. Size             |
| -------- | -------------------- | ----------------- | --------------------- |
| maximum  | Profile 3 (HQ)       | Profile 3         | ~200% of H.264 source |
| balanced | Profile 2 (Standard) | Profile 2         | ~120% of H.264 source |
| compact  | Profile 1 (LT)       | Profile 1         | ~80% of H.264 source  |

---

### Step 4 -- Resolution Impact Analysis

Show how resolution scaling affects both quality and size.

**Pixel count ratios relative to source:**

| Source            | -> 1080p          | -> 720p     | -> 480p    | -> 360p    |
| ----------------- | ----------------- | ----------- | ---------- | ---------- |
| 4K (3840x2160)    | 25% pixels        | 11% pixels  | 5% pixels  | 3% pixels  |
| 1440p (2560x1440) | 56% pixels        | 25% pixels  | 11% pixels | 6% pixels  |
| 1080p (1920x1080) | 100% (skip)       | 44% pixels  | 20% pixels | 11% pixels |
| 720p (1280x720)   | (upscale blocked) | 100% (skip) | 44% pixels | 25% pixels |

**File size roughly scales with pixel ratio** (not exactly, due to encoding overhead).

**Quality impact of downscaling:**

- 4K -> 1080p: Minimal perceptible loss on displays < 27"
- 1080p -> 720p: Noticeable softening, acceptable for streaming
- 720p -> 480p: Significant detail loss, only for mobile/bandwidth-constrained
- Any -> 360p: Low quality, only for previews or extreme bandwidth constraints

---

### Step 5 -- Show Estimation and Compare

Present the options to the user with estimated sizes.

**Estimation formula (HW/bitrate-based):**

```
estimatedSize = (adjustedBitrate * 1000 / 8) * duration * pixelRatio
```

Where `adjustedBitrate = min(targetBitrate, sourceBitrate * capRatio)`

**Estimation formula (SW/CRF-based):**

```
estimatedSize = originalSize * compressionRatio * pixelRatio
```

**Color-coded indicators in UI:**

- Green (#4ade80): 20%+ reduction expected
- Gray (#a3a3a3): 0-20% reduction
- Orange (#fb923c): File may get LARGER

**Recommendation summary format:**

```
For your [content type] at [resolution]:
  Best quality:  H.265 maximum    -> ~X MB (Y% of original)
  Best balance:  H.265 balanced -> ~X MB (Y% of original)  [RECOMMENDED]
  Smallest file: AV1 compact    -> ~X MB (Y% of original)
  Fastest:       H.264 HW balanced -> ~X MB (Y% of original)
```

**Verification Step:**

- [ ] All estimations computed correctly
- [ ] Color indicators match expected direction
- [ ] Recommendation accounts for content type
- [ ] HW availability checked for HW-based recommendations

---

## Deep Knowledge: CRF Values Explained

CRF (Constant Rate Factor) controls quality on a logarithmic scale.

**For libx264:**

- CRF 0: Lossless (huge files)
- CRF 17-18: Visually lossless
- CRF 23: Default, good balance
- CRF 28: Noticeable quality reduction
- CRF 51: Worst possible quality

**For libx265:**

- Same concept but shifted ~6 points (CRF 28 in x265 ~ CRF 23 in x264)
- CRF 22: Visually lossless
- CRF 28: Good balance
- CRF 32: Noticeable reduction

**For libsvtav1:**

- Uses "QP" mode mapped to CRF-like behavior
- CRF 25: Very high quality
- CRF 30: Good balance
- CRF 38: Aggressive compression

**Key insight:** CRF is NOT directly comparable across codecs.
CRF 28 in libx265 produces roughly the same perceptual quality as CRF 23 in libx264,
but at approximately 50% of the file size. AV1 at CRF 30 matches both at even smaller sizes.

---

## Reference: Encoding Speed Comparison (M2 Max)

Approximate encoding speed for 1080p 30fps content:

| Encoder              | Speed (relative to realtime) | 1-hour video encode time |
| -------------------- | ---------------------------- | ------------------------ |
| h264_videotoolbox    | 8-15x realtime               | 4-8 minutes              |
| hevc_videotoolbox    | 5-10x realtime               | 6-12 minutes             |
| libx264 (medium)     | 1.5-3x realtime              | 20-40 minutes            |
| libx265 (medium)     | 0.5-1.5x realtime            | 40-120 minutes           |
| libsvtav1 (preset 6) | 0.3-0.8x realtime            | 75-200 minutes           |

**Speed vs Quality tradeoff:**

- HW encoding: Fast, good quality, less size efficiency
- SW encoding: Slow, excellent quality-to-size ratio
- AV1: Very slow, best compression efficiency
