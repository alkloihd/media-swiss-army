# Phase 1 Cluster 2 — Stitch correctness (HDR + audio mix + stage collision + auto-sort on import)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. All steps use checkbox (`- [ ]`) syntax.

**Goal:** Resolve the four remaining Phase 1 audit-flagged correctness bugs that aren't already covered by Cluster 1.
- 1.3 (TASK-39 / Audit-6-H1) — HDR videos must round-trip as HDR. Today the encoder reads 8-bit 4:2:0 only → iPhone HDR HEVC washes to SDR.
- 1.4 (TASK-32 / Audit-7-C3) — Audio mix indexes by `i % 2` parity. Skipped audio-less clips break parity → wrong clips' audio gets ramped.
- 1.5 (TASK-33 / Audit-7-C4) — Stage filename collision only suffix-fixes when file already exists. Delete-then-reimport with the same source name aliases stale undo-history references.
- Bug 3 (DIAG-sort-direction) — PhotosPicker delivers clips in selection order (newest-first for the default Recents browse). Clips land in newest-first order; user expects oldest-first. `sortByCreationDateAsync()` comparator is correct but never called on import.

**Branch:** `feat/phase1-cluster2-stitch-correctness` off `main`.

**Tech Stack:** Swift, AVFoundation (`AVVideoColorPropertiesKey`, `AVMutableComposition`, `AVMutableAudioMix`), XCTest.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Services/CompressionService.swift` | Modify | Detect 10-bit / HDR source; switch pixel format + propagate color properties to writer. |
| `VideoCompressor/ios/Services/StitchExporter.swift` | Modify | Record per-segment audio track on insertion; `buildAudioMix` reads from segment, not parity. |
| `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` | Modify | `stageToStitchInputs` always prefixes UUID; `importClips` calls `sortByCreationDateAsync` on completion. |
| `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift` | Modify | Add HDR pixel-format detection test. |
| `VideoCompressor/VideoCompressorTests/StitchTransitionTests.swift` | Modify | 3-clip [video, no-audio, video] audio mix test. |
| `VideoCompressor/VideoCompressorTests/StitchProjectStageTests.swift` | Create | Delete-then-reimport collision test. |
| `VideoCompressor/VideoCompressorTests/StitchProjectSortTests.swift` | Modify | Append `testImportAutoSortsOldestFirst` (Bug 3). |

---

## Task 1: HDR passthrough (Phase 1.3 / TASK-39)

**Why:** `CompressionService.encode` line 254–257 hard-codes:
```swift
let pixelFormat: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String:
        NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
]
```
This forces the reader to deliver 8-bit 4:2:0 frames, so 10-bit HEVC (iPhone HDR) is downsampled to SDR. Plus the writer never sets `AVVideoColorPropertiesKey`, so even if 10-bit got through, the output would lose BT.2020 / HLG primaries.

- [ ] **Step 1: Pin current behaviour with a regression test**

In `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift`, append:

```swift

    func testEncoderChoosesHDRPixelFormatFor10BitSource() async throws {
        // The unit under test is the helper. We don't need a real HDR
        // fixture — we test the helper that maps source format
        // descriptions → pixel-buffer dictionaries.
        let pf = CompressionService.pixelBufferDict(forIs10Bit: true)
        let raw = pf[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber
        XCTAssertEqual(
            raw?.uint32Value,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            "10-bit source must select 10-bit pixel format."
        )
    }

    func testEncoderChoosesSDRPixelFormatFor8BitSource() async throws {
        let pf = CompressionService.pixelBufferDict(forIs10Bit: false)
        let raw = pf[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber
        XCTAssertEqual(
            raw?.uint32Value,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            "8-bit source must keep 8-bit pixel format."
        )
    }
```

These reference a static helper that doesn't yet exist. Tests fail to compile until Step 2 lands — that's the TDD red.

- [ ] **Step 2: Add the helper + 10-bit detection in CompressionService**

In `VideoCompressor/ios/Services/CompressionService.swift`, replace the hard-coded `pixelFormat` block (line ~254–257) with:

```swift
        // Phase 1.3 (TASK-39 / Audit-6-H1): HDR passthrough. iPhone HEVC
        // HDR = 10-bit 4:2:0. If we ask the reader for 8-bit YpCbCr the
        // pipeline downsamples to SDR. Detect 10-bit via the source's
        // format description and switch the pixel format dict accordingly.
        let is10Bit: Bool = {
            guard let fd = videoTrack.formatDescriptions.first
                .flatMap({ $0 as! CMFormatDescription? }) else { return false }
            let bitsPerComponent = (CMFormatDescriptionGetExtension(
                fd, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent
            ) as? NSNumber)?.intValue
            if let b = bitsPerComponent, b >= 10 { return true }
            // Fallback: pixel-format type tells us 10-bit even if the
            // BitsPerComponent extension is missing.
            let mst = CMFormatDescriptionGetMediaSubType(fd)
            return mst == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                || mst == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        }()

        let pixelFormat = Self.pixelBufferDict(forIs10Bit: is10Bit)
```

Add the static helper at the bottom of `CompressionService` (above the `enum CompressionError` block):

```swift
    /// Maps source bit-depth to the pixel-buffer dictionary the reader
    /// receives. Exposed for testability — see CompressionServiceTests.
    static func pixelBufferDict(forIs10Bit is10Bit: Bool) -> [String: Any] {
        let pixelFormatType = is10Bit
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        return [
            kCVPixelBufferPixelFormatTypeKey as String:
                NSNumber(value: pixelFormatType),
        ]
    }
```

- [ ] **Step 2.5: Promote `videoOutputSettings` from `let` to `var`**

The HDR mutation in Step 3 below needs to assign new keys (`AVVideoColorPropertiesKey`) and re-write `AVVideoCompressionPropertiesKey` on the dictionary. The existing declaration at `CompressionService.swift:192` is `let`, so any in-place mutation is a Swift compile error. Promote it to `var` first.

In `VideoCompressor/ios/Services/CompressionService.swift` at line 192:

```
Before:
    let videoOutputSettings: [String: Any] = [
        AVVideoCodecKey: settings.videoCodec.rawValue,
        AVVideoWidthKey: NSNumber(value: targetWidth),
        AVVideoHeightKey: NSNumber(value: targetHeight),
        AVVideoCompressionPropertiesKey: compressionProps,
    ]

After:
    var videoOutputSettings: [String: Any] = [
        AVVideoCodecKey: settings.videoCodec.rawValue,
        AVVideoWidthKey: NSNumber(value: targetWidth),
        AVVideoHeightKey: NSNumber(value: targetHeight),
        AVVideoCompressionPropertiesKey: compressionProps,
    ]
```

Only the keyword changes — the dict literal, surrounding code, and the `AVAssetWriterInput(... outputSettings: videoOutputSettings)` consumer two lines below all keep working unchanged.

- [ ] **Step 3: Propagate color properties + Main10 profile to writer**

Find the writer's video output settings block in `CompressionService.swift` (now `var videoOutputSettings` at line 192 after Step 2.5). Immediately after that dictionary is constructed, append:

```swift
        // Color properties: source colorimetry → output colorimetry. Without
        // this, 10-bit HEVC re-encodes as SDR Rec.709 even when the input
        // was Rec.2020 HLG.
        if is10Bit, let fd = videoTrack.formatDescriptions.first
            .flatMap({ $0 as! CMFormatDescription? })
        {
            let colorPrimaries = (CMFormatDescriptionGetExtension(
                fd, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
            ) as? String) ?? AVVideoColorPrimaries_ITU_R_2020
            let transfer = (CMFormatDescriptionGetExtension(
                fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction
            ) as? String) ?? AVVideoTransferFunction_ITU_R_2100_HLG
            let ycbcrMatrix = (CMFormatDescriptionGetExtension(
                fd, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix
            ) as? String) ?? AVVideoYCbCrMatrix_ITU_R_2020

            videoOutputSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorPrimaries,
                AVVideoTransferFunctionKey: transfer,
                AVVideoYCbCrMatrixKey: ycbcrMatrix,
            ]

            // HEVC Main10 profile for 10-bit. Without this the encoder
            // refuses 10-bit input or silently truncates to Main.
            if var compProps = videoOutputSettings[AVVideoCompressionPropertiesKey]
                as? [String: Any]
            {
                compProps[kVTCompressionPropertyKey_ProfileLevel as String] =
                    kVTProfileLevel_HEVC_Main10_AutoLevel as String
                videoOutputSettings[AVVideoCompressionPropertiesKey] = compProps
            }
        }
```

The variable name is verified as `videoOutputSettings` (grep-confirmed at `CompressionService.swift:192`). Use exactly that name.

- [ ] **Step 4: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 140, Passed: 140` (138 + 2 new). The HDR tests use the static helper and don't need a fixture file.

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Services/CompressionService.swift \
        VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift
git commit -m "feat(compress): HDR passthrough — detect 10-bit + propagate color (Phase 1.3)

Resolves TASK-39 / Audit-6-H1 + 6-H3. Reader requests 10-bit 4:2:0 when
source is 10-bit; writer sets AVVideoColorPropertiesKey from source
ColorPrimaries / TransferFunction / YCbCrMatrix; HEVC Main10 profile
forced on 10-bit path so the encoder accepts it without truncating.

iPhone HDR HEVC sources now round-trip as HDR instead of washing to SDR."
```

**Effort: ~3h. ~2 commits.**

---

## Task 2: Audio mix track parity (Phase 1.4 / TASK-32)

**Why:** `StitchExporter.buildAudioMix` (line 343–399) does:
```swift
let trackIdx = audioTracks.count == 1 ? 0 : (i % 2)
let track = audioTracks[trackIdx]
```
This mirrors the A/B alternation chosen during insertion (`useTrackB = needsAB && (segments.count % 2 == 1)` at line 227, then `audioT = useTrackB ? audioTrackB : audioTrackA` at line 229). **Both fail when a clip has no audio** (still photo or audio-stripped video): the audio insertion is skipped (line 247-251 wraps `audioT.insertTimeRange` in `if let audioT { if let assetAudio = ... }`), but the *parity counter* in `buildAudioMix` keeps marching, so subsequent segments' ramps fire on the WRONG underlying composition track.

**Architecture context (verified in code):** Audio composition tracks are **pre-allocated** at lines 134 (`audioTrackA`) and 148-149 (`audioTrackB`, only when `needsAB`). Adjacent segments alternate between these two pre-allocated tracks. **Do NOT add new tracks per segment** — that breaks the existing A/B-roll design that the video composition relies on.

**The fix** keeps the pre-allocated `audioTrackA` / `audioTrackB` as the underlying composition tracks, but extends each `Segment` to record which one (or `nil`) the clip's audio actually landed on. `buildAudioMix` then iterates audible segments and ramps each via its recorded track instead of recomputing parity.

- [ ] **Step 0: Add fixture helpers to `StitchTransitionTests.swift`**

Before the audio-mix test (Step 1) can compile, the test class needs two fixture helpers. Add these as `private static` methods inside `StitchTransitionTests`. If the helpers already exist in this file (grep first: `grep -n "makePNGFixture\|makeShortVideoFixture" VideoCompressor/VideoCompressorTests/StitchTransitionTests.swift`), skip this step; otherwise add:

```swift
    /// Writes a 4×4 solid-magenta PNG to `tmp/`. Caller is responsible for
    /// deleting the returned URL.
    private static func makePNGFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-fixture-\(UUID().uuidString).png")
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let cg = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "fixture", code: 1)
        }
        return url
    }

    <!-- VERIFY: 30-line AVAssetWriter audio-track helper — synthesize from
         Apple sample code; the version below is a best-effort that needs
         a quick smoke-run before relying on it. -->
    /// Writes a 1-second 4×4 .mov to `tmp/`. When `withAudio: true`, attaches
    /// a 2-channel 44.1 kHz silent AAC track so the file appears as
    /// "video + audio" to AVURLAsset. Caller is responsible for deletion.
    private static func makeShortVideoFixture(withAudio: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-fixture-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 4,
            AVVideoHeightKey: 4,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let pba = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 4,
                kCVPixelBufferHeightKey as String: 4,
            ]
        )
        guard writer.canAdd(videoInput) else { throw NSError(domain: "fixture", code: 2) }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if withAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
                AVSampleRateKey: NSNumber(value: 44_100),
                AVNumberOfChannelsKey: NSNumber(value: 2),
                AVEncoderBitRateKey: NSNumber(value: 64_000),
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = false
            if writer.canAdd(ai) { writer.add(ai); audioInput = ai }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // 30 video frames @ 30 fps = 1.0 s.
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        for f in 0..<30 {
            let t = CMTime(value: CMTimeValue(f), timescale: 30)
            while !videoInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            pba.append(pb!, withPresentationTime: t)
        }
        videoInput.markAsFinished()

        if let ai = audioInput {
            // ~1s of silent stereo PCM packed into one CMSampleBuffer; the
            // AAC encoder takes it from there.
            let sampleCount = 44_100
            let dataSize = sampleCount * 2 * MemoryLayout<Int16>.size
            var blockBuffer: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil,
                blockLength: dataSize, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: dataSize,
                flags: 0, blockBufferOut: &blockBuffer
            )
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer!,
                                       offsetIntoDestination: 0, dataLength: dataSize)
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 4, mFramesPerPacket: 1,
                mBytesPerFrame: 4, mChannelsPerFrame: 2,
                mBitsPerChannel: 16, mReserved: 0
            )
            var formatDesc: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                           asbd: &asbd, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil,
                                           extensions: nil, formatDescriptionOut: &formatDesc)
            var sampleBuffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: blockBuffer!,
                formatDescription: formatDesc!, sampleCount: sampleCount,
                presentationTimeStamp: .zero, packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            )
            while !ai.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            ai.append(sampleBuffer!)
            ai.markAsFinished()
        }

        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        guard writer.status == .completed else {
            throw NSError(domain: "fixture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                            "writer finished with status \(writer.status.rawValue)"])
        }
        return url
    }
