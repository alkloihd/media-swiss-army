//
//  CompressionSettingsTests.swift
//  VideoCompressorTests
//
//  Pins the smart-cap bitrate math + codec/dimension mapping for the
//  Phase 3 AVAssetWriter migration. Mirrors lib/ffmpeg.js:
//
//    Max:       source bitrate (no cap), no floor
//    Balanced:  min(6 Mbps, source × 0.7), floor 1 Mbps
//    Small:     min(3 Mbps, source × 0.4), floor 500 kbps
//    Streaming: min(4 Mbps, source × 0.5), floor 750 kbps
//

import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class CompressionSettingsTests: XCTestCase {

    // MARK: - bitrate(forSourceBitrate:)

    func testMaxReturnsSourceBitrate() {
        // Max preset: no cap. Output bitrate equals source.
        XCTAssertEqual(CompressionSettings.max.bitrate(forSourceBitrate: 1_000_000), 1_000_000)
        XCTAssertEqual(CompressionSettings.max.bitrate(forSourceBitrate: 6_000_000), 6_000_000)
        XCTAssertEqual(CompressionSettings.max.bitrate(forSourceBitrate: 50_000_000), 50_000_000)
    }

    func testBalancedSmartCap() {
        // Below the floor → floored to 1 Mbps.
        // Source 1 Mbps × 0.7 = 700 kbps → bumped to 1 Mbps floor.
        XCTAssertEqual(CompressionSettings.balanced.bitrate(forSourceBitrate: 1_000_000), 1_000_000)

        // Mid-range: source × 0.7 dominates.
        // 6 Mbps × 0.7 = 4.2 Mbps (less than 6 Mbps target).
        XCTAssertEqual(CompressionSettings.balanced.bitrate(forSourceBitrate: 6_000_000), 4_200_000)

        // High source: target dominates (cap at 6 Mbps).
        // 50 Mbps × 0.7 = 35 Mbps; min(6 Mbps, 35 Mbps) = 6 Mbps.
        XCTAssertEqual(CompressionSettings.balanced.bitrate(forSourceBitrate: 50_000_000), 6_000_000)
    }

    func testSmallSmartCap() {
        // 1 Mbps × 0.4 = 400 kbps → floored to 500 kbps.
        XCTAssertEqual(CompressionSettings.small.bitrate(forSourceBitrate: 1_000_000), 500_000)

        // 6 Mbps × 0.4 = 2.4 Mbps (less than 3 Mbps target).
        XCTAssertEqual(CompressionSettings.small.bitrate(forSourceBitrate: 6_000_000), 2_400_000)

        // 50 Mbps × 0.4 = 20 Mbps; min(3, 20) = 3 Mbps.
        XCTAssertEqual(CompressionSettings.small.bitrate(forSourceBitrate: 50_000_000), 3_000_000)
    }

    func testStreamingSmartCap() {
        // 1 Mbps × 0.5 = 500 kbps → floored to 750 kbps.
        XCTAssertEqual(CompressionSettings.streaming.bitrate(forSourceBitrate: 1_000_000), 750_000)

        // 6 Mbps × 0.5 = 3 Mbps (less than 4 Mbps target).
        XCTAssertEqual(CompressionSettings.streaming.bitrate(forSourceBitrate: 6_000_000), 3_000_000)

        // 50 Mbps × 0.5 = 25 Mbps; min(4, 25) = 4 Mbps.
        XCTAssertEqual(CompressionSettings.streaming.bitrate(forSourceBitrate: 50_000_000), 4_000_000)
    }

    func testZeroSourceBitrateFallsBackToTarget() {
        // Probe failure → 0. We expect the target without a source cap so we
        // still produce a reasonable output.
        XCTAssertEqual(CompressionSettings.balanced.bitrate(forSourceBitrate: 0), 6_000_000)
        XCTAssertEqual(CompressionSettings.small.bitrate(forSourceBitrate: 0), 3_000_000)
        XCTAssertEqual(CompressionSettings.streaming.bitrate(forSourceBitrate: 0), 4_000_000)
    }

    // MARK: - videoCodec

    func testVideoCodecMapping() {
        XCTAssertEqual(CompressionSettings.max.videoCodec, .hevc)
        XCTAssertEqual(CompressionSettings.balanced.videoCodec, .hevc)
        XCTAssertEqual(CompressionSettings.small.videoCodec, .hevc)
        XCTAssertEqual(CompressionSettings.streaming.videoCodec, .h264)
    }

    // MARK: - maxOutputDimension

    func testMaxOutputDimensionByResolution() {
        XCTAssertNil(CompressionSettings.max.maxOutputDimension)  // .source
        XCTAssertEqual(CompressionSettings.balanced.maxOutputDimension, 1920)  // .fhd1080
        XCTAssertEqual(CompressionSettings.small.maxOutputDimension, 1280)  // .hd720
        XCTAssertEqual(CompressionSettings.streaming.maxOutputDimension, 960)  // .sd540

        // Latent resolutions in the 2D matrix.
        let uhd = CompressionSettings(resolution: .uhd2160, quality: .high)
        XCTAssertEqual(uhd.maxOutputDimension, 3840)
        let qhd = CompressionSettings(resolution: .qhd1440, quality: .high)
        XCTAssertEqual(qhd.maxOutputDimension, 2560)
        let sd480 = CompressionSettings(resolution: .sd480, quality: .balanced)
        XCTAssertEqual(sd480.maxOutputDimension, 854)
    }

    // MARK: - optimizesForNetwork (faststart) — already covered before
    //         the migration but still part of the encode contract.

    func testStreamingOptimizesForNetwork() {
        XCTAssertTrue(CompressionSettings.streaming.optimizesForNetwork)
        XCTAssertFalse(CompressionSettings.max.optimizesForNetwork)
        XCTAssertFalse(CompressionSettings.balanced.optimizesForNetwork)
        XCTAssertFalse(CompressionSettings.small.optimizesForNetwork)
    }

    // MARK: - targetDimensions helper

    func testTargetDimensionsLandscape1080CapTo720() {
        // 1920×1080 source, cap 1280 → scale to 1280×720.
        let (w, h) = CompressionService.targetDimensions(
            for: CGSize(width: 1920, height: 1080),
            longEdgeCap: 1280
        )
        XCTAssertEqual(w, 1280)
        XCTAssertEqual(h, 720)
    }

    func testTargetDimensionsPortrait1080CapTo720() {
        // 1080×1920 portrait, cap 1280 → 720×1280.
        let (w, h) = CompressionService.targetDimensions(
            for: CGSize(width: 1080, height: 1920),
            longEdgeCap: 1280
        )
        XCTAssertEqual(w, 720)
        XCTAssertEqual(h, 1280)
    }

    func testTargetDimensionsNoCapPreservesSourceEvened() {
        // Odd-sized source → evened down.
        let (w, h) = CompressionService.targetDimensions(
            for: CGSize(width: 1921, height: 1081),
            longEdgeCap: nil
        )
        XCTAssertTrue(w.isMultiple(of: 2))
        XCTAssertTrue(h.isMultiple(of: 2))
        XCTAssertEqual(w, 1920)
        XCTAssertEqual(h, 1080)
    }

    func testTargetDimensionsSourceSmallerThanCapUnchanged() {
        // 720p source, cap 1080 → unchanged.
        let (w, h) = CompressionService.targetDimensions(
            for: CGSize(width: 1280, height: 720),
            longEdgeCap: 1920
        )
        XCTAssertEqual(w, 1280)
        XCTAssertEqual(h, 720)
    }
}
