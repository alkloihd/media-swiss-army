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
            title: "No media yet",
            message: "Import videos or photos from your library to start compressing on-device."
        ) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 50,
                matching: .any(of: [.videos, .images]),
                preferredItemEncoding: .current
            ) {
                Label("Import Media", systemImage: "photo.on.rectangle.angled")
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
