//
//  LibraryError.swift
//  VideoCompressor
//
//  Sum type for all errors that bubble to the user. Replaces
//  `lastErrorMessage: String?` with structure so callers can branch
//  (e.g. show a Settings link for `.photosNotAuthorized`).

import Foundation

enum LibraryError: Error, Hashable, Sendable {
    case metadata(VideoMetadataError)
    case compression(CompressionError)
    case photos(PhotosSaverError)
    case fileSystem(message: String)

    var displayMessage: String {
        switch self {
        case .metadata(let e):           return e.errorDescription ?? "Metadata error."
        case .compression(let e):        return e.errorDescription ?? "Compression error."
        case .photos(let e):             return e.errorDescription ?? "Photos error."
        case .fileSystem(let m):         return m
        }
    }

    /// Optional recovery hint (deep-link to Settings, etc).
    var recoverySuggestion: String? {
        switch self {
        case .photos(.notAuthorized):
            return "Open Settings → Video Compressor → Photos and choose Add Photos Only."
        default:
            return nil
        }
    }
}
