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
//  See `.agents/work-sessions/2026-05-03/plans/PLAN-stitch-metaclean.md` task M3.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct MetaCleanTabView: View {
    @StateObject private var queue = MetaCleanQueue()
    @EnvironmentObject private var library: VideoLibrary
    @Environment(\.colorScheme) private var colorScheme
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedItem: MetaCleanItem?
    @State private var batchToast: SaveBatchResult?

    private var dominantKind: MediaKind {
        let stills = queue.items.filter { $0.kind == .still }.count
        let videos = queue.items.filter { $0.kind == .video }.count
        return stills >= videos ? .still : .video
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshAuroraView(tint: metaTint)

                if queue.items.isEmpty {
                    CenteredEmptyState(
                        systemImage: "eye.slash.circle",
                        title: "No videos to clean",
                        message: "Pick videos to inspect and strip metadata before sharing.",
                        tint: metaTint,
                        symbolSize: 96
                    ) {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: 50,
                            matching: .any(of: [.videos, .images]),
                            preferredItemEncoding: .current
                        ) {
                            Label("Import Videos", systemImage: "photo.on.rectangle.angled")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .appMaterialBackground(
                                    .regularMaterial,
                                    fallback: AppMesh.backdrop(colorScheme),
                                    in: Capsule()
                                )
                                .overlay(Capsule().strokeBorder(metaTint.opacity(0.25), lineWidth: AppShape.strokeHairline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metaCleanImportButton")
                    }
                } else {
                    VStack(spacing: 0) {
                        List {
                            ForEach(queue.items) { item in
                                MetaCleanRowView(item: item, tint: metaTint)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedItem = item }
                            }
                            .onDelete { indexSet in
                                for offset in indexSet {
                                    queue.remove(queue.items[offset].id)
                                }
                            }
                        }
                        batchControls
                    }
                }
            }
            .tint(metaTint)
            .navigationTitle("MetaClean")
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
        .onChange(of: library.lastSaveBatch) { _, newValue in
            guard let result = newValue else { return }
            batchToast = result
            Task {
                try? await Task.sleep(for: .seconds(3))
                if batchToast == result {
                    batchToast = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = batchToast {
                Label(toast.displayMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .appMaterialBackground(
                        .thinMaterial,
                        fallback: AppMesh.backdrop(colorScheme),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(metaTint.opacity(0.20), lineWidth: AppShape.strokeHairline))
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("metaCleanBatchSaveToast")
            }
        }
        .animation(.easeInOut(duration: 0.20), value: batchToast)
    }

    private var metaTint: Color {
        AppTint.metaClean(colorScheme)
    }

    // MARK: - Import

    private func importItems(_ items: [PhotosPickerItem]) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stagingDir = docs.appendingPathComponent("CleanInputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for item in items {
            // Try video first; fall back to photo. Mirrors VideoLibrary's
            // dual-loadTransferable pattern.
            var stagedURL: URL?
            var displayName: String = ""
            var kind: MediaKind = .video
            var defaultExt = "mov"

            do {
                if let transferable = try await item.loadTransferable(type: VideoTransferable.self) {
                    stagedURL = transferable.url
                    displayName = transferable.suggestedName ?? transferable.url.lastPathComponent
                    kind = .video
                    defaultExt = "mov"
                }
            } catch { /* fall through */ }
            if stagedURL == nil {
                do {
                    if let transferable = try await item.loadTransferable(type: PhotoTransferable.self) {
                        stagedURL = transferable.url
                        displayName = transferable.suggestedName ?? transferable.url.lastPathComponent
                        kind = .still
                        defaultExt = "heic"
                    }
                } catch {
                    queue.lastImportError = .fileSystem(message: error.localizedDescription)
                    continue
                }
            }
            guard let transferableURL = stagedURL else { continue }

            do {
                let ext = transferableURL.pathExtension.isEmpty
                    ? defaultExt
                    : transferableURL.pathExtension
                let rawBase = displayName
                let base = rawBase
                    .replacingOccurrences(of: "/", with: "_")
                    .deletingSuffix(".\(ext)")

                var target = stagingDir.appendingPathComponent("\(base).\(ext)")
                if FileManager.default.fileExists(atPath: target.path) {
                    let suffix = UUID().uuidString.prefix(6)
                    target = stagingDir.appendingPathComponent("\(base)-\(suffix).\(ext)")
                }

                try FileManager.default.moveItem(at: transferableURL, to: target)

                let parent = transferableURL.deletingLastPathComponent()
                if parent.lastPathComponent.hasPrefix("Picks-") {
                    try? FileManager.default.removeItem(at: parent)
                }

                let assetID = item.itemIdentifier

                let newItem = MetaCleanItem(
                    id: UUID(),
                    sourceURL: target,
                    displayName: displayName.isEmpty ? target.lastPathComponent : displayName,
                    kind: kind,
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

    // MARK: - Batch controls (Clean All)

    @ViewBuilder
    private var batchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Replace originals in Photos", isOn: $queue.replaceOriginalsOnBatch)
                .font(.subheadline)
                .tint(.red)
            Text(queue.replaceOriginalsOnBatch
                 ? "Cleans, saves to Photos, then deletes the source asset (recoverable from Recently Deleted for 30 days)."
                 : "Cleans in place — sources remain in Photos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if queue.batchProgress.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: queue.batchProgress.fraction)
                    HStack {
                        Text(queue.batchProgress.userFacingLabel(kind: dominantKind))
                            .font(.caption.monospacedDigit())
                            .accessibilityIdentifier("metaCleanBatchProgressLabel")
                        Spacer()
                        if queue.batchProgress.failed > 0 {
                            Label("\(queue.batchProgress.failed) failed", systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Button("Cancel") { queue.cancelBatch() }
                            .font(.caption.weight(.semibold))
                    }
                    if let err = queue.batchProgress.lastError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            } else {
                Button {
                    queue.cleanAll(onBatchSaveComplete: { result in
                        library.notifySaveBatchCompleted(result)
                    })
                } label: {
                    Label(
                        queue.replaceOriginalsOnBatch
                            ? "Clean All & Replace"
                            : "Clean All",
                        systemImage: "wand.and.stars"
                    )
                    .frame(maxWidth: .infinity)
                    .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(queue.items.isEmpty)
                .accessibilityIdentifier("metaCleanCleanAllButton")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
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
        .environmentObject(VideoLibrary.preview())
}
