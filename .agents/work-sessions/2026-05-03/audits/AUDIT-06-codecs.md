# AUDIT-06: Codec / Encoding Correctness

[2026-05-03 18:18 IST] [subagent/opus] [AUDIT] iOS Services codec/encoding audit
Scope: `VideoCompressor/ios/Services/` (CompressionService, StitchExporter,
MetadataService, PhotoMetadataService, StillVideoBaker, CompressionEstimator).

Findings sorted by severity. File paths are absolute, line numbers cite the
exact site of the issue.

---

## Counts
- CRITICAL: 2
- HIGH:     5
- MEDIUM:   5
- LOW:      3
- TOTAL:    15

---

## CRITICAL

### C1. StillVideoBaker writes only one frame — bake math is broken

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StillVideoBaker.swift:171-200, 250-255`

`FrameCounter.markDoneIfPossible()` is invoked at the TOP of every iteration of
the `while inputRef.isReadyForMoreMediaData` loop. Its current implementation:

```swift
func markDoneIfPossible() -> Bool {
    lock.lock(); defer { lock.unlock() }
    let wasDone = _done
    _done = true            // <-- sets unconditionally on EVERY call
    return wasDone
}
```

Trace:
- Iter 1: `wasDone = false`, `_done := true`, returns `false` → loop continues,
  appends frame 0, increments counter.
- Iter 2: `wasDone = true` (because iter 1 set it), returns `true` → closure
  returns immediately without appending.

Net effect: bakes ONE frame regardless of `totalFrames`. The output `.mov` is
either single-frame (so the still appears for ~33ms instead of `duration`
seconds in the stitch), or `writer.finishWriting()` succeeds with a degenerate
file that downstream tools may reject.

Severity: stills in stitched outputs flash for one frame instead of holding
for the configured 1-10 s. Users would file this as "stitch eats my photos."

**Fix:** the guard's intent (per its docstring) is "short-circuit re-entry
AFTER markAsFinished was called." Only set `_done = true` at the actual
finish points (frame >= totalFrames OR adaptor.append failed). Replace
`markDoneIfPossible` with two methods:

```swift
func isDone() -> Bool { lock.lock(); defer { lock.unlock() }; return _done }
func markDone() { lock.lock(); defer { lock.unlock() }; _done = true }
```

…then call `if counter.isDone() { return }` at the top of the while loop and
`counter.markDone()` immediately before the two `markAsFinished()` exits. The
re-entry guard then works as documented.

---

### C2. Wipe transition does not actually wipe — it horizontally squishes

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StitchExporter.swift:800-832`

The wipe ramps `setCropRectangleRamp` from full-frame down to a 1×height strip
on the left edge of the OUTGOING clip and from a 1×height strip on the right
edge up to full-frame on the INCOMING clip. The comment claims this produces a
left-traveling wipe.

Per AVFoundation contract (`AVMutableVideoCompositionLayerInstruction`), the
crop rectangle is applied to the SOURCE in source pixel space, AFTER which the
layer transform (`setTransform`) renders that cropped region onto the canvas.
The transform here is the aspect-fit chain
(`preferredTransform → rotation → scaleToFit → translateCenter`) which scales
`displaySize` to `renderSize`. When the source crop shrinks to 1×height, the
aspect-fit scale operates on the cropped 1px-wide region — that 1px column is
SCALED to fill the canvas at the same aspect-fit ratio. The visible behaviour:
the outgoing clip horizontally squashes toward a 1px line at the left edge of
the canvas while remaining full-height; the incoming does the inverse.

That's a "squish-to-line" effect, not a wipe. A wipe should reveal pixels in
their ORIGINAL screen position (left half stays left, right half is hidden by
the moving wipe boundary).

**Fix:** wipes need to be implemented via per-frame transform animation
(translate the outgoing layer offscreen progressively while leaving the
incoming layer in place), or via a custom `AVVideoCompositing` that renders a
moving rectangular mask. With the current vanilla `AVMutableVideoComposition`
toolset the simplest correct approach is:
1. Both layers render at full canvas with their normal aspect-fit transforms.
2. Animate the OUTGOING layer's `setTransformRamp` so it translates from
   `(0, 0)` to `(-renderSize.width, 0)` over `gapRange` — moves it offscreen
   to the left.
3. Leave the incoming layer at the full transform; it's revealed because the
   outgoing slid off.

