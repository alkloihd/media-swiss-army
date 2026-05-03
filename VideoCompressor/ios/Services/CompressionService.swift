//
//  CompressionService.swift
//  VideoCompressor
//
//  Phase 3: AVAssetWriter-driven compression with per-preset SMART
//  bitrate caps. Replaces the curated AVAssetExportSession path. The
//  cap math mirrors the web app's `lib/ffmpeg.js`:
//
//    Max       — source bitrate (no cap)              HEVC
//    Balanced  — min(6 Mbps, source × 0.7)            HEVC
//    Small     — min(3 Mbps, source × 0.4)            HEVC
//    Streaming — min(4 Mbps, source × 0.5) + faststart H.264
//
//  Per-preset floors prevent absurdly low bitrates on already-compact
//  sources (1 Mbps balanced, 500 kbps small, 750 kbps streaming).
//  Closes the Build 11 user-reported defect "files getting larger on
//  Small preset" at the encoder level. The post-flight size guard in
//  `VideoLibrary` stays as defense-in-depth.
//
//  Concurrency notes:
//  - AVAssetReader / AVAssetWriter are not Sendable. Per-track
//    `AVAssetWriterInput.requestMediaDataWhenReady` runs on its own
//    DispatchQueue. Shared state (latest PTS, remaining-pumps counter,
//    one-shot continuation) lives on a lock-protected reference
//    `PumpState` — same shape proven in `MetadataService.strip`.
//  - The 10 Hz progress poller hops to the main actor; we never resume
//    the continuation from a sample-buffer callback's hot path.
//  - `withTaskCancellationHandler` wires `Task.cancel()` to
//    `reader.cancelReading()` so cancellation is honoured within one
//    sample-buffer cycle.
//

import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import VideoToolbox

