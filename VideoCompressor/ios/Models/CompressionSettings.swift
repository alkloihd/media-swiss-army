//
//  CompressionSettings.swift
//  VideoCompressor
//
//  Value type replacing the flat `CompressionPreset` enum. Expresses a
//  (Resolution × QualityLevel) pair so Phase 2's 2D matrix can unlock the
//  full grid without API churn. Phase 1 ships only the four static factory
//  points; the rest of the matrix is latent.

import Foundation
import AVFoundation

struct CompressionSettings: Hashable, Sendable, Identifiable {
    let resolution: Resolution
    let quality: QualityLevel

    var id: String { "\(resolution.rawValue)-\(quality.rawValue)" }

    /// True if this settings cell should write fast-start metadata for HTTP
    /// streaming. Replaces a fragile string check on `outputSuffix`.
    var optimizesForNetwork: Bool {
        // Streaming = the dedicated SD540 cell. The 2D matrix can extend this
        // to (any resolution × .compact / .tiny) once those cells light up.
        switch (resolution, quality) {
        case (.sd540, _):  return true
        default:           return false
        }
    }

    /// AVAssetExportSession preset name used for the MVP. The phase 2
    /// AVAssetWriter migration will switch to bitrate-driven output.
    /// Unconfigured cells (any combination not yet wired to a Phase 1
    /// factory or a future matrix cell) trip a precondition in DEBUG so the
    /// developer notices before shipping a broken UI cell. In RELEASE we
    /// fall back to medium quality as a last-resort safety net.
    var avExportPresetName: String {
        switch (resolution, quality) {
        case (.source,  .lossless):  return AVAssetExportPresetHEVCHighestQuality
        case (.fhd1080, .high):      return AVAssetExportPreset1920x1080
        case (.hd720,   .balanced):  return AVAssetExportPreset1280x720
        case (.sd540,   .balanced):  return AVAssetExportPreset960x540
        default:
            assertionFailure("CompressionSettings cell (\(resolution), \(quality)) is not configured. Wire it up before exposing in UI.")
            return AVAssetExportPresetMediumQuality
        }
    }

    var fileType: AVFileType { .mp4 }

    /// Suffix appended to the output filename, e.g. "_BAL".
    var outputSuffix: String {
        switch (resolution, quality) {
        case (.source,  .lossless):  return "_MAX"
        case (.fhd1080, .high):      return "_BAL"
        case (.hd720,   .balanced):  return "_SM"
        case (.sd540,   .balanced):  return "_WEB"
        default:
            return "_R\(resolution.rawValue)_Q\(quality.rawValue)"
        }
    }

    /// UI label shown in pickers / matrix.
    var title: String {
        switch (resolution, quality) {
        case (.source,  .lossless):  return "Max Quality"
        case (.fhd1080, .high):      return "Balanced"
        case (.hd720,   .balanced):  return "Small"
        case (.sd540,   .balanced):  return "Streaming"
        default:
            return "\(resolution.displayName) · \(quality.displayName)"
        }
    }

    var subtitle: String {
        switch (resolution, quality) {
        case (.source,  .lossless):  return "Visually lossless. Largest file."
        case (.fhd1080, .high):      return "Great for sharing. Roughly half the size."
        case (.hd720,   .balanced):  return "Aggressive shrink for chat / email."
        case (.sd540,   .balanced):  return "Web-friendly with fast-start metadata."
        default:
            return "Custom matrix cell."
        }
    }

    var symbolName: String {
        switch (resolution, quality) {
        case (.source,  .lossless):  return "sparkles"
        case (.fhd1080, .high):      return "scalemass"
        case (.hd720,   .balanced):  return "arrow.down.right.and.arrow.up.left"
        case (.sd540,   .balanced):  return "globe"
        default:
            return "gear"
        }
    }

    /// Phase 1 named factories that mirror the old `CompressionPreset` enum.
    static let max       = CompressionSettings(resolution: .source,  quality: .lossless)
    static let balanced  = CompressionSettings(resolution: .fhd1080, quality: .high)
    static let small     = CompressionSettings(resolution: .hd720,   quality: .balanced)
    static let streaming = CompressionSettings(resolution: .sd540,   quality: .balanced)

    /// Same ordering the picker uses today.
    static let phase1Presets: [CompressionSettings] = [.max, .balanced, .small, .streaming]
}

enum Resolution: String, Hashable, Sendable, CaseIterable {
    case source       // keep source dimensions
    case uhd2160      // 3840
    case qhd1440      // 2560
    case fhd1080      // 1920
    case hd720        // 1280
    case sd540        // 960
    case sd480        //  854

    var displayName: String {
        switch self {
        case .source:   return "Source"
        case .uhd2160:  return "4K"
        case .qhd1440:  return "1440p"
        case .fhd1080:  return "1080p"
        case .hd720:    return "720p"
        case .sd540:    return "540p"
        case .sd480:    return "480p"
        }
    }
}

enum QualityLevel: String, Hashable, Sendable, CaseIterable {
    case lossless
    case maximum
    case high
    case balanced
    case compact
    case tiny

    var displayName: String {
        switch self {
        case .lossless: return "Lossless"
        case .maximum:  return "Maximum"
        case .high:     return "High"
        case .balanced: return "Balanced"
        case .compact:  return "Compact"
        case .tiny:     return "Tiny"
        }
    }
}