Alternatively, hide the wipe option from the UI until a custom compositor is
written.

---

## HIGH

### H1. HDR (10-bit / BT.2020 / HLG) content is silently downgraded to 8-bit SDR

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:254-257, 178-197`

The reader requests pixel format
`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (8-bit) for both the
URL-asset path and the videoComposition path. iPhone HDR HEVC source is
10-bit Rec.2020 with HLG transfer (or Dolby Vision Profile 8.4). Decoding it
into an 8-bit pixel buffer truncates precision and applies an implicit
gamut/transfer conversion using AVFoundation defaults — the user sees a
visibly washed-out, lower-contrast file.

Additionally, `AVVideoCompressionPropertiesKey` does NOT include
`AVVideoColorPrimariesKey`, `AVVideoTransferFunctionKey`, or
`AVVideoYCbCrMatrixKey`. Without them, the encoder writes BT.709 by default
even if 10-bit precision had been preserved, so playback on HDR displays
would still be wrong.

**Fix:**
1. Inspect the source video track's
   `formatDescription.extensions[kCVImageBufferTransferFunctionKey]`,
   `kCVImageBufferColorPrimariesKey`, and
   `kCVImageBufferYCbCrMatrixKey` (or read via
   `videoTrack.load(.formatDescriptions)`).
2. If any of these indicate HDR (e.g. transfer = `_ITU_R_2100_HLG` or
   `_SMPTE_ST_2084_PQ`, primaries = `_ITU_R_2020`), switch the reader pixel
   format to `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` and add an
   `AVVideoColorPropertiesKey` dict to compressionProps with those three
   tags.
3. Use HEVC Main10 profile (`kVTProfileLevel_HEVC_Main10_AutoLevel`) when
   encoding 10-bit.

This is the single biggest perceptual-quality gap in the encode pipeline.

---

### H2. Audio bitrate hard-coded at 192 kbps; estimator assumes 128 kbps

**File:**
- Encoder: `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:225` (`AVEncoderBitRateKey: 192_000`)
- Estimator: `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionEstimator.swift:27` (`audioBitsPerSecond: Int64 = 128_000`)

The encoder writes 192 kbps AAC; the estimator predicts at 128 kbps. For a
60-second clip with audio, the estimator under-predicts by
`(192-128) × 60 / 8 = 480 KB`. For a 30-min clip, ~14 MB. The audit asks for
±15% — for a 6 Mbps Balanced 30-min clip the video is ~1.35 GB, audio
disagreement is ~14 MB, so within tolerance. But for a 750-kbps streaming
30-min clip the video is ~169 MB, audio mispredict is ~14 MB = ~8% all on
its own. Stacked with VBR pessimism the total can drift past 15%.

**Fix:** pick one and use it consistently. Either:
- Drop encoder to 128 kbps (reasonable for consumer mobile content), or
- Bump `audioBitsPerSecond` in `CompressionEstimator` to 192_000.

Given that the task description suggests "AAC 128 kbps reasonable", the
former is recommended — also slightly improves video bitrate share at
streaming preset.

Note: the legacy `CompressionService.estimateOutputBytes` (line 503) uses
`192_000` correctly, so there are now THREE places with audio bitrate
literals — consolidate into a single shared constant.

---

### H3. Color primaries / transfer / YCbCr matrix not preserved in encode

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:178-197`

Independent of HDR (H1), even SDR videos shot in BT.601 (older sources, some
imported clips) or with a non-standard YCbCr matrix get re-tagged as BT.709
on output because nothing copies these atoms. Mismatch → wrong colors in
playback. iPhone-shot SDR is BT.709 so this rarely bites Apple-native
content, but ANY imported / shared / converted file is at risk.

**Fix:** plumb `AVVideoColorPropertiesKey` from the source's
`formatDescription` extensions into `compressionProps`. Skeleton:

```swift
let fmtDescs = try await videoTrack.load(.formatDescriptions)
if let fd = fmtDescs.first {
    let exts = CMFormatDescriptionGetExtensions(fd) as? [CFString: Any] ?? [:]
    if let primaries = exts[kCVImageBufferColorPrimariesKey],
       let transfer  = exts[kCVImageBufferTransferFunctionKey],
       let matrix    = exts[kCVImageBufferYCbCrMatrixKey] {
        compressionProps[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey:    primaries,
            AVVideoTransferFunctionKey:  transfer,
            AVVideoYCbCrMatrixKey:       matrix,
        ]
    }
}
```

---

### H4. Max preset re-encodes at source bitrate — likely produces a same-sized file

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Models/CompressionSettings.swift:128-153`

