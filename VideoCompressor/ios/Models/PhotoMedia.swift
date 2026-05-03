//
//  PhotoMedia.swift
//  VideoCompressor
//
//  Photos as first-class media. Mirrors the shape of `CompressionSettings`
//  but for stills (HEIC / JPEG / PNG). The compress/MetaClean pipelines
//  branch on `MediaKind` to dispatch to either the AVAssetWriter video path
//  or the ImageIO photo path.
//
//  Phase 3 commit 5 (2026-05-03). User direction:
//  > "i want photos to be a native feature of the app, compressing them
//  > (without reducing quality), and stitching. as well as removing stupid
//  > meta meta data sinc ethey take ownership of those photos too"
//
//  Live Photos note: when iOS Photos sync delivers a Live Photo via
//  `PhotosPicker(matching: .images)`, only the still HEIC component is
//  imported. The accompanying motion `.mov` sidecar is intentionally
//  ignored — v1 treats Live Photos as plain stills. Full Live Photo
//  preservation (writing both halves back) is a Phase 4 follow-up.
//

import Foundation
import UniformTypeIdentifiers

/// What kind of media a `VideoFile` (or imported clip) actually is.
/// `VideoFile` originally only modelled video; this enum lets us reuse the
/// same row/list infrastructure for stills without duplicating UI state.
enum MediaKind: String, Hashable, Sendable {
    case video
    case still
}

/// Image container format we read or write. Detection is by extension —
/// CGImageSource sniffs by content-type but we want a synchronous answer
/// at picker-import time before we open the file.
enum PhotoFormat: String, Hashable, Sendable, CaseIterable {
    case heic
    case jpeg
    case png

    /// Detect from the URL's path extension. Returns nil for unknown extensions
    /// (which the picker shouldn't deliver under `.images` filter, but defensive
    /// against arbitrary file paths from a future Share Extension).
    static func detect(from url: URL) -> PhotoFormat? {
        switch url.pathExtension.lowercased() {
        case "heic", "heif":   return .heic
        case "jpg", "jpeg":    return .jpeg
        case "png":            return .png
        default:               return nil
        }
    }

    /// UTType used by `CGImageDestination`. HEIC requires iOS 11+; on
    /// every modern iPhone target this is always present.
    var utType: UTType {
        switch self {
        case .heic: return .heic
        case .jpeg: return .jpeg
        case .png:  return .png
        }
    }

    /// File extension used when constructing output URLs.
    var fileExtension: String {
        switch self {
        case .heic: return "heic"
        case .jpeg: return "jpg"
        case .png:  return "png"
        }
    }
}

/// Photo equivalent of `CompressionSettings`. A (quality × maxDimension ×
/// outputFormat) triple. Static factories mirror the four named video presets
/// so the UI flows identically on the still side.
///
/// Quality semantics: `quality` maps directly to
/// `kCGImageDestinationLossyCompressionQuality`. 1.0 = visually lossless,
/// 0.92 = HEIC default (negligible perceptual difference from source),
/// 0.80 = streaming-grade.
///
/// `maxDimension` clamps the LONG edge in pixels; preserves aspect ratio.
/// `nil` = source resolution.
struct PhotoCompressionSettings: Hashable, Sendable, Identifiable {
    let quality: Double
    let maxDimension: Int?
    let outputFormat: PhotoFormat

    var id: String {
        let dim = maxDimension.map(String.init) ?? "src"
        return "q\(Int((quality * 100).rounded()))-d\(dim)-\(outputFormat.rawValue)"
    }

    // MARK: - Phase 1 photo presets
    //
    // The four named presets parallel the video Compress flow:
    //   .lossless  : HEIC, 1.0, source resolution. Re-encode but quality
    //                ceiling. Useful for JPEG → HEIC conversion at full
    //                fidelity.
    //   .balanced  : HEIC, 0.92, source. Default. ~50% smaller than JPEG
    //                at perceptually identical quality.
    //   .small     : HEIC, 0.85, 8 MP cap. Reasonable for sharing.
    //   .streaming : HEIC, 0.80, 5 MP cap. Web/chat-friendly.

    static let lossless = PhotoCompressionSettings(
        quality: 1.0,
        maxDimension: nil,
        outputFormat: .heic
    )

    static let balanced = PhotoCompressionSettings(
        quality: 0.92,
        maxDimension: nil,
        outputFormat: .heic
    )

    /// 8 MP cap = sqrt(8_000_000) ≈ 2828 long-edge for 1:1; a 4:3 photo
    /// ends up about 3266×2449 (~8.0 MP). Pick 3264 as a clean number near
    /// the iPhone 12 sensor's 4032 long-edge truncation.
    static let small = PhotoCompressionSettings(
        quality: 0.85,
        maxDimension: 3264,
        outputFormat: .heic
    )

    /// 5 MP cap ≈ 2560 long edge; matches the iOS Mail "Medium" attachment
    /// size and most chat-app upload limits.
    static let streaming = PhotoCompressionSettings(
        quality: 0.80,
        maxDimension: 2560,
        outputFormat: .heic
    )

    static let phase1Presets: [PhotoCompressionSettings] = [
        .lossless, .balanced, .small, .streaming,
    ]

    /// Filename suffix appended before the extension. Mirrors video's `_BAL`
    /// shape so users can tell at a glance which preset produced an output.
    var outputSuffix: String {
        switch (quality, maxDimension, outputFormat) {
        case (1.0, nil, .heic):  return "_MAX"
        case (0.92, nil, .heic): return "_BAL"
        case (0.85, 3264?, .heic): return "_SM"
        case (0.80, 2560?, .heic): return "_WEB"
        default:
            let dim = maxDimension.map { "\($0)" } ?? "src"
            return "_Q\(Int((quality * 100).rounded()))_\(dim)"
        }
    }

    var displayName: String {
        switch (quality, maxDimension, outputFormat) {
        case (1.0, nil, .heic):    return "Lossless"
        case (0.92, nil, .heic):   return "Balanced"
        case (0.85, 3264?, .heic): return "Small"
        case (0.80, 2560?, .heic): return "Streaming"
        default:
            let dim = maxDimension.map { "\($0)px" } ?? "Source"
            return "Q\(Int((quality * 100).rounded())) · \(dim)"
        }
    }

    var subtitle: String {
        switch (quality, maxDimension, outputFormat) {
        case (1.0, nil, .heic):    return "Visually lossless. Largest file."
        case (0.92, nil, .heic):   return "Source resolution, HEIC. Great default."
        case (0.85, 3264?, .heic): return "8 MP cap. Smaller, still print-sharp."
        case (0.80, 2560?, .heic): return "5 MP cap. Web / chat-friendly."
        default:                   return "Custom photo settings."
        }
    }

    var symbolName: String {
        switch (quality, maxDimension, outputFormat) {
        case (1.0, nil, .heic):    return "sparkles"
        case (0.92, nil, .heic):   return "scalemass"
        case (0.85, 3264?, .heic): return "arrow.down.right.and.arrow.up.left"
        case (0.80, 2560?, .heic): return "globe"
        default:                   return "gear"
        }
    }
}
