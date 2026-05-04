//
//  StitchClipFetcher.swift
//  VideoCompressor
//
//  Looks up Photos library metadata (creation date primarily) for a
//  given asset identifier. Used at import time to capture each clip's
//  date so the user can later "Sort by date taken" without re-picking.
//
//  All access goes through Photos's public API and is gated on the
//  already-granted read-write authorization state. Returns nil on any
//  failure (no asset, no read permission, etc.) so callers can degrade
//  gracefully rather than blocking import.
//

import Foundation
import Photos

enum StitchClipFetcher {

    /// Production auth provider. Tests inject a fake status closure so this
    /// type never has to mutate real Photos library permissions.
    static let liveAuthStatusProvider: @Sendable () -> PHAuthorizationStatus = {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static let liveAssetCreationDateProvider: @Sendable (String) async -> Date? = { assetID in
        await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetID],
                options: nil
            )
            guard let asset = result.firstObject else { return nil as Date? }
            return asset.creationDate
        }.value
    }

    static let liveAssetCreationDatesProvider: @Sendable ([String]) async -> [String: Date] = { assetIDs in
        await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: assetIDs,
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

    private static func authorizedToRead(
        _ provider: @Sendable () -> PHAuthorizationStatus
    ) -> Bool {
        let status = provider()
        return status == .authorized || status == .limited
    }

    /// Best-effort lookup of `PHAsset.creationDate` for the given asset
    /// identifier. Returns nil when:
    /// - assetID is nil (not a Photos-library import)
    /// - Photos read-write authorization is not .authorized or .limited
    /// - the user has limited Photos access and didn't grant this asset
    /// - the asset was deleted between import and lookup
    /// - any other Photos error
    static func creationDate(
        forAssetID assetID: String?,
        authStatusProvider: @Sendable () -> PHAuthorizationStatus = liveAuthStatusProvider,
        assetCreationDateProvider: @Sendable (String) async -> Date? = liveAssetCreationDateProvider
    ) async -> Date? {
        guard let assetID = assetID else { return nil }
        guard authorizedToRead(authStatusProvider) else { return nil }
        return await assetCreationDateProvider(assetID)
    }

    /// BATCH variant — single Photos fetch resolves N asset IDs in one go.
    /// Used by `StitchProject.sortByCreationDate` so a 50-clip sort doesn't
    /// fire 50 separate Photos lookups. Returns a [assetID: Date] dict.
    /// Missing / inaccessible assets are absent (caller treats them as
    /// "no date"). Empty dict when Photos read-write authorization is not
    /// .authorized or .limited.
    static func creationDates(
        forAssetIDs assetIDs: [String],
        authStatusProvider: @Sendable () -> PHAuthorizationStatus = liveAuthStatusProvider,
        assetCreationDatesProvider: @Sendable ([String]) async -> [String: Date] = liveAssetCreationDatesProvider
    ) async -> [String: Date] {
        let unique = Array(Set(assetIDs.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }
        guard authorizedToRead(authStatusProvider) else { return [:] }
        return await assetCreationDatesProvider(unique)
    }
}
