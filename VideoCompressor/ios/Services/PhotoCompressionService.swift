//
//  PhotoCompressionService.swift
//  VideoCompressor
//
//  ImageIO-based encoder for stills. Mirrors the actor + async API shape of
//  `CompressionService` so `VideoLibrary.runJob` can branch on `MediaKind`
//  and call either service uniformly.
//
//  Pipeline:
//   1. Open the source via `CGImageSource`.
//   2. Read source-level properties (orientation, color profile).
//   3. If `maxDimension` is set, decode-and-clamp via
//      `CGImageSourceCreateThumbnailAtIndex` with
//      `kCGImageSourceCreateThumbnailFromImageAlways = true` —
//      ImageIO does the resampling at decode time, which is dramatically
//      faster than draw-into-CGContext re-render.
//   4. Open a `CGImageDestination` with the target UTI.
//   5. Set destination properties including
//      `kCGImageDestinationLossyCompressionQuality`.
//   6. Copy source metadata MINUS embedded thumbnails (they're stale once
//      we re-encode and balloon the file size).
//   7. Add the image and finalize.
//
//  Progress: photo encode is fast (~50–150 ms for a 12 MP HEIC). We emit
//  three milestones (0.0, 0.5, 1.0) — fine-grained polling would be more
//  bookkeeping than the user can perceive.
//
//  Phase 3 commit 5 (2026-05-03).
//

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum PhotoCompressionError: Error, LocalizedError, Hashable, Sendable {
    case sourceUnreadable(String)
    case noImage
    case destinationFailed(String)
    case writeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceUnreadable(let m): return "Could not read photo: \(m)"
        case .noImage:                 return "Source has no decodable image."
        case .destinationFailed(let m): return "Could not create output: \(m)"
        case .writeFailed(let m):      return "Failed to write photo: \(m)"
        case .cancelled:               return "Photo compression was cancelled."
        }
    }
}

actor PhotoCompressionService {

    /// Compress a still image. Returns the URL of the encoded output. The
    /// caller (`VideoLibrary.runJob`) reads its size off disk and runs the
    /// auto-fingerprint-strip pass after.
    ///
    /// `onProgress` fires at three milestones (0.0 → 0.5 → 1.0) on the main
    /// actor, matching the `CompressionService` contract so views can use a
    /// single `BoundedProgress` state for both kinds.
    func compress(
        input: URL,
        settings: PhotoCompressionSettings,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {
        await MainActor.run { onProgress(BoundedProgress(0.0)) }
        try Task.checkCancellation()

        // 1. Open source.
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw PhotoCompressionError.sourceUnreadable("CGImageSourceCreateWithURL returned nil")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw PhotoCompressionError.noImage
        }

        // 2. Source properties (orientation, color, dimensions, etc).
        // CGImageSourceCopyPropertiesAtIndex is synchronous file IO; fast
        // for HEIC/JPEG headers (<5 ms typical).
        let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] ?? [:]

        // 3. Decode the image, optionally clamping the long edge.
        // `kCGImageSourceCreateThumbnailFromImageAlways = true` forces ImageIO
        // to actually decode the full image and downsample, rather than
        // returning a bundled-but-tiny preview JPEG when the source is a HEIC
        // with a 320×240 thumb sidecar.
        let cgImage: CGImage
        if let maxDim = settings.maxDimension {
            var thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDim,
            ]
            // Don't set thumbOpts[shouldCache]; default is fine.
            _ = thumbOpts // silence unused-key warning if any future change
            guard let img = CGImageSourceCreateThumbnailAtIndex(
                source, 0, thumbOpts as CFDictionary
            ) else {
                throw PhotoCompressionError.noImage
            }
            cgImage = img
        } else {
            // Full-resolution decode.
            guard let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw PhotoCompressionError.noImage
            }
            cgImage = img
        }

        try Task.checkCancellation()
        await MainActor.run { onProgress(BoundedProgress(0.5)) }

        // 4. Build output URL (caller doesn't supply one, mirroring the photo
        // compress flow's file-naming convention; the `_BAL.heic` etc. suffix
        // comes from the settings).
        let outputURL = Self.outputURL(for: input, settings: settings)
        try? FileManager.default.removeItem(at: outputURL)

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            settings.outputFormat.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoCompressionError.destinationFailed(
                "CGImageDestinationCreateWithURL nil for \(settings.outputFormat.fileExtension)"
            )
        }

        // 5. Build the per-image properties dict that will accompany the image.
        // We start from source props (preserving EXIF/TIFF/GPS/MakerApple) and
        // strip the embedded thumbnail dictionary — once we re-encode, that
        // tiny preview JPEG is stale and inflates output size.
        var imageProps = sourceProps
        // Remove any embedded thumbnail-sidecar dictionaries. CG_IMAGE
        // doesn't write these by default unless we ask, but some HEIC sources
        // can carry them in the auxiliary properties.
        imageProps.removeValue(forKey: kCGImagePropertyExifAuxDictionary)
        imageProps.removeValue(forKey: kCGImagePropertyJFIFDictionary)
        // Set lossy compression quality. PNG ignores this (lossless); HEIC
        // and JPEG honor it directly.
        imageProps[kCGImageDestinationLossyCompressionQuality] = settings.quality

        CGImageDestinationAddImage(dest, cgImage, imageProps as CFDictionary)

        try Task.checkCancellation()

        guard CGImageDestinationFinalize(dest) else {
            throw PhotoCompressionError.writeFailed(
                "CGImageDestinationFinalize returned false"
            )
        }

        await MainActor.run { onProgress(BoundedProgress(1.0)) }
        return outputURL
    }

    /// Output path: same parent as `CompressionService` (Documents/Outputs)
    /// so the cache sweeper picks it up under the existing rules.
    static func outputURL(for source: URL, settings: PhotoCompressionSettings) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent(
            "\(stem)\(settings.outputSuffix).\(settings.outputFormat.fileExtension)"
        )
    }
}
