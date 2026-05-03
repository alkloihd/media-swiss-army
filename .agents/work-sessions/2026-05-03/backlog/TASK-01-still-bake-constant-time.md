# TASK-01 — Still-image bake should be O(1)

**Priority:** HIGH — user-reported perf concern.
**Estimated effort:** 1-2 hours.
**Branch:** `feat/still-bake-constant-time` off `main`.

## Problem

`StillVideoBaker.bake(still:duration:)` writes `duration × 30` identical frames to a temp .mov file. For a 10-second still, that's 300 frames. Bake time scales linearly with the user's chosen still duration (1–10 s slider). Users complained the export feels frozen.

## Goal

Bake time becomes constant (~30 frames worst case ≈ 0.5 s), regardless of `duration`.

## Approach (native AVFoundation, no custom compositor)

**Option A — single frame held by sample timing duration:**

Instead of pushing N frames at PTS 0, 1/30, 2/30…, push ONE frame at PTS=0 with `presentationTimeStamp = 0` and `decodeTimeStamp = 0`, then call `markAsFinished()` immediately. The session's `endSession(atSourceTime:)` is set to `duration`, so the resulting movie has duration = `duration` with one frame held. Most players / AVFoundation honor this.

But: AVAssetWriter requires you to use `AVAssetWriterInputPixelBufferAdaptor.append(_:withPresentationTime:)`, which doesn't take a sample-buffer duration directly. So the single-frame-held trick is fiddly.

**Option B (recommended) — bake 1-second 1-frame video, scale in composition:**

1. In `StillVideoBaker.bake`, ALWAYS bake exactly 1 second (30 frames at 30 fps, OR even simpler: 1 frame total for an explicit 1-second sample-buffer duration). Drop the `duration` parameter.
2. In `StitchExporter.buildPlan`, when inserting the baked clip into the composition, instead of using the bake's natural duration, call `videoTrack.insertTimeRange(_, of: assetVideoTrack, at: cursor)` with the source range `CMTimeRange(start: .zero, duration: 1.0s)`, then call `videoTrack.scaleTimeRange(_, toDuration: stillDuration)` to stretch.

`AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` is documented to handle this correctly. The single frame gets held for `stillDuration` seconds in the composition.

Match the audio track too — but stills bake without audio so there's nothing to scale.

## Files to change

- `VideoCompressor/ios/Services/StillVideoBaker.swift` — drop `duration` param, hardcode 1-second bake
- `VideoCompressor/ios/Services/StitchExporter.swift` — in the bake loop (around line 80-110), call `scaleTimeRange` on the inserted track segment for stills

## Tests

Add `VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift`:

- Test that bake() produces a non-empty file regardless of input image size
- Test that the result has duration ~1 second (not user-facing duration)
- Test that StitchExporter.buildPlan correctly scales the result to user duration (composition timeline length matches expectations)

## Out of scope

- Don't change the duration slider UI (1-10s, default 3s)
- Don't change the user-perceived behavior — just make it instant

## Acceptance criteria

- [ ] Bake of any-duration still completes in < 0.5 s on iPhone 16 Pro
- [ ] Resulting stitched video plays correctly (still held for the full duration)
- [ ] All existing tests still pass
- [ ] New StillVideoBakerTests pass
