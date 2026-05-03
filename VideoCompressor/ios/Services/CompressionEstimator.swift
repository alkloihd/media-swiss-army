//
//  CompressionEstimator.swift
//  VideoCompressor
//
//  Phase 3 commit 9 — Advanced mode size preview.
//
//  Given a CompressionSettings preset and a set of source videos (with
//  metadata), produce an estimated output byte count. Uses the same smart
//  bitrate cap math as the encoder (`CompressionSettings.bitrate(forSourceBitrate:)`)
//  so the estimate matches what the encoder will actually emit.
//
//  Caveats:
//  - HEVC at the same target bitrate produces ~30–50% smaller files than
//    H.264 at equal visual quality. We don't try to model that here — the
//    estimate is a *bitrate budget*, not a perceptual model. Real output
//    can be smaller; that's a feature, not a bug.
//  - Audio bitrate (~128 kbps for AAC) is folded in as a flat per-second cost.
//  - Stills aren't priced here — `PhotoCompressionSettings` is its own world.
//

import Foundation

enum CompressionEstimator {

    /// Estimated audio cost in bits per second. AAC at 128 kbps is the
    /// AVAssetWriter default and what we ship.
    static let audioBitsPerSecond: Int64 = 128_000

    /// Estimate the output size in bytes for a single video at a given preset.
    /// Returns nil if the video has no metadata (we don't fabricate a guess).
    static func estimatedBytes(
        for video: VideoFile,
        preset: CompressionSettings
    ) -> Int64? {
        guard let metadata = video.metadata else { return nil }
        guard metadata.durationSeconds > 0 else { return 0 }

        let videoBitrate = preset.bitrate(forSourceBitrate: metadata.estimatedDataRate)
        let totalBitrate = videoBitrate + audioBitsPerSecond

        // bits = bps × seconds; bytes = bits / 8
        let bits = Double(totalBitrate) * metadata.durationSeconds
        let bytes = Int64(bits / 8.0)

        // Safety floor: a real encoded file is at least a few KB of headers.
        return Swift.max(bytes, 4096)
    }

    /// Sum estimated output bytes across multiple videos at one preset.
    /// Videos without metadata (or stills) are skipped silently — the
    /// returned total is conservative.
    static func estimatedTotalBytes(
        for videos: [VideoFile],
        preset: CompressionSettings
    ) -> Int64 {
        var total: Int64 = 0
        for video in videos where video.kind == .video {
            if let bytes = estimatedBytes(for: video, preset: preset) {
                total += bytes
            }
        }
        return total
    }

    /// Source file size sum (for the "save XX MB" delta UI).
    static func sourceTotalBytes(for videos: [VideoFile]) -> Int64 {
        videos
            .filter { $0.kind == .video }
            .compactMap { $0.metadata?.fileSizeBytes }
            .reduce(0, +)
    }

    /// Pretty-print bytes using ByteCountFormatter, file style.
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
