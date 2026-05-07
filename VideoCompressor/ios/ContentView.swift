//
//  ContentView.swift
//  VideoCompressor
//
//  Root tab shell plus first-launch onboarding.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .compress
    @AppStorage("hasSeenOnboarding_v1") private var hasSeenOnboarding = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView(selection: $selectedTab) {
            VideoListView()
                .tabItem {
                    Label("Compress", systemImage: AppTab.compress.symbolName)
                }
                .tag(AppTab.compress)

            StitchTabView()
                .tabItem {
                    Label("Stitch", systemImage: AppTab.stitch.symbolName)
                }
                .tag(AppTab.stitch)

            MetaCleanTabView()
                .tabItem {
                    Label("MetaClean", systemImage: AppTab.metaClean.symbolName)
                }
                .tag(AppTab.metaClean)

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: AppTab.settings.symbolName)
                }
                .tag(AppTab.settings)
        }
        .tint(tint(for: selectedTab))
        .toolbarBackground(.thinMaterial, for: .tabBar)
        .animation(.smooth(duration: 0.20), value: selectedTab)
        .fullScreenCover(isPresented: Binding(
            get: { OnboardingGate(hasSeen: hasSeenOnboarding).shouldPresent },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView {
                var gate = OnboardingGate(hasSeen: hasSeenOnboarding)
                gate.markSeen()
                hasSeenOnboarding = gate.hasSeen
                selectedTab = gate.landingTab
            }
        }
    }

    private func tint(for tab: AppTab) -> Color {
        switch tab {
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
}

enum AppTab: Hashable {
    case compress
    case stitch
    case metaClean
    case settings

    var title: String {
        switch self {
        case .compress:  return "Compress"
        case .stitch:    return "Stitch"
        case .metaClean: return "MetaClean"
        case .settings:  return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .compress:  return "wand.and.stars"
        case .stitch:    return "square.stack.3d.up"
        case .metaClean: return "eye.slash"
        case .settings:  return "gearshape"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(VideoLibrary.preview())
}
