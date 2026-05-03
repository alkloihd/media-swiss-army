//
//  PhotoMetadataLoader.swift
//  VideoCompressor
//
//  Thin loader that fills a `VideoMetadata` for still images so the row UI
//  in `VideoListView` can show resolution + size without branching by kind.
//
//  For stills:
//     durationSeconds   = 0
//     nominalFrameRate  = 0
//     codec             = format.rawValue (e.g. "heic")
//     estimatedDataRate = 0
//     pixelWidth/Height = from CGImageSource properties
//     fileSizeBytes     = file attributes
//
//  Phase 3 commit 5 (2026-05-03).
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PhotoMetadataLoader {
    static func load(from url: URL) async throws -> VideoMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoMetadataError.fileMissing
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw VideoMetadataError.loadFailed("CGImageSourceCreateWithURL nil")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw VideoMetadataError.loadFailed("Empty image source")
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] ?? [:]

        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        let format = PhotoFormat.detect(from: url)?.rawValue ?? "image"

        let fileSize: Int64 = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }()

        return VideoMetadata(
            durationSeconds: 0,
            pixelWidth: width,
            pixelHeight: height,
            nominalFrameRate: 0,
            codec: format,
            estimatedDataRate: 0,
            fileSizeBytes: fileSize
        )
    }
}
