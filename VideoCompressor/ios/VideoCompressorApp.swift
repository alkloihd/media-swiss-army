//
//  VideoCompressorApp.swift
//  VideoCompressor
//

import SwiftUI

@main
struct VideoCompressorApp: App {
    @StateObject private var library = VideoLibrary()

    init() {
        // Sweep files older than 7 days at launch. Task.detached so startup
        // is not blocked — filesystem enumeration runs off the main thread.
        Task.detached(priority: .utility) {
            await CacheSweeper.shared.sweepOnLaunch(daysOld: 7)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}
