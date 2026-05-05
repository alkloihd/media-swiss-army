//
//  VideoCardView.swift
//  VideoCompressor
//
//  Card surface for imported media in the Compress tab. Shows a thumbnail,
//  metadata, per-file compression state, and Photos save actions.
//

import AVFoundation
import CoreGraphics
import ImageIO
import SwiftUI
import UIKit

struct VideoCardView: View {
    let video: VideoFile
    @EnvironmentObject private var library: VideoLibrary
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        AppTint.compress(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            header
            metadataLine
            stateLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(tint: tint)
        .contextMenu {
            if case .finished = video.jobState {
                Button {
                    Task { await library.saveOutputToPhotos(for: video.id) }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }
            Button(role: .destructive) {
                library.remove(video.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var thumbnail: some View {
        VideoCardThumbnailView(video: video, tint: tint)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppShape.radiusS))
            .overlay(
                RoundedRectangle(cornerRadius: AppShape.radiusS)
                    .strokeBorder(tint.opacity(0.18), lineWidth: AppShape.strokeHairline)
            )
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: video.kind == .still ? "photo" : "film")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(video.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if case .finished = video.jobState {
                saveControl
                    .accessibilityIdentifier("saveToPhotos-\(video.id.uuidString)")
            }
        }
    }

    @ViewBuilder
    private var saveControl: some View {
        switch video.saveStatus {
        case .unsaved:
            Button {
                Task { await library.saveOutputToPhotos(for: video.id) }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .appMaterialBackground(
                        .regularMaterial,
                        fallback: AppMesh.backdrop(colorScheme),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: AppShape.strokeHairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save to Photos")
        case .saving:
            GaugePill(state: .saving(progress: 0.35), tint: tint)
        case .saved:
            GaugePill(state: .saved, tint: tint)
        case .saveFailed(let reason):
            Button {
                Task { await library.saveOutputToPhotos(for: video.id) }
            } label: {
                GaugePill(state: .failed(message: reason.isEmpty ? "Retry" : "Retry"), tint: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry save to Photos")
        }
    }

    private var metadataLine: some View {
        FlowLikePillRow {
            if let meta = video.metadata {
                tag(text: meta.resolutionLabel, system: "rectangle.ratio.16.to.9")
                tag(text: meta.durationLabel, system: "clock")
                tag(text: meta.sizeLabel, system: "internaldrive")
                tag(text: meta.codec.uppercased(), system: "waveform")
            } else {
                Text("Reading metadata...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stateLine: some View {
        switch video.jobState {
        case .idle:
            EmptyView()
        case .queued:
            ProgressView("Queued")
                .progressViewStyle(.linear)
        case .running(let progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress.value)
                    .progressViewStyle(.linear)
                    .tint(tint)
                Text(String(format: "Compressing... %d%%", progress.percent))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .finished:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(savingsLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let note = video.output?.note {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(tint)
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        case .skipped(let reason):
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(tint)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error.displayMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func tag(text: String, system: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system)
                .imageScale(.small)
            Text(text)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .appMaterialBackground(
            .thinMaterial,
            fallback: AppMesh.backdrop(colorScheme),
            in: Capsule()
        )
        .foregroundStyle(.secondary)
    }

    private var savingsLine: String {
        guard let outBytes = video.output?.bytes,
              let inBytes = video.metadata?.fileSizeBytes,
              inBytes > 0 else { return "Done" }
        let saved = inBytes - outBytes
        let pct = Double(saved) / Double(inBytes) * 100
        let sizeBefore = ByteCountFormatter.string(fromByteCount: inBytes, countStyle: .file)
        let sizeAfter = ByteCountFormatter.string(fromByteCount: outBytes, countStyle: .file)
        if saved > 0 {
            return String(format: "%@ -> %@ (-%.0f%%)", sizeBefore, sizeAfter, pct)
        } else {
            return "\(sizeBefore) -> \(sizeAfter)"
        }
    }
}

private struct VideoCardThumbnailView: View {
    let video: VideoFile
    let tint: Color
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.24), tint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: video.kind == .still ? "photo" : "film")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(tint, tint.opacity(0.28))
            }
        }
        .clipped()
        .task(id: video.sourceURL) {
            image = await Self.loadThumbnail(for: video)
        }
    }

    private static func loadThumbnail(for video: VideoFile) async -> UIImage? {
        await Task.detached(priority: .utility) {
            switch video.kind {
            case .still:
                guard let source = CGImageSourceCreateWithURL(video.sourceURL as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    return nil
                }
                return UIImage(cgImage: cgImage)
            case .video:
                let asset = AVURLAsset(url: video.sourceURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 360)
                guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
                    return nil
                }
                return UIImage(cgImage: cgImage)
            }
        }.value
    }
}

private struct FlowLikePillRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}
