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

    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0

    init(initialPage: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: min(max(initialPage, 0), Self.pages.count - 1))
    }

    var body: some View {
        ZStack {
            MeshAuroraView(tint: currentTint)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, model in
                        card(model, tint: tint(for: index))
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < Self.pages.count - 1 {
                        withAnimation(.smooth(duration: 0.20)) {
                            page += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < Self.pages.count - 1 ? "Next" : "Get started")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(currentTint)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .accessibilityIdentifier("onboardingPrimaryButton")
            }
        }
    }

    private var currentTint: Color {
        tint(for: page)
    }

    private func card(_ model: OnboardingPage, tint: Color) -> some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: model.symbol)
                    .font(.system(size: 62, weight: .light))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(tint, AppMesh.bloom(colorScheme), .secondary)
                    .frame(width: 116, height: 116)
                    .appMaterialBackground(
                        .ultraThinMaterial,
                        fallback: Color(.secondarySystemBackground),
                        in: Circle()
                    )
                    .accessibilityHidden(true)

                Text(model.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(model.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 360)
            .cardStyle(tint: tint)
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func tint(for index: Int) -> Color {
        switch Self.pages[index].tab {
        case .compress:
            AppTint.compress(colorScheme)
        case .stitch:
            AppTint.stitch(colorScheme)
        case .metaClean:
            AppTint.metaClean(colorScheme)
        case .settings:
            AppTint.settings(colorScheme)
        }
    }

    private static let pages = [
        OnboardingPage(
            tab: .metaClean,
            symbol: "eye.slash",
            title: "Strip Meta AI fingerprints",
            body: "Remove the hidden Meta glasses marker while keeping the photo details that make your library useful."
        ),
        OnboardingPage(
            tab: .compress,
            symbol: "wand.and.stars",
            title: "Shrink before sharing",
            body: "Compress photos and videos on device with smart presets built for everyday sharing."
        ),
        OnboardingPage(
            tab: .stitch,
            symbol: "square.stack.3d.up",
            title: "Stitch clips together",
            body: "Combine photos and videos, reorder the timeline, and export a clean result without cloud processing."
        ),
    ]
}

private struct OnboardingPage {
    let tab: AppTab
    let symbol: String
    let title: String
    let body: String
}

#Preview {
    OnboardingView(onFinish: {})
}
