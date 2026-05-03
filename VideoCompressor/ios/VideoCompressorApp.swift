//
//  VideoCompressorApp.swift
//  VideoCompressor
//

import SwiftUI

@main
struct VideoCompressorApp: App {
    @StateObject private var library = VideoLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}
