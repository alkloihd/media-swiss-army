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
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "film.stack")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("No videos yet")
                    .font(.title3.weight(.semibold))
                Text("Import from your Photos library to start compressing on-device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 20,
                matching: .videos,
                preferredItemEncoding: .current
            ) {
                Label("Import Videos", systemImage: "photo.on.rectangle.angled")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("importVideosButton")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView(pickerItems: .constant([]))
}
