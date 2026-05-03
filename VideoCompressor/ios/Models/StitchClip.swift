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

struct StitchClip: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    let naturalDuration: CMTime
    let naturalSize: CGSize
    /// Defaults to `.video` for source-compat with all existing call sites
    /// that construct StitchClip without specifying a kind.
    let kind: ClipKind
    var edits: ClipEdits

    init(
        id: UUID,
        sourceURL: URL,
        displayName: String,
        naturalDuration: CMTime,
        naturalSize: CGSize,
        kind: ClipKind = .video,
        edits: ClipEdits
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.naturalDuration = naturalDuration
        self.naturalSize = naturalSize
        self.kind = kind
        self.edits = edits
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
