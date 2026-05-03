//
//  ContentView.swift
//  VideoCompressor
//
//  Root view: routes to the main video list. Kept thin so the shell is
//  obvious. Heavy lifting lives in VideoListView and VideoLibrary.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VideoListView()
    }
}

#Preview {
    ContentView()
        .environmentObject(VideoLibrary.preview())
}
