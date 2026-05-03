//
//  StitchClip.swift
//  VideoCompressor
//
//  Value types for the Stitch feature. `StitchClip` represents one imported
//  clip in the timeline. `ClipEdits` holds all lazy, non-destructive edits
//  (trim, crop, rotation) that are only applied at export time.
//

import Foundation
import AVFoundation
import CoreGraphics

/// What kind of media a `StitchClip` represents. Phase 3 commit 5 added
/// stills as a first-class import target. Composition rendering for stills
/// (single-frame video segment via `AVAssetWriterInputPixelBufferAdaptor`)
/// is a Phase 3 commit 6 follow-up — for this commit, stills CAN be added
/// to the timeline but cannot yet be exported.
enum ClipKind: String, Sendable, Hashable {
    case video
    case still
}

/// Transitions between adjacent clips in a stitch. All effects use built-in
/// AVFoundation APIs (no custom AVVideoCompositing class), so they're
/// GPU-accelerated and run at near-zero CPU cost during render.
///
/// Cost summary at 1080p: each transition adds ~5-10% to the render time of
/// the OVERLAPPING window (typically 1s per clip-gap), nothing during the
/// non-transition portion.
enum StitchTransition: String, CaseIterable, Hashable, Sendable, Identifiable {
    case none
    case crossfade      // both clips visible, opacities ramp opposing
    case fadeToBlack    // clip A fades to black (0.5s), clip B fades from black (0.5s)
    case wipeLeft       // clip A's crop shrinks rightward, clip B's grows from left
    case random         // pick one of {crossfade, fadeToBlack, wipeLeft} per gap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:        return "None"
        case .crossfade:   return "Crossfade"
        case .fadeToBlack: return "Fade Black"
        case .wipeLeft:    return "Wipe"
        case .random:      return "Random"
        }
    }

    var systemImage: String {
        switch self {
        case .none:        return "arrow.right.to.line"
        case .crossfade:   return "circle.lefthalf.filled"
        case .fadeToBlack: return "moonphase.first.quarter"
        case .wipeLeft:    return "arrow.left.and.right"
        case .random:      return "shuffle"
        }
    }

    /// Duration of the transition in seconds. 1.0s is the standard editor
    /// default and matches user request. Transitions are centred on the clip
    /// boundary, i.e. they consume 0.5s of clip A's tail + 0.5s of clip B's head.
    static let durationSeconds: Double = 1.0
}

/// Aspect-ratio canvas mode for the stitched output. `.auto` picks orientation
/// from a majority vote across the clips (fall-back: landscape on tie). The
/// explicit modes use canonical 1080-edge sizes. Mismatched clips render with
/// black bars (letterbox / pillarbox) instead of being cropped — that was the
/// pre-fix behaviour and the user's main complaint.
enum StitchAspectMode: String, CaseIterable, Hashable, Sendable, Identifiable {
    case auto
    case portrait
    case landscape
    case square

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:      return "Auto"
        case .portrait:  return "9:16"
        case .landscape: return "16:9"
        case .square:    return "1:1"
        }
    }

    var systemImage: String {
        switch self {
        case .auto:      return "rectangle.dashed"
        case .portrait:  return "rectangle.portrait"
        case .landscape: return "rectangle"
        case .square:    return "square"
        }
    }

    /// Canonical render size for the explicit modes. `.auto` returns nil and
    /// callers compute from clip orientation distribution.
    var fixedRenderSize: CGSize? {
        switch self {
        case .portrait:  return CGSize(width: 1080, height: 1920)
        case .landscape: return CGSize(width: 1920, height: 1080)
        case .square:    return CGSize(width: 1080, height: 1080)
        case .auto:      return nil
        }
    }
}

