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

    /// AVAssetExportSession preset name used for the MVP. The phase 2
    /// AVAssetWriter migration will switch to bitrate-driven output.
    var avExportPresetName: String {
        // Mirror the existing CompressionPreset.avExportPresetName mapping.
        switch (resolution, quality) {
        case (.source, .lossless):   return AVAssetExportPresetHEVCHighestQuality
        case (.fhd1080, _):          return AVAssetExportPreset1920x1080
        case (.hd720, _):            return AVAssetExportPreset1280x720
        case (.sd540, _):            return AVAssetExportPreset960x540
        default:                     return AVAssetExportPresetHEVCHighestQuality
        }
    }

    var fileType: AVFileType { .mp4 }

    /// Suffix appended to the output filename, e.g. "_BAL".
    var outputSuffix: String {
        switch (resolution, quality) {
        case (.source, .lossless):   return "_MAX"
        case (.fhd1080, _):          return "_BAL"
        case (.hd720, _):            return "_SM"
        case (.sd540, _):            return "_WEB"
        default:                     return "_OUT"
        }
    }

    /// UI label shown in pickers / matrix.
    var title: String {
        switch (resolution, quality) {
        case (.source, .lossless):   return "Max Quality"
        case (.fhd1080, _):          return "Balanced"
        case (.hd720, _):            return "Small"
        case (.sd540, _):            return "Streaming"
        default:                     return "Custom"
        }
    }

    var subtitle: String {
        switch (resolution, quality) {
        case (.source, .lossless):   return "Visually lossless. Largest file."
        case (.fhd1080, _):          return "Great for sharing. Roughly half the size."
        case (.hd720, _):            return "Aggressive shrink for chat / email."
        case (.sd540, _):            return "Web-friendly with fast-start metadata."
        default:                     return ""
        }
    }

    var symbolName: String {
        switch (resolution, quality) {
        case (.source, .lossless):   return "sparkles"
        case (.fhd1080, _):          return "scalemass"
        case (.hd720, _):            return "arrow.down.right.and.arrow.up.left"
        case (.sd540, _):            return "globe"
        default:                     return "gear"
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
}

enum QualityLevel: String, Hashable, Sendable, CaseIterable {
    case lossless
    case maximum
    case high
    case balanced
    case compact
    case tiny
}
