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

struct StitchClip: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    let naturalDuration: CMTime
    let naturalSize: CGSize
    var edits: ClipEdits

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

    static let identity = ClipEdits(
        trimStartSeconds: nil,
        trimEndSeconds: nil,
        cropNormalized: nil,
        rotationDegrees: 0
    )
}
