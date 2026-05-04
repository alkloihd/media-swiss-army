//
//  VideoCompressorApp.swift
//  VideoCompressor
//

import SwiftUI

@main
struct VideoCompressorApp: App {
    @StateObject private var library = VideoLibrary()

    init() {
        // Tight launch hygiene for app-owned working files. Task.detached so
        // startup is not blocked — filesystem enumeration runs off the main
        // thread.
        Task.detached(priority: .utility) {
            await CacheSweeper.shared.sweepOnLaunchTight()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}
