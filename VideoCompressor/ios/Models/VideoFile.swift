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

struct VideoFile: Identifiable, Hashable, Sendable {
    let id: UUID
    /// On-disk URL inside the app's tmp/import directory. PhotosPicker hands
    /// us scoped URLs that vanish on scope exit, so we copy into our own tmp
    /// before constructing this struct.
    let sourceURL: URL
    let displayName: String
    let importedAt: Date

    var metadata: VideoMetadata?
    var jobState: CompressionJobState
    var outputURL: URL?
    var outputBytes: Int64?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        displayName: String,
        importedAt: Date = Date(),
        metadata: VideoMetadata? = nil,
        jobState: CompressionJobState = .idle,
        outputURL: URL? = nil,
        outputBytes: Int64? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.importedAt = importedAt
        self.metadata = metadata
        self.jobState = jobState
        self.outputURL = outputURL
        self.outputBytes = outputBytes
    }
}

struct VideoMetadata: Hashable, Sendable {
    let durationSeconds: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let nominalFrameRate: Float
    let codec: String          // e.g. "hvc1", "avc1"
    let estimatedDataRate: Float  // bits per second
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
        let mbps = estimatedDataRate / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

enum CompressionJobState: Hashable, Sendable {
    case idle
    case queued
    case running(progress: Double)
    case finished
    case failed(message: String)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .finished, .failed, .cancelled: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .running: return true
        default: return false
        }
    }

    var progress: Double {
        if case let .running(p) = self { return p }
        if case .finished = self { return 1.0 }
        return 0
    }
}
