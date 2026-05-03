//
//  MetaCleanTabView.swift
//  VideoCompressor
//
//  Root view for the MetaClean tab. Manages the import queue and routes taps
//  to MetadataInspectorView. Mirrors StitchTabView's structural shape:
//  - PhotosPicker in toolbar + empty-state CTA
//  - List with swipe-to-delete
//  - Alert for import errors
//  - Sheet for per-item detail
//
//  See `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` task M3.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct MetaCleanTabView: View {
    @StateObject private var queue = MetaCleanQueue()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedItem: MetaCleanItem?

    var body: some View {
        NavigationStack {
            Group {
                if queue.items.isEmpty {
                    CenteredEmptyState(
                        systemImage: "eye.slash",
                        title: "No videos to clean",
                        message: "Pick videos to inspect and strip metadata before sharing."
                    ) {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: 50,
                            matching: .any(of: [.videos, .images]),
                            preferredItemEncoding: .current
                        ) {
                            Label("Import Videos", systemImage: "photo.on.rectangle.angled")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("metaCleanImportButton")
                    }
                } else {
                    List {
                        ForEach(queue.items) { item in
                            MetaCleanRowView(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedItem = item }
                        }
                        .onDelete { indexSet in
                            for offset in indexSet {
                                queue.remove(queue.items[offset].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MetaClean")
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
                    .accessibilityIdentifier("metaCleanAddButton")
                }
            }
            .sheet(item: $selectedItem) { item in
                MetadataInspectorView(queue: queue, itemID: item.id)
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { queue.lastImportError != nil },
                    set: { if !$0 { queue.lastImportError = nil } }
                ),
                presenting: queue.lastImportError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.displayMessage)
            }
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let items = newItems
            pickerItems = []
            Task { await importItems(items) }
        }
    }

    // MARK: - Import

    private func importItems(_ items: [PhotosPickerItem]) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stagingDir = docs.appendingPathComponent("CleanInputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for item in items {
            do {
                guard let transferable = try await item.loadTransferable(type: VideoTransferable.self) else {
                    continue
                }

                let ext = transferable.url.pathExtension.isEmpty
                    ? "mov"
                    : transferable.url.pathExtension
                let rawBase = transferable.suggestedName
                    ?? "clip-\(UUID().uuidString.prefix(8))"
                let base = rawBase
                    .replacingOccurrences(of: "/", with: "_")
                    .deletingSuffix(".\(ext)")

                var target = stagingDir.appendingPathComponent("\(base).\(ext)")
                if FileManager.default.fileExists(atPath: target.path) {
                    let suffix = UUID().uuidString.prefix(6)
                    target = stagingDir.appendingPathComponent("\(base)-\(suffix).\(ext)")
                }

                try FileManager.default.moveItem(at: transferable.url, to: target)

                // Clean up the Picks-* wrapper directory left by VideoTransferable.
                let parent = transferable.url.deletingLastPathComponent()
                if parent.lastPathComponent.hasPrefix("Picks-") {
                    try? FileManager.default.removeItem(at: parent)
                }

                let displayName = transferable.suggestedName ?? target.lastPathComponent

                // PhotosPickerItem.itemIdentifier is available on iOS 16+ when the
                // user has granted full (.readWrite) authorization. Under limited
                // access it returns nil — we store it anyway and the ExportSheet
                // disables delete-original gracefully when nil.
                let assetID = item.itemIdentifier

                let newItem = MetaCleanItem(
                    id: UUID(),
                    sourceURL: target,
                    displayName: displayName,
                    originalAssetID: assetID,
                    tags: [],
                    scanError: nil,
                    cleanResult: nil
                )
                await queue.append(newItem)

            } catch {
                queue.lastImportError = .fileSystem(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - String helper (mirrors StitchTabView)

private extension String {
    func deletingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

#Preview {
    MetaCleanTabView()
}
