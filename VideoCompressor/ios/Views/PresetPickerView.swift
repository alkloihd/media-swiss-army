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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var videoPresetList: some View {
        List(CompressionSettings.phase1Presets) { setting in
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
        .listStyle(.plain)
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
