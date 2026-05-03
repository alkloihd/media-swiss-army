//
//  StitchExporter.swift
//  VideoCompressor
//
//  Builds an AVMutableComposition from an ordered array of `StitchClip`s and
//  drives an AVAssetExportSession to produce a single output file. Supports
//  two paths:
//
//   1. **Passthrough** — when every clip shares codec + naturalSize and no
//      clip has any active edits, we use AVAssetExportPresetPassthrough
//      which copies samples without re-encoding (fastest, lossless).
//   2. **Re-encode** — anything else: differing codecs, mismatched
//      dimensions, or any crop/rotate/trim edit. We hand the composition
//      and (if needed) an AVMutableVideoComposition to
//      `CompressionService.encode(asset:videoComposition:settings:...)` and
//      reuse its progress / cancellation plumbing.
//
//  Concurrency:
//  - Actor-isolated. `Plan` is `@unchecked Sendable` because it carries
//    `AVMutableComposition` / `AVMutableVideoComposition` (reference types,
//    not Sendable). The struct flows from the actor to the caller and back
//    in once, immediately, in `StitchProject.runExport` — no concurrent
//    access in practice.
//  - All AVFoundation property access uses the iOS 16+ `load(_:)` async
//    APIs to satisfy strict concurrency.
//
//  Phase 3 upgrade path: swap the re-encode branch's
//  AVAssetExportSession for a real AVAssetWriter pipeline so
//  per-preset bitrate caps from CLAUDE.md actually take effect. The
//  StitchExporter API does not change.
//

import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import CoreGraphics