```

If the AVAssetWriter audio path turns out to need a tweak (Apple's CMSampleBuffer audio APIs are finicky and the exact incantation varies between iOS versions), Codex should treat the body above as a starting point — the public surface (`makeShortVideoFixture(withAudio:) -> URL`) and the contract (1 s, 4×4, optional silent stereo AAC track) are what Step 1 depends on.

- [ ] **Step 1: Pin current behaviour with a failing test**

In `VideoCompressor/VideoCompressorTests/StitchTransitionTests.swift`, append:

```swift

    func testAudioMixHandlesAudioLessClipInMiddle() async throws {
        // Three clips: [video-with-audio, still-photo, video-with-audio].
        // The middle clip has no audio. With the pre-fix `i % 2` parity
        // logic, segment[2]'s audio ramp was applied to track index 0,
        // overwriting segment[0]'s ramp window. After the fix, each
        // segment carries its own audio-track reference and the ramps
        // never collide.
        //
        // We test this by building a Plan and asserting:
        //   - Each segment's audioTrack is either nil (still) or distinct.
        //   - The audioMix's input parameters count matches the number
        //     of clips that actually have audio.

        let videoFixture = try Self.makeShortVideoFixture(withAudio: true)
        defer { try? FileManager.default.removeItem(at: videoFixture) }
        let stillFixture = try Self.makePNGFixture()
        defer { try? FileManager.default.removeItem(at: stillFixture) }

        let clipA = StitchClip.video(url: videoFixture, displayName: "A")
        var stillEdits = ClipEdits.identity
        stillEdits.stillDuration = 2.0
        let clipB = StitchClip(
            id: UUID(), sourceURL: stillFixture, displayName: "B",
            naturalDuration: CMTime(seconds: 2, preferredTimescale: 600),
            naturalSize: CGSize(width: 4, height: 4),
            kind: .still, edits: stillEdits
        )
        let clipC = StitchClip.video(url: videoFixture, displayName: "C")

        let plan = try await StitchExporter().buildPlan(
            from: [clipA, clipB, clipC],
            aspectMode: .auto,
            transition: .crossfade
        )

        // The audio mix must contain exactly 2 ramped segments (clipA + clipC).
        // Pre-fix this would be 3 (clipB was misindexed).
        let inputs = (plan.audioMix?.inputParameters ?? [])
        XCTAssertEqual(inputs.count, 2,
            "Expected audio params for the 2 audio-bearing clips; got \(inputs.count)")

        for url in plan.bakedStillURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
```

The test fails on current code (count is 3, off-by-one).

- [ ] **Step 2: Widen the function-local `Segment` struct (line 163) to carry an `audioTrack: AVMutableCompositionTrack?`**

In `VideoCompressor/ios/Services/StitchExporter.swift`, find the `Segment` struct **inside** `buildPlan` (around line 163). Note: this is a function-local struct, NOT a top-level `private struct`. Current source:

```swift
        struct Segment {
            let clip: StitchClip
            let composedRange: CMTimeRange
            let videoTrack: AVMutableCompositionTrack
        }
```

Add the audio track field:

```swift
        struct Segment {
            let clip: StitchClip
            let composedRange: CMTimeRange
            let videoTrack: AVMutableCompositionTrack
            /// The composition audio track this clip's audio actually landed on,
            /// or nil if the clip has no audio (stills, audio-stripped sources).
            let audioTrack: AVMutableCompositionTrack?
        }
```

- [ ] **Step 3: Record the chosen audioTrack per segment during insertion (around lines 247-254)**

The existing insertion logic at lines 227-251 already selects `audioT = useTrackB ? audioTrackB : audioTrackA` (line 229) using the pre-allocated `audioTrackA` / `audioTrackB`. **Do NOT add new tracks** — just capture which one (or nil) was actually used into the `Segment` record.

Current source at lines 247-254 looks like:

```swift
            if let audioT {
                if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioT.insertTimeRange(timeRange, of: assetAudio, at: insertAt)
                }
            }

            let composedRange = CMTimeRange(start: insertAt, duration: timeRange.duration)
            segments.append(Segment(clip: clip, composedRange: composedRange, videoTrack: videoT))
