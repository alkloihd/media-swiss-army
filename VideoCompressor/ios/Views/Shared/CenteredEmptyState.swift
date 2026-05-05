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
    var tint: Color = .accentColor
    var symbolSize: CGFloat = 72
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, tint.opacity(0.35))
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
                .tint(tint)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .tint(tint)
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
