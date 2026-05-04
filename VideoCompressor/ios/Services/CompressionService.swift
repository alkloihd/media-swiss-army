//
//  CompressionService.swift
//  VideoCompressor
//
//  Phase 3: AVAssetWriter-driven compression with per-preset SMART
//  bitrate caps. Replaces the curated AVAssetExportSession path. The
//  cap math mirrors the web app's `lib/ffmpeg.js`:
//
//    Max       — min(50 Mbps, source × 0.9)           HEVC
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

struct CompressionResult: Hashable, Sendable {
    let url: URL
    let settings: CompressionSettings
    let fallbackMessage: String?
}

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
    ) async throws -> CompressionResult {

        let asset = AVURLAsset(url: inputURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])

        // Sanity check: must have a video track.
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw CompressionError.noVideoTrack
        }

        return try await Self.runWithOneShotDownshift(
            inputURL: inputURL,
            settings: settings,
            onRetry: {
                onProgress(.zero)
            }
        ) { attemptSettings, attemptOutputURL, attempt in
            let attemptAsset: AVAsset
            if attempt == 0 {
                attemptAsset = asset
            } else {
                attemptAsset = AVURLAsset(url: inputURL, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true,
                ])
            }
            return try await self.encode(
                asset: attemptAsset,
                videoComposition: nil,
                settings: attemptSettings,
                outputURL: attemptOutputURL,
                onProgress: onProgress
            )
        }
    }

    static func runWithOneShotDownshift(
        inputURL: URL,
        settings: CompressionSettings,
        onRetry: @MainActor @escaping () async -> Void,
        encodeAttempt: @escaping (_ settings: CompressionSettings, _ outputURL: URL, _ attempt: Int) async throws -> URL
    ) async throws -> CompressionResult {
        let outputURL = Self.outputURL(forInput: inputURL, settings: settings)
        do {
            let url = try await encodeAttempt(settings, outputURL, 0)
            return CompressionResult(url: url, settings: settings, fallbackMessage: nil)
        } catch {
            guard
                case let CompressionError.exportFailed(message) = error,
                Self.isEncoderEnvelopeRejectionMessage(message),
                let fallback = Self.downshift(from: settings)
            else {
                throw error
            }
            await onRetry()
            let fallbackOutputURL = Self.outputURL(forInput: inputURL, settings: fallback)
            let url = try await encodeAttempt(fallback, fallbackOutputURL, 1)
            return CompressionResult(
                url: url,
                settings: fallback,
                fallbackMessage: Self.downshiftMessage(from: settings, to: fallback)
            )
        }
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
        audioMix: AVMutableAudioMix? = nil,
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
        let formatDescriptions = (try? await videoTrack.load(.formatDescriptions)) ?? []
        let is10Bit = Self.is10Bit(formatDescriptions: formatDescriptions)
        let videoColorProperties = Self.colorProperties(
            formatDescriptions: formatDescriptions,
            is10Bit: is10Bit
        )

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
        let frameRate = Self.clamp(frameRate: nominalFrameRate)
        let gop = Self.clamp(gop: Int(frameRate.rounded()) * 2)

        let profileLevel = Self.profileLevel(
            for: settings.videoCodec,
            is10Bit: is10Bit
        )

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
            AVVideoColorPropertiesKey: videoColorProperties,
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

        let pixelFormat = Self.pixelBufferDict(forIs10Bit: is10Bit)

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
        let audioReadSettings: [String: Any] = [
            AVFormatIDKey: NSNumber(value: kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: NSNumber(value: 16),
            AVLinearPCMIsFloatKey: NSNumber(value: false),
            AVLinearPCMIsBigEndianKey: NSNumber(value: false),
            AVLinearPCMIsNonInterleaved: NSNumber(value: false),
        ]
        // When the caller supplied an audio mix (stitch transitions), read
        // ALL audio tracks through `AVAssetReaderAudioMixOutput` so the mix's
        // volume ramps actually fire. Otherwise fall back to single-track
        // output (legacy single-clip compress path).
        let allAudioTracks = tracks.filter { $0.mediaType == .audio }
        if audioMix != nil, !allAudioTracks.isEmpty {
            let mixOut = AVAssetReaderAudioMixOutput(
                audioTracks: allAudioTracks,
                audioSettings: audioReadSettings
            )
            mixOut.audioMix = audioMix
            mixOut.alwaysCopiesSampleData = false
            if reader.canAdd(mixOut) {
                reader.add(mixOut)
                audioReaderOutput = mixOut
            } else {
                audioReaderOutput = nil
            }
        } else if let aTrack = audioTrack {
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

        // Cancel/registration coordination — see CancelCoordinator below for
        // the full race analysis. In short: onCancel can fire synchronously
        // before the body runs OR concurrently while we're mid-registration.
        // Either path tries to call `markAsFinished()` on inputs that the
        // body would then re-touch via `requestMediaDataWhenReady`, which
        // throws NSInternalInconsistencyException.
        let coordinator = CancelCoordinator()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let bridge = ContinuationBridge(continuation: cont)
                pumpState.setBridge(bridge)

                if pumpsSnapshot.isEmpty {
                    pumpState.tryResume()
                    return
                }

                // Atomically: if not yet cancelled, register all pumps under
                // the lock so onCancel will see registration is complete and
                // mark the inputs finished. If already cancelled, finish each
                // pump's bookkeeping without ever touching the inputs.
                let didRegister = coordinator.tryRegister {
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

                if !didRegister {
                    // Cancelled before/during the registration window. The
                    // continuation must still resume — finishOnePump per
                    // pump tells pumpState to stop waiting for samples.
                    for _ in pumpsSnapshot { pumpState.finishOnePump() }
                }
            }
        } onCancel: {
            // Atomically observe whether registration completed. If yes,
            // it's safe to mark inputs finished (race with the dispatch
            // pumps still exists, but the pumps' own Task.isCancelled
            // check + idempotent markAsFinished handles that). If no,
            // do NOT touch the inputs — the body's `didRegister == false`
            // branch will tear down via pumpState.
            if coordinator.cancelAfterRegistration() {
                reader.cancelReading()
                for pair in cancelSnapshot { pair.input.markAsFinished() }
            } else {
                reader.cancelReading()
            }
        }

        progressTask.cancel()

        if Task.isCancelled {
            writer.cancelWriting()
            await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)
            throw CompressionError.cancelled
        }

        // Surface reader-side errors before declaring success.
        if reader.status == .failed {
            writer.cancelWriting()
            await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)
            let detail = reader.error?.localizedDescription ?? "Reader failed."
            throw CompressionError.exportFailed("Read failed: \(detail)")
        }

        await writer.finishWriting()
        if writer.status != .completed {
            await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)
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

    static func is10Bit(formatDescriptions: [CMFormatDescription]) -> Bool {
        formatDescriptions.contains { fd in
            let bitsPerComponent = CMFormatDescriptionGetExtension(
                fd,
                extensionKey: kCMFormatDescriptionExtension_BitsPerComponent
            ) as? NSNumber
            return (bitsPerComponent?.intValue ?? 8) >= 10
        }
    }

    /// Maps source bit-depth to the pixel-buffer dictionary the reader
    /// receives. Exposed for testability — see CompressionServiceTests.
    static func pixelBufferDict(forIs10Bit is10Bit: Bool) -> [String: Any] {
        let pixelFormatType = is10Bit
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        return [
            kCVPixelBufferPixelFormatTypeKey as String:
                NSNumber(value: pixelFormatType),
        ]
    }

    static func colorProperties(
        formatDescriptions: [CMFormatDescription],
        is10Bit: Bool
    ) -> [String: Any] {
        guard is10Bit else { return sdrColorProperties() }

        let fd = formatDescriptions.first
        let colorPrimaries = fd.flatMap {
            CMFormatDescriptionGetExtension(
                $0,
                extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
            ) as? String
        } ?? AVVideoColorPrimaries_ITU_R_2020
        let transferFunction = fd.flatMap {
            CMFormatDescriptionGetExtension(
                $0,
                extensionKey: kCMFormatDescriptionExtension_TransferFunction
            ) as? String
        } ?? AVVideoTransferFunction_ITU_R_2100_HLG
        let yCbCrMatrix = fd.flatMap {
            CMFormatDescriptionGetExtension(
                $0,
                extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix
            ) as? String
        } ?? AVVideoYCbCrMatrix_ITU_R_2020

        return [
            AVVideoColorPrimariesKey: colorPrimaries,
            AVVideoTransferFunctionKey: transferFunction,
            AVVideoYCbCrMatrixKey: yCbCrMatrix,
        ]
    }

    static func profileLevel(for codec: AVVideoCodecType, is10Bit: Bool) -> String {
        if codec == .h264 {
            return AVVideoProfileLevelH264HighAutoLevel
        }
        if is10Bit {
            return kVTProfileLevel_HEVC_Main10_AutoLevel as String
        }
        return kVTProfileLevel_HEVC_Main_AutoLevel as String
    }

    static func sdrColorProperties() -> [String: Any] {
        [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
    }

    static func clamp(frameRate: Float) -> Float {
        guard frameRate > 0 else { return 30 }
        return min(frameRate, 120)
    }

    static func clamp(gop: Int) -> Int {
        Swift.max(2, Swift.min(gop, 60))
    }

    static func downshift(from settings: CompressionSettings) -> CompressionSettings? {
        switch (settings.resolution, settings.quality) {
        case (.source, .lossless):   return .balanced
        case (.fhd1080, .high):      return .small
        case (.sd540, .balanced):    return .small
        case (.hd720, .balanced):    return nil
        default:                     return nil
        }
    }

    static func downshiftMessage(from: CompressionSettings, to: CompressionSettings) -> String {
        "\(from.title) was rejected by the encoder for this source. Falling back to \(to.title)."
    }

    static func isEncoderEnvelopeRejectionMessage(_ message: String) -> Bool {
        message.contains("-11841")
    }
}

