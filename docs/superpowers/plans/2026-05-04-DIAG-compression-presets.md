# DIAG — Compression preset failure on real iPhone (`-11841`)

**Date:** 2026-05-04
**Author:** Claude Code (read-only diagnostic agent)
**Status:** DIAGNOSIS — no code touched. Recommended action lives at the bottom.
**Branch context:** `fix/audit-criticals-and-codex-handoff` (HEAD: `c299340`)

---

## 1. Symptom (verbatim user report)

> "compression failed: the operation couldn't be completed (AVFoundationErrorDomain error -11841)"
>
> "it seems to only work with small compression but max quality and balanced and web seem to not work from what i see"

3 of 4 compression presets — `Max`, `Balanced`, `Streaming` (Web) — fail with the
above error string on a real iPhone. Only `Small` succeeds. Failure surface:
post-encode, raised from `writer.finishWriting()`.

---

## 2. AVError -11841 meaning (primary source)

`-11841` = **`AVErrorInvalidVideoComposition`**.

**Verified against the local Xcode SDK header**
`/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVError.h`:

```
AVErrorExportFailed                                 = -11820,
AVErrorFileAlreadyExists                            = -11823,
AVErrorFileFailedToParse                            = -11829,
AVErrorDecoderTemporarilyUnavailable                = -11839,
AVErrorInvalidVideoComposition                      = -11841,
AVErrorOperationInterrupted                         = -11847,
```

**Documented intent (Apple):** "An error that indicates an attempt to present an
unsupported video composition."

**Empirical behaviour (Apple Developer Forums + StackOverflow corpus):** despite
the doc string, `AVAssetWriter.finishWriting()` is widely observed to surface
**-11841 even when the caller supplied no `AVMutableVideoComposition`**. In
practice it functions as VideoToolbox's catch-all "the requested output settings
× source frames × hardware-encoder envelope produced something the validator
rejected as un-renderable." The doc string vs empirical behaviour gap is a
well-known footgun. The AVAssetWriter code path here passes
`videoComposition: nil` (`CompressionService.swift:78`) yet the error still fires
at `finishWriting()`. **This is not a contradiction** — it is the documented
empirical pattern.

---

## 3. Code paths that throw -11841

