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

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Choose Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PresetPickerView()
        .environmentObject(VideoLibrary.preview())
}
