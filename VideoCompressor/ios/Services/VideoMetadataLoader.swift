//
//  VideoMetadataLoader.swift
//  VideoCompressor
//
//  Async metadata extraction. iOS 17 deprecated the synchronous accessors on
//  AVAsset (track count, duration, preferredTransform) — they now require the
//  async `load(_:)` API. We hide that ceremony behind a single async call and
//  return a flat `VideoMetadata` struct.
//

import Foundation
import AVFoundation

enum VideoMetadataError: Error, LocalizedError {
    case noVideoTrack
    case fileMissing
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:        return "This file does not contain a video track."
        case .fileMissing:         return "Source file is missing or unreadable."
        case .loadFailed(let why): return "Could not read video metadata: \(why)"
        }
    }
}

struct VideoMetadataLoader {
    static func load(from url: URL) async throws -> VideoMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoMetadataError.fileMissing
        }

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        do {
            let (loadedDuration, tracks) = try await asset.load(.duration, .tracks)
            let durationSeconds = CMTimeGetSeconds(loadedDuration)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            guard let videoTrack = videoTracks.first else {
                throw VideoMetadataError.noVideoTrack
            }

            // Track-level metadata is also async-loaded.
            let (naturalSize, transform, frameRate, bitrate, formatDescriptions) = try await videoTrack.load(
                .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions
            )

            // Apply rotation transform so the resolution we report matches
            // what the user sees on playback (portrait videos report
            // 1080×1920 instead of 1920×1080).
            let rotated = naturalSize.applying(transform)
            let displayWidth = Int(abs(rotated.width).rounded())
            let displayHeight = Int(abs(rotated.height).rounded())

            let codecLabel: String = {
                guard let firstFormat = formatDescriptions.first as CMFormatDescription? else { return "unknown" }
                let typeCode = CMFormatDescriptionGetMediaSubType(firstFormat)
                return fourCCString(from: typeCode)
            }()

            let fileSize: Int64 = {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            }()

            return VideoMetadata(
                durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
                pixelWidth: displayWidth,
                pixelHeight: displayHeight,
                nominalFrameRate: frameRate,
                codec: codecLabel,
                estimatedDataRate: bitrate,
                fileSizeBytes: fileSize
            )
        } catch let error as VideoMetadataError {
            throw error
        } catch {
            throw VideoMetadataError.loadFailed(error.localizedDescription)
        }
    }

    /// Convert a four-character code (e.g. 'hvc1') from `OSType` into a
    /// printable string. Returns hex if the code is not printable.
    private static func fourCCString(from code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >>  8) & 0xFF),
            UInt8( code        & 0xFF),
        ]
        if bytes.allSatisfy({ (0x20...0x7E).contains($0) }) {
            return String(bytes: bytes, encoding: .ascii) ?? "unknown"
        }
        return String(format: "0x%08X", code)
    }
}
