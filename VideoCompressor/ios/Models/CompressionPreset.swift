//
//  CompressionPreset.swift
//  VideoCompressor
//
//  Mirrors the web app's preset model (Max / Balanced / Small / Streaming)
//  but maps to AVAssetExportSession built-in presets for the MVP. We can
//  switch to AVAssetWriter for full bitrate control later — the UI surface
//  stays identical.
//

import Foundation
import AVFoundation

enum CompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case max
    case balanced
    case small
    case streaming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .max:       return "Max Quality"
        case .balanced:  return "Balanced"
        case .small:     return "Small"
        case .streaming: return "Streaming"
        }
    }

    var subtitle: String {
        switch self {
        case .max:       return "Visually lossless. Largest file."
        case .balanced:  return "Great for sharing. Roughly half the size."
        case .small:     return "Aggressive shrink for chat / email."
        case .streaming: return "Web-friendly with fast-start metadata."
        }
    }

    var symbolName: String {
        switch self {
        case .max:       return "sparkles"
        case .balanced:  return "scalemass"
        case .small:     return "arrow.down.right.and.arrow.up.left"
        case .streaming: return "globe"
        }
    }

    /// AVAssetExportSession preset name used by the MVP exporter.
    /// HEVC variants chosen by default — Apple silicon Macs and any iPhone
    /// since the iPhone 7 will hardware-encode HEVC at lower bitrate than
    /// H.264 for the same quality.
    var avExportPresetName: String {
        switch self {
        case .max:       return AVAssetExportPresetHEVCHighestQuality
        case .balanced:  return AVAssetExportPreset1920x1080
        case .small:     return AVAssetExportPreset1280x720
        case .streaming: return AVAssetExportPreset960x540
        }
    }

    /// Output container. iOS 18 PhotosPicker prefers .mov for HEVC, .mp4 for
    /// H.264. Use .mp4 always for streaming so HTTP servers handle it cleanly.
    var fileType: AVFileType { .mp4 }

    /// Suffix appended to the output filename, mirroring the web app's
    /// `_COMP` convention but with the preset baked in for clarity.
    var outputSuffix: String {
        switch self {
        case .max:       return "_MAX"
        case .balanced:  return "_BAL"
        case .small:     return "_SM"
        case .streaming: return "_WEB"
        }
    }

    /// Approximate bitrate in bps used only for size-prediction UI. Matches
    /// the web app's default targets — the exporter itself uses Apple's
    /// preset internally.
    var approximateBitrateBps: Double {
        switch self {
        case .max:       return 12_000_000   // HEVC ≈ 12 Mbps
        case .balanced:  return 6_000_000    // 1080p ≈ 6 Mbps
        case .small:     return 3_000_000    // 720p ≈ 3 Mbps
        case .streaming: return 4_000_000    // 540p ≈ 4 Mbps with faststart
        }
    }
}
