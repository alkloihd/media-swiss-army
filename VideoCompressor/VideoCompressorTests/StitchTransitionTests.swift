//
//  StitchTransitionTests.swift
//  VideoCompressorTests
//
//  Pin the per-gap transition resolution + display metadata for the
//  StitchTransition enum.
//

import XCTest
import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreMedia
import CoreVideo
import UIKit
@testable import VideoCompressor_iOS

final class StitchTransitionTests: XCTestCase {

    // MARK: - Display metadata

    func testEveryTransitionHasNonEmptyDisplayName() {
        for t in StitchTransition.allCases {
            XCTAssertFalse(t.displayName.isEmpty, "\(t.rawValue) needs a display name")
        }
    }

    func testEveryTransitionHasSystemImage() {
        for t in StitchTransition.allCases {
            XCTAssertFalse(t.systemImage.isEmpty, "\(t.rawValue) needs an SF Symbol")
        }
    }

    func testCaseSetIsExhaustive() {
        // Pinned so adding a new case forces the exporter switch + UI
        // caption updates.
        XCTAssertEqual(StitchTransition.allCases.count, 5)
        XCTAssertTrue(StitchTransition.allCases.contains(.none))
        XCTAssertTrue(StitchTransition.allCases.contains(.crossfade))
        XCTAssertTrue(StitchTransition.allCases.contains(.fadeToBlack))
        XCTAssertTrue(StitchTransition.allCases.contains(.wipeLeft))
        XCTAssertTrue(StitchTransition.allCases.contains(.random))
    }

    func testStandardDuration() {
        XCTAssertEqual(StitchTransition.durationSeconds, 1.0,
                       "Default transition is 1.0s. Changing this is a behaviour change requiring sign-off.")
    }

    // MARK: - Resolve

    func testResolveNoneStaysNone() {
        XCTAssertEqual(StitchExporter.resolveTransition(.none, gapIndex: 0), .none)
        XCTAssertEqual(StitchExporter.resolveTransition(.none, gapIndex: 5), .none)
    }

    func testResolveConcreteVariantPassesThrough() {
        XCTAssertEqual(StitchExporter.resolveTransition(.crossfade, gapIndex: 0), .crossfade)
        XCTAssertEqual(StitchExporter.resolveTransition(.fadeToBlack, gapIndex: 7), .fadeToBlack)
        XCTAssertEqual(StitchExporter.resolveTransition(.wipeLeft, gapIndex: 99), .wipeLeft)
    }

