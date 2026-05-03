//
//  CenteredEmptyState.swift
//  VideoCompressor
//
//  Generic empty-state placeholder. Pass any label content via the
//  `action` ViewBuilder so each tab can embed its own PhotosPicker or CTA.
//

import SwiftUI

/// Reusable centred empty-state layout.
/// - `systemImage`: SF Symbol name shown in tint colour.
/// - `title`: primary headline.
/// - `message`: secondary descriptive text.
/// - `action`: bottom call-to-action (PhotosPicker, Button, etc.).
struct CenteredEmptyState<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            action()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    CenteredEmptyState(
        systemImage: "film.stack",
        title: "No videos yet",
        message: "Import from your Photos library to start compressing on-device."
    ) {
        Button("Import") {}
            .buttonStyle(.borderedProminent)
    }
}