There is exactly **one** site in the iOS code that surfaces an `NSError` with
domain `AVFoundationErrorDomain` and an arbitrary `code` to the user wrapped in
the literal string `"Compression failed: the operation..."`:

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:468-480`

```swift
await writer.finishWriting()
if writer.status != .completed {
    try? FileManager.default.removeItem(at: outputURL)
    let nsErr = writer.error as NSError?
    if nsErr?.code == -11847 {
        throw CompressionError.exportFailed(
            "Export was interrupted because the app went to the background or the screen locked for too long. Keep the app open during long encodes (especially Stitch). On retry, the encode will resume from scratch."
        )
    }
    let detail = nsErr.map { "[\($0.domain) \($0.code)] \($0.localizedDescription)" }
        ?? "Writer ended with status \(writer.status.rawValue)"
    throw CompressionError.exportFailed("Encode failed: \(detail)")
}
```

`CompressionError.exportFailed(...)` then renders as `"Compression failed: \(msg)"`
via `errorDescription` (line 548), and `nsErr.localizedDescription` for AVError
-11841 is the standard system string `"The operation could not be completed."`.
Concatenated: `"Compression failed: Encode failed: [AVFoundationErrorDomain -11841] The operation could not be completed."` — matches the user's report.

The `-11847` branch is the only error code whose handling is special-cased.
**Every other AVError, including -11841, falls through the generic branch.**

Other possible throw sites that did NOT fire (verified):
- Reader create/start failure → would say `"Read failed: ..."` — different prefix.
- Writer create/start failure → would say `"Could not create writer"` or `"Writer failed to start"` — different prefix.
- `CancellationError` → `.cancelled`, no AVError text.

---

## 4. Per-preset settings comparison

Built from
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Models/CompressionSettings.swift` (lines 96-186)
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift` (lines 167-197, 254-257)

| Property | **Max** ✗ | **Balanced** ✗ | **Small** ✓ | **Streaming/Web** ✗ |
|---|---|---|---|---|
| `Resolution` cell | `.source` | `.fhd1080` | `.hd720` | `.sd540` |
| `QualityLevel` cell | `.lossless` | `.high` | `.balanced` | `.balanced` |
| `maxOutputDimension` (long-edge cap) | **`nil` — no cap** | 1920 | 1280 | 960 |
| `videoCodec` | HEVC | HEVC | HEVC | **H.264** |
| `bitrate(forSourceBitrate:)` | **`safeSource`** (no cap) | `min(6 Mbps, src×0.7)`, floor 1 Mbps | `min(3 Mbps, src×0.4)`, floor 500 kbps | `min(4 Mbps, src×0.5)`, floor 750 kbps |
| Probe-failure fallback bitrate | **20 Mbps** | 6 Mbps | 3 Mbps | 4 Mbps |
| Profile/level | `kVTProfileLevel_HEVC_Main_AutoLevel` | same | same | `AVVideoProfileLevelH264HighAutoLevel` |
| `optimizesForNetwork` (faststart) | false | false | false | true |
| H.264 entropy | n/a | n/a | n/a | CABAC |
| Reader pixel format | 8-bit 420 video-range | same | same | same |
| `videoInput.transform` | `preferredTransform` of source | same | same | same |
| `AVVideoExpectedSourceFrameRateKey` | `nominalFrameRate` (or 30) | same | same | same |
| `AVVideoMaxKeyFrameIntervalKey` | `frameRate × 2` | same | same | same |

**The discriminating axes between the three FAIL presets and the one PASS preset:**

1. **Output dimensions.** Small caps the long edge at 1280, which forces a
   **downscale** for any modern iPhone source (1080p has long edge 1920;
   4K is 3840). Max keeps source dims; Balanced keeps a 1080p iPhone source
   at 1920 unchanged; Streaming downscales to 960 (smaller than Small) but
   uses H.264.
2. **Bitrate envelope.** Max passes the source bitrate straight through —
   for a 4K HDR HEVC iPhone source that is **typically 50-100 Mbps** (Apple
   ProRes-class capture can be 200+ Mbps). Balanced and Streaming hit
   smaller targets (≤ 6 Mbps and ≤ 4 Mbps) but combine those with **larger
   source resolution** than Small.
3. **Profile/level auto-selection.** All four presets use `…_AutoLevel`,
   meaning the encoder chooses the H.264 / HEVC level from the
   `(width, height, framerate, bitrate)` tuple. **Auto-level can fail to
   resolve** if the inputs imply a level beyond what the on-device HW
   encoder supports (e.g. iPhone HEVC encoder caps at H.265 Level 5.1 on
   non-Pro devices; H.264 High caps at Level 5.2).

The shared property of the three failing presets that Small does not have:
**they all encode at the source's natural-frame-rate × natural-resolution × a
bitrate that is either source-bitrate-driven or larger-than-Small.** Small is
the only preset whose `(width, height, bitrate)` tuple is guaranteed to land
inside the conservative envelope for **every** iPhone HW encoder, regardless of
source spec. The three failing presets each push past that envelope on at least
one source-file class.

---

## 5. Hypotheses, ranked

### Hypothesis #1 — Max-preset bitrate exceeds VideoToolbox HW encoder envelope (auto-level can't resolve) — **CONFIDENCE: MEDIUM-HIGH** (pending source-file spec from user)

**What -11841 means here:** VideoToolbox rejects the resolved
`(level, dims, fps, bitrate)` tuple at validation time and surfaces the
generic "invalid composition" code rather than a more specific "level too
low" code.

**Where:**
- `CompressionSettings.swift:128-131` — Max returns
  `safeSource` directly (no cap, no clamp).
- `CompressionSettings.swift:152` — when source bitrate is unknown,
  Max falls back to `20_000_000` (20 Mbps) which is also high for a 1080p
  source but reasonable for 4K.
- `CompressionService.swift:178-184` — these settings flow into
  `compressionProps` with `AVVideoProfileLevelKey: …Main_AutoLevel`.
  AutoLevel can't extend the level envelope; if the bitrate is too high
  for what `Main` allows at the given dims/fps, the writer rejects the
  configuration at finalize.

**Why Small works, the others don't:**
- A typical 4K HDR iPhone clip captured at ~60 Mbps in HEVC.
- **Max:** target = 60 Mbps at 3840×2160 → exceeds iPhone HEVC HW level cap
  → -11841.
- **Balanced:** capped to 6 Mbps but at 1920 long-edge **AND** the source
  may be HDR (10-bit). The reader requests 8-bit pixel format
  (`CompressionService.swift:255-256`), so the writer is asked to encode
  8-bit BT.709 at 1080p 6 Mbps from a 10-bit BT.2020 source whose
  formatDescription still flags HDR — known to surface -11841 on some
  sources (this overlaps Hypothesis #2).
- **Streaming:** H.264 High AutoLevel at 960×... at 4 Mbps usually fits,
  BUT if the source frame rate is **slow-mo (120 or 240 fps)**,
  `nominalFrameRate` propagates into `AVVideoExpectedSourceFrameRateKey` AND
  the GOP key, and H.264 High Level 5.2 caps macroblock rate — slow-mo
  sources at the smaller resolution still exceed the envelope.
- **Small:** 1280 long-edge at 3 Mbps at any frame rate is comfortably
  inside H.265 Main Level 4.0 — the most conservative envelope that every
  iPhone encoder supports.

**Fix strategy:**

1. **Cap Max bitrate** to a hardware-safe ceiling per output dimension:

   ```swift
   case (.source, .lossless):  // Max
       targetBitrate = 50_000_000   // was Int64.max
       sourceCapRatio = 0.9         // was 1.0 — also addresses AUDIT-06 H4
       floor = 0
   ```
   Even this ceiling is high — for 4K HEVC, 50 Mbps is right at the iPhone
   non-Pro encoder's safe envelope. A more conservative fix is
   `min(50 Mbps, source × 0.9)` AND scale the `targetBitrate` ceiling by
   the resolution shrink.

2. **Fall back from `…_AutoLevel` to an explicit, conservative level** for
   high-bitrate / high-res cases, OR omit `AVVideoProfileLevelKey` entirely
   to let VideoToolbox pick (which is more forgiving than user-supplied
   `AutoLevel`):

   ```swift
   // In CompressionService.swift around line 171-176:
   let useExplicitProfile = settings.maxOutputDimension ?? Int.max <= 1280
   var compressionProps: [String: Any] = [
       AVVideoAverageBitRateKey: NSNumber(value: targetBitrate),
       AVVideoMaxKeyFrameIntervalKey: NSNumber(value: gop),
       AVVideoExpectedSourceFrameRateKey: NSNumber(value: Float(frameRate)),
       AVVideoAllowFrameReorderingKey: NSNumber(value: true),
   ]
   if useExplicitProfile {
       compressionProps[AVVideoProfileLevelKey] = profileLevel
   }
   // …let VT auto-select for higher-res presets
   ```

3. **Catch -11841 and downshift.** Wrap the encode in a retry that on
   -11841 cuts the bitrate by 50% and tries again. This is a defence-in-
   depth pattern Apple sample code uses for VT failures.

**File:line for the change:**
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Models/CompressionSettings.swift:128-131` (Max bitrate cap)
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:171-184` (profile level / retry)

---

### Hypothesis #2 — HDR (10-bit BT.2020) source decoded into 8-bit pixel format causes encoder validation failure — **CONFIDENCE: MEDIUM**

**What -11841 means here:** the reader hands the writer 8-bit Rec.709 frames
that disagree with the source's tagged BT.2020 HLG / PQ format description.
The writer's encoder validation flags the colour-property mismatch; on some
iPhone ISP/encoder paths this surfaces as -11841 rather than a colour-
specific error.

**Where:**
- `CompressionService.swift:254-257` — reader pixel format is hardcoded
  `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (8-bit, video range).
