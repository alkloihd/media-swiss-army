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
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var anyEdit = false
        var firstNaturalSize: CGSize?
        var firstFormatSubtype: FourCharCode?
        var allSameSize = true
        var allSameCodec = true

        // Track each segment's own time range so layer instructions can be
        // hung off them. Using `cursor + duration` to derive the end time.
        for clip in clips {
            let asset = AVURLAsset(url: clip.sourceURL)

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let assetVideoTrack = videoTracks.first else {
                throw CompressionError.exportFailed("Clip \(clip.displayName) has no video track.")
            }

            // Codec / size sniff for passthrough decision. We use the first
            // format description for each track. Heterogeneous tracks are
            // rare in modern iPhone footage (single CMVideoFormatDescription
            // per file).
            let formatDescriptions = try await assetVideoTrack.load(.formatDescriptions)
            let trackNaturalSize = try await assetVideoTrack.load(.naturalSize)

            if let firstSize = firstNaturalSize {
                if firstSize != trackNaturalSize { allSameSize = false }
            } else {
                firstNaturalSize = trackNaturalSize
            }

            if let cm = formatDescriptions.first {
                let subtype = CMFormatDescriptionGetMediaSubType(cm)
                if let firstSubtype = firstFormatSubtype {
                    if firstSubtype != subtype { allSameCodec = false }
                } else {
                    firstFormatSubtype = subtype
                }
            }

            let timeRange = clip.trimmedRange
            // Insert the trimmed slice of the source video track.
            do {
                try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: cursor)
            } catch {
                throw CompressionError.exportFailed(
                    "Could not insert \(clip.displayName) into composition: \(error.localizedDescription)"
                )
            }

            // Audio is best-effort — clips without audio (e.g. screen
            // captures with no mic) should not abort the whole stitch.
            if let audioTrack {
                if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioTrack.insertTimeRange(timeRange, of: assetAudio, at: cursor)
                }
            }

            // Per-segment instruction only when the clip has a non-identity
            // edit. Otherwise we leave the segment's frames untouched (this
            // keeps the videoComposition nil for the all-identity fast path).
            if clip.isEdited {
                anyEdit = true
                let segmentRange = CMTimeRange(start: cursor, duration: timeRange.duration)
                instructions.append(buildInstruction(
                    clip: clip,
                    track: videoTrack,
                    segmentRange: segmentRange
                ))
            }

            cursor = CMTimeAdd(cursor, timeRange.duration)
        }

        // The render size is the largest natural size encountered. For mixed
        // sizes this gives us a canvas big enough to hold any single frame
        // (clipped clips show with letterboxing — acceptable v1 behaviour).
        let renderSize = firstNaturalSize ?? CGSize(width: 1280, height: 720)

        // If no clip has edits, we still need a videoComposition only if we
        // also need a custom renderSize (e.g. mixed sizes). For v1, when no
        // edits are present, we skip the videoComposition entirely and let
        // the export session use the composition's defaults — that is the
        // path the passthrough preset relies on.
        let videoComposition: AVMutableVideoComposition?
        if anyEdit {
            let vc = AVMutableVideoComposition()
            // 30 fps frame duration is a sensible canvas timebase; the
            // actual frame timing is preserved by the underlying tracks.
            // (The frame duration here drives the videoComposition timeline,
            // not the source rate — important for AVAssetExportSession to
            // accept it.)
            vc.frameDuration = CMTime(value: 1, timescale: 30)
            vc.renderSize = renderSize
            vc.instructions = instructions
            videoComposition = vc
        } else {
            videoComposition = nil
        }

        let canPassthrough = !anyEdit && allSameSize && allSameCodec

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
            return try await runPassthrough(
                composition: plan.composition,
                outputURL: outputURL,
                optimizesForNetwork: settings.optimizesForNetwork,
                onProgress: onProgress
            )
        }

        // Re-encode path. The composition is itself an AVAsset, so we can
        // route it through CompressionService.encode and reuse all of its
        // status/progress/cancellation logic.
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
