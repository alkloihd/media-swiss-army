//
//  ClipBlockView.swift
//  VideoCompressor
//
//  A single row in the Stitch timeline. Renders a 4-frame thumbnail strip
//  on the left, clip name + trimmed duration + "Edited" badge on the right.
//  Thumbnails are loaded asynchronously via ThumbnailStripGenerator.
//

import SwiftUI

struct ClipBlockView: View {
    let clip: StitchClip
    @State private var thumbnails: [UIImage] = []
    @State private var thumbnailLoadError: String?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailStrip
                .frame(width: 144, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .task(id: clip.sourceURL) { await loadThumbnails() }
    }

    @ViewBuilder
    private var thumbnailStrip: some View {
        if thumbnails.isEmpty {
            Rectangle().fill(.quaternary)
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
        let gen = ThumbnailStripGenerator()
        do {
            thumbnails = try await gen.generate(for: clip.sourceURL, count: 4, maxDimension: 80)
        } catch {
            thumbnailLoadError = error.localizedDescription
        }
    }
}
