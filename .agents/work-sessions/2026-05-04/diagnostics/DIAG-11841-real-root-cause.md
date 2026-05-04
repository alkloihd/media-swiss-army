# DIAG — `-11841` real root cause on iPhone 18

**Date:** 2026-05-04, post-Cluster-2.5 evening session
**Author:** Claude Opus 4.7 (read-only investigation prompted by user skepticism that "encoder envelope" was the right diagnosis on iPhone 18)
**Status:** Diagnosis confirmed in code; **fix shipped in PR #18** (`fix/cluster-2.5-tests`).
**Supersedes:** the "encoder envelope" framing in `docs/superpowers/plans/2026-05-04-DIAG-compression-presets.md` for the user's iPhone 18 / iOS 26.3.1 / HDR-source case. The original DIAG was written for weaker hardware (iPhone XS / 11 / 12) where bitrate-tuple rejections are real. iPhone 18's encoder is more capable; the user's `-11841` failures have a different root cause.

---

## TL;DR

`-11841` (`AVErrorInvalidVideoComposition`) is Apple's catch-all for "the writer can't reconcile the configuration you gave it." On iPhone 18 with HDR-recorded clips, two specific cases trigger it deterministically:

1. **Streaming preset on any HDR (10-bit) source.** `H.264 High AutoLevel` is 8-bit only on Apple's HW encoder, but the writer was being configured to receive 10-bit pixel buffers + BT.2020 colors when source was HDR. → `-11841` at `finishWriting()`.
2. **Stitch path (any preset that uses `AVMutableVideoComposition`) on HDR source.** `StitchExporter.swift:330-352` always emits a videoComposition since Cluster 2. The composition has no color properties set, so it renders 8-bit BT.709. The writer was being declared HDR (10-bit BT.2020) based on SOURCE format descriptions. → mismatch → `-11841`.

The "fails sometimes, works after retries" pattern is consistent with mixed-source stitches: `is10Bit` is computed via `formatDescriptions.contains { ... ≥ 10 bpc }` on the composition's combined track, and AVFoundation does not guarantee ordering — a stitch with one HDR video + one baked still toggled between paths run-to-run.

## Why the original "encoder envelope" framing missed this

iPhone 18's HEVC encoder supports Main10 at Level 6.2 with BT.2020/HLG. The hardware envelope is not the bottleneck for the user's reported failures. The failures are a **bit-depth / codec / color-space contract violation** between reader, composition, and writer — entirely software, entirely on us.

## Why existing fallbacks didn't catch it

- Cluster 0's bitrate cap and Max-preset clamp targeted the bitrate-tuple problem on weaker hardware. Doesn't address bit depth.
- Cluster 0's BT.709 default applied only when source was 8-bit. Cluster 2's HDR commit (`fffdaa6`) made BT.2020 the default for any 10-bit source — including the broken cases.
- Cluster 0's one-shot downshift retries with the same flawed `is10Bit` detection on the same composition, so every retry hits the same mismatch.
- Cluster 2.5's friendly error wrap (PR #17) hides the symptom but doesn't fix it — the user still saw the friendly message, just not the raw `-11841`.

## The fix (shipped in PR #18)

`CompressionService.canEncodeHDR(sourceIs10Bit:codec:hasVideoComposition:)` gates the HDR pipeline on three preconditions; all must hold:

1. Source is 10-bit (`AVFoundation` reports ≥ 10 bpc on the format description).
2. Output codec is HEVC (H.264 High AutoLevel is 8-bit-only on Apple's HW encoder).
3. There is no `AVMutableVideoComposition` (compositions emit 8-bit BT.709 by default and we don't override that).

If any precondition fails, the pipeline drops to SDR: 8-bit pixel format, BT.709 colors, HEVC Main / H.264 High profile. Reader, composition, and writer are then all internally consistent → no -11841.

```swift
// CompressionService.swift, replacing the old direct is10Bit assignment
let is10Bit = Self.canEncodeHDR(
    sourceIs10Bit: sourceIs10Bit,
    codec: settings.videoCodec,
    hasVideoComposition: videoComposition != nil
)
```

Pure 4-line static helper, no async, no `AVAssetReader` setup needed for unit tests.

## Tests added in PR #18

- `testCanEncodeHDR_HEVC_noComposition_HDRSource_isTrue` — HDR Compress flow stays HDR.
- `testCanEncodeHDR_H264_HDRSource_isFalse` — Streaming preset on HDR source drops to SDR.
- `testCanEncodeHDR_HEVC_withComposition_HDRSource_isFalse` — Stitch path drops to SDR even on HEVC.
- `testCanEncodeHDR_SDRSource_alwaysFalse` — 8-bit source never enters HDR pipeline regardless of codec/composition.

Local run on iPhone 16 Pro sim (iOS 18.0): **268 passed / 1 skipped / 0 failed** (up from the 248 baseline; +16 wrap/clearAll tests + 4 HDR-precondition tests).

## Risk

- **Compress flow on HDR clip** continues to encode HDR HEVC Main10 BT.2020. No regression.
- **Stitch flow on HDR clip** now encodes SDR HEVC Main BT.709 (composition path, was already producing 8-bit frames anyway). User-visible change: stitched output is no longer flagged as HDR by Photos. Acceptable — a stitched video that mixes HDR and SDR sources can't be HDR end-to-end anyway.
- **Streaming preset on HDR clip** now encodes SDR H.264 BT.709. Was previously throwing `-11841`. Net win.

## Real-device gate

Same protocol as PR #17. After this PR merges and TestFlight delivers the new build, user re-walks: Stitch + Random transition + Small preset on an HDR clip; Streaming preset on an HDR clip; Compress on an HDR clip (regression check). Expected: clean exports, no `-11841`.

---

## Open question for follow-up

If the user wants HDR stitches to STAY HDR end-to-end, we would need to set `AVMutableVideoComposition.colorPrimaries / colorYCbCrMatrix / colorTransferFunction` to BT.2020 / HLG in `StitchExporter.swift`, and ensure all clip layer instructions render in the HDR color space. That's a separate, larger change — for now the priority is "don't crash the export".