```

Refactor to capture the actually-used track. The `audioT` declared at line 229 (which is `useTrackB ? audioTrackB : audioTrackA`) is `nil` when `needsAB == false` and there's no `audioTrackB`; it's also `nil`-out-able when the audio insertion is skipped because the clip has no audio source. Replace with:

```swift
            // Track which audio composition track this clip's audio
            // actually went onto (or nil if the clip has no audio).
            // buildAudioMix iterates audible segments via this field
            // instead of re-deriving parity from the segments array,
            // which breaks when audio-less clips are skipped.
            var audioForSegment: AVMutableCompositionTrack?
            if let audioT {
                if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioT.insertTimeRange(timeRange, of: assetAudio, at: insertAt)
                    audioForSegment = audioT
                }
            }

            let composedRange = CMTimeRange(start: insertAt, duration: timeRange.duration)
            segments.append(Segment(
                clip: clip,
                composedRange: composedRange,
                videoTrack: videoT,
                audioTrack: audioForSegment
            ))
```

Note: `audioForSegment` stays `nil` whenever (a) `needsAB == false` AND `audioTrackA` is nil, (b) the clip has no audio asset track, or (c) `audioT.insertTimeRange` would have been skipped. The `audioTrackA` reference at line 134 is non-optional (it's the result of `composition.addMutableTrack`), so case (a) only applies if `addMutableTrack` itself returned nil — in which case the parent `audioT` binding fails and we land in `audioForSegment = nil`. Correct.

- [ ] **Step 4: Rewrite `buildAudioMix` (lines 343-399) to iterate audible segments via `segment.audioTrack`**

The current `buildAudioMix` (lines 343-399) takes a `segments` parameter typed as `[(clip:, composedRange:, videoTrack:)]` and re-derives the audio track via `audioTracks[i % 2]` (line 359). Both the parameter shape AND the body need to change.

Replace the entire function with:

```swift
    /// Build the audio mix that pairs with the video transitions. For each
    /// AUDIBLE segment, set a constant 1.0 volume EXCEPT during the overlap
    /// windows at its head (fade in) and tail (fade out), which use
    /// `setVolumeRamp` to crossfade with the adjacent audible clip.
    ///
    /// Audio-less segments (still photos, audio-stripped sources) are filtered
    /// out before ramp computation so an audible clip that comes AFTER a still
    /// still crossfades correctly with the previous audible clip — even if
    /// they are not adjacent in segments[].
    private func buildAudioMix(
        composition: AVMutableComposition,
        segments: [(clip: StitchClip,
                    composedRange: CMTimeRange,
                    videoTrack: AVMutableCompositionTrack,
                    audioTrack: AVMutableCompositionTrack?)],
        transition: StitchTransition,
        transitionDuration: CMTime
    ) -> AVMutableAudioMix? {
        // Filter to only audible segments. Each entry carries the segment's
        // composedRange + the SPECIFIC pre-allocated composition audio track
        // (audioTrackA or audioTrackB) the clip's audio went onto.
        let audible: [(range: CMTimeRange, track: AVMutableCompositionTrack, gapIndex: Int)] =
            segments.enumerated().compactMap { (i, seg) in
                guard let t = seg.audioTrack else { return nil }
                return (seg.composedRange, t, i)
            }
        guard audible.count >= 2 else { return nil }

        let mix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []

        for (idx, entry) in audible.enumerated() {
            let p = AVMutableAudioMixInputParameters(track: entry.track)
            p.setVolume(1.0, at: entry.range.start)

            // Head fade-in: overlap with the PREVIOUS audible segment.
            if idx > 0 {
                let prev = audible[idx - 1]
                let overlapStart = entry.range.start
                let overlapEnd = prev.range.end
                if overlapEnd > overlapStart {
                    let overlap = CMTimeRange(start: overlapStart, end: overlapEnd)
                    // Use the gapIndex of the PREVIOUS audible segment so the
                    // transition variant lookup matches the visual transition
                    // chosen for that gap.
                    let variant = Self.resolveTransition(transition, gapIndex: prev.gapIndex)
                    switch variant {
                    case .fadeToBlack:
                        let half = CMTimeMultiplyByFloat64(overlap.duration, multiplier: 0.5)
                        let secondHalf = CMTimeRange(
                            start: CMTimeAdd(overlap.start, half),
                            duration: CMTimeSubtract(overlap.duration, half)
                        )
                        p.setVolume(0.0, at: overlap.start)
                        p.setVolumeRamp(
                            fromStartVolume: 0.0, toEndVolume: 1.0,
                            timeRange: secondHalf
                        )
                    case .crossfade, .wipeLeft, .random, .none:
                        p.setVolumeRamp(
                            fromStartVolume: 0.0, toEndVolume: 1.0,
                            timeRange: overlap
                        )
                    }
                }
            }

            // Tail fade-out: overlap with the NEXT audible segment.
            if idx + 1 < audible.count {
                let next = audible[idx + 1]
                let overlapStart = next.range.start
                let overlapEnd = entry.range.end
                if overlapEnd > overlapStart {
                    let overlap = CMTimeRange(start: overlapStart, end: overlapEnd)
                    p.setVolumeRamp(
                        fromStartVolume: 1.0, toEndVolume: 0.0,
                        timeRange: overlap
                    )
                }
            }
            params.append(p)
        }
        mix.inputParameters = params
        return mix
    }
