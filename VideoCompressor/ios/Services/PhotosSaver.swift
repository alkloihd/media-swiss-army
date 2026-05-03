//
//  PhotosSaver.swift
//  VideoCompressor
//
//  Saves a finished compressed video to the user's Photos library using the
//  `.addOnly` authorization scope — we never need to read photos, only write.
//

import Foundation
import Photos

enum PhotosSaverError: Error, LocalizedError {
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
