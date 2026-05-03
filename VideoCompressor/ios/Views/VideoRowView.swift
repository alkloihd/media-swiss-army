//
//  VideoRowView.swift
//  VideoCompressor
//
//  Single row in the imported-video list. Shows filename, metadata,
//  per-video state, and (when finished) a save-to-Photos action.
//

import SwiftUI

struct VideoRowView: View {
    let video: VideoFile
    @EnvironmentObject private var library: VideoLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            metadataLine
            stateLine
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "film")
                .foregroundStyle(.tint)
            Text(video.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if case .finished = video.jobState {
                Button {
                    Task { await library.saveOutputToPhotos(for: video.id) }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("saveToPhotos-\(video.id.uuidString)")
            }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 10) {
            if let meta = video.metadata {
                tag(text: meta.resolutionLabel, system: "rectangle.ratio.16.to.9")
                tag(text: meta.durationLabel, system: "clock")
                tag(text: meta.sizeLabel, system: "internaldrive")
                tag(text: meta.codec.uppercased(), system: "waveform")
            } else {
                Text("Reading metadata…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
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
                Text(String(format: "Compressing… %d%%", progress.percent))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .finished:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(savingsLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .skipped(let reason):
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
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
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
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
            return String(format: "%@ → %@ (-%.0f%%)", sizeBefore, sizeAfter, pct)
        } else {
            return "\(sizeBefore) → \(sizeAfter)"
        }
    }
}
