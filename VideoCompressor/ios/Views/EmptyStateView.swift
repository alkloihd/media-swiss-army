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
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    init(pickerItems: Binding<[PhotosPickerItem]>, tint: Color = .accentColor) {
        _pickerItems = pickerItems
        self.tint = tint
    }

    var body: some View {
        CenteredEmptyState(
            systemImage: "wand.and.stars",
            title: "No media yet",
            message: "Import videos or photos from your library to start compressing on-device.",
            tint: tint,
            symbolSize: 96
        ) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 50,
                matching: .any(of: [.videos, .images]),
                preferredItemEncoding: .current
            ) {
                Label("Import Media", systemImage: "photo.on.rectangle.angled")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .appMaterialBackground(
                        .regularMaterial,
                        fallback: AppMesh.backdrop(colorScheme),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: AppShape.strokeHairline))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("importVideosButton")
        }
    }
}

#Preview {
    EmptyStateView(pickerItems: .constant([]))
}
