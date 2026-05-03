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
        /// Audio mix carrying volume ramps for transitions. nil when there
        /// are no transitions (single audio track passthrough is fine).
        let audioMix: AVMutableAudioMix?
        let renderSize: CGSize
        let canPassthrough: Bool
        /// Temp .mov files baked from still images during buildPlan. The
        /// caller (StitchProject.runExport) is expected to delete these
        /// after export completes — they live in NSTemporaryDirectory
        /// which iOS doesn't reliably reap on its own.
        let bakedStillURLs: [URL]
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
    func buildPlan(
        from clips: [StitchClip],
        aspectMode: StitchAspectMode = .auto,
        transition: StitchTransition = .none
    ) async throws -> Plan {
        guard !clips.isEmpty else {
            throw CompressionError.exportFailed("Stitch export requires at least one clip.")
        }
        // Bake any still-image clips to temp .mov files so the rest of the
        // composition pipeline can treat them uniformly.
        let baker = StillVideoBaker()
        var bakedClips: [StitchClip] = []
        var bakedStillURLs: [URL] = []
        for clip in clips {
            // Honour cancellation between bakes — a 10-still bake otherwise
            // wastes seconds of work after the user taps Cancel.
            try Task.checkCancellation()
            if clip.kind == .still {
                let stillDuration = clip.edits.stillDuration ?? 3.0
                let clamped = min(10.0, max(1.0, stillDuration))
                let bakedURL = try await baker.bake(
                    still: clip.sourceURL,
                    duration: clamped
                )
                bakedStillURLs.append(bakedURL)
                var bakedEdits = clip.edits
                bakedEdits.trimStartSeconds = 0
                bakedEdits.trimEndSeconds = clamped
                let baked = StitchClip(
                    id: clip.id,
                    sourceURL: bakedURL,
                    displayName: clip.displayName,
                    naturalDuration: CMTime(seconds: clamped, preferredTimescale: 600),
                    naturalSize: clip.naturalSize,
                    kind: .video,
                    preferredTransform: .identity,
                    edits: bakedEdits
                )
                bakedClips.append(baked)
            } else {
                bakedClips.append(clip)
            }
        }
        let clips = bakedClips

        let composition = AVMutableComposition()
        guard let videoTrackA = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CompressionError.exportFailed("Could not create composition video track.")
        }
        let audioTrackA = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        // Second video + audio track pair for A/B-roll when transitions are
        // enabled. Adjacent clips alternate tracks so they can OVERLAP in
        // composition time without one stomping the other on a single track.
        let needsAB = transition != .none && clips.count >= 2
        let videoTrackB: AVMutableCompositionTrack? = needsAB
            ? composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            : nil
        let audioTrackB: AVMutableCompositionTrack? = needsAB
            ? composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            : nil

        let transitionDuration: CMTime = needsAB
            ? CMTime(seconds: StitchTransition.durationSeconds, preferredTimescale: 600)
            : .zero

        var cursor: CMTime = .zero
        // Per-segment records keep cursor positions and which track the clip
        // went on so we can emit the full instructions list — solo per clip
        // plus a per-gap dual-layer transition instruction when needed.
        struct Segment {
            let clip: StitchClip
            let composedRange: CMTimeRange
            let videoTrack: AVMutableCompositionTrack
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

            // Alternate tracks A/B when transitions are on so adjacent clips
            // can OVERLAP in composition time without stomping each other.
            let useTrackB = needsAB && (segments.count % 2 == 1)
            let videoT = useTrackB ? videoTrackB! : videoTrackA
            let audioT: AVMutableCompositionTrack? = useTrackB ? audioTrackB : audioTrackA

            // For clips after the first, when transitions are on, pull the
            // insertion cursor back by transitionDuration so the new clip
            // overlaps the tail of the previous clip. The previous clip's
            // tail is on the OTHER track, so insertions don't collide.
            let insertAt = (segments.isEmpty || !needsAB)
                ? cursor
                : CMTimeMaximum(.zero, CMTimeSubtract(cursor, transitionDuration))

            do {
                try videoT.insertTimeRange(timeRange, of: assetVideoTrack, at: insertAt)
            } catch {
                throw CompressionError.exportFailed(
                    "Could not insert \(clip.displayName) into composition: \(error.localizedDescription)"
                )
            }

            if let audioT {
                if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioT.insertTimeRange(timeRange, of: assetAudio, at: insertAt)
                }
            }

            let composedRange = CMTimeRange(start: insertAt, duration: timeRange.duration)
            segments.append(Segment(clip: clip, composedRange: composedRange, videoTrack: videoT))
            if clip.isEdited { anyEdit = true }

            cursor = CMTimeAdd(insertAt, timeRange.duration)
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
            vc.instructions = buildInstructions(
                segments: segments.map {
                    (clip: $0.clip, composedRange: $0.composedRange, videoTrack: $0.videoTrack)
                },
                renderSize: renderSize,
                transition: transition,
                transitionDuration: transitionDuration
            )
            videoComposition = vc
        } else {
            videoComposition = nil
        }

        // Passthrough is only safe when the canvas exactly matches every
        // clip's display size AND no transitions are active (transitions
        // need ramps on layer instructions, which the passthrough preset
        // can't honour).
        let canPassthrough = !anyEdit
            && allSameSize
            && allSameCodec
            && allSameFrameRate
            && transition == .none
            && Self.allClipsMatchCanvas(clips: clips, renderSize: renderSize)

        // Audio mix mirrors video opacity ramps so the audio of clip A
        // fades out as clip B's audio fades in during the overlap window.
        // For .none transition there's only one audio track and no mix is
        // needed (CompressionService falls back to single-track output).
        let audioMix: AVMutableAudioMix?
        if needsAB {
            audioMix = buildAudioMix(
                composition: composition,
                segments: segments.map {
                    (clip: $0.clip, composedRange: $0.composedRange, videoTrack: $0.videoTrack)
                },
                transition: transition,
                transitionDuration: transitionDuration
            )
        } else {
            audioMix = nil
        }

        return Plan(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            renderSize: renderSize,
            canPassthrough: canPassthrough,
            bakedStillURLs: bakedStillURLs
        )
    }

    /// Build the audio mix that pairs with the video transitions. For each
    /// clip's audio track, set a constant 1.0 volume EXCEPT during the
    /// overlap windows at its head (fade in) and tail (fade out), which use
    /// `setVolumeRamp` to crossfade with the adjacent clip.
    private func buildAudioMix(
        composition: AVMutableComposition,
        segments: [(clip: StitchClip, composedRange: CMTimeRange, videoTrack: AVMutableCompositionTrack)],
        transition: StitchTransition,
        transitionDuration: CMTime
    ) -> AVMutableAudioMix? {
        let audioTracks = composition.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty, segments.count >= 2 else { return nil }

        let mix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []

        for (i, seg) in segments.enumerated() {
            // The audio track for this segment was inserted on the same
            // alternating A/B as the video. Find which composition audio
            // track holds this clip's audio by matching the index parity.
            let trackIdx = audioTracks.count == 1 ? 0 : (i % 2)
            guard trackIdx < audioTracks.count else { continue }
            let track = audioTracks[trackIdx]

            let p = AVMutableAudioMixInputParameters(track: track)

            // Default: full volume across the clip's composed range.
            p.setVolume(1.0, at: seg.composedRange.start)

            // Head fade-in (overlap with PREVIOUS clip on the other track).
            if i > 0 {
                let prev = segments[i - 1]
                let overlapStart = seg.composedRange.start
                let overlapEnd = prev.composedRange.end
                if overlapEnd > overlapStart {
                    let overlap = CMTimeRange(start: overlapStart, end: overlapEnd)
                    let variant = Self.resolveTransition(transition, gapIndex: i - 1)
                    switch variant {
                    case .fadeToBlack:
                        // First half is silent (both faded), second half ramps in.
                        let half = CMTimeMultiplyByFloat64(overlap.duration, multiplier: 0.5)
                        let secondHalf = CMTimeRange(
                            start: CMTimeAdd(overlap.start, half),
                            duration: CMTimeSubtract(overlap.duration, half)
                        )
                        p.setVolume(0.0, at: overlap.start)
                        p.setVolumeRamp(
                            fromStartVolume: 0.0,
                            toEndVolume: 1.0,
                            timeRange: secondHalf
                        )
                    case .crossfade, .wipeLeft, .random, .none:
                        // Linear ramp from 0 → 1 mirrors the video reveal.
                        p.setVolumeRamp(
                            fromStartVolume: 0.0,
                            toEndVolume: 1.0,
                            timeRange: overlap
                        )
                    }
                }
            }

            // Tail fade-out (overlap with NEXT clip on the other track).
            if i + 1 < segments.count {
                let next = segments[i + 1]
                let overlapStart = next.composedRange.start
                let overlapEnd = seg.composedRange.end
                if overlapEnd > overlapStart {
                    let overlap = CMTimeRange(start: overlapStart, end: overlapEnd)
                    let variant = Self.resolveTransition(transition, gapIndex: i)
                    switch variant {
                    case .fadeToBlack:
                        // First half ramps out, second half silent.
                        let half = CMTimeMultiplyByFloat64(overlap.duration, multiplier: 0.5)
                        let firstHalf = CMTimeRange(start: overlap.start, duration: half)
                        p.setVolumeRamp(
                            fromStartVolume: 1.0,
                            toEndVolume: 0.0,
                            timeRange: firstHalf
                        )
                    case .crossfade, .wipeLeft, .random, .none:
                        p.setVolumeRamp(
                            fromStartVolume: 1.0,
                            toEndVolume: 0.0,
                            timeRange: overlap
                        )
                    }
                }
            }

            params.append(p)
        }

        mix.inputParameters = params
        return mix
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
            audioMix: plan.audioMix,
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

    // MARK: - Instructions emission

    /// Build the full ordered instructions list. When `transition == .none`,
    /// emits one solo instruction per segment (legacy behaviour). Otherwise,
    /// emits a per-clip "solo" instruction plus a per-gap "transition"
    /// instruction with two layer instructions (out + in, both with ramps)
    /// covering the overlap window.
    ///
    /// AVFoundation contract: `instructions` must cover the timeline
    /// contiguously without gaps.
    private struct SegmentInfo {
        let clip: StitchClip
        let composedRange: CMTimeRange
        let videoTrack: AVMutableCompositionTrack
    }

    private func buildInstructions(
        segments: [(clip: StitchClip, composedRange: CMTimeRange, videoTrack: AVMutableCompositionTrack)],
        renderSize: CGSize,
        transition: StitchTransition,
        transitionDuration: CMTime
    ) -> [AVMutableVideoCompositionInstruction] {
        var out: [AVMutableVideoCompositionInstruction] = []
        guard !segments.isEmpty else { return out }

        // Single-clip case: just one solo instruction covering the whole
        // composition. No transitions possible.
        if segments.count == 1 || transition == .none {
            for (i, seg) in segments.enumerated() {
                let _ = i
                out.append(makeInstruction(
                    layers: [makeAspectFitLayer(
                        clip: seg.clip,
                        track: seg.videoTrack,
                        timeRange: seg.composedRange,
                        renderSize: renderSize
                    )],
                    range: seg.composedRange
                ))
            }
            return out
        }

        // Multi-clip with transitions. Walk the segments. Each segment's
        // composedRange may overlap the next segment's start by exactly
        // `transitionDuration` (enforced by the insert loop).
        for (i, seg) in segments.enumerated() {
            let next: (clip: StitchClip, composedRange: CMTimeRange, videoTrack: AVMutableCompositionTrack)? =
                i + 1 < segments.count ? segments[i + 1] : nil

            let soloEnd = next.map { $0.composedRange.start } ?? seg.composedRange.end
            let soloRange = CMTimeRange(start: seg.composedRange.start, end: soloEnd)
            if soloRange.duration > .zero {
                out.append(makeInstruction(
                    layers: [makeAspectFitLayer(
                        clip: seg.clip,
                        track: seg.videoTrack,
                        timeRange: soloRange,
                        renderSize: renderSize
                    )],
                    range: soloRange
                ))
            }

            // Gap (overlap) between this clip and the next.
            if let n = next {
                let gapRange = CMTimeRange(start: n.composedRange.start, end: seg.composedRange.end)
                if gapRange.duration > .zero {
                    let variant = Self.resolveTransition(transition, gapIndex: i)
                    let layerOut = makeAspectFitLayer(
                        clip: seg.clip,
                        track: seg.videoTrack,
                        timeRange: gapRange,
                        renderSize: renderSize
                    )
                    let layerIn = makeAspectFitLayer(
                        clip: n.clip,
                        track: n.videoTrack,
                        timeRange: gapRange,
                        renderSize: renderSize
                    )
                    applyTransition(
                        variant: variant,
                        layerOut: layerOut,
                        layerIn: layerIn,
                        clipOut: seg.clip,
                        clipIn: n.clip,
                        gapRange: gapRange,
                        renderSize: renderSize
                    )
                    // Order matters: layerIn rendered FIRST (bottom),
                    // layerOut on top, so for crossfade ramping layerOut to 0
                    // reveals layerIn. AVFoundation paints first instruction
                    // first → topmost layer is the LAST in the array.
                    out.append(makeInstruction(
                        layers: [layerIn, layerOut],
                        range: gapRange
                    ))
                }
            }
        }

        return out
    }

    private func makeInstruction(
        layers: [AVMutableVideoCompositionLayerInstruction],
        range: CMTimeRange
    ) -> AVMutableVideoCompositionInstruction {
        let inst = AVMutableVideoCompositionInstruction()
        inst.timeRange = range
        inst.backgroundColor = UIColor.black.cgColor
        inst.layerInstructions = layers
        return inst
    }

    /// Build a layer instruction with the aspect-fit transform but with no
    /// transition ramps. Identical math to `buildInstruction` (legacy entry
    /// point), but emits a layer rather than an instruction so callers can
    /// compose multiple layers into a single instruction (transitions).
    private func makeAspectFitLayer(
        clip: StitchClip,
        track: AVMutableCompositionTrack,
        timeRange: CMTimeRange,
        renderSize: CGSize
    ) -> AVMutableVideoCompositionLayerInstruction {
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        var t = clip.preferredTransform

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

        layer.setTransform(t, at: timeRange.start)

        if let crop = clip.edits.cropNormalized {
            let pixelRect = CGRect(
                x: crop.origin.x * clip.naturalSize.width,
                y: crop.origin.y * clip.naturalSize.height,
                width: crop.size.width * clip.naturalSize.width,
                height: crop.size.height * clip.naturalSize.height
            )
            layer.setCropRectangle(pixelRect, at: timeRange.start)
        }

        return layer
    }

    /// Apply a transition's ramps to the OUT (current clip) and IN (next
    /// clip) layer instructions over the overlap window.
    private func applyTransition(
        variant: StitchTransition,
        layerOut: AVMutableVideoCompositionLayerInstruction,
        layerIn: AVMutableVideoCompositionLayerInstruction,
        clipOut: StitchClip,
        clipIn: StitchClip,
        gapRange: CMTimeRange,
        renderSize: CGSize
    ) {
        switch variant {
        case .none, .random:
            // .random already resolved to a concrete variant before this call.
            // .none should never reach this code path (instruction emission
            // guards against it). Defensive no-op.
            return

        case .crossfade:
            // Outgoing fades 1 → 0; incoming is fully visible the whole time
            // and gets revealed as outgoing fades. We're rendering layerIn
            // BELOW layerOut (see makeInstruction layer order).
            layerOut.setOpacityRamp(
                fromStartOpacity: 1.0,
                toEndOpacity: 0.0,
                timeRange: gapRange
            )
            // layerIn stays at default (1.0) opacity; visible through the
            // outgoing as it fades.

        case .fadeToBlack:
            // Two phases: first half outgoing fades to 0 (revealing black);
            // second half incoming fades from 0 to 1.
            let halfDuration = CMTimeMultiplyByFloat64(gapRange.duration, multiplier: 0.5)
            let firstHalf = CMTimeRange(start: gapRange.start, duration: halfDuration)
            let secondHalf = CMTimeRange(
                start: CMTimeAdd(gapRange.start, halfDuration),
                duration: CMTimeSubtract(gapRange.duration, halfDuration)
            )
            layerOut.setOpacityRamp(
                fromStartOpacity: 1.0,
                toEndOpacity: 0.0,
                timeRange: firstHalf
            )
            layerIn.setOpacityRamp(
                fromStartOpacity: 0.0,
                toEndOpacity: 1.0,
                timeRange: secondHalf
            )

        case .wipeLeft:
            // Source-pixel crop animation: outgoing's crop shrinks from full
            // width → zero width starting at the LEFT edge (so the right
            // side is wiped away first, traveling left). Incoming's crop
            // grows from zero width at right edge → full width.
            //
            // setCropRectangleRamp uses CLIP-SOURCE pixel coordinates,
            // applied BEFORE setTransform. Since our setTransform
            // aspect-fits the cropped portion onto the canvas, the visible
            // aspect-fit rect on the canvas tracks the crop linearly —
            // a left-wipe in source space appears as a left-wipe on the
            // rendered canvas (with the visible portion progressively
            // narrowing).
            let outW = clipOut.naturalSize.width
            let outH = clipOut.naturalSize.height
            let outFullCrop = CGRect(x: 0, y: 0, width: outW, height: outH)
            let outEndCrop = CGRect(x: 0, y: 0, width: 1, height: outH) // 1px to avoid division-by-zero in renderer
            layerOut.setCropRectangleRamp(
                fromStartCropRectangle: outFullCrop,
                toEndCropRectangle: outEndCrop,
                timeRange: gapRange
            )

            let inW = clipIn.naturalSize.width
            let inH = clipIn.naturalSize.height
            let inStartCrop = CGRect(x: max(0, inW - 1), y: 0, width: 1, height: inH)
            let inEndCrop = CGRect(x: 0, y: 0, width: inW, height: inH)
            layerIn.setCropRectangleRamp(
                fromStartCropRectangle: inStartCrop,
                toEndCropRectangle: inEndCrop,
                timeRange: gapRange
            )
        }
    }

    /// Resolve a transition setting to a concrete variant. `.random` picks
    /// per-gap from {crossfade, fadeToBlack, wipeLeft} using the gap index
    /// as a stable seed so re-renders produce the same picks.
    static func resolveTransition(
        _ transition: StitchTransition,
        gapIndex: Int
    ) -> StitchTransition {
        switch transition {
        case .none, .crossfade, .fadeToBlack, .wipeLeft:
            return transition
        case .random:
            // Deterministic round-robin keyed on gap index. Avoids
            // non-deterministic re-renders.
            let pool: [StitchTransition] = [.crossfade, .fadeToBlack, .wipeLeft]
            return pool[gapIndex % pool.count]
        }
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