For `(.source, .lossless)` the smart-cap returns `safeSource` directly (or
20 Mbps fallback). Re-encoding HEVC at the same average bitrate as the source
produces a file roughly the same size, possibly larger after container
overhead (4-Byte NAL prefixes for AVCC, mp4 atom padding). The Max preset's
selling point ("Visually lossless. Largest file.") is honest about size, but
this also means **Max usually offers no compression benefit and may even
inflate**.

The web app's lib/ffmpeg.js Max preset at least caps to 90% of source via the
streaming-preset mapping when source bitrate is known; the iOS port doesn't.

**Fix options:**
- Cap to `min(safeSource, 90% × safeSource)` for parity with the web app, OR
- Switch Max to passthrough remux when source codec matches output codec
  (HEVC→HEVC) and only metadata strip is requested. Then it's lossless AND
  fast AND can never be larger.

The latter is preferred — it would also dodge the H1/H3 HDR issues for
unmodified Max output.

---

### H5. Audio mix volume ramps and video opacity ramps disagree (intentional but undocumented)

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StitchExporter.swift:343-434, 760-832`

Audio crossfade: outgoing tail ramps 1→0 AND incoming head ramps 0→1.
Video crossfade: outgoing top layer ramps 1→0; incoming bottom layer stays
at 1.0 the entire overlap.

For audio this is correct (sum of both must not double-loud through the
crossfade — both must ramp). For video this is correct (alpha-blend reveal).
But the comment at line 312-313 claims "audio mix mirrors video opacity
ramps" — they don't, and the asymmetry is load-bearing. Either rewrite the
comment or — more importantly — verify the audio-mix `setVolumeRamp` calls
actually cover the entire overlap window. Looking at lines 369-398 and
402-426, the head fade is set independently on the incoming clip's audio
parameter and the tail fade on the outgoing's. Since both use the SAME
overlap range as the video instruction, the math lines up.

**However:** the `setVolume(1.0, at: seg.composedRange.start)` on line 366
runs before any ramp setup, but volume points are sticky — setting volume
1.0 at start, then a head ramp on the same segment, may cause the start
point to override the ramp's `fromStartVolume: 0.0` if AVFoundation
processes them in declaration order. Worth a unit test.

**Fix:**
1. Remove the misleading "mirrors" comment.
2. Add a stitch-export integration test that probes the output and asserts
   the audio at `composedRange.start + 0.05s` is silent for the incoming
   clip during a crossfade (catches the volume-stickiness regression).

---

## MEDIUM

### M1. CompressionEstimator assumes target bitrate ≈ output bitrate — VBR can be 30%+ lower

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionEstimator.swift:31-47`

`AVVideoAverageBitRateKey` is a TARGET, not a guarantee. VideoToolbox HEVC at
6 Mbps target produces ~5 Mbps for low-complexity scenes (talking head, slow
motion, static cameras). Estimator prediction can be high by 15-30% — the
audit's stated tolerance is ±15%. For consumer iPhone footage the estimator
will systematically over-estimate file size, which the user sees as the
saved-bytes counter under-counting (they see "you saved 200 MB" but actually
saved 280 MB).

**Fix:** apply a complexity discount factor of ~0.85-0.90 to the bitrate ×
duration calculation, OR document that the estimate is a budget upper bound.

---

### M2. Reader pixel format not specified for videoComposition path with non-standard color spaces

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:254-281`

`AVAssetReaderVideoCompositionOutput` accepts a `videoSettings` dict whose
pixel format defaults to BGRA when unspecified, but the code passes an
8-bit YpCbCr request. For heterogeneous-codec stitches (e.g. mixing an
H.264 and an HEVC clip), AVFoundation handles the conversion internally,
but if any source is HDR the output is downsampled to SDR before reaching
the encoder (see H1).

**Fix:** combine with H1 — when ANY clip in the stitch is HDR, request 10-bit
on the videoComposition output and tag the encoder accordingly. Until then,
document in the UI that mixing HDR + SDR clips will produce SDR.

---

### M3. CompressionService rounds to nearest even, can round DOWN — loses 1 row/col

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:531-535`