actor CompressionService {
    /// Output URL is derived from `inputURL` + settings suffix and lives in
    /// the app's Documents/Outputs folder so users can find their files via
    /// Files.app even before we copy to Photos.
    static func outputURL(forInput inputURL: URL, settings: CompressionSettings) -> URL {
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
    /// to the reader's video output via `AVAssetReaderVideoCompositionOutput`
    /// so per-clip layer instructions (crop / rotate / render-size) are
    /// honoured. Single source of truth for the encode pipeline shared by
    /// the Compress flow and the Stitch flow.
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

        // Remove any previous output at the target URL — AVAssetWriter
        // refuses to overwrite an existing file.
        try? FileManager.default.removeItem(at: outputURL)

        // -------------------------------------------------------------
        // Source inspection: tracks, dimensions, fps, source bitrate.
        // -------------------------------------------------------------
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw CompressionError.noVideoTrack
        }
        let audioTrack = tracks.first(where: { $0.mediaType == .audio })

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let assetDuration = try await asset.load(.duration)

        // Apply the preferred transform to figure out the rendered size.
        // For a portrait iPhone clip naturalSize is landscape (1920×1080)
        // and the transform rotates 90°; we want to encode at the rotated
        // 1080×1920 size unless a videoComposition has already established
        // a render canvas.
        let orientedSize: CGSize
        if let vc = videoComposition {
            orientedSize = vc.renderSize == .zero ? naturalSize : vc.renderSize
        } else {
            let rect = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
            orientedSize = CGSize(width: abs(rect.width), height: abs(rect.height))
        }

        // -------------------------------------------------------------
        // Target dimensions — long-edge cap, even-ed to multiples of 2.
        // -------------------------------------------------------------
        let (targetWidth, targetHeight) = Self.targetDimensions(
            for: orientedSize,
            longEdgeCap: settings.maxOutputDimension
        )

        // -------------------------------------------------------------
        // Bitrate — smart-capped per preset.
        // -------------------------------------------------------------
        let sourceBitrate: Int64 = {
            if estimatedDataRate.isFinite, estimatedDataRate > 0 {
                return Int64(estimatedDataRate.rounded())
            }
            return 0
        }()
        let targetBitrate = settings.bitrate(forSourceBitrate: sourceBitrate)

        // -------------------------------------------------------------
        // Writer setup.
        // -------------------------------------------------------------
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw CompressionError.exportFailed("Could not create writer: \(error.localizedDescription)")
        }
        writer.shouldOptimizeForNetworkUse = settings.optimizesForNetwork

        // Video output settings dict.
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30
        let gop = Int(frameRate.rounded()) * 2  // 2-second GOP

        let profileLevel: String = {
            if settings.videoCodec == .h264 {
                return AVVideoProfileLevelH264HighAutoLevel
            }
            return kVTProfileLevel_HEVC_Main_AutoLevel as String
        }()

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: NSNumber(value: targetBitrate),
            AVVideoMaxKeyFrameIntervalKey: NSNumber(value: gop),
            AVVideoExpectedSourceFrameRateKey: NSNumber(value: Float(frameRate)),
            AVVideoProfileLevelKey: profileLevel,
            AVVideoAllowFrameReorderingKey: NSNumber(value: true),
        ]
        // H.264 entropy mode — CABAC is the modern default and matters for
        // a faithful 6 Mbps output; the encoder defaults to CABAC on iOS
        // anyway but we set it explicitly.
        if settings.videoCodec == .h264 {
            compressionProps[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }

        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec.rawValue,
            AVVideoWidthKey: NSNumber(value: targetWidth),
            AVVideoHeightKey: NSNumber(value: targetHeight),
            AVVideoCompressionPropertiesKey: compressionProps,
        ]

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings
        )
        videoInput.expectsMediaDataInRealTime = false
        // When a videoComposition is attached, the reader's video output
        // already produces the rendered frames at the target render size
        // and orientation, so we don't need to set a preferredTransform
        // on the writer input. For the URL-asset path we adopt the source
        // transform so the encoded frames are oriented correctly.
        if videoComposition == nil {
            videoInput.transform = preferredTransform
        }

        guard writer.canAdd(videoInput) else {
            throw CompressionError.exportFailed("Writer rejected video input.")
        }
        writer.add(videoInput)

        // Audio: AAC 192 kbps stereo 48 kHz.
        let audioInput: AVAssetWriterInput?
        if audioTrack != nil {
            let audioOutputSettings: [String: Any] = [
                AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
                AVSampleRateKey: NSNumber(value: 48000),
                AVNumberOfChannelsKey: NSNumber(value: 2),
                AVEncoderBitRateKey: NSNumber(value: 192_000),
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                audioInput = nil
            }
        } else {
            audioInput = nil
        }

        // -------------------------------------------------------------
        // Reader setup. Two paths:
        //  - With videoComposition → AVAssetReaderVideoCompositionOutput
        //    so layer instructions (crop, rotate) are baked into the
        //    decoded frames the writer sees.
        //  - URL-asset path → AVAssetReaderTrackOutput with a BGRA
        //    pixel-buffer dict so the writer can re-encode.
        // -------------------------------------------------------------
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw CompressionError.exportFailed("Could not create reader: \(error.localizedDescription)")
        }

        let pixelFormat: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        ]

        let videoReaderOutput: AVAssetReaderOutput
        if let vc = videoComposition {
            // Use ALL video tracks the composition references.
            let videoTracks = tracks.filter { $0.mediaType == .video }
            let compOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: videoTracks,
                videoSettings: pixelFormat
            )
            compOutput.videoComposition = vc
            compOutput.alwaysCopiesSampleData = false
            videoReaderOutput = compOutput
        } else {
            let trackOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: pixelFormat
            )
            trackOutput.alwaysCopiesSampleData = false
            videoReaderOutput = trackOutput
        }
        guard reader.canAdd(videoReaderOutput) else {
            throw CompressionError.exportFailed("Reader rejected video output.")
        }
        reader.add(videoReaderOutput)

        let audioReaderOutput: AVAssetReaderOutput?
        if let aTrack = audioTrack {
            let audioReadSettings: [String: Any] = [
                AVFormatIDKey: NSNumber(value: kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: NSNumber(value: 16),
                AVLinearPCMIsFloatKey: NSNumber(value: false),
                AVLinearPCMIsBigEndianKey: NSNumber(value: false),
                AVLinearPCMIsNonInterleaved: NSNumber(value: false),
            ]
            let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: audioReadSettings)
            aOut.alwaysCopiesSampleData = false
            if reader.canAdd(aOut) {
                reader.add(aOut)
                audioReaderOutput = aOut
            } else {
                audioReaderOutput = nil
            }
        } else {
            audioReaderOutput = nil
        }

        // -------------------------------------------------------------
        // Start session.
        // -------------------------------------------------------------
        guard reader.startReading() else {
            throw CompressionError.exportFailed(
                reader.error?.localizedDescription ?? "Reader failed to start."
            )
        }
        guard writer.startWriting() else {
            throw CompressionError.exportFailed(
                writer.error?.localizedDescription ?? "Writer failed to start."
            )
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = max(CMTimeGetSeconds(assetDuration), 0)

        // Pump pairs. Audio is optional — when missing we skip its pump.
        struct PumpPair {
            let input: AVAssetWriterInput
            let output: AVAssetReaderOutput
            let label: String
        }
        var pumps: [PumpPair] = [
            PumpPair(input: videoInput, output: videoReaderOutput, label: "video"),
        ]
        if let aIn = audioInput, let aOut = audioReaderOutput {
            pumps.append(PumpPair(input: aIn, output: aOut, label: "audio"))
        }

        let pumpState = PumpState(remaining: pumps.count)

        // 10 Hz progress poller — main-actor isolated, reads PTS from the
        // shared lock-protected state.
        let progressTask = Task { @MainActor [totalSeconds, pumpState] in
            while !Task.isCancelled {
                let pts = pumpState.latestPTS()
                if totalSeconds > 0, pts.isFinite {
                    onProgress(BoundedProgress(pts / totalSeconds))
                }
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
            }
        }

        // Snapshot for `@Sendable` capture.
        let pumpsSnapshot = pumps
        let cancelSnapshot = pumps

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let bridge = ContinuationBridge(continuation: cont)
                pumpState.setBridge(bridge)

                if pumpsSnapshot.isEmpty {
                    pumpState.tryResume()
                    return
                }

                for pair in pumpsSnapshot {
                    let queue = DispatchQueue(label: "compress.pump.\(pair.label)")
                    let input = pair.input
                    let output = pair.output
                    let state = pumpState
                    let isVideo = pair.label == "video"
                    input.requestMediaDataWhenReady(on: queue) {
                        while input.isReadyForMoreMediaData {
                            if Task.isCancelled {
                                input.markAsFinished()
                                state.finishOnePump()
                                return
                            }
                            if let sample = output.copyNextSampleBuffer() {
                                if !input.append(sample) {
                                    input.markAsFinished()
                                    state.finishOnePump()
                                    return
                                }
                                if isVideo {
                                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                                    let ptsSec = CMTimeGetSeconds(pts)
                                    if ptsSec.isFinite {
                                        state.recordPTS(ptsSec)
                                    }
                                }
                            } else {
                                input.markAsFinished()
                                state.finishOnePump()
                                return
                            }
                        }
                    }
                }
            }
        } onCancel: {
            reader.cancelReading()
            for pair in cancelSnapshot { pair.input.markAsFinished() }
        }

        progressTask.cancel()

        if Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.cancelled
        }

        // Surface reader-side errors before declaring success.
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            let detail = reader.error?.localizedDescription ?? "Reader failed."
            throw CompressionError.exportFailed("Read failed: \(detail)")
        }

        await writer.finishWriting()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: outputURL)
            let nsErr = writer.error as NSError?
            if nsErr?.code == -11847 {
                throw CompressionError.exportFailed(
                    "Export was interrupted because the app went to the background or the screen locked for too long. Keep the app open during long encodes (especially Stitch). On retry, the encode will resume from scratch."
                )
            }
            let detail = nsErr.map { "[\($0.domain) \($0.code)] \($0.localizedDescription)" }
                ?? "Writer ended with status \(writer.status.rawValue)"
            throw CompressionError.exportFailed("Encode failed: \(detail)")
        }

        await MainActor.run { onProgress(.complete) }
        return outputURL
    }

    /// Pre-flight estimate of output file size for the size-prediction UI.
    /// With AVAssetWriter we have no built-in estimator — we compute
    /// `targetBitrate × duration` and add a small audio overhead. Reasonably
    /// accurate for CBR-ish HEVC/H.264; off by 10-20% for VBR pathologies.
    static func estimateOutputBytes(for inputURL: URL, settings: CompressionSettings) async -> Int64? {
        let asset = AVURLAsset(url: inputURL)
        guard
            let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
            let durationSeconds = try? await asset.load(.duration).seconds
        else { return nil }

        let estimatedDataRate = (try? await videoTrack.load(.estimatedDataRate)) ?? 0
        let sourceBitrate: Int64 = estimatedDataRate.isFinite && estimatedDataRate > 0
            ? Int64(estimatedDataRate.rounded())
            : 0

        let videoBitrate = settings.bitrate(forSourceBitrate: sourceBitrate)
        let audioBitrate: Int64 = 192_000  // Matches encode() audio settings.

        // Bytes = (bps × duration_seconds) / 8
        let bytes = Int64((Double(videoBitrate + audioBitrate) * durationSeconds) / 8.0)
        return bytes > 0 ? bytes : nil
    }

    // MARK: - Helpers

    /// Computes target (width, height) from a source size and an optional
    /// long-edge cap. Preserves aspect ratio. Output dimensions are even
    /// (H.264/HEVC require even dimensions).
    static func targetDimensions(for size: CGSize, longEdgeCap: Int?) -> (Int, Int) {
        let srcW = max(Int(size.width.rounded()), 2)
        let srcH = max(Int(size.height.rounded()), 2)
        guard let cap = longEdgeCap else {
            return (Self.evenize(srcW), Self.evenize(srcH))
        }
        let longEdge = max(srcW, srcH)
        if longEdge <= cap {
            return (Self.evenize(srcW), Self.evenize(srcH))
        }
        let scale = Double(cap) / Double(longEdge)
        let outW = Int((Double(srcW) * scale).rounded())
        let outH = Int((Double(srcH) * scale).rounded())
        return (Self.evenize(outW), Self.evenize(outH))
    }

    private static func evenize(_ v: Int) -> Int {
        // Round to nearest even, minimum 2.
        let n = max(v, 2)
        return n.isMultiple(of: 2) ? n : n - 1
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

// MARK: - Pump shared state
//
// Reference-typed state shared across the per-track pump closures and
// the 10 Hz progress poller. Lock-protected to keep Swift 6 strict
// concurrency happy without `nonisolated(unsafe)` on captured vars.
// Mirrors the proven pattern in `MetadataService.strip`.

private final class PumpState: @unchecked Sendable {
    private let lock = NSLock()
    private var _latestPTS: Double = 0
    private var _remaining: Int
    private var _bridge: ContinuationBridge?

    init(remaining: Int) {
        self._remaining = remaining
    }

    func setBridge(_ bridge: ContinuationBridge) {
        lock.lock(); defer { lock.unlock() }
        self._bridge = bridge
    }

    func latestPTS() -> Double {
        lock.lock(); defer { lock.unlock() }
        return _latestPTS
    }

    func recordPTS(_ pts: Double) {
        lock.lock(); defer { lock.unlock() }
        if pts > _latestPTS { _latestPTS = pts }
    }

    /// Decrement the remaining-pumps counter. When it hits zero, resume
    /// the continuation exactly once.
    func finishOnePump() {
        lock.lock()
        _remaining -= 1
        let done = _remaining <= 0
        let bridge = _bridge
        lock.unlock()
        if done { bridge?.resume() }
    }

    /// Used for the zero-track edge case to resume immediately.
    func tryResume() {
        lock.lock()
        let bridge = _bridge
        lock.unlock()
        bridge?.resume()
    }
}

/// Wraps a `CheckedContinuation` so it can be safely resumed from any
/// thread once. `CheckedContinuation` is itself non-Sendable in strict
/// mode; this class enforces the once-only semantics with a lock.
private final class ContinuationBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}
