//
//  VideoFile.swift
//  VideoCompressor
//
//  A video the user has imported (from PhotosPicker or Files). Holds the
//  source URL, derived metadata, and whatever the in-flight compression job
//  has produced so far.
//

import Foundation
import AVFoundation

/// Tracks whether this video's output has been saved to Photos.
enum SaveStatus: Hashable, Sendable {
    case unsaved
    case saving
    case saved
    case saveFailed(reason: String)
}

struct VideoFile: Identifiable, Hashable, Sendable {
    let id: UUID
    /// On-disk URL inside the app's tmp/import directory. PhotosPicker hands
    /// us scoped URLs that vanish on scope exit, so we copy into our own tmp
    /// before constructing this struct.
    let sourceURL: URL
    let displayName: String
    let importedAt: Date
    /// What kind of media this is. Defaults to `.video` for source-compat
    /// with all existing call sites; the still-image import path passes
    /// `.still` explicitly. See PhotoMedia.swift.
    ///
    /// `metadata` and `output` cover both kinds — for stills the metadata
    /// holder reports `pixelWidth/Height` from CGImageSource, with
    /// `durationSeconds = 0` and `nominalFrameRate = 0`.
    let kind: MediaKind

    var metadata: VideoMetadata?
    var jobState: CompressionJobState
    /// Cohesive output payload — set together when compression finishes.
    /// Replaces the former `outputURL: URL?` + `outputBytes: Int64?` pair.
    var output: CompressedOutput?
    /// Per-row Photos save state — drives the save icon in VideoRowView.
    var saveStatus: SaveStatus = .unsaved

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        displayName: String,
        importedAt: Date = Date(),
        kind: MediaKind = .video,
        metadata: VideoMetadata? = nil,
        jobState: CompressionJobState = .idle,
        output: CompressedOutput? = nil,
        saveStatus: SaveStatus = .unsaved
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.importedAt = importedAt
        self.kind = kind
        self.metadata = metadata
        self.jobState = jobState
        self.output = output
        self.saveStatus = saveStatus
    }
}

struct VideoMetadata: Hashable, Sendable {
    let durationSeconds: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let nominalFrameRate: Float
    let codec: String          // e.g. "hvc1", "avc1"
    let estimatedDataRate: Int64  // bits per second (was Float; Float loses precision past 16.7 Mbps)
    let fileSizeBytes: Int64

    var resolutionLabel: String {
        "\(pixelWidth)×\(pixelHeight)"
    }

    var durationLabel: String {
        let total = Int(durationSeconds.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var bitrateLabel: String {
        let mbps = Double(estimatedDataRate) / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

enum CompressionJobState: Hashable, Sendable {
    case idle
    case queued
    case running(progress: BoundedProgress)
    case finished
    /// Output was not meaningfully smaller than source — we discarded
    /// the result and kept the original. Source is already efficiently
    /// encoded (e.g. iPhone HEVC) and Apple's curated AVAssetExportSession
    /// presets are fixed-bitrate (no smart cap). Phase 3 AVAssetWriter
    /// migration enables true smart-cap output to fix this surgically.
    case skipped(reason: String)
    case failed(error: LibraryError)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .finished, .skipped, .failed, .cancelled: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .running: return true
        default: return false
        }
    }

    /// Double value in 0.0…1.0 for ProgressView and arithmetic.
    var progress: Double {
        if case let .running(p) = self { return p.value }
        if case .finished = self { return 1.0 }
        return 0
    }

    /// Convenience accessor for views that only need a display string.
    /// Returns `nil` for all non-failed states.
    var failureMessage: String? {
        if case let .failed(error) = self { return error.displayMessage }
        return nil
    }
}
