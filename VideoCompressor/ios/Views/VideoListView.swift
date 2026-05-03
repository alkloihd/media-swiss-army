//
//  VideoListView.swift
//  VideoCompressor
//
//  Top-level screen. List of imported videos, preset picker pinned to the
//  toolbar, action bar at the bottom for batch compress.
//

import SwiftUI
import PhotosUI

struct VideoListView: View {
    @EnvironmentObject private var library: VideoLibrary
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var presetSheet = false
    @State private var saveToastVisible = false
    @State private var saveToastMessage = ""
    @State private var saveToastIsError = false
    /// Track last-seen saved ID to detect new saves without re-firing.
    @State private var lastNotifiedSaveID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if library.videos.isEmpty {
                    EmptyStateView(pickerItems: $pickerItems)
                } else {
                    populatedList
                }
            }
            .navigationTitle("Alkloihd Video Swiss-AK")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 50,
                        matching: .any(of: [.videos, .images]),
                        preferredItemEncoding: .current
                    ) {
                        Label("Add", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                }
                if !library.videos.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") { library.removeAll() }
                            .tint(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !library.videos.isEmpty {
                    actionBar
                }
            }
            .sheet(isPresented: $presetSheet) {
                PresetPickerView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { library.lastError != nil },
                    set: { if !$0 { library.lastError = nil } }
                ),
                presenting: library.lastError
            ) { error in
                if let url = URL(string: UIApplication.openSettingsURLString),
                   error.recoverySuggestion != nil {
                    Button("Open Settings") { UIApplication.shared.open(url) }
                }
                Button("OK", role: .cancel) {}
            } message: { error in
                if let suggestion = error.recoverySuggestion {
                    Text("\(error.displayMessage)\n\n\(suggestion)")
                } else {
                    Text(error.displayMessage)
                }
            }
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await library.importPickedItems(newItems)
                pickerItems = []
            }
        }
    }

    private var populatedList: some View {
        List {
            ForEach(library.videos) { video in
                VideoRowView(video: video)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            library.remove(video.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("videoList")
        .overlay(alignment: .bottom) {
            if saveToastVisible {
                saveToast
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: saveToastVisible)
        .onChange(of: library.videos) { _, newVideos in
            for video in newVideos {
                // Fire toast when a row transitions to .saved (de-duped by ID).
                if case .saved = video.saveStatus, video.id != lastNotifiedSaveID {
                    lastNotifiedSaveID = video.id
                    saveToastMessage = "Saved to Photos"
                    saveToastIsError = false
                    showToast()
                }
                // Fire toast on failure too.
                if case .saveFailed(let reason) = video.saveStatus, video.id != lastNotifiedSaveID {
                    lastNotifiedSaveID = video.id
                    saveToastMessage = reason
                    saveToastIsError = true
                    showToast()
                }
            }
        }
    }

    private var saveToast: some View {
        HStack(spacing: 8) {
            Image(systemName: saveToastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(saveToastIsError ? .red : .green)
            Text(saveToastMessage)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityIdentifier("saveToast")
    }

    private func showToast() {
        saveToastVisible = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            saveToastVisible = false
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    presetSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: library.selectedSettings.symbolName)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(library.selectedSettings.title)
                                .font(.subheadline.weight(.semibold))
                            Text("Preset")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("presetButton")

                Spacer()

                Button {
                    library.compressAll()
                } label: {
                    Label("Compress All", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasCompressible)
                .accessibilityIdentifier("compressAllButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var hasCompressible: Bool {
        library.videos.contains { !$0.jobState.isActive && $0.jobState != .finished }
    }
}

#Preview {
    VideoListView()
        .environmentObject(VideoLibrary.preview())
}