struct StitchClip: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    let naturalDuration: CMTime
    let naturalSize: CGSize
    /// Defaults to `.video` for source-compat with all existing call sites
    /// that construct StitchClip without specifying a kind.
    let kind: ClipKind
    /// AVAssetTrack.preferredTransform — captured at import. iPhone portrait
    /// videos report `naturalSize = (1920, 1080)` PRE-rotation; the
    /// preferredTransform is a 90° rotation that flips them upright. Without
    /// applying this in the composition layer instructions, portrait clips
    /// render sideways and aspect-fit math is wrong. Defaults to `.identity`
    /// for backward compat with old call sites + tests.
    let preferredTransform: CGAffineTransform
    var edits: ClipEdits

    init(
        id: UUID,
        sourceURL: URL,
        displayName: String,
        naturalDuration: CMTime,
        naturalSize: CGSize,
        kind: ClipKind = .video,
        preferredTransform: CGAffineTransform = .identity,
        edits: ClipEdits
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.naturalDuration = naturalDuration
        self.naturalSize = naturalSize
        self.kind = kind
        self.preferredTransform = preferredTransform
        self.edits = edits
    }

    /// Display-space size after applying `preferredTransform`. Use this for
    /// orientation comparisons and aspect-fit math — `naturalSize` alone is
    /// in pre-rotation pixel space and gives wrong answers for iPhone
    /// portrait video.
    var displaySize: CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Coarse orientation classification used by `.auto` aspect mode.
    var displayOrientation: DisplayOrientation {
        let s = displaySize
        guard s.width > 0, s.height > 0 else { return .square }
        if s.width > s.height * 1.05 { return .landscape }
        if s.height > s.width * 1.05 { return .portrait }
        return .square
    }

    enum DisplayOrientation: Sendable, Hashable {
        case landscape, portrait, square
    }

    /// The source-clip time range to insert into an AVMutableComposition.
    /// Both ends are clamped to [0, naturalDuration]. Uses timescale 600
    /// (sub-frame precision; standard for AVFoundation composition work)
    /// and rounds (rather than truncates) so non-600-timescale sources
    /// don't lose ticks.
    var trimmedRange: CMTimeRange {
        let natural = CMTimeGetSeconds(naturalDuration)
        let start = edits.trimStartSeconds ?? 0
        let end = edits.trimEndSeconds ?? natural
        let clampedStart = max(0, min(start, natural))
        let clampedEnd = min(natural, max(clampedStart, end))
        let startTime = CMTimeMakeWithSeconds(clampedStart, preferredTimescale: 600)
        let endTime = CMTimeMakeWithSeconds(clampedEnd, preferredTimescale: 600)
        return CMTimeRangeFromTimeToTime(start: startTime, end: endTime)
    }

    /// Effective duration after trim, in seconds. Single source of truth
    /// derived from `trimmedRange` so the timeline label and the export
    /// composition can never disagree (closes review {E-0503-1032} H1).
    var trimmedDurationSeconds: Double {
        CMTimeGetSeconds(trimmedRange.duration)
    }

    /// Returns true if ANY field on `edits` differs from `.identity`.
    /// Useful for the StitchExporter passthrough check.
    var isEdited: Bool {
        edits != .identity
    }
}

struct ClipEdits: Hashable, Sendable {
    /// nil = use clip start (0). In source clip seconds.
    var trimStartSeconds: Double?
    /// nil = use clip end (naturalDuration). In source clip seconds.
    var trimEndSeconds: Double?
    /// Crop rect in normalized 0...1 coordinates over the clip's natural size.
    /// nil = no crop.
    var cropNormalized: CGRect?
    /// 0 / 90 / 180 / 270 — clockwise rotation applied at render time.
    var rotationDegrees: Int
    /// Display duration in seconds for `.still` clips. Ignored for `.video`.
    /// Phase 3 commit 5 stores this; commit 6 honors it during composition.
    /// Default 3.0 s per backlog spec; clamped to [0.5, 10.0] at the editor
    /// boundary, not here (model is permissive).
    var stillDuration: Double?

    static let identity = ClipEdits(
        trimStartSeconds: nil,
        trimEndSeconds: nil,
        cropNormalized: nil,
        rotationDegrees: 0,
        stillDuration: nil
    )
}
