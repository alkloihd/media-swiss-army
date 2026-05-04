//
//  OnboardingView.swift
//  VideoCompressor
//
//  First-launch 3-card onboarding.
//

import SwiftUI

struct OnboardingGate {
    private(set) var hasSeen: Bool

    var shouldPresent: Bool { !hasSeen }
    var landingTab: AppTab { .metaClean }

    mutating func markSeen() {
        hasSeen = true
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                card(
                    symbol: "eye.slash",
                    title: "Strip Meta AI fingerprints",
                    body: "Remove the hidden Meta glasses marker while keeping the photo details that make your library useful."
                )
                .tag(0)

                card(
                    symbol: "wand.and.stars",
                    title: "Shrink before sharing",
                    body: "Compress photos and videos on device with smart presets built for everyday sharing."
                )
                .tag(1)

                card(
                    symbol: "square.stack.3d.up",
                    title: "Stitch clips together",
                    body: "Combine photos and videos, reorder the timeline, and export a clean result without cloud processing."
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        page += 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < 2 ? "Next" : "Get started")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("onboardingPrimaryButton")
        }
        .background(Color(.systemBackground))
    }

    private func card(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