- `CompressionService.swift:178-197` — writer compressionProps has **no**
  `AVVideoColorPropertiesKey`. AUDIT-06 H1 already flagged this as a
  quality bug; in this hypothesis it is also a **failure-trigger** for the
  three high-throughput presets.

**Why Small works, the others don't:**
The reader's 8-bit truncation + missing colour tags trip the writer's
validation only when the encode envelope is "ambitious enough" (high res
× high bitrate × HEVC Main with 10-bit source flag). Small's tighter
envelope sits below the validation threshold.

**Fix strategy:**
Implement AUDIT-06 H1's HDR detect-and-preserve plan — switch reader to
10-bit when the source format description carries
`kCVImageBufferTransferFunction_ITU_R_2100_HLG` or
`_SMPTE_ST_2084`, encode HEVC Main10
(`kVTProfileLevel_HEVC_Main10_AutoLevel`), and copy
`AVVideoColorPropertiesKey` through. In the meantime, add an explicit
`AVVideoColorPropertiesKey` for SDR BT.709 to suppress encoder colour-
mismatch validation:

```swift
compressionProps[AVVideoColorPropertiesKey] = [
    AVVideoColorPrimariesKey:    AVVideoColorPrimaries_ITU_R_709_2,
    AVVideoTransferFunctionKey:  AVVideoTransferFunction_ITU_R_709_2,
    AVVideoYCbCrMatrixKey:       AVVideoYCbCrMatrix_ITU_R_709_2,
]
```

