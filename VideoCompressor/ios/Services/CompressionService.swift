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
    /// Output URL is derived from `inputURL` + settings suffix and lives in
    /// the app's Documents/Outputs folder so users can find their files via
    /// Files.app even before we copy to Photos.
    static func outputURL(forInput inputURL: URL, settings: CompressionSettings) -> URL {
        // Backup-exclusion happens once at app launch in
        // VideoLibrary.markDirectoriesAsNonBackup. Don't repeat the dance
        // here — earlier code mutated a local URL copy without persisting.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputs = docs.appendingPathComponent("Outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)

        let stem = inputURL.deletingPathExtension().lastPathComponent
        let ext = "mp4"
        let filename = "\(stem)\(settings.outputSuffix).\(ext)"
        return outputs.appendingPathComponent(filename)
    }

    /// Run a compression. Reports progress on the main actor via `onProgress`.
    /// Returns the output URL when complete. Throws on failure.
    ///
    /// Thin wrapper around `encode(asset:videoComposition:settings:outputURL:onProgress:)` —
    /// the Stitch flow uses the same underlying pipeline with an
    /// `AVMutableComposition` instead of an `AVURLAsset`.
    func compress(
        input inputURL: URL,
        settings: CompressionSettings,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {

        let asset = AVURLAsset(url: inputURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])

        // Sanity check: must have a video track.
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw CompressionError.noVideoTrack
        }

        let outputURL = Self.outputURL(forInput: inputURL, settings: settings)
        return try await encode(
            asset: asset,
            videoComposition: nil,
            settings: settings,
            outputURL: outputURL,
            onProgress: onProgress
        )
    }

    /// Encode an arbitrary `AVAsset` (URL-backed or composition-backed) using
    /// the given settings. When `videoComposition` is non-nil it is attached
    /// to the export session so per-clip layer instructions (crop / rotate)
    /// are honoured. Single source of truth for the export pipeline shared
    /// by the Compress flow and the Stitch flow.
    ///
    /// `outputURL` is passed in explicitly because the Stitch flow has no
    /// "input URL" to derive from — composition assets are synthesised in
    /// memory.
    func encode(
        asset: AVAsset,
        videoComposition: AVMutableVideoComposition?,
        settings: CompressionSettings,
        outputURL: URL,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: settings.avExportPresetName
        ) else {
            throw CompressionError.exporterUnavailable(settings.avExportPresetName)
        }

        // Remove any previous output with the same name to avoid the
        // "Cannot Open" error AVAssetExportSession raises.
        try? FileManager.default.removeItem(at: outputURL)

        exporter.outputURL = outputURL
        exporter.outputFileType = settings.fileType
        exporter.shouldOptimizeForNetworkUse = settings.optimizesForNetwork
        if let videoComposition {
            exporter.videoComposition = videoComposition
        }

        // Spawn a polling task that publishes progress at 10 Hz.
        let progressTask = Task { @MainActor [weak exporter] in
            while !Task.isCancelled {
                guard let exporter else { return }
                onProgress(BoundedProgress(Double(exporter.progress)))
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
            }
        }

        // Run the export. We use withTaskCancellationHandler so a cooperative
        // Task.cancel() actually stops the underlying AVAssetExportSession.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exporter.exportAsynchronously {
                    continuation.resume()
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }

        // Stop the poller BEFORE we emit the final 1.0 — otherwise the poller
        // can race in and overwrite with the latest exporter.progress (~0.99).
        progressTask.cancel()
        await MainActor.run { onProgress(.complete) }

        switch exporter.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw CompressionError.cancelled
        case .failed:
            let nsErr = exporter.error as NSError?
            // Translate the most common interruption cause into something a
            // user can act on. -11847 (AVErrorOperationInterrupted) fires
            // when iOS kills the export — almost always because the app was
            // backgrounded past the ~30 s UIBackgroundTask grace window.
            if nsErr?.code == -11847 {
                throw CompressionError.exportFailed(
                    "Export was interrupted because the app went to the background or the screen locked for too long. Keep the app open during long encodes (especially Stitch). On retry, the encode will resume from scratch."
                )
            }
            let detail = nsErr.map { "[\($0.domain) \($0.code)] \($0.localizedDescription)" } ?? "Unknown export error"
            let underlying = (nsErr?.userInfo[NSUnderlyingErrorKey] as? NSError)
                .map { " (underlying: \($0.domain) \($0.code))" } ?? ""
            throw CompressionError.exportFailed(detail + underlying)
        @unknown default:
            let detail = (exporter.error as NSError?).map { "[\($0.domain) \($0.code)] \($0.localizedDescription)" } ?? "no error attached"
            throw CompressionError.exportFailed("Exporter reached non-terminal state \(exporter.status.rawValue) — \(detail)")
        }
    }

    /// Pre-flight estimate of output file size for the size-prediction UI.
    /// AVAssetExportSession exposes `estimatedOutputFileLength` but it
    /// requires the session to be configured; we build a transient one and
    /// query it. Returns nil if no estimate is available.
    static func estimateOutputBytes(for inputURL: URL, settings: CompressionSettings) async -> Int64? {
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: settings.avExportPresetName
        ) else { return nil }
        exporter.outputFileType = settings.fileType
        exporter.outputURL = outputURL(forInput: inputURL, settings: settings)

        // The async accessor is iOS 16+.
        if #available(iOS 16, *) {
            return try? await exporter.estimatedOutputFileLengthInBytes
        }
        return exporter.estimatedOutputFileLength == 0 ? nil : exporter.estimatedOutputFileLength
    }
}

enum CompressionError: Error, LocalizedError, Hashable, Sendable {
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
