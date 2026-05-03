//
//  EmptyStateView.swift
//  VideoCompressor
//
//  Shown when the library has no imported videos. Centred call-to-action
//  using the system PhotosPicker.
//

import SwiftUI
import PhotosUI

struct EmptyStateView: View {
    @Binding var pickerItems: [PhotosPickerItem]

    var body: some View {
        CenteredEmptyState(
            systemImage: "film.stack",
            title: "No videos yet",
            message: "Import from your Photos library to start compressing on-device."
        ) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 50,
                matching: .videos,
                preferredItemEncoding: .current
            ) {
                Label("Import Videos", systemImage: "photo.on.rectangle.angled")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("importVideosButton")
        }
    }
}

#Preview {
    EmptyStateView(pickerItems: .constant([]))
}
