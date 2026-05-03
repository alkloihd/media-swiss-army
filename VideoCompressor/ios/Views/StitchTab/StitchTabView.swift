//
//  StitchTabView.swift
//  VideoCompressor
//
//  Top-level screen for the Stitch tab. Manages an ordered clip list via
//  StitchProject. Mirrors the VideoListView shape: PhotosPicker in the
//  toolbar, bottom action bar, alert for import errors.
//
//  Export (commit 4) and per-clip editing (commit 3) are not wired yet.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct StitchTabView: View {
    @StateObject private var project = StitchProject()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showExportSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if project.clips.isEmpty {
                    CenteredEmptyState(
                        systemImage: "square.stack.3d.up",
                        title: "No clips yet",
                        message: "Pick two or more videos to stitch together into one."
                    ) {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: 20,
                            matching: .videos,
                            preferredItemEncoding: .current
                        ) {
                            Label("Import Videos", systemImage: "photo.on.rectangle.angled")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("stitchImportButton")
                    }
                } else {
                    StitchTimelineView(project: project)
                }
            }
            .navigationTitle("Stitch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 20,
                        matching: .videos,
                        preferredItemEncoding: .current
                    ) {
                        Label("Add", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                    .accessibilityIdentifier("stitchAddButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !project.clips.isEmpty {
                    stitchActionBar
                }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { project.lastImportError != nil },
                    set: { if !$0 { project.lastImportError = nil } }
                ),
                presenting: project.lastImportError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.displayMessage)
            }
            .sheet(isPresented: $showExportSheet) {
                StitchExportSheet(project: project)
            }
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let items = newItems
            pickerItems = []
            Task { await importClips(items) }
        }
    }

    // MARK: - Bottom action bar

    private var stitchActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button {
                    showExportSheet = true
                } label: {
                    Label("Stitch & Export", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!project.canExport)
                .accessibilityIdentifier("stitchExportButton")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: - Import

    /// Imports picked items sequentially, preserving picker order.
    /// Each item is staged via VideoTransferable, copied to Documents/StitchInputs/,
    /// then probed for duration/size before appending to the project.
    private func importClips(_ items: [PhotosPickerItem]) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stitchInputs = docs.appendingPathComponent("StitchInputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: stitchInputs, withIntermediateDirectories: true)

        for item in items {
            do {
                // 1. Transferable gives us a temp-dir-staged file.
                guard let transferable = try await item.loadTransferable(type: VideoTransferable.self) else {
                    continue
                }

                // 2. Copy into a stable directory so sourceURL survives picker scope exit.
                let stableURL = try stageToStitchInputs(
                    source: transferable.url,
                    suggestedName: transferable.suggestedName,
                    into: stitchInputs
                )

                // 3. Probe duration (required) and natural size (best-effort).
                let asset = AVURLAsset(url: stableURL)
                let duration: CMTime
                do {
                    duration = try await asset.load(.duration)
                } catch {
                    // Can't place clip without duration — surface error, clean up.
                    try? FileManager.default.removeItem(at: stableURL)
                    await MainActor.run {
                        project.lastImportError = .fileSystem(
                            message: "Could not read \(stableURL.lastPathComponent): \(error.localizedDescription)"
                        )
                    }
                    continue
                }

                // Natural size via video track — required. A zero size would
                // cause CropEditorView's normalized math to divide by zero.
                let naturalSize: CGSize
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let size = try? await track.load(.naturalSize),
                   size.width > 0, size.height > 0 {
                    naturalSize = size
                } else {
                    try? FileManager.default.removeItem(at: stableURL)
                    await MainActor.run {
                        project.lastImportError = .fileSystem(
                            message: "Could not read video dimensions for \(stableURL.lastPathComponent). The file may be corrupt or use an unsupported codec."
                        )
                    }
                    continue
                }

                let displayName = transferable.suggestedName
                    ?? stableURL.deletingPathExtension().lastPathComponent

                let clip = StitchClip(
                    id: UUID(),
                    sourceURL: stableURL,
                    displayName: displayName,
                    naturalDuration: duration,
                    naturalSize: naturalSize,
                    edits: .identity
                )

                await MainActor.run {
                    project.append(clip)
                }

            } catch {
                await MainActor.run {
                    project.lastImportError = .fileSystem(message: error.localizedDescription)
                }
            }
        }
    }

    /// Moves the picker-staged temp file into `StitchInputs/`. If a file
    /// with the same name already exists (because an earlier-imported clip
    /// is still in the project and references that path), append a UUID
    /// suffix instead of overwriting — overwriting would leave the prior
    /// in-memory `StitchClip` with a dangling URL (closes review
    /// {E-0503-1050} HIGH-1).
    private func stageToStitchInputs(
        source: URL,
        suggestedName: String?,
        into dir: URL
    ) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let base = (suggestedName ?? "clip-\(UUID().uuidString.prefix(8))")
            .replacingOccurrences(of: "/", with: "_")
            .deletingSuffix(".\(ext)")
        var target = dir.appendingPathComponent("\(base).\(ext)")

        if FileManager.default.fileExists(atPath: target.path) {
            let suffix = UUID().uuidString.prefix(6)
            target = dir.appendingPathComponent("\(base)-\(suffix).\(ext)")
        }
        try FileManager.default.moveItem(at: source, to: target)

        // Clean up the Picks-* wrapper directory left by VideoTransferable.
        let parent = source.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("Picks-") {
            try? FileManager.default.removeItem(at: parent)
        }
        return target
    }
}

private extension String {
    /// Removes a trailing `suffix` if present. Used so we don't end up with
    /// `clip.mov.mov` when the picker hands us a name that already includes
    /// the extension.
    func deletingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

#Preview {
    StitchTabView()
}