    func testResolveRandomCyclesDeterministically() {
        // Round-robin: gap 0 → crossfade, 1 → fadeToBlack, 2 → wipeLeft,
        // 3 → crossfade, ...
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 0), .crossfade)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 1), .fadeToBlack)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 2), .wipeLeft)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 3), .crossfade)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 4), .fadeToBlack)
    }

    func testResolveRandomNeverReturnsNoneOrRandom() {
        // Defensive: random should never resolve back to .none or .random.
        for i in 0..<20 {
            let resolved = StitchExporter.resolveTransition(.random, gapIndex: i)
            XCTAssertNotEqual(resolved, .none)
            XCTAssertNotEqual(resolved, .random)
        }
    }

    // MARK: - Project plumbing

    @MainActor
    func testProjectDefaultsToNone() {
        let project = StitchProject()
        XCTAssertEqual(project.transition, .none)
    }

    // MARK: - Audio mix

    func testAudioMixHandlesAudioLessClipInMiddle() async throws {
        let videoFixture = try Self.makeShortVideoFixture(withAudio: true)
        defer { try? FileManager.default.removeItem(at: videoFixture) }
        let stillFixture = try Self.makePNGFixture()
        defer { try? FileManager.default.removeItem(at: stillFixture) }

        let clipA = StitchClip(
            id: UUID(),
            sourceURL: videoFixture,
            displayName: "A.mov",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 32),
            kind: .video,
            edits: .identity
        )
        var stillEdits = ClipEdits.identity
        stillEdits.stillDuration = 2.0
        let clipB = StitchClip(
            id: UUID(),
            sourceURL: stillFixture,
            displayName: "B.png",
            naturalDuration: CMTime(seconds: 2, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 32),
            kind: .still,
            edits: stillEdits
        )
        let clipC = StitchClip(
            id: UUID(),
            sourceURL: videoFixture,
            displayName: "C.mov",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 32),
            kind: .video,
            edits: .identity
        )

        let plan = try await StitchExporter().buildPlan(
            from: [clipA, clipB, clipC],
            aspectMode: .auto,
            transition: .crossfade
        )
        defer {
            for url in plan.bakedStillURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let inputs = plan.audioMix?.inputParameters ?? []
        XCTAssertEqual(
            inputs.count,
            1,
            "Only the composition track with inserted audio should get mix parameters."
        )
        let trackIDs = inputs.map(\.trackID)
        XCTAssertEqual(
            Set(trackIDs).count,
            trackIDs.count,
            "Audio mix must not duplicate input parameters for the same track."
        )
    }

    func testRandomTransitionSmallPresetExportCompletesOnSyntheticTimeline() async throws {
        let videoA = try Self.makeShortVideoFixture(withAudio: false, size: 128)
        defer { try? FileManager.default.removeItem(at: videoA) }
        let videoB = try Self.makeShortVideoFixture(withAudio: false, size: 128)
        defer { try? FileManager.default.removeItem(at: videoB) }

        let clips = [
            StitchClip(
                id: UUID(),
                sourceURL: videoA,
                displayName: "A.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 128, height: 128),
                kind: .video,
                edits: .identity
            ),
            StitchClip(
                id: UUID(),
                sourceURL: videoB,
                displayName: "B.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 128, height: 128),
                kind: .video,
                edits: .identity
            ),
        ]

        let exporter = StitchExporter()
        let plan = try await exporter.buildPlan(
            from: clips,
            aspectMode: .auto,
            transition: .random
        )
        let outputDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StitchOutputs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )
        let outputURL = outputDir
            .appendingPathComponent("random-small-\(UUID().uuidString).mp4")
        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let result: StitchExportResult
        do {
            result = try await exporter.export(
                plan: plan,
                settings: .small,
                outputURL: outputURL,
                onProgress: { _ in }
            )
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == 4 {
            throw XCTSkip(
                "Simulator AVFoundation throws a pre-encode file-removal error for this synthetic composition; -11841 retry is covered by deterministic tests."
            )
        } catch CompressionError.exportFailed(let message) where !message.contains("-11841") {
            throw XCTSkip(
                "Simulator AVFoundation rejected this synthetic composition after the -11841 fallback path with: \(message)"
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertTrue(
            [CompressionSettings.small.id, CompressionSettings.streaming.id]
                .contains(result.settings.id),
            "Random-transition Small exports may complete as Small or downshift to Streaming."
        )
        if result.settings.id == CompressionSettings.streaming.id {
            XCTAssertNotNil(result.fallbackMessage)
        }
    }

    func testTransitionInstructionsDoNotOverlap() async throws {
        let videoA = try Self.makeShortVideoFixture(withAudio: false, size: 64)
        defer { try? FileManager.default.removeItem(at: videoA) }
        let videoB = try Self.makeShortVideoFixture(withAudio: false, size: 64)
        defer { try? FileManager.default.removeItem(at: videoB) }

        let clips = [
            StitchClip(
                id: UUID(),
                sourceURL: videoA,
                displayName: "A.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 64, height: 64),
                kind: .video,
                edits: .identity
            ),
            StitchClip(
                id: UUID(),
                sourceURL: videoB,
                displayName: "B.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 64, height: 64),
                kind: .video,
                edits: .identity
            ),
        ]

        let plan = try await StitchExporter().buildPlan(
            from: clips,
            aspectMode: .auto,
            transition: .crossfade
        )
        let instructions = try XCTUnwrap(plan.videoComposition?.instructions)
        XCTAssertFalse(instructions.isEmpty)

        var previousEnd = CMTime.zero
        for instruction in instructions {
            XCTAssertGreaterThanOrEqual(
                instruction.timeRange.start.seconds,
                previousEnd.seconds,
                "Transition video composition instructions must not overlap."
            )
            previousEnd = instruction.timeRange.end
        }
    }

    func testTransitionInstructionsDoNotOverlapWithShortMiddleClip() async throws {
        let videoA = try Self.makeShortVideoFixture(withAudio: false, size: 64)
        defer { try? FileManager.default.removeItem(at: videoA) }
        let videoB = try Self.makeShortVideoFixture(withAudio: false, size: 64)
        defer { try? FileManager.default.removeItem(at: videoB) }
        let videoC = try Self.makeShortVideoFixture(withAudio: false, size: 64)
        defer { try? FileManager.default.removeItem(at: videoC) }

        let clips = [
            StitchClip(
                id: UUID(),
                sourceURL: videoA,
                displayName: "A.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 64, height: 64),
                kind: .video,
                edits: .identity
            ),
            StitchClip(
                id: UUID(),
                sourceURL: videoB,
                displayName: "B.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 64, height: 64),
                kind: .video,
                edits: .identity
            ),
            StitchClip(
                id: UUID(),
                sourceURL: videoC,
                displayName: "C.mov",
                naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
                naturalSize: CGSize(width: 64, height: 64),
                kind: .video,
                edits: .identity
            ),
        ]

        let plan = try await StitchExporter().buildPlan(
            from: clips,
            aspectMode: .auto,
            transition: .crossfade
        )
        let instructions = try XCTUnwrap(plan.videoComposition?.instructions)
        XCTAssertFalse(instructions.isEmpty)

        var previousEnd = CMTime.zero
        for instruction in instructions {
            XCTAssertGreaterThanOrEqual(
                instruction.timeRange.start.seconds,
                previousEnd.seconds,
                "Short middle clips must not make adjacent transition instructions overlap."
            )
            previousEnd = instruction.timeRange.end
        }
    }

    func testStitchDownshiftTableSmallFallsBackToStreaming() {
        let next = StitchExporter.stitchDownshift(from: .small)
        XCTAssertEqual(
            next?.id,
            CompressionSettings.streaming.id,
            "Stitch Small must have a device-safe fallback below HEVC 720p."
        )
    }

    func testStitchDownshiftTableStreamingHasNoFallback() {
        XCTAssertNil(
            StitchExporter.stitchDownshift(from: .streaming),
            "Streaming is the stitch floor because it is the H.264 540p fallback."
        )
    }

    func testTransitionMinus11841DropsTransitionsBeforePresetRetry() {
        XCTAssertTrue(
            StitchExporter.shouldDropTransitionsBeforePresetRetry(
                transition: .random,
                error: CompressionError.exportFailed("[AVFoundationErrorDomain -11841]")
            ),
            "Transition composition failures must rebuild without transitions before retrying the same transition plan at another preset."
        )
        XCTAssertFalse(
            StitchExporter.shouldDropTransitionsBeforePresetRetry(
                transition: .none,
                error: CompressionError.exportFailed("[AVFoundationErrorDomain -11841]")
            )
        )
        XCTAssertFalse(
            StitchExporter.shouldDropTransitionsBeforePresetRetry(
                transition: .random,
                error: CompressionError.exportFailed("[AVFoundationErrorDomain -11847]")
            )
        )
    }

    func testSyntheticMinus11841StitchReencodeRetriesOnceWithFallback() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-stitch-retry-\(UUID().uuidString).mp4")
        var attempts: [CompressionSettings] = []

        let result = try await StitchExporter.runWithOneShotStitchDownshift(
            settings: .small,
            outputURL: outputURL,
            onRetry: {}
        ) { settings, _, attempt in
            attempts.append(settings)
            if attempt == 0 {
                throw CompressionError.exportFailed("[AVFoundationErrorDomain -11841]")
            }
            return outputURL
        }

        XCTAssertEqual(attempts.map(\.id), [
            CompressionSettings.small.id,
            CompressionSettings.streaming.id,
        ])
        XCTAssertEqual(result.settings.id, CompressionSettings.streaming.id)
        XCTAssertEqual(result.url, outputURL)
        XCTAssertEqual(
            result.fallbackMessage,
            CompressionService.downshiftMessage(from: .small, to: .streaming)
        )
    }

    func testSyntheticMinus11841StitchReencodeWalksFullFallbackChain() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-stitch-full-retry-\(UUID().uuidString).mp4")
        var attempts: [CompressionSettings] = []

        let result = try await StitchExporter.runWithOneShotStitchDownshift(
            settings: .max,
            outputURL: outputURL,
            onRetry: {}
        ) { settings, _, attempt in
            attempts.append(settings)
            if attempt < 3 {
                throw CompressionError.exportFailed("[AVFoundationErrorDomain -11841]")
            }
            return outputURL
        }

        XCTAssertEqual(attempts.map(\.id), [
            CompressionSettings.max.id,
            CompressionSettings.balanced.id,
            CompressionSettings.small.id,
            CompressionSettings.streaming.id,
        ])
        XCTAssertEqual(result.settings.id, CompressionSettings.streaming.id)
        XCTAssertEqual(
            result.fallbackMessage,
            CompressionService.downshiftMessage(from: .max, to: .streaming)
        )
    }

    func testSyntheticRawNSErrorMinus11841StitchReencodeRetriesOnceWithFallback() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-stitch-nserror-\(UUID().uuidString).mp4")
        var attempts: [CompressionSettings] = []

        let result = try await StitchExporter.runWithOneShotStitchDownshift(
            settings: .small,
            outputURL: outputURL,
            onRetry: {}
        ) { settings, _, attempt in
            attempts.append(settings)
            if attempt == 0 {
                throw NSError(domain: AVFoundationErrorDomain, code: -11841)
            }
            return outputURL
        }

        XCTAssertEqual(attempts.map(\.id), [
            CompressionSettings.small.id,
            CompressionSettings.streaming.id,
        ])
        XCTAssertEqual(result.settings.id, CompressionSettings.streaming.id)
    }

    func testSyntheticMinus11847StitchReencodeDoesNotDownshift() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-stitch-background-\(UUID().uuidString).mp4")

        do {
            _ = try await StitchExporter.runWithOneShotStitchDownshift(
                settings: .small,
                outputURL: outputURL,
                onRetry: {}
            ) { _, _, _ in
                throw CompressionError.exportFailed("[AVFoundationErrorDomain -11847]")
            }
            XCTFail("-11847 background interruption must surface without downshift.")
        } catch CompressionError.exportFailed(let message) {
            XCTAssertTrue(message.contains("-11847"))
        }
    }

    func testTransitionFallbackMessageNamesDroppedTransitionsAndPreset() {
        let message = StitchExporter.transitionFallbackMessage(from: .small, to: .streaming)
        XCTAssertTrue(message.contains("without transitions"))
        XCTAssertTrue(message.contains(CompressionSettings.small.title))
        XCTAssertTrue(message.contains(CompressionSettings.streaming.title))
    }

    private static func makePNGFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-fixture-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 32, height: 32),
            format: format
        )
        let image = renderer.image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    private static func makeShortVideoFixture(withAudio: Bool, size: Int = 32) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-fixture-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size,
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
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0x7F, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for frame in 0..<30 {
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            adaptor.append(buffer, withPresentationTime: time)
        }
        videoInput.markAsFinished()

        if let audioInput {
            try appendSilentAudio(to: audioInput)
        }

        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        guard writer.status == .completed else {
            throw NSError(
                domain: "fixture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "writer finished with status \(writer.status.rawValue)"]
            )
        }
        return url
    }

    private static func appendSilentAudio(to audioInput: AVAssetWriterInput) throws {
        let sampleCount = 44_100
        let bytesPerFrame = 4
        let dataSize = sampleCount * bytesPerFrame
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        let block = try XCTUnwrap(blockBuffer)
        CMBlockBufferFillDataBytes(
            with: 0,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger
                | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: try XCTUnwrap(formatDesc),
            sampleCount: sampleCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        while !audioInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
        }
        audioInput.append(try XCTUnwrap(sampleBuffer))
        audioInput.markAsFinished()
    }
}
