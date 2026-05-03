//
//  PhotosSaver.swift
//  VideoCompressor
//
//  Saves a finished compressed video to the user's Photos library using the
//  `.addOnly` authorization scope — we never need to read photos, only write.
//

import Foundation
import Photos
import UniformTypeIdentifiers

enum PhotosSaverError: Error, LocalizedError, Hashable, Sendable {
    case notAuthorized
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:           return "Permission to save to Photos was denied."
        case .saveFailed(let message): return "Failed to save to Photos: \(message)"
        }
    }
}

struct PhotosSaver {
    /// Best-effort PHAssetResourceType mapping from a file URL. Falls back to
     /// `.video` (legacy default) only when the type can't be inferred — but
     /// the common image extensions (heic, heif, jpg, jpeg, png) and Apple's
     /// UTType conformance check both route to `.photo` correctly.
    static func resourceType(for url: URL) -> PHAssetResourceType {
        let ext = url.pathExtension.lowercased()
        // Fast path on extensions to avoid an UTI roundtrip for common cases.
        switch ext {
        case "heic", "heif", "jpg", "jpeg", "png", "webp", "tiff", "tif", "gif", "bmp":
            return .photo
        case "mp4", "m4v", "mov", "qt":
            return .video
        default:
            break
        }
        // Fallback: ask UTType. Conforms-to image → .photo; conforms-to movie → .video.
        if let uti = UTType(filenameExtension: ext) {
            if uti.conforms(to: .image) { return .photo }
            if uti.conforms(to: .movie) { return .video }
        }
        // Last-resort default. Better wrong than crash; the caller's error
        // path will surface 3302 if the file truly doesn't match.
        return .video
    }

    static func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotosSaverError.notAuthorized
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            throw PhotosSaverError.saveFailed(error.localizedDescription)
        }
    }
}

// MARK: - MetaClean extension

extension PhotosSaver {
    /// Saves `cleanedURL` to Photos, then optionally deletes the original asset.
    ///
    /// When `originalAssetID` is non-nil, we request `.readWrite` authorization
    /// (superset of `.addOnly`) so the same grant covers both the save and the
    /// delete. iOS will surface its own system confirmation dialog for the
    /// delete; the user must tap Delete there — we cannot suppress it. The
    /// original then moves to Recently Deleted (recoverable for 30 days).
    ///
    /// If `originalAssetID` is nil (limited access, not from Photos, or the
    /// delete-original toggle was off), only the save step runs and we use the
    /// cheaper `.addOnly` scope.
    static func saveAndOptionallyDeleteOriginal(
        cleanedURL: URL,
        originalAssetID: String?
    ) async throws {
        let scope: PHAccessLevel = (originalAssetID != nil) ? .readWrite : .addOnly
        let status = await PHPhotoLibrary.requestAuthorization(for: scope)
        guard status == .authorized || status == .limited else {
            throw PhotosSaverError.notAuthorized
        }

        // Step 1 — save the cleaned copy. Resource type MUST match the file —
        // passing `.video` for an image triggers PHPhotosErrorDomain 3302
        // (incompatible resource). Detect from UTI / extension.
        let resourceType = Self.resourceType(for: cleanedURL)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: resourceType, fileURL: cleanedURL, options: options)
            }
        } catch {
            throw PhotosSaverError.saveFailed(error.localizedDescription)
        }

        // Step 2 — optional delete of the original.
        guard let id = originalAssetID else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard assets.count > 0 else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }
        } catch {
            // Save already succeeded; surface delete failure so the caller can inform the user.
            throw PhotosSaverError.saveFailed(
                "Saved, but could not delete original: \(error.localizedDescription)"
            )
        }
    }
}
