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
import UIKit
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
    ///
    /// `aspectMode` controls the output canvas:
    /// - `.auto` (default): majority-vote on clip orientation
    /// - `.portrait` / `.landscape` / `.square`: pin a fixed 1080-edge canvas
    /// In all modes, mismatched clips render with letterbox / pillarbox bars
    /// rather than being cropped.
    func buildPlan(from clips: [StitchClip], aspectMode: StitchAspectMode = .auto) async throws -> Plan {
        guard !clips.isEmpty else {
            throw CompressionError.exportFailed("Stitch export requires at least one clip.")
        }
        // Phase 3 commit 5: stills can be added to the timeline but cannot
        // yet be exported. Composition rendering for stills (single-frame
        // video segment via AVAssetWriterInputPixelBufferAdaptor) lands in
        // commit 6. Fail gracefully here rather than producing a confusing
        // AVFoundation error.
        if clips.contains(where: { $0.kind == .still }) {
            throw CompressionError.exportFailed(
                "Photo clips can be added to the timeline but stitch export with photos is coming soon. Remove photo clips and re-export."
            )
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

        // Render size derives from aspect mode. `.auto` votes from clip
        // display orientations (majority wins; landscape on tie); explicit
        // modes pin canonical 1080-edge sizes. We ALWAYS emit a real canvas
        // (no shrink-to-fit on the smallest clip) so users get predictable
        // 16:9 / 9:16 output regardless of which clips are present.
        let renderSize = Self.computeRenderSize(
            aspectMode: aspectMode,
            clips: segments.map(\.clip),
            fallback: maxNaturalSize == .zero
                ? CGSize(width: 1920, height: 1080)
                : maxNaturalSize
        )

        // We ALWAYS emit a videoComposition now — even with no user edits —
        // because the aspect-fit transform is a per-clip render-time concern.
        // A missing videoComposition would let AVFoundation use the source's
        // own preferredTransform without scaling onto our canvas, producing
        // crops when the canvas and clip orientations don't match (this was
        // the user-reported bug). The instructions list still covers the
        // timeline contiguously without gaps (closes review {E-0503-1114}
        // C1's invariant).
        let videoComposition: AVMutableVideoComposition?
        if !segments.isEmpty {
            let vc = AVMutableVideoComposition()
            let fps = firstNominalFrameRate.map { max($0, 1) } ?? 30
            vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
            vc.renderSize = renderSize
            vc.instructions = segments.map { seg in
                buildInstruction(
                    clip: seg.clip,
                    track: videoTrack,
                    segmentRange: seg.composedRange,
                    renderSize: renderSize
                )
            }
            videoComposition = vc
        } else {
            videoComposition = nil
        }

        // Passthrough is only safe when the canvas exactly matches every
        // clip's display size — which is now ALSO contingent on aspect mode
        // matching the natural orientation. With aspect-fit always on, we
        // disable passthrough whenever clips disagree with the canvas. This
        // is correctness over speed; users can still get a fast same-size
        // stitch when all clips share the same display aspect.
        let canPassthrough = !anyEdit
            && allSameSize
            && allSameCodec
            && allSameFrameRate
            && Self.allClipsMatchCanvas(clips: clips, renderSize: renderSize)

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

    /// Builds a per-segment layer instruction that:
    /// 1. Applies the clip's `preferredTransform` (rotate iPhone portrait into
    ///    upright orientation)
    /// 2. Applies user rotation edits (about the rotated-display centre)
    /// 3. Scales the rotated display to FIT inside `renderSize` while
    ///    preserving aspect (`min(canvasW/displayW, canvasH/displayH)`)
    /// 4. Translates to centre — black bars (letterbox or pillarbox) fill
    ///    the residual canvas
    /// 5. Applies user crop in clip-space (after step 1's rotation but before
    ///    step 3's scale)
    ///
    /// The transform composition order matters: with CGAffineTransform's
    /// concatenating semantics ("apply self first, then other"), the chain
    /// reads as: preferred → rotation → scale → translate. Tested in
    /// `StitchAspectRatioTests.testTransformComposesInRightOrder`.
    private func buildInstruction(
        clip: StitchClip,
        track: AVMutableCompositionTrack,
        segmentRange: CMTimeRange,
        renderSize: CGSize
    ) -> AVMutableVideoCompositionInstruction {
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

        // Step 1: clip's natural preferred transform (orientation correction).
        var t = clip.preferredTransform

        // Step 2: optional user rotation, applied about the display-space
        // centre. We work in display space (post-preferredTransform) so the
        // rotation is intuitive ("rotate the visible image").
        if clip.edits.rotationDegrees != 0 {
            let radians = CGFloat(clip.edits.rotationDegrees) * .pi / 180
            let display = clip.displaySize
            let cx = display.width / 2
            let cy = display.height / 2
            let toC = CGAffineTransform(translationX: -cx, y: -cy)
            let rot = CGAffineTransform(rotationAngle: radians)
            let fromC = CGAffineTransform(translationX: cx, y: cy)
            t = t.concatenating(toC).concatenating(rot).concatenating(fromC)
        }

        // Step 3 + 4: scale-to-fit on canvas, then centre.
        let display = clip.displaySize
        if display.width > 0, display.height > 0,
           renderSize.width > 0, renderSize.height > 0 {
            let scale = min(
                renderSize.width / display.width,
                renderSize.height / display.height
            )
            let scaledW = display.width * scale
            let scaledH = display.height * scale
            let dx = (renderSize.width - scaledW) / 2
            let dy = (renderSize.height - scaledH) / 2
            t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            t = t.concatenating(CGAffineTransform(translationX: dx, y: dy))
        }

        layer.setTransform(t, at: segmentRange.start)

        // Step 5: optional user crop in clip-space pixel coords (de-normalize
        // from the 0...1 stored value over naturalSize). AVFoundation applies
        // setCropRectangle in clip-source coordinates BEFORE the layer
        // transform — so crop semantics are unaffected by the canvas math.
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
        instruction.backgroundColor = UIColor.black.cgColor
        instruction.layerInstructions = [layer]
        return instruction
    }

    /// Pure function — pinned by `StitchAspectRatioTests`.
    static func computeRenderSize(
        aspectMode: StitchAspectMode,
        clips: [StitchClip],
        fallback: CGSize = CGSize(width: 1920, height: 1080)
    ) -> CGSize {
        if let fixed = aspectMode.fixedRenderSize { return fixed }

        // Auto: majority vote on display orientation.
        var landscape = 0, portrait = 0, square = 0
        for clip in clips {
            switch clip.displayOrientation {
            case .landscape: landscape += 1
            case .portrait:  portrait += 1
            case .square:    square += 1
            }
        }
        // Landscape wins ties (most common phone-shot videos).
        if landscape >= portrait && landscape >= square {
            return CGSize(width: 1920, height: 1080)
        }
        if portrait >= square {
            return CGSize(width: 1080, height: 1920)
        }
        if square > 0 {
            return CGSize(width: 1080, height: 1080)
        }
        return fallback
    }

    /// True when every clip's display size matches the canvas exactly. Used
    /// to gate the passthrough fast path — when this is true and there are
    /// no edits / codec drift / fps drift, we can skip the videoComposition
    /// re-encode entirely.
    static func allClipsMatchCanvas(clips: [StitchClip], renderSize: CGSize) -> Bool {
        clips.allSatisfy { clip in
            let s = clip.displaySize
            return abs(s.width - renderSize.width) < 1.0
                && abs(s.height - renderSize.height) < 1.0
        }
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
            // Translate the most common interruption cause for the user.
            if nsErr?.code == -11847 {
                throw CompressionError.exportFailed(
                    "Stitch was interrupted because the app went to the background or the screen locked for too long. Keep the app open during a stitch — iOS only allows ~30 seconds of background time."
                )
            }
            let detail = nsErr.map { "[\($0.domain) \($0.code)] \($0.localizedDescription)" } ?? "Unknown export error"
            throw CompressionError.exportFailed("Stitch passthrough failed: \(detail)")
        @unknown default:
            throw CompressionError.exportFailed("Stitch passthrough reached non-terminal state.")
        }
    }
}
