//
//  ThumbnailStripGenerator.swift
//  VideoCompressor
//
//  Generates evenly-spaced thumbnails across a video's natural duration.
//  Used by `ClipBlockView` to render a 4-frame strip per clip on the
//  Stitch timeline.
//

import Foundation
import AVFoundation
import UIKit
import CoreGraphics

/// Generates evenly-spaced thumbnails across a video's natural duration.
/// Used by `ClipBlockView` to render a 4-frame strip per clip on the
/// Stitch timeline.
actor ThumbnailStripGenerator {
    enum ThumbnailError: Error, LocalizedError, Hashable, Sendable {
        case assetLoadFailed(String)
        case noFramesGenerated

        var errorDescription: String? {
            switch self {
            case .assetLoadFailed(let m): return "Could not load video for thumbnail: \(m)"
            case .noFramesGenerated:      return "No thumbnails could be generated."
            }
        }
    }

    /// Returns evenly-spaced thumbnails as `UIImage`s. The async sequence
    /// can yield failures for individual frames near keyframe boundaries —
    /// we log and continue, returning whatever frames succeeded. If zero
    /// frames succeed, throws `noFramesGenerated`.
    func generate(
        for url: URL,
        count: Int,
        maxDimension: CGFloat
    ) async throws -> [UIImage] {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw ThumbnailError.assetLoadFailed(error.localizedDescription)
        }

        let total = CMTimeGetSeconds(duration)
        guard total.isFinite, total > 0, count > 0 else {
            throw ThumbnailError.noFramesGenerated
        }

        // Sample at the midpoint of N evenly-spaced segments so the
        // first thumbnail isn't always the (often-black) frame 0.
        let times: [CMTime] = (0..<count).map { i in
            let pos = (Double(i) + 0.5) / Double(count)
            return CMTime(seconds: total * pos, preferredTimescale: 600)
        }

        var images: [UIImage] = []
        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: _, image: let cg, actualTime: _):
                images.append(UIImage(cgImage: cg))
            case .failure(requestedTime: _, error: _):
                // Intentionally swallow: missing thumbnails are fine;
                // ClipBlockView shows a neutral placeholder.
                break
            }
        }

        guard !images.isEmpty else { throw ThumbnailError.noFramesGenerated }
        return images
    }
}
