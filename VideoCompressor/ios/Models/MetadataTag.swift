//
//  MetadataTag.swift
//  VideoCompressor
//
//  Typed model for the MetaClean tab. Mirrors the web app's exiftool.js
//  output but classifies tags into a small fixed set of categories so the
//  UI can colour-code red (will be stripped) vs green (will be kept).
//
//  See `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` task M1.
//

import Foundation

/// Single classified metadata atom from an `AVMetadataItem`.
///
/// `key` is the raw `AVMetadataIdentifier.rawValue` (e.g.
/// `"com.apple.quicktime.location.ISO6709"`). `value` is a stringified
/// preview suitable for display — for binary blobs we substitute
/// `"<binary, N bytes>"` rather than dumping raw bytes into the UI.
struct MetadataTag: Identifiable, Hashable, Sendable {
    let id: UUID
    let key: String
    let displayName: String
    let value: String
    let category: MetadataCategory
    /// True when the atom matches the Meta Ray-Ban / Meta glasses
    /// fingerprint pattern (binary "Comment" or "Description" with
    /// Ray-Ban / Meta marker bytes). The web app discovered this in
    /// commits `a3ad413` and `be6e360`; we surface it as a first-class
    /// flag so the auto-strip rule can target it exactly without
    /// stripping every `.custom` atom.
    let isMetaFingerprint: Bool
}

/// Coarse classification used for grouping in the inspector and for
/// `StripRules` membership checks.
///
/// `.technical` covers atoms that are intrinsic to the encoded media
/// (codec, framerate, sample rate, etc.) and are NEVER stripped — they
/// would corrupt the file. The strip filter always preserves this
/// category regardless of `StripRules` content.
enum MetadataCategory: String, CaseIterable, Hashable, Sendable {
    case device
    case location
    case time
    case technical
    case custom

    var displayName: String {
        switch self {
        case .device:    return "Device"
        case .location:  return "Location"
        case .time:      return "Time"
        case .technical: return "Technical"
        case .custom:    return "Custom"
        }
    }

    /// SF Symbol name for the category header chip.
    var systemImage: String {
        switch self {
        case .device:    return "camera"
        case .location:  return "location"
        case .time:      return "clock"
        case .technical: return "waveform"
        case .custom:    return "tag"
        }
    }
}

/// User intent for what to strip during `MetadataService.strip`.
///
/// `stripCategories` is a positive set: anything in here is stripped.
/// `.technical` is honoured if added but the service treats it as a no-op
/// (we never strip codec/fps/etc — they're intrinsic).
///
/// `stripMetaFingerprintAlways` overrides category membership for any
/// tag flagged `isMetaFingerprint == true`. Useful for the auto rule
/// that doesn't want to nuke other custom atoms.
struct StripRules: Hashable, Sendable {
    var stripCategories: Set<MetadataCategory>
    var stripMetaFingerprintAlways: Bool

    /// Default for a Meta glasses video: ONLY strip the binary fingerprint
    /// Comment atom (the actual Ray-Ban / Meta AI fingerprint), leaving
    /// every other tag (Device / Location / Time / other custom atoms)
    /// untouched. User can opt into broader stripping via `.stripAll`.
    ///
    /// Per user direction 2026-05-03: "just the meta ai stuff and nothing
    /// else but also i'd like the stitch of videos to automatically strip
    /// of metadata as well please if it's there in the video".
    static let autoMetaGlasses = StripRules(
        stripCategories: [],
        stripMetaFingerprintAlways: true
    )

    /// Strip every category except `.technical`. The "share to a
    /// stranger" preset.
    static let stripAll = StripRules(
        stripCategories: Set(MetadataCategory.allCases).subtracting([.technical]),
        stripMetaFingerprintAlways: true
    )

    /// Strip nothing. Useful as the starting state of the manual mode
    /// builder and as a regression baseline (output should equal input
    /// modulo container rewrite).
    static let identity = StripRules(
        stripCategories: [],
        stripMetaFingerprintAlways: false
    )
}

// MARK: - StripRules helpers

extension StripRules {
    /// Predicts whether a tag would be stripped under these rules.
    /// Mirrors `MetadataService.shouldStrip(tag:rules:)` exactly so the
    /// MetadataInspectorView can show red/green indicators without running
    /// the full remux pipeline.
    ///
    /// Note: `.technical` is never stripped even if included in
    /// `stripCategories` — that mirrors the service's guard.
    func willStrip(_ tag: MetadataTag) -> Bool {
        if tag.category == .technical { return false }
        if tag.isMetaFingerprint && stripMetaFingerprintAlways { return true }
        return stripCategories.contains(tag.category)
    }
}

/// Result payload of `MetadataService.strip` — mirrors `CompressedOutput`.
///
/// `tagsKept` and `tagsStripped` are the as-classified record so the UI
/// can show before/after counts and a strikethrough animation per card.
struct MetadataCleanResult: Hashable, Sendable {
    let cleanedURL: URL
    let bytes: Int64
    let tagsStripped: [MetadataTag]
    let tagsKept: [MetadataTag]

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