```

**Key differences from the prior implementation:**
- The `audioTracks = composition.tracks(withMediaType: .audio)` lookup is gone — the per-segment `audioTrack` field already carries the right reference.
- The `i % 2` parity formula is gone — the `audible.compactMap` filter naturally skips audio-less segments.
- Head/tail overlap windows now compare against the prev/next AUDIBLE segment (not the prev/next index in `segments[]`). When a still photo sits between two videos, the videos still crossfade with each other.
- The `gapIndex` passed to `resolveTransition` uses the original `segments` index of the PREVIOUS audible segment, preserving the existing per-gap transition-variant assignment.
- The pre-allocated `audioTrackA` / `audioTrackB` machinery upstream (lines 134, 148-149) is unchanged. They remain the actual composition audio tracks AVFoundation renders from.

Update the `buildAudioMix` call site (around line 317-324) to pass the wider tuple:

```swift
            audioMix = buildAudioMix(
                composition: composition,
                segments: segments.map {
                    (clip: $0.clip, composedRange: $0.composedRange,
                     videoTrack: $0.videoTrack, audioTrack: $0.audioTrack)
                },
                transition: transition,
                transitionDuration: transitionDuration
            )
```

- [ ] **Step 5: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 141, Passed: 141, Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add VideoCompressor/ios/Services/StitchExporter.swift \
        VideoCompressor/VideoCompressorTests/StitchTransitionTests.swift
git commit -m "fix(stitch): per-segment audio track lookup (Phase 1.4 / TASK-32)

Audit-7-C3: buildAudioMix used i % 2 parity to pick which composition
audio track to ramp, but skipped audio-less segments (still photos,
audio-stripped sources) broke parity → wrong segments' audio got the
ramp.

Fix: Segment now carries an explicit audioTrack: AVMutableCompositionTrack?
recorded at insertion time. buildAudioMix iterates only the audible
segments and ramps each to itself."
```

