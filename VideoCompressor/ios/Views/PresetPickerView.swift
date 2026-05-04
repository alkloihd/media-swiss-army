//
//  PresetPickerView.swift
//  VideoCompressor
//
//  Bottom sheet that lets the user pick a compression preset. One row per
//  preset with icon, title, blurb, and a check next to the current choice.
//

import SwiftUI

struct PresetPickerView: View {
    @EnvironmentObject private var library: VideoLibrary
    @Environment(\.dismiss) private var dismiss

    /// Phase 3 commit 9 — Advanced mode toggle. Persists across launches so
    /// users who like the detail don't have to flip it every time.
    @AppStorage("showAdvancedDetails") private var showAdvanced: Bool = false

    /// True when the current selection is photos-only. Drives which preset
    /// list is rendered. Mixed selections fall through to the video picker
    /// (video flow handles still pass-through; the still flow can't run a
    /// CompressionSettings preset).
    private var allStills: Bool {
        !library.videos.isEmpty && library.videos.allSatisfy { $0.kind == .still }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allStills {
                    photoPresetList
                } else {
                    videoPresetList
                }
            }
            .navigationTitle("Choose Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $showAdvanced) {
                        Image(systemName: showAdvanced
                              ? "chart.bar.doc.horizontal.fill"
                              : "chart.bar.doc.horizontal")
                            .font(.body)
                    }
                    .toggleStyle(.button)
                    .help("Show estimated output size per preset")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var videoPresetList: some View {
        List {
            Section {
                presetRow(.balanced)
                presetRow(.small)
            }

            Section {
                DisclosureGroup("Advanced") {
                    if showAdvanced {
                        advancedSummary
                    }
                    presetRow(.max)
                    presetRow(.streaming)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func presetRow(_ setting: CompressionSettings) -> some View {
        Button {
            library.selectedSettings = setting
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: setting.symbolName)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(setting.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(setting.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showAdvanced {
                        advancedDetail(for: setting)
                    }
                }
                Spacer()
                if library.selectedSettings == setting {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var advancedSummary: some View {
        let videoCount = library.videos.filter { $0.kind == .video }.count
        let sourceTotal = CompressionEstimator.sourceTotalBytes(for: library.videos)
        if videoCount > 0 && sourceTotal > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(videoCount) video\(videoCount == 1 ? "" : "s") selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Source total: \(CompressionEstimator.format(sourceTotal))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Estimates use HEVC bitrate × duration. Real output is often smaller — HEVC compresses well below its bitrate budget on simple content.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("Pick at least one video to see size estimates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func advancedDetail(for setting: CompressionSettings) -> some View {
        let videos = library.videos.filter { $0.kind == .video }
        let estimated = CompressionEstimator.estimatedTotalBytes(for: videos, preset: setting)
        let source = CompressionEstimator.sourceTotalBytes(for: videos)

        if estimated > 0 && source > 0 {
            HStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("≈ \(CompressionEstimator.format(estimated))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                if estimated < source {
                    let savedPct = Int(round(Double(source - estimated) / Double(source) * 100))
                    Text("(saves ~\(savedPct)%)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                } else {
                    Text("(may keep original)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
    }

    private var photoPresetList: some View {
        List(PhotoCompressionSettings.phase1Presets) { setting in
            Button {
                library.selectedPhotoSettings = setting
                dismiss()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: setting.symbolName)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setting.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(setting.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if library.selectedPhotoSettings == setting {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}

#Preview {
    PresetPickerView()
        .environmentObject(VideoLibrary.preview())
}
