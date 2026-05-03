//
//  CompressionEstimatorTests.swift
//  VideoCompressorTests
//
//  Pin the size-estimate math used by Phase 3 commit 9's Advanced Mode UI.
//  Drift here would mislead users into picking presets that don't actually
//  shrink their files.
//

import XCTest
@testable import VideoCompressor_iOS

final class CompressionEstimatorTests: XCTestCase {

    // MARK: - Fixtures

    private func makeVideo(
        durationSeconds: Double,
        sourceBitrate: Int64,
        fileSizeBytes: Int64? = nil,
        kind: MediaKind = .video
    ) -> VideoFile {
        let inferredSize = fileSizeBytes
            ?? Int64((Double(sourceBitrate) * durationSeconds) / 8.0)
        let metadata = VideoMetadata(
            durationSeconds: durationSeconds,
            pixelWidth: 1920,
            pixelHeight: 1080,
            nominalFrameRate: 30,
            codec: "hvc1",
            estimatedDataRate: sourceBitrate,
            fileSizeBytes: inferredSize
        )
        return VideoFile(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/test.mov"),
            displayName: "test.mov",
            importedAt: Date(),
            kind: kind,
            metadata: metadata
        )
    }

    // MARK: - Single-video estimate

    func testEstimateScalesWithDuration() {
        let video10s = makeVideo(durationSeconds: 10, sourceBitrate: 10_000_000)
        let video20s = makeVideo(durationSeconds: 20, sourceBitrate: 10_000_000)

        let est10 = CompressionEstimator.estimatedBytes(for: video10s, preset: .balanced)!
        let est20 = CompressionEstimator.estimatedBytes(for: video20s, preset: .balanced)!

        // 20s should be ~2× the 10s estimate (within 5% — audio bitrate
        // adds a small constant offset that scales linearly too).
        let ratio = Double(est20) / Double(est10)
        XCTAssertEqual(ratio, 2.0, accuracy: 0.05,
                       "Doubling duration should ~double the estimate.")
    }

    func testEstimateRespectsBalancedTargetBitrate() {
        // Source 10 Mbps; balanced caps at min(6 Mbps target, 10M × 0.7 = 7M)
        // → 6 Mbps video + 128 kbps audio = 6.128 Mbps total over 60s.
        // Expected: 6_128_000 × 60 / 8 = 45_960_000 bytes.
        let video = makeVideo(durationSeconds: 60, sourceBitrate: 10_000_000)
        let est = CompressionEstimator.estimatedBytes(for: video, preset: .balanced)!

        let expected: Int64 = 45_960_000
        let lower = Int64(Double(expected) * 0.95)
        let upper = Int64(Double(expected) * 1.05)
        XCTAssertGreaterThanOrEqual(est, lower)
        XCTAssertLessThanOrEqual(est, upper)
    }

    func testEstimateForLowBitrateSourceStaysBelowSource() {
        // Source already 2 Mbps. Balanced cap → min(target, 2M × 0.7) = 1.4M.
        // Output should be smaller than source.
        let video = makeVideo(durationSeconds: 60, sourceBitrate: 2_000_000)
        let sourceBytes = video.metadata!.fileSizeBytes
        let estimated = CompressionEstimator.estimatedBytes(for: video, preset: .balanced)!

        XCTAssertLessThan(estimated, sourceBytes,
                          "Smart-cap should produce a smaller estimate than source.")
    }

    func testEstimateNilForVideoWithoutMetadata() {
        let bare = VideoFile(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/nometa.mov"),
            displayName: "nometa.mov",
            importedAt: Date(),
            kind: .video,
            metadata: nil
        )
        XCTAssertNil(CompressionEstimator.estimatedBytes(for: bare, preset: .balanced))
    }

    func testEstimateZeroDurationIsNotNegative() {
        let zero = makeVideo(durationSeconds: 0, sourceBitrate: 10_000_000)
        let est = CompressionEstimator.estimatedBytes(for: zero, preset: .balanced)
        XCTAssertNotNil(est)
        XCTAssertGreaterThanOrEqual(est!, 0)
    }

    // MARK: - Multi-video totals

    func testTotalBytesSumsAcrossVideos() {
        let a = makeVideo(durationSeconds: 10, sourceBitrate: 10_000_000)
        let b = makeVideo(durationSeconds: 20, sourceBitrate: 10_000_000)

        let totalA = CompressionEstimator.estimatedBytes(for: a, preset: .balanced)!
        let totalB = CompressionEstimator.estimatedBytes(for: b, preset: .balanced)!
        let combined = CompressionEstimator.estimatedTotalBytes(
            for: [a, b], preset: .balanced
        )

        XCTAssertEqual(combined, totalA + totalB)
    }

    func testTotalBytesIgnoresStills() {
        let video = makeVideo(durationSeconds: 10, sourceBitrate: 10_000_000)
        let still = makeVideo(durationSeconds: 0, sourceBitrate: 0, kind: .still)

        let videoOnly = CompressionEstimator.estimatedTotalBytes(
            for: [video], preset: .balanced
        )
        let mixed = CompressionEstimator.estimatedTotalBytes(
            for: [video, still], preset: .balanced
        )
        XCTAssertEqual(videoOnly, mixed,
                       "Stills should not contribute to video-preset totals.")
    }

    func testTotalBytesEmptyArray() {
        XCTAssertEqual(
            CompressionEstimator.estimatedTotalBytes(for: [], preset: .balanced),
            0
        )
    }

    // MARK: - Source totals

    func testSourceTotalBytesSumsFileSizes() {
        let a = makeVideo(durationSeconds: 10, sourceBitrate: 10_000_000, fileSizeBytes: 1_000_000)
        let b = makeVideo(durationSeconds: 20, sourceBitrate: 10_000_000, fileSizeBytes: 2_500_000)
        let total = CompressionEstimator.sourceTotalBytes(for: [a, b])
        XCTAssertEqual(total, 3_500_000)
    }

    // MARK: - Format

    func testFormatProducesByteSuffix() {
        let label = CompressionEstimator.format(1_500_000)
        XCTAssertFalse(label.isEmpty)
        XCTAssertTrue(
            label.contains("MB") || label.contains("KB") || label.contains("B"),
            "Expected unit suffix in \(label)"
        )
    }

    // MARK: - Preset ranking

    func testStreamingPresetEstimatesSmallerThanBalanced() {
        let video = makeVideo(durationSeconds: 60, sourceBitrate: 10_000_000)
        let balanced = CompressionEstimator.estimatedBytes(for: video, preset: .balanced)!
        let streaming = CompressionEstimator.estimatedBytes(for: video, preset: .streaming)!
        XCTAssertLessThan(
            streaming, balanced,
            "Streaming (50% cap) must produce a smaller estimate than balanced (70% cap)."
        )
    }

    func testSmallPresetEstimatesSmallerThanStreaming() {
        let video = makeVideo(durationSeconds: 60, sourceBitrate: 10_000_000)
        let streaming = CompressionEstimator.estimatedBytes(for: video, preset: .streaming)!
        let small = CompressionEstimator.estimatedBytes(for: video, preset: .small)!
        XCTAssertLessThan(
            small, streaming,
            "Small (40% cap) must produce a smaller estimate than streaming (50% cap)."
        )
    }
}
