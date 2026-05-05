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
    @Environment(\.colorScheme) private var colorScheme
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var presetSheet = false
    @State private var saveToastVisible = false
    @State private var saveToastMessage = ""
    @State private var saveToastIsError = false
    /// Track last-seen saved ID to detect new saves without re-firing.
    @State private var lastNotifiedSaveID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                MeshAuroraView(tint: compressTint)

                if library.videos.isEmpty {
                    EmptyStateView(pickerItems: $pickerItems, tint: compressTint)
                } else {
                    populatedList
                }
            }
            .tint(compressTint)
            .navigationTitle("Compress")
            .toolbarBackground(.hidden, for: .navigationBar)
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
        ScrollView {
            queueHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(library.videos) { video in
                    VideoCardView(video: video)
                        .environmentObject(library)
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .background(Color.clear)
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

    private var queueHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title3.weight(.semibold))
                .foregroundStyle(compressTint)
                .frame(width: 36, height: 36)
                .appMaterialBackground(
                    .regularMaterial,
                    fallback: AppMesh.backdrop(colorScheme),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(compressTint.opacity(0.18), lineWidth: AppShape.strokeHairline))

            VStack(alignment: .leading, spacing: 3) {
                Text("Encoding Queue")
                    .font(.headline.weight(.semibold))
                Text(queueSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(library.selectedSettings.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .appMaterialBackground(
                    .thinMaterial,
                    fallback: AppMesh.backdrop(colorScheme),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(compressTint.opacity(0.22), lineWidth: AppShape.strokeHairline))
                .foregroundStyle(compressTint)
        }
        .cardStyle(tint: compressTint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Encoding queue, \(queueSummary), preset \(library.selectedSettings.title)")
    }

    private var queueSummary: String {
        let count = library.videos.count
        let noun = count == 1 ? "item" : "items"
        let active = library.videos.filter(\.jobState.isActive).count
        if active > 0 {
            return "\(active) active of \(count) \(noun)"
        }
        return "\(count) \(noun) ready"
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 168), spacing: 12)]
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
        .appMaterialBackground(
            .regularMaterial,
            fallback: AppMesh.backdrop(colorScheme),
            in: RoundedRectangle(cornerRadius: AppShape.radiusM)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppShape.radiusM)
                .strokeBorder(
                    (saveToastIsError ? Color.red : Color.green).opacity(0.25),
                    lineWidth: AppShape.strokeHairline
                )
        )
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
        HStack(spacing: 12) {
            Button {
                presetSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: library.selectedSettings.symbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(compressTint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(library.selectedSettings.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("Preset")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .appMaterialBackground(
                    .regularMaterial,
                    fallback: AppMesh.backdrop(colorScheme),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(compressTint.opacity(0.20), lineWidth: AppShape.strokeHairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose preset, \(library.selectedSettings.title)")
            .accessibilityIdentifier("presetButton")

            Spacer(minLength: 4)

            Button {
                library.compressAll()
            } label: {
                Label("Compress All", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [compressTint.opacity(0.92), compressTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasCompressible)
            .opacity(hasCompressible ? 1 : 0.45)
            .accessibilityIdentifier("compressAllButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .appMaterialBackground(
            .ultraThinMaterial,
            fallback: AppMesh.backdrop(colorScheme),
            in: RoundedRectangle(cornerRadius: AppShape.radiusL)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppShape.radiusL)
                .strokeBorder(compressTint.opacity(0.16), lineWidth: AppShape.strokeHairline)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var hasCompressible: Bool {
        library.videos.contains { !$0.jobState.isActive && $0.jobState != .finished }
    }

    private var compressTint: Color {
        AppTint.compress(colorScheme)
    }
}

#Preview {
    VideoListView()
        .environmentObject(VideoLibrary.preview())
}