actor StitchExporter {
    /// A composition + (optional) videoComposition pair ready to feed into
    /// AVAssetExportSession. `canPassthrough` lets the caller pick a fast
    /// preset name when all clips line up.
    ///
    /// `@unchecked Sendable` because AVMutableComposition is a class without
    /// a Sendable conformance. Callers are expected to use this struct in a
    /// single linear flow (build → export → discard) without sharing it
    /// across tasks.
    struct Plan: @unchecked Sendable {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?
        let renderSize: CGSize
        let canPassthrough: Bool
    }

    /// Builds the composition. Any failure (missing video track, codec
    /// mismatch on insert) throws and the caller surfaces it via
    /// `LibraryError.compression(.exportFailed)`.
    func buildPlan(from clips: [StitchClip]) async throws -> Plan {
        guard !clips.isEmpty else {
            throw CompressionError.exportFailed("Stitch export requires at least one clip.")
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CompressionError.exportFailed("Could not create composition video track.")
        }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor: CMTime = .zero
        // Per-segment records keep cursor positions so we can emit the full
        // contiguous instructions list (closes review {E-0503-1114} C1).
        struct Segment {
            let clip: StitchClip
            let composedRange: CMTimeRange
        }
        var segments: [Segment] = []
        var anyEdit = false
        var maxNaturalSize: CGSize = .zero
        var firstFormatSubtype: FourCharCode?
        var firstNominalFrameRate: Float?
        var allSameSize = true
        var allSameCodec = true
        var allSameFrameRate = true

        for clip in clips {
            // Cooperative cancellation between clips so a 20-clip
            // buildPlan stops promptly when the user taps Cancel
            // (closes review {E-0503-1114} H4).
            try Task.checkCancellation()

            let asset = AVURLAsset(url: clip.sourceURL)

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let assetVideoTrack = videoTracks.first else {
                throw CompressionError.exportFailed("Clip \(clip.displayName) has no video track.")
            }

            // Codec / size / fps sniff for passthrough decision. Heterogeneous
            // format descriptions per-track are rare in modern iPhone footage.
            let formatDescriptions = try await assetVideoTrack.load(.formatDescriptions)
            let trackNaturalSize = try await assetVideoTrack.load(.naturalSize)
            let trackFrameRate = try await assetVideoTrack.load(.nominalFrameRate)

            // Track the largest natural size so the render canvas accommodates
            // every clip (closes review {E-0503-1114} H2).
            if trackNaturalSize.width * trackNaturalSize.height
                > maxNaturalSize.width * maxNaturalSize.height {
                maxNaturalSize = trackNaturalSize
            }
            if !segments.isEmpty, trackNaturalSize != segments[0].clip.naturalSize {
                allSameSize = false
            }

            if let cm = formatDescriptions.first {
                let subtype = CMFormatDescriptionGetMediaSubType(cm)
                if let firstSubtype = firstFormatSubtype {
                    if firstSubtype != subtype { allSameCodec = false }
                } else {
                    firstFormatSubtype = subtype
                }
            }

            // Frame-rate homogeneity (closes review {E-0503-1114} M1). Mixed
            // fps in a single composition track plays at the wrong speed.
            if let firstFps = firstNominalFrameRate {
                if abs(firstFps - trackFrameRate) > 0.5 { allSameFrameRate = false }
            } else {
                firstNominalFrameRate = trackFrameRate
            }

            let timeRange = clip.trimmedRange
            do {
                try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: cursor)
            } catch {
                throw CompressionError.exportFailed(
                    "Could not insert \(clip.displayName) into composition: \(error.localizedDescription)"
                )
            }

            if let audioTrack {
                if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioTrack.insertTimeRange(timeRange, of: assetAudio, at: cursor)
                }
            }

            let composedRange = CMTimeRange(start: cursor, duration: timeRange.duration)
            segments.append(Segment(clip: clip, composedRange: composedRange))
            if clip.isEdited { anyEdit = true }

            cursor = CMTimeAdd(cursor, timeRange.duration)
        }

        // Render size: largest natural size seen. Smaller clips letterbox
        // inside this canvas (acceptable v1 behaviour). Phase 3 may swap to a
        // computed tight bounding box.
        let renderSize = maxNaturalSize == .zero
            ? CGSize(width: 1280, height: 720)
            : maxNaturalSize

        // When ANY clip has an edit, the videoComposition's `instructions`
        // array must cover the full timeline contiguously and without gaps.
        // We emit a layer instruction per segment — passthrough (no transform
        // or crop) for unedited segments. This keeps Apple's contract happy
        // (AVErrorInvalidVideoComposition -11841 otherwise — closes review
        // {E-0503-1114} C1).
        let videoComposition: AVMutableVideoComposition?
        if anyEdit {
            let vc = AVMutableVideoComposition()
            // Adopt the source frame rate when homogeneous; otherwise pick the
            // higher rate seen so we don't drop frames. 30 is a safe default
            // when the assets didn't report a value.
            let fps = firstNominalFrameRate.map { max($0, 1) } ?? 30
            vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
            vc.renderSize = renderSize
            vc.instructions = segments.map { seg in
                buildInstruction(
                    clip: seg.clip,
                    track: videoTrack,
                    segmentRange: seg.composedRange
                )
            }
            videoComposition = vc
        } else {
            videoComposition = nil
        }

        // Passthrough requires same size + same codec + same fps + no edits.
        let canPassthrough = !anyEdit && allSameSize && allSameCodec && allSameFrameRate

        return Plan(
            composition: composition,
            videoComposition: videoComposition,
            renderSize: renderSize,
            canPassthrough: canPassthrough
        )
    }

    /// Drives the export. Two branches:
    /// - Passthrough: AVAssetExportPresetPassthrough — fast, lossless, no
    ///   re-encode. Settings are mostly ignored on this path (only
    ///   `optimizesForNetwork` and `outputFileType` apply).
    /// - Re-encode: hands off to `CompressionService.encode(...)` so the
    ///   Compress flow's progress / cancellation / preset-name plumbing is
    ///   reused.
    func export(
        plan: Plan,
        settings: CompressionSettings,
        outputURL: URL,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {
        if plan.canPassthrough {
            do {
                return try await runPassthrough(
                    composition: plan.composition,
                    outputURL: outputURL,
                    optimizesForNetwork: settings.optimizesForNetwork,
                    onProgress: onProgress
                )
            } catch CompressionError.cancelled {
                throw CompressionError.cancelled
            } catch {
                // Passthrough is finicky — codec subtype matched but profile,
                // colorspace, or other format-description fields can still
                // make AVFoundation refuse the sample copy. Fall back to the
                // re-encode path rather than surfacing an unrecoverable error
                // to the user (closes review {E-0503-1114} H1).
                return try await runReencode(
                    plan: plan,
                    settings: settings,
                    outputURL: outputURL,
                    onProgress: onProgress
                )
            }
        }

        return try await runReencode(
            plan: plan,
            settings: settings,
            outputURL: outputURL,
            onProgress: onProgress
        )
    }

    private func runReencode(
        plan: Plan,
        settings: CompressionSettings,
        outputURL: URL,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {
        let service = CompressionService()
        return try await service.encode(
            asset: plan.composition,
            videoComposition: plan.videoComposition,
            settings: settings,
            outputURL: outputURL,
            onProgress: onProgress
        )
    }

    // MARK: - Private helpers

    /// Builds a single videoComposition layer instruction for a clip whose
    /// `edits` are non-identity. Combines rotation (about the clip centre)
    /// and crop into one transform plus an optional crop rectangle.
    ///
    /// The layer instruction's time range lives in **composition** time
    /// (where this segment was inserted), not source time.
    private func buildInstruction(
        clip: StitchClip,
        track: AVMutableCompositionTrack,
        segmentRange: CMTimeRange
    ) -> AVMutableVideoCompositionInstruction {
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

        // Rotation: setTransform is applied as a single transform across the
        // whole segment. We rotate about the clip's natural centre so the
        // visible content stays roughly in-frame for 90/270 degrees, but the
        // export render size in v1 is the source size — meaning a 90°
        // rotation of a landscape clip will render letterboxed inside the
        // landscape canvas. Acceptable for v1; Phase 3 can compute a
        // tight render size.
        if clip.edits.rotationDegrees != 0 {
            let radians = CGFloat(clip.edits.rotationDegrees) * .pi / 180
            let size = clip.naturalSize
            // Rotate about the clip centre by translating to centre, rotating,
            // then translating back. Pre-multiplied so order is rotate-first.
            let toCentre = CGAffineTransform(
                translationX: -size.width / 2,
                y: -size.height / 2
            )
            let rotate = CGAffineTransform(rotationAngle: radians)
            let fromCentre = CGAffineTransform(
                translationX: size.width / 2,
                y: size.height / 2
            )
            let combined = toCentre.concatenating(rotate).concatenating(fromCentre)
            layer.setTransform(combined, at: segmentRange.start)
        }

        // Crop: setCropRectangle expects clip-space pixel coordinates. We
        // store crop in normalized 0...1 over the clip's natural size, so
        // we de-normalize here.
        if let crop = clip.edits.cropNormalized {
            let pixelRect = CGRect(
                x: crop.origin.x * clip.naturalSize.width,
                y: crop.origin.y * clip.naturalSize.height,
                width: crop.size.width * clip.naturalSize.width,
                height: crop.size.height * clip.naturalSize.height
            )
            layer.setCropRectangle(pixelRect, at: segmentRange.start)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = segmentRange
        instruction.layerInstructions = [layer]
        return instruction
    }

    /// AVAssetExportPresetPassthrough run. Mirrors the polling/progress
    /// shape used by `CompressionService.encode` so callers see identical
    /// progress events on either path.
    private func runPassthrough(
        composition: AVMutableComposition,
        outputURL: URL,
        optimizesForNetwork: Bool,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw CompressionError.exporterUnavailable(AVAssetExportPresetPassthrough)
        }

        try? FileManager.default.removeItem(at: outputURL)
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = optimizesForNetwork

        let progressTask = Task { @MainActor [weak exporter] in
            while !Task.isCancelled {
                guard let exporter else { return }
                onProgress(BoundedProgress(Double(exporter.progress)))
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
            }
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exporter.exportAsynchronously {
                    continuation.resume()
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }

        progressTask.cancel()
        await MainActor.run { onProgress(.complete) }

        switch exporter.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw CompressionError.cancelled
        case .failed:
            let nsErr = exporter.error as NSError?
            let detail = nsErr.map { "[\($0.domain) \($0.code)] \($0.localizedDescription)" } ?? "Unknown export error"
            throw CompressionError.exportFailed("Stitch passthrough failed: \(detail)")
        @unknown default:
            throw CompressionError.exportFailed("Stitch passthrough reached non-terminal state.")
        }
    }
}
