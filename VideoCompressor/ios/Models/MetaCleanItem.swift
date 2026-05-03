//
//  MetaCleanItem.swift
//  VideoCompressor
//
//  Helper model for the MetaClean tab. Mirrors StitchClip but for metadata
//  inspection and stripping — no duration/naturalSize needed, just the
//  source URL, scanned tags, and final clean result.
//
//  See `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` task M3.
//

import Foundation

struct MetaCleanItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    /// What kind of media this item represents. Phase 3 commit 5 added
    /// stills as a first-class MetaClean target.
    let kind: MediaKind
    /// PHAsset.localIdentifier captured at import time so we can target the
    /// original for deletion later. nil if not from Photos library or if
    /// Photos access was limited (PhotosPickerItem.itemIdentifier requires
    /// full authorization to be non-nil).
    let originalAssetID: String?
    var tags: [MetadataTag]
    var scanError: String?
    var cleanResult: MetadataCleanResult?

    init(
        id: UUID,
        sourceURL: URL,
        displayName: String,
        kind: MediaKind = .video,
        originalAssetID: String?,
        tags: [MetadataTag],
        scanError: String?,
        cleanResult: MetadataCleanResult?
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.kind = kind
        self.originalAssetID = originalAssetID
        self.tags = tags
        self.scanError = scanError
        self.cleanResult = cleanResult
    }
}
