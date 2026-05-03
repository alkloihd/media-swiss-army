//
//  StitchClipFetcher.swift
//  VideoCompressor
//
//  Looks up Photos library metadata (creation date primarily) for a
//  given asset identifier. Used at import time to capture each clip's
//  date so the user can later "Sort by date taken" without re-picking.
//
//  All access goes through Photos's public API — no extra entitlements
//  required beyond the existing NSPhotoLibraryUsageDescription. Returns
//  nil on any failure (no asset, no read permission, etc.) so callers
//  can degrade gracefully rather than blocking import.
//

import Foundation
import Photos

enum StitchClipFetcher {

    /// Best-effort lookup of `PHAsset.creationDate` for the given asset
    /// identifier. Returns nil when:
    /// - assetID is nil (not a Photos-library import)
    /// - the user has limited Photos access and didn't grant this asset
    /// - the asset was deleted between import and lookup
    /// - any other Photos error
    static func creationDate(forAssetID assetID: String?) async -> Date? {
        guard let assetID = assetID else { return nil }
        // PHAsset.fetchAssets is synchronous — wrap in a detached Task so we
        // don't block the import flow's main-actor context for assets that
        // are slow to materialise on first access.
        return await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetID],
                options: nil
            )
            guard let asset = result.firstObject else { return nil as Date? }
            return asset.creationDate
        }.value
    }

    /// BATCH variant — single Photos fetch resolves N asset IDs in one go.
    /// Used by `StitchProject.sortByCreationDate` so a 50-clip sort doesn't
    /// fire 50 separate Photos lookups. Returns a [assetID: Date?] dict.
    /// Missing / inaccessible assets map to nil (caller treats them as
    /// "no date"). nil-valued asset IDs in input are skipped.
    static func creationDates(forAssetIDs assetIDs: [String]) async -> [String: Date] {
        let unique = Array(Set(assetIDs.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: unique,
                options: nil
            )
            var out: [String: Date] = [:]
            result.enumerateObjects { asset, _, _ in
                if let date = asset.creationDate {
                    out[asset.localIdentifier] = date
                }
            }
            return out
        }.value
    }
}