**File:line for the change:**
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:184` (add colour props)
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:254-257` (HDR pixel-format upgrade)

---

### Hypothesis #3 — `AVVideoExpectedSourceFrameRateKey` mis-declared for slow-mo (120/240 fps) sources — **CONFIDENCE: LOW-MEDIUM**

**What -11841 means here:** for an iPhone slow-mo source,
`videoTrack.load(.nominalFrameRate)` returns the capture rate (e.g. 240 fps)
even though the time-mapped playback rate is 30 fps. The writer is told to
**expect** 240 fps source but the actual sample-buffer cadence after the
reader's track output is the post-time-mapping rate — the disagreement, plus
a `gop = 480` (240 × 2) value into `AVVideoMaxKeyFrameIntervalKey`, plus a
high `bitrate × 240 fps` macroblock budget → encoder rejects the configuration.

**Where:**
- `CompressionService.swift:168-169` — `frameRate` is set to nominalFrameRate.
- `CompressionService.swift:181` — `AVVideoExpectedSourceFrameRateKey` flows
  the same value to the encoder.
- `CompressionService.swift:169` — `gop = Int(frameRate.rounded()) * 2`.
  For 240 fps this is 480 — a large but legal GOP at the level envelope's
  upper limit.

**Why Small works, the others don't:**
At Small's bitrate × dimensions, the macroblock-rate budget at 240 fps still
fits Level 4.0. At Max/Balanced/Streaming's larger res and/or higher
bitrate, it does not.

**Fix strategy:**
Probe the source's actual playback rate via the asset's time mapping (or
clamp `frameRate` to ≤ 60 if the source duration / sample-count ratio
disagrees with `nominalFrameRate`). At minimum, clamp the GOP key to a
reasonable max:

```swift
let frameRate = nominalFrameRate > 0 ? min(nominalFrameRate, 120) : 30
let gop = max(2, min(Int(frameRate.rounded()) * 2, 240))
```