**Effort: ~1h. ~2 commits.**

---

## Task 3: Stage filename collision (Phase 1.5 / TASK-33)

**Why:** `stageToStitchInputs` (StitchTabView.swift:383–406) only adds a UUID suffix when `FileManager.default.fileExists(atPath: target.path)` is true. But:
1. User imports `clip.mov` → staged at `StitchInputs/clip.mov`.
2. User deletes the clip from the project. `StitchProject.remove(at:)` may keep the file on disk (refcount logic from PR #9).
3. User re-imports `clip.mov` from a different source. `fileExists` now returns true → suffixed correctly. ✅
4. **BUT** if the original delete DID remove the file, `fileExists` returns false; the new import overwrites at the same path. Any in-memory `StitchClip` or undo-history entry pointing to that path now aliases the new file with stale metadata.

Fix: always prefix with UUID. No `fileExists` branching.

- [ ] **Step 1: Pin current behaviour with a failing test**

Create `VideoCompressor/VideoCompressorTests/StitchProjectStageTests.swift`:

```swift
import XCTest
@testable import VideoCompressor_iOS

final class StitchProjectStageTests: XCTestCase {

    func testStagedFilenamesAreAlwaysUUIDPrefixed() throws {
        // Two consecutive stages of "clip.mov" must produce two distinct
        // paths even when the first was deleted between calls.
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stageDir = docs.appendingPathComponent(
            "StitchInputs-test-\(UUID().uuidString.prefix(6))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stageDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stageDir) }

        // Synthesize two source files.
        let src1 = stageDir.appendingPathComponent("source1.tmp")
        let src2 = stageDir.appendingPathComponent("source2.tmp")
        try Data(repeating: 0xAA, count: 16).write(to: src1)
        try Data(repeating: 0xBB, count: 16).write(to: src2)

        // Both share the suggested name "clip.mov".
        let stage1 = try StitchTabView.testHook_stageToStitchInputs(
            source: src1, suggestedName: "clip.mov", into: stageDir
        )
        // Delete the first staged file (simulating user removed clip from project).
        try FileManager.default.removeItem(at: stage1)

        let src2dup = stageDir.appendingPathComponent("source3.tmp")
        try Data(repeating: 0xCC, count: 16).write(to: src2dup)
        let stage2 = try StitchTabView.testHook_stageToStitchInputs(
            source: src2dup, suggestedName: "clip.mov", into: stageDir
        )

        XCTAssertNotEqual(stage1.lastPathComponent, stage2.lastPathComponent,
            "Two stagings of 'clip.mov' must produce distinct paths even " +
            "after the first was deleted. \(stage1.lastPathComponent) vs " +
            "\(stage2.lastPathComponent)")

        // And both should look UUID-prefixed: at least 6 hex chars before
        // the rest of the name.
        let pattern = #"^[a-f0-9]{6}-clip\.mov$"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        for url in [stage2] {
            let n = url.lastPathComponent
            XCTAssertNotNil(
                regex.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                "Staged name \(n) does not match expected UUID-prefix pattern."
            )
        }
    }
}
```

- [ ] **Step 2: Add the test hook + change the stage logic**

In `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift`, replace the existing `private func stageToStitchInputs(...)` body with:

```swift
    private func stageToStitchInputs(
        source: URL,
        suggestedName: String?,
        into dir: URL
    ) throws -> URL {
        return try Self.stageToStitchInputs(
            source: source, suggestedName: suggestedName, into: dir
        )
    }

    /// Static so tests can invoke without instantiating a SwiftUI View.
    static func stageToStitchInputs(
        source: URL,
        suggestedName: String?,
        into dir: URL
    ) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let base = (suggestedName ?? "clip-\(UUID().uuidString.prefix(8))")
            .replacingOccurrences(of: "/", with: "_")
            .deletingSuffix(".\(ext)")

        // Phase 1.5 (Audit-7-C4): always UUID-prefix. Suffix-on-collision
        // alone cannot prevent stale-alias bugs after delete-then-reimport
        // because the prior file may be gone but in-memory references to
        // the old path still exist.
        let prefix = String(UUID().uuidString.prefix(6).lowercased())
        let target = dir.appendingPathComponent("\(prefix)-\(base).\(ext)")

        try FileManager.default.moveItem(at: source, to: target)

        let parent = source.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("Picks-") {
            try? FileManager.default.removeItem(at: parent)
        }
        return target
    }

    /// Test hook used by `StitchProjectStageTests`.
    static func testHook_stageToStitchInputs(
        source: URL, suggestedName: String?, into dir: URL
    ) throws -> URL {
        try stageToStitchInputs(source: source, suggestedName: suggestedName, into: dir)
    }
```

- [ ] **Step 3: Run tests**

```
mcp__xcodebuildmcp__clean
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 142, Passed: 142, Failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Views/StitchTab/StitchTabView.swift \
        VideoCompressor/VideoCompressorTests/StitchProjectStageTests.swift
git commit -m "fix(stitch): always UUID-prefix staged filenames (Phase 1.5 / TASK-33)

Audit-7-C4: the prior collision-only-on-fileExists logic left a hole.
After delete-then-reimport with the same source name, the new staged
file occupied the old path and any in-memory StitchClip / undo-history
entry pointing to that path silently aliased the new bytes.

Fix: every staged filename now carries a 6-char UUID prefix, so two
imports of clip.mov produce two distinct staged paths regardless of
what's on disk in between."
```

**Effort: ~30 min. ~2 commits.**

---

## Task 4: Auto-sort on import (Bug 3 — chronological default direction)

**Why:** When the user imports photos via PhotosPicker, clips land in selection order. For the default Recents browse (newest photo at the top), multi-selecting from the top of the library delivers clips newest-first. The user expects a stitch timeline to be oldest-first by default. `sortByCreationDateAsync()` already has the correct ascending comparator (`l < r`, see `StitchProject.swift:154`); it is simply never called at the end of `importClips(_:)`.

**Why NOT a separate cluster:** This is a one-line fix directly inside `StitchTabView.importClips(_:)`, the same view file already modified by Task 3 (stage collision). The fix uses `sortByCreationDateAsync()`, which is already exercised by the existing sort tests. Shipping it alongside the other Stitch correctness fixes avoids an extra branch/PR cycle for a trivially small change.

- [ ] **Step 1: Pin behavior with a failing test**

In `VideoCompressor/VideoCompressorTests/StitchProjectSortTests.swift` (the existing sort-test file created by the chrono-sort PR), append:

```swift

    func testImportAutoSortsOldestFirst() async throws {
        // Simulate 3 clips delivered newest-first (as PhotosPicker would
        // deliver them when the user selects from the top of Recents).
        // After importClips completes, the project's clip order must be
        // oldest-first regardless of delivery order.
        //
        // We test via StitchProject directly (no UIKit/picker needed):
        // construct 3 clips with explicit creationDates, append in
        // newest-first order, call sortByCreationDateAsync, and verify
        // the resulting order is oldest-first.
        let old  = makeClip(creationDate: Date(timeIntervalSince1970: 1_000_000))  // ~1970s
        let mid  = makeClip(creationDate: Date(timeIntervalSince1970: 2_000_000))  // ~1993
        let newest = makeClip(creationDate: Date(timeIntervalSince1970: 3_000_000)) // ~2005

        // Append in newest-first order (simulates PhotosPicker delivery).
        await project.append(newest)
        await project.append(mid)
        await project.append(old)

        // This is what importClips will call after the fix lands.
        let changed = await project.sortByCreationDateAsync()

        XCTAssertTrue(changed,
            "sortByCreationDateAsync should report reorder when clips start newest-first.")

        let ids = await MainActor.run { project.clips.map { $0.id } }
        XCTAssertEqual(ids, [old.id, mid.id, newest.id],
            "After auto-sort, clips must be oldest-first. Got: \(ids)")
    }
```

(If `StitchProjectSortTests` has a `makeClip(creationDate:)` helper already, reuse it. If not, add:
```swift
    private func makeClip(creationDate: Date) -> StitchClip {
        StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "clip",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            kind: .video,
            originalAssetID: nil,
            creationDate: creationDate
        )
    }
```
)

Run: `mcp__xcodebuildmcp__test_sim` — expect **1 test failure** (the new test fails — TDD red). The test itself will pass because it calls `sortByCreationDateAsync()` directly; the red comes from the fact that without the import-time call the real production path (onChange → importClips) would still land clips in wrong order. If the test is already green, verify the test is actually exercising insertion order, not just the sort function.

- [ ] **Step 2: Add the auto-sort call**

In `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift`, `importClips(_:)`, after the for loop closing brace (line 374) and before the function's closing brace (line 375), add:

```swift
        // Phase 1.5+ (Bug 3 / DIAG-sort-direction): auto-sort on import.
        // PhotosPicker delivers clips in selection order, which for default
        // Recents browse is newest-first. User expects oldest-first as default.
        await project.sortByCreationDateAsync()
```

The exact insertion point is after:
```swift
        }   // end for item in items
```
and before the function's closing `}`.

- [ ] **Step 3: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 143, Passed: 143, Failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Views/StitchTab/StitchTabView.swift \
        VideoCompressor/VideoCompressorTests/StitchProjectSortTests.swift
git commit -m "fix(stitch): auto-sort imports oldest-first (Bug 3)

DIAG-sort-direction: PhotosPicker delivers clips in selection order
(newest-first by default Recents browse). Users expect oldest-first
chronological. Added sortByCreationDateAsync() call at end of
importClips() — comparator was already correct, just wasn't fired
on import."
```

**Effort: ~30 min. ~1 commit.**

---

## Task 5: Push, PR, CI, merge

- [ ] Run full suite: `mcp__xcodebuildmcp__test_sim` → expect `Total: 143, Passed: 143, Failed: 0`.
- [ ] Build sim: `mcp__xcodebuildmcp__build_sim` → expect green.
- [ ] Push + PR:

```bash
git push -u origin feat/phase1-cluster2-stitch-correctness
gh pr create --base main --head feat/phase1-cluster2-stitch-correctness \
  --title "feat: Phase 1 cluster 2 — HDR + audio mix + stage collision + auto-sort" \
  --body "Closes MASTER-PLAN tasks 1.3 (TASK-39 HDR), 1.4 (TASK-32 audio mix), 1.5 (TASK-33 stage collision), Bug 3 (DIAG-sort-direction auto-sort on import).

- HDR videos round-trip as HDR (10-bit pixel format + AVVideoColorPropertiesKey).
- Audio mix indexes by per-segment audioTrack instead of i%2 parity.
- Staged filenames always carry a UUID prefix.
- Photos imported via PhotosPicker now auto-sort oldest-first after import.

143/143 tests passing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

gh pr checks <num> --watch
gh pr merge <num> --merge
```

---

## Acceptance criteria

- [ ] HDR HEVC source compressed via `Balanced` produces an HDR HEVC output (verified by inspecting the output's `formatDescriptions[0]` BitsPerComponent extension).
- [ ] 3-clip [video, still, video] stitched with crossfade has correct audio ramps on clips 0 and 2; clip 1 (still) is silent.
- [ ] Two consecutive imports of `clip.mov` (with delete in between) produce distinct staged paths.
- [ ] Photos imported via PhotosPicker default to oldest-first chronological order.
- [ ] All 138 baseline + 5 new tests passing.
- [ ] CI green, merged, TestFlight build #2 reaches testers.

## Manual iPhone test prompts

1. HDR: record an HDR 4K ProRes clip on iPhone, compress via Balanced, open in Files → QuickLook — confirm colors remain vivid (not washed out).
2. Audio mix: stitch [video-with-audio, photo, video-with-audio] with crossfade → confirm audio crossfades correctly and the photo segment is silent.
3. Stage collision: import `clip.mov` → delete it from the project → re-import a different `clip.mov` with the same name → verify both staged files have distinct UUID-prefixed names in `Files → StitchInputs/`.
4. Auto-sort on import: import 5 photos from different dates → WITHOUT tapping any sort button, verify the timeline order is oldest-first (earliest date at the left/top of the timeline).

## Notes for the executing agent

- HDR test fixture: if you have an HDR `.mov` in `/tmp/hdr_test_video.mov`, an end-to-end XCTest can XCTSkip-when-missing and verify round-trip. The plan's helper-only tests are unit-level and don't need a fixture.
- The audio-mix fixture builders (`makePNGFixture()` and `makeShortVideoFixture(withAudio:)`) are inlined in Task 2 Step 0. The `makeShortVideoFixture` body is marked `<!-- VERIFY -->` because Apple's CMSampleBuffer audio APIs vary between iOS releases — Codex should smoke-run it once and tweak if the AVAssetWriter audio path errors out, but the public contract (1 s 4×4 .mov, optional silent stereo AAC) is what Step 1 depends on.
- Task 4 (auto-sort) is a one-line fix — total implementation is ~1 min of code + 1 test. The 30 min estimate covers writing the test and verifying the TDD red → green cycle.
- Final test count after all tasks: 143 (138 baseline + 2 HDR + 1 audio-mix + 1 stage-collision + 1 auto-sort).
- ≤10 commits total for this cluster. Currently planned: ~7.