```swift
private static func evenize(_ v: Int) -> Int {
    let n = max(v, 2)
    return n.isMultiple(of: 2) ? n : n - 1
}
```

For a source that, after scaling, comes out to 1081 pixels, this returns
1080. Always rounds DOWN. Acceptable but unconventional — typical FFmpeg
practice is to round up (`-2` flag rounds to nearest even, but H.264/HEVC
spec accepts either). One-pixel rounding doesn't materially affect quality
but it does mean encoded outputs are 1px shorter than expected on some
aspect ratios.

**Fix (optional):** round to nearest even (i.e. `(n + 1) / 2 * 2`) so a
1081 → 1082, 1080 → 1080.

---

### M4. Smart bitrate cap math: target vs cap-by-source not floor-aware

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Models/CompressionSettings.swift:155-162`

The math is: `smart = min(target, source × ratio)`, then
`return max(floor, smart)`. For an already-tiny source (e.g. 800 kbps mp4),
Streaming preset: `min(4M, 800k × 0.5 = 400k) = 400k`, then `max(750k, 400k)
= 750k`. So the floor kicks in and we encode at 750k, which is HIGHER than
source 800k × 0.5 = 400k AND higher than the smart cap. That's fine
mathematically but it means for a source already smaller than the
preset-floor × duration, we re-encode UPWARD and produce a larger file. The
user reports "Streaming preset made my tiny clip bigger."

The web app comment in `lib/ffmpeg.js` mentions this exact case — already-
compressed input can produce same-or-larger output under HW encoders.

**Fix:**
- Add a final guard: `return min(safeSource, max(floor, smart))` — never
  exceed source bitrate. This makes the floor opportunistic.
- Better: bypass re-encode entirely (passthrough) when the source already
  meets the preset's effective bitrate budget for its target resolution.

The post-flight size guard in `VideoLibrary` mentioned in the file's header
comment is defense-in-depth, but a pre-flight skip is cheaper.

---

### M5. Bake H.264 settings ignore YUV format; output is BGRA-decoded

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StillVideoBaker.swift:81-97`

