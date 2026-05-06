//
//  ClipBlockView.swift
//  VideoCompressor
//
//  A single row in the Stitch timeline. Renders a 4-frame thumbnail strip
//  on the left, clip name + trimmed duration + "Edited" badge on the right.
//  Thumbnails are loaded asynchronously via ThumbnailStripGenerator.
//

import SwiftUI
import ImageIO
import UIKit

struct ClipBlockView: View {
    let clip: StitchClip
    let tint: Color
    @State private var thumbnails: [UIImage] = []
    @State private var thumbnailLoadError: String?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailStrip
                .frame(width: 144, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: AppShape.radiusS))
                .overlay(
                    RoundedRectangle(cornerRadius: AppShape.radiusS)
                        .strokeBorder(tint.opacity(0.18), lineWidth: AppShape.strokeHairline)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if clip.isEdited {
                    Label("Edited", systemImage: "scissors")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(tint)
                }
            }
            Spacer()
        }
        .cardStyle(tint: tint)
        .task(id: clip.sourceURL) { await loadThumbnails() }
    }

    @ViewBuilder
    private var thumbnailStrip: some View {
        if let _ = thumbnailLoadError {
            // Show a neutral placeholder with a warning glyph so the user
            // knows thumbnails couldn't be generated for this clip but the
            // import itself is valid (closes review {E-0503-1050} MED-3).
            ZStack {
                Rectangle().fill(tint.opacity(0.10))
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
            }
        } else if thumbnails.isEmpty {
            Rectangle().fill(tint.opacity(0.10))
        } else {
            HStack(spacing: 1) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
            }
        }
    }

    private var durationLabel: String {
        let total = Int(clip.trimmedDurationSeconds.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func loadThumbnails() async {
        // Stills come straight from ImageIO — AVAssetImageGenerator can't
        // read HEIC / JPEG / PNG (they're not movies) so it would error and
        // we'd end up with the warning-triangle placeholder for every photo
        // the user imports. Render the still itself as the thumbnail.
        if clip.kind == .still {
            if let img = await Self.loadStillThumbnail(from: clip.sourceURL) {
                thumbnails = Array(repeating: img, count: 4)
            } else {
                thumbnailLoadError = "Couldn't decode still."
            }
            return
        }

        let gen = ThumbnailStripGenerator()
        do {
            thumbnails = try await gen.generate(for: clip.sourceURL, count: 4, maxDimension: 80)
        } catch {
            thumbnailLoadError = error.localizedDescription
        }
    }

    private static func loadStillThumbnail(from url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(src) > 0 else {
                return nil as UIImage?
            }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 200,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            else { return nil as UIImage? }
            return UIImage(cgImage: cg)
        }.value
    }
}