enum CompressionError: Error, LocalizedError, Hashable, Sendable {
    case noVideoTrack
    case exporterUnavailable(String)
    case exportFailed(String)
    case cancelled
    /// All retry attempts in the stitch fallback chain failed with the
    /// device's hardware encoder rejecting the configuration. Surfaced
    /// instead of raw `AVFoundationErrorDomain -11841` so the user gets a
    /// recovery hint rather than an opaque error code. Carries a friendly,
    /// pre-formatted message that the UI renders inline.
    case encoderEnvelopeRejected(message: String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:                     return "Source file has no video track."
        case .exporterUnavailable(let p):       return "AVAssetExportSession does not support preset \(p) on this device."
        case .exportFailed(let msg):            return "Compression failed: \(msg)"
        case .cancelled:                        return "Compression was cancelled."
        case .encoderEnvelopeRejected(let msg): return msg
        }
    }
}

// MARK: - Pump shared state
//
// Reference-typed state shared across the per-track pump closures and
// the 10 Hz progress poller. Lock-protected to keep Swift 6 strict
// concurrency happy without `nonisolated(unsafe)` on captured vars.
// Mirrors the proven pattern in `MetadataService.strip`.

/// Coordinates the race between the encoder body's `requestMediaDataWhenReady`
/// registration loop and `withTaskCancellationHandler.onCancel`. Two windows
/// of trouble exist:
///
/// 1. **Pre-registration cancel** — `withTaskCancellationHandler` invokes
///    onCancel synchronously when the surrounding Task was already cancelled
///    BEFORE the body ran. If onCancel calls `markAsFinished()` on the
///    inputs in that state, the body then trying to call
///    `requestMediaDataWhenReady` on those finished inputs raises
///    `NSInternalInconsistencyException` (status 2).
///
/// 2. **Mid-registration cancel** — the body is mid-loop (registered the
///    video pump, about to register the audio pump). Cancellation fires.
///    onCancel runs concurrently, marks both inputs finished. The body
///    then tries to register the audio pump on a now-finished input and
///    crashes the same way.
///
/// Solution: the body's whole registration block runs under a lock, with a
/// `registrationComplete` flag. onCancel checks the flag — if registration
/// finished, it's safe to mark inputs finished (the dispatch pumps' own
/// `Task.isCancelled` checks + idempotent `markAsFinished` keep things
/// clean). If registration didn't finish, onCancel only cancels the reader
/// and the body's `tryRegister` returns false so it can clean up
/// gracefully without ever touching the inputs.
private final class CancelCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var registrationComplete = false
    private var cancelled = false

    /// Run `body` (the registration loop) inside the lock IF cancellation
    /// hasn't already fired. Returns true if the body ran. False means the
    /// caller must clean up without registering.
    func tryRegister(_ body: () -> Void) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            return false
        }
        body()
        registrationComplete = true
        lock.unlock()
        return true
    }

    /// Mark cancellation. Returns true if registration had already
    /// completed (so it's safe to call `markAsFinished` on the inputs);
    /// false if registration never ran (in which case the inputs were
    /// never touched and don't need finishing).
    func cancelAfterRegistration() -> Bool {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        return registrationComplete
    }
}

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
