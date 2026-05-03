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

    /// Effective duration after trim, in seconds.
    /// Clamped to [0, naturalDuration].
    var trimmedDurationSeconds: Double {
        let natural = CMTimeGetSeconds(naturalDuration)
        let start = edits.trimStartSeconds ?? 0
        let end = edits.trimEndSeconds ?? natural
        return min(natural, max(0, end - start))
    }

    /// The source-clip time range to insert into an AVMutableComposition.
    /// Both ends use timescale 600 for sub-frame precision.
    var trimmedRange: CMTimeRange {
        let natural = CMTimeGetSeconds(naturalDuration)
        let start = edits.trimStartSeconds ?? 0
        let end = edits.trimEndSeconds ?? natural
        let clampedStart = max(0, start)
        let clampedEnd = min(natural, max(clampedStart, end))
        let startTime = CMTimeMake(value: Int64(clampedStart * 600), timescale: 600)
        let endTime = CMTimeMake(value: Int64(clampedEnd * 600), timescale: 600)
        return CMTimeRangeFromTimeToTime(start: startTime, end: endTime)
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
