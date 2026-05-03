//
//  ContentView.swift
//  VideoCompressor
//
//  Root tab shell. Three tabs per the design spec
//  (`docs/superpowers/specs/2026-04-09-ios-app-design.md` §2):
//    1. Compress — the existing VideoListView
//    2. Stitch — placeholder until phase 2/3 ships
//    3. MetaClean — placeholder until phase 2/3 ships
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .compress

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
        }
    }
}

enum AppTab: Hashable {
    case compress
    case stitch
    case metaClean

    var title: String {
        switch self {
        case .compress:  return "Compress"
        case .stitch:    return "Stitch"
        case .metaClean: return "MetaClean"
        }
    }

    var symbolName: String {
        switch self {
        case .compress:  return "wand.and.stars"
        case .stitch:    return "square.stack.3d.up"
        case .metaClean: return "eye.slash"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(VideoLibrary.preview())
}