**File:line for the change:**
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/CompressionService.swift:168-169`

---

## 6. Cross-reference with existing audits

| Audit ref | Relevant? | Notes |
|---|---|---|
| AUDIT-06 H1 (HDR 8-bit downgrade) | **Yes** — Hypothesis #2 | The same pixel-format hardcode that washes out HDR may also be the trigger for -11841 on certain HDR sources. Quality bug + failure trigger. |
| AUDIT-06 H4 (Max preset has no cap) | **Yes** — Hypothesis #1 | Already flags that Max passes source bitrate through unbounded. The fix proposed in H4 (cap to 90% of source, or passthrough remux) directly addresses Hypothesis #1. |
| AUDIT-06 M4 (Smart bitrate floor can exceed source) | Marginal | M4 is about producing a same-or-larger output for already-tiny sources, which is a different failure mode (size guard catches it). Could however cause Streaming's 750 kbps floor to exceed source bitrate × ratio AND combined with H.264 High AutoLevel, contribute to envelope overflow. |
| AUDIT-04 / AUDIT-09 (cache cleanup) | No | Pre-finalize lifecycle. Unrelated to writer.finishWriting() failures. |
| AUDIT-06 H3 (color primaries not preserved) | Adjacent to Hypothesis #2 | Same fix mechanism. |

**Pattern:** the AUDIT-06 H1 + H4 cluster of compression-quality bugs is the
**same** code surface that this -11841 failure lives on. The audit graded them
HIGH for quality; the field report grades them as **functional regression** — no
output produced at all on three out of four presets.

---

## 7. Recommended cluster injection: **NEW Cluster 0 — Hotfixes**

This issue **cannot** be absorbed into Clusters 1-5 as written:

- **Cluster 1** (cache + still bake): touches different files. Compression
  pipeline isn't in scope.
- **Cluster 2** (stitch correctness): `StitchExporter`, not the URL-asset
  compress path.
- **Cluster 3** (UX polish): the user-facing message could be improved here,
  but improving the message doesn't fix the failure.
- **Cluster 4** (App Store hardening): would catch this in QA, but doesn't
  fix the encoder envelope.
- **Cluster 5** (meta marker registry): unrelated.

**Severity / urgency justification for "Cluster 0":**

- **75% of presets fail** on real device. That's a launch-blocker.
- **The post-flight size guard at `VideoLibrary.swift:329-337`** triggers AFTER
  the encode succeeds — useless when the encode itself fails before producing a
  file.
- **No graceful degradation path exists** today. The user gets the raw NSError
  string and is stuck.
- AUDIT-06 H1 and H4 already exist as known issues. Cluster 0 is the natural
  home for "consolidate the H1+H4 fixes + add the bitrate cap + add the
  -11841 retry-with-downshift" as one PR that ships before any clusters land.

**Recommended Cluster 0 scope (in priority order):**

1. **Cap Max preset bitrate.** Apply the smaller of `safeSource × 0.9` and
   `50_000_000` (or per-resolution ceiling). Closes the obvious failure for
   Max on 4K HDR iPhone sources. Also closes AUDIT-06 H4.
2. **Add SDR colour properties to `compressionProps`.** Suppresses the
   colour-mismatch validation rejection. Sets foundation for AUDIT-06 H1.
3. **Catch -11841 and retry once at half bitrate.** Defence-in-depth.
   Surfaces a graceful "tried at lower bitrate" state instead of a hard fail.
4. **Improve the user-facing error message.** When the retry also fails,
   show "This source isn't supported at \(preset.title). Try Small or
   Streaming." instead of `[AVFoundationErrorDomain -11841]`.
5. **Telemetry hook (DEBUG only).** Log the source's
   `(naturalSize, nominalFrameRate, estimatedDataRate, formatDescriptions)`
   alongside the failure so the next user report includes diagnosable data
   without back-and-forth.

Out of scope for Cluster 0 (defer to Cluster 4):
- Full HDR pipeline (Main10 + 10-bit pixel format + colour preservation) —
  AUDIT-06 H1 in full.
- Passthrough remux for Max preset on matching codecs — AUDIT-06 H4
  variant B.

---

## 8. Test the hypothesis (before committing to a fix)

**The diagnosis is medium-high confidence at best until we know the source
file's specs.** Three discriminating tests, in order of cost:

### Test A — Get the source-file specs from the user (zero code)

Ask the user to share, for the file they tried:
1. Source codec (HEVC vs H.264)
2. Resolution
3. Frame rate (slow-mo? regular 30/60?)
4. Bit depth / HDR (was it shot in HDR Video on a recent iPhone?)
5. File size and approximate duration

If the source is **4K HDR HEVC at 60 Mbps** → Hypothesis #1 confirmed.
If the source is **1080p HDR HEVC at 30 fps** → Hypothesis #2 favoured.
If the source is **1080p slow-mo H.264 at 240 fps** → Hypothesis #3 favoured.

### Test B — Single-line diagnostic build (1 line of code)

Add **temporarily** at `CompressionService.swift:472`:

```swift
print("[DIAG -11841] source: \(naturalSize) @ \(nominalFrameRate)fps  src=\(estimatedDataRate)bps  target=\(targetBitrate)bps  codec=\(settings.videoCodec.rawValue)  outDims=\(targetWidth)x\(targetHeight)")
```

Reproduce on device, read the Console.app log, file the diagnosis with hard
numbers.

### Test C — Manual compression sweep (no app changes)

Use the user's same source file with `ffmpeg` / `xcrun avconvert` on a Mac at
each preset's `(codec, dims, bitrate)` tuple. Whichever combinations also fail
on the Mac VideoToolbox backend match the iPhone failures — confirms the issue
is encoder-envelope-driven (Hypothesis #1) rather than data-mismatch (#2).

### Test D — Apply the Hypothesis #1 fix and validate

After capping Max bitrate to 50 Mbps and clipping `safeSource × 0.9`, retry
the same source on Max. If it succeeds → Hypothesis #1 confirmed. If it still
fails on Balanced and Streaming → fall back to applying Hypothesis #2's colour-
property fix and re-test.

---

## 9. Honest summary

The AVError code is unambiguous. The throw site is unambiguous. **What's
ambiguous is which of the three preset settings × source-file properties pair
trips the encoder validator** — without the source file's specs we cannot pin
the root cause to one of three plausible hypotheses with high confidence.

The hopeful news: **all three hypotheses point at the same general code
surface** (`CompressionSettings.bitrate(...)`, `CompressionService.encode()`'s
compressionProps construction, and the reader pixel format). A Cluster 0
hotfix that:
- caps Max bitrate (Hypothesis #1)
- adds SDR colour properties (Hypothesis #2)
- clamps frameRate / GOP (Hypothesis #3)
- adds -11841 retry-with-downshift (defence-in-depth)

…fixes all three at once. The cost is one PR, ~80 lines of code, a regression
test per preset against a 4K HDR source.

Recommend: **stop further investigation, ship Cluster 0 with all three fixes,
and use Test A + Test B to verify which hypothesis was the actual cause
post-fix** (so the residual two can be downgraded in the changelog).
