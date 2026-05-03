//
//  CompressionService.swift
//  VideoCompressor
//
//  AVAssetExportSession-based compression for the MVP. The Web app uses
//  per-preset bitrate caps which AVAssetExportSession does NOT expose
//  directly — that's a v2 upgrade to AVAssetWriter. For v1 we use Apple's
//  curated presets and surface progress + estimated output size.
//
//  Concurrency notes:
//  - AVAssetExportSession is reference-typed and not Sendable. We confine
//    each export to a `Task` and avoid hopping the session between actors.
//  - Progress is polled from a 10 Hz timer because the new
//    `states(updateInterval:)` AsyncSequence is iOS 18+ only and we want to
//    keep the deployment floor at iOS 17.
//

import Foundation
import AVFoundation

actor CompressionService {
    /// Output URL is derived from `inputURL` + preset suffix and lives in
    /// the app's Documents/Outputs folder so users can find their files via
    /// Files.app even before we copy to Photos.
    static func outputURL(forInput inputURL: URL, preset: CompressionPreset) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputs = docs.appendingPathComponent("Outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)

        let stem = inputURL.deletingPathExtension().lastPathComponent
        let ext = "mp4"
        let filename = "\(stem)\(preset.outputSuffix).\(ext)"
        return outputs.appendingPathComponent(filename)
    }

    /// Run a compression. Reports progress on the main actor via `onProgress`.
    /// Returns the output URL when complete. Throws on failure.
    func compress(
        input inputURL: URL,
        preset: CompressionPreset,
        onProgress: @MainActor @escaping (Double) -> Void
    ) async throws -> URL {

        let asset = AVURLAsset(url: inputURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])

        // Sanity check: must have a video track.
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw CompressionError.noVideoTrack
        }

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: preset.avExportPresetName
        ) else {
            throw CompressionError.exporterUnavailable(preset.avExportPresetName)
        }

        let outputURL = Self.outputURL(forInput: inputURL, preset: preset)
        // Remove any previous output with the same name to avoid the
        // "Cannot Open" error AVAssetExportSession raises.
        try? FileManager.default.removeItem(at: outputURL)

        exporter.outputURL = outputURL
        exporter.outputFileType = preset.fileType
        exporter.shouldOptimizeForNetworkUse = (preset == .streaming)

        // Spawn a polling task that publishes progress at 10 Hz. We cancel
        // it as soon as the export completes.
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                onProgress(Double(exporter.progress))
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
            }
        }

        defer { progressTask.cancel() }

        // Run the export. `export()` is now async on iOS 18 but we keep the
        // older callback-based wait pattern so iOS 17 stays supported.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        // Surface a final 1.0 in case the poller missed the last tick.
        await MainActor.run { onProgress(1.0) }

        switch exporter.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw CompressionError.cancelled
        case .failed:
            throw CompressionError.exportFailed(exporter.error?.localizedDescription ?? "Unknown export error")
        default:
            throw CompressionError.exportFailed("Unexpected exporter status: \(exporter.status.rawValue)")
        }
    }

    /// Pre-flight estimate of output file size for the size-prediction UI.
    /// AVAssetExportSession exposes `estimatedOutputFileLength` but it
    /// requires the session to be configured; we build a transient one and
    /// query it. Returns nil if no estimate is available.
    static func estimateOutputBytes(for inputURL: URL, preset: CompressionPreset) async -> Int64? {
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: preset.avExportPresetName
        ) else { return nil }
        exporter.outputFileType = preset.fileType
        exporter.outputURL = outputURL(forInput: inputURL, preset: preset)

        // The async accessor is iOS 16+.
        if #available(iOS 16, *) {
            return try? await exporter.estimatedOutputFileLengthInBytes
        }
        return exporter.estimatedOutputFileLength == 0 ? nil : exporter.estimatedOutputFileLength
    }
}

enum CompressionError: Error, LocalizedError {
    case noVideoTrack
    case exporterUnavailable(String)
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:               return "Source file has no video track."
        case .exporterUnavailable(let p): return "AVAssetExportSession does not support preset \(p) on this device."
        case .exportFailed(let msg):      return "Compression failed: \(msg)"
        case .cancelled:                  return "Compression was cancelled."
        }
    }
}