The bake pipeline encodes H.264 from a 32BGRA source pixel buffer pool. iOS
H.264 hardware encoders prefer NV12 (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`)
and convert internally; this works but adds a software RGB→YUV step per
frame. For a 1920×1080 still held for 10s = 300 frames @ 30fps, that's 300
unnecessary conversions. Negligible on modern hardware but it adds 10-30%
to the bake time.

**Fix (perf):** decode the still directly to NV12 via vImage YUV conversion
and feed `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` to the adaptor.
Only worth it if bakes are user-perceived slow.

Better fix that obsoletes this: see L1 (constant-time bake).

---

## LOW

### L1. Bake writes N frames; could write 2 and rely on encoder duplication

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StillVideoBaker.swift:162-202`

For a 10-second still at 30fps, the baker submits 300 identical pixel
buffers. AVAssetWriter then re-encodes each, producing tiny B-frames that
predict from the I-frame perfectly but still cost CPU and a few KB of
stream overhead. The encoder cannot legally produce a constant-time output
without input frame supply, so we DO need to feed at least the bookend
PTSes. Practical minimum: 2 frames at PTS=0 and PTS=duration-1/fps. The
encoder produces a single GOP with one I-frame and one P-frame referencing
it, total file ~5-10 KB regardless of duration.

This is a significant perceptual-fluidity win: a 10s still bake currently
takes 1-2 seconds; a 2-frame bake takes <100ms.

**Fix:** keep the current pump skeleton, but when totalFrames > 2, set
`totalFrames = 2` and emit PTSes at 0 and `duration - 1/frameRate`.
Test with a 30s still clip to confirm the player extends the display
correctly. Some legacy MOV players sample every Nth frame; if any of the
test players show a black gap between the two PTSes, fall back to N-frame
mode for video durations >= 5s.

Alternative that's even more constant: write a 1-frame `.mov` and then add
an `AVMutableComposition` time range entry that maps the 1-frame source to
`duration` seconds. The composition path is already in use by Stitch — so
the bake can just produce a 1-frame asset and `StitchExporter` extends the
clip's `composedRange.duration` itself. This makes still bakes truly
constant-time AND removes the temp .mov bloat.

---

### L2. Non-cardinal user rotation breaks aspect-fit

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StitchExporter.swift:530-555`

After applying user rotation about display center, the code uses the
ORIGINAL `clip.displaySize` for the scale-to-fit calculation. For a 90/180/
270° rotation, displaySize is still right (the rotated bounding box is
displaySize.swap or unchanged). For ANY arbitrary angle (e.g. user typed in
17°), the rotated bounding box is larger than displaySize, so the
scale-to-fit produces a clip whose corners hang off the canvas (cropped to
black at frame edge).

If the UI exposes only multiples of 90° this is moot. If it allows any
angle, this is a user-visible bug.

**Fix:** after rotation, compute the rotated bounding box (use
`CGRect.applying(rotation)`), use THAT for scale-to-fit. This recovers
aspect-fit behavior for arbitrary angles.

---

### L3. .mov input is silently re-containered to .mp4 on Compress, losing chapter / timecode tracks

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:42-51`

`outputURL` always uses `.mp4` extension, and `AVAssetWriter` is created with
`fileType: .mp4` (line 161). For a `.mov` input (e.g. older iPhone footage,
ProRes from Final Cut), this silently re-containers to MP4. MP4 supports
fewer track types than MOV — chapter tracks, timecode tracks, and alternate
language tracks are dropped without warning.

For consumer iPhone-only footage this rarely matters. For users who import
edited clips it can cause data loss.

**Fix:** when `inputURL.pathExtension == "mov"`, output as `.mov`
(`fileType: .mov`). Mirrors the MetadataService behavior at lines 106-112.
Add a per-input check in `outputURL(forInput:)`.

---

## Verified-correct (no finding)

- Codec selection: HEVC for max/balanced/small, H.264 for streaming. 
  Confirmed `CompressionSettings.videoCodec` lines 167-172.
- PreferredTransform application: only set on writer input when no
  videoComposition is attached. Confirmed `CompressionService.swift:209-211`.
- Cursor pull-back math for transitions:
  `CMTimeMaximum(.zero, CMTimeSubtract(cursor, transitionDuration))` correctly
  prevents negative time. `StitchExporter.swift:235-237`.
- A/B alternating tracks for transition overlaps: clip i goes on track A
  when i%2==0, B when i%2==1. Adjacent clips are on different tracks so
  insert ranges don't collide. `StitchExporter.swift:225-258`.
- shouldKeepTrack(.metadata): timed-metadata tracks pass through unless
  `.location` or `.custom` strip rule is active. Preserves iPhone GPS
  streams under autoMetaGlasses. `MetadataService.swift:339-345`.
- autoMetaGlasses surgical: XMP packet wipe is gated on
  `fileHasFingerprint` (set true only when an atom matches Ray-Ban / Meta
  markers). `PhotoMetadataService.swift:206-207`, `347-396`.
- cleanedURL extension preservation: `.mov` stays `.mov`, `.m4v` stays
  `.m4v`. `MetadataService.swift:316-332`.
- Writer fileType matches output extension. `MetadataService.swift:106-115`.
- CGContext bitmap info for BGRA pixel buffer: `byteOrder32Little |
  premultipliedFirst` matches `kCVPixelFormatType_32BGRA`.
  `StillVideoBaker.swift:135-138`.
- Even-dimension rounding in StillVideoBaker (H.264 hard requirement):
  `(cgImage.width / 2) * 2`. `StillVideoBaker.swift:67-70`.
- AVAssetReaderAudioMixOutput is wired up correctly when audioMix is
  non-nil — passes ALL composition audio tracks and the mix.
  `CompressionService.swift:295-308`.

---

## Summary

The encode pipeline's structural plumbing (concurrency, cancellation,
per-track pumps, audio mix attachment) is sound. The defects cluster in two
places:

1. **Color-space fidelity (H1, H3, M2):** the encoder ignores HDR / non-709
   color metadata. A user-visible quality regression on iPhone HDR content.
   This is the biggest single fix.
2. **Stitch ergonomics (C1, C2, L1):** stills bake one frame, the wipe is
   actually a horizontal squish, and the bake is N-frame instead of
   constant-time. C1 in particular looks like a regression test was never
   added; it would catch on the first stitch with a still-photo clip.

Bitrate-cap math is faithful to the web app spec, but the Max preset and the
floor logic combine to produce same-size or larger outputs on already-
compact sources (H4, M4) — both fixable with a final `min(safeSource, …)`
clamp.
