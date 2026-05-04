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
import ImageIO
import CoreGraphics

struct StitchTabView: View {
    @StateObject private var project = StitchProject()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showExportSheet = false
    @State private var showStartOverConfirmation = false
    @State private var sortBanner: String = ""
    @State private var sortBannerVisible: Bool = false
    /// Drives the inline ClipEditorInlinePanel below the timeline. nil when
    /// no clip is being edited. Tapping a timeline tile sets it; tapping
    /// the same tile again or the panel's X button clears it.
    @State private var selectedClipID: StitchClip.ID?

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
                            maxSelectionCount: 50,
                            matching: .any(of: [.videos, .images]),
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
                    VStack(spacing: 0) {
                        aspectModePicker
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        transitionPicker
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                        StitchTimelineView(
                            project: project,
                            selectedClipID: $selectedClipID
                        )
                        if let id = selectedClipID {
                            ClipEditorInlinePanel(
                                project: project,
                                clipID: id,
                                onClose: { selectedClipID = nil }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        Spacer(minLength: 0)
                    }
                    .animation(.easeInOut(duration: 0.22), value: selectedClipID)
                }
            }
            .navigationTitle("Stitch")
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
                    .accessibilityIdentifier("stitchAddButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !project.clips.isEmpty {
                        Menu {
                            if project.clips.count >= 2 {
                                Button {
                                    Task {
                                        let outcome = await project.sortByCreationDateAsync()
                                        if outcome.didChange {
                                            Haptics.tapMedium()
                                        } else {
                                            Haptics.notifyWarning()
                                        }
                                        // Cluster 2.5 audit follow-up: when
                                        // some clips lacked dates (Limited
                                        // Photos auth / drag-drop / Share
                                        // Extension), surface a banner so
                                        // the user knows why their timeline
                                        // didn't fully re-order.
                                        if outcome.unresolvedCount > 0 {
                                            sortBanner = "Couldn't read date for \(outcome.unresolvedCount) clip\(outcome.unresolvedCount == 1 ? "" : "s") — those moved to the end."
                                            sortBannerVisible = true
                                            Task {
                                                try? await Task.sleep(for: .seconds(3))
                                                sortBannerVisible = false
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Sort by Date Taken", systemImage: "calendar")
                                }
                            }
                            Button(role: .destructive) {
                                showStartOverConfirmation = true
                            } label: {
                                Label("Start Over", systemImage: "arrow.counterclockwise.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .imageScale(.large)
                        }
                        .accessibilityIdentifier("stitchSortMenu")
                    }
                }
            }
            .confirmationDialog(
                "Clear all \(project.clips.count) clip\(project.clips.count == 1 ? "" : "s") and start over?",
                isPresented: $showStartOverConfirmation,
                titleVisibility: .visible
            ) {
                Button("Start Over", role: .destructive) {
                    Task {
                        await project.clearAll()
                        Haptics.notifyWarning()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the staged clips from the app's storage. Files in your Photos library are untouched.")
            }
            .safeAreaInset(edge: .bottom) {
                if !project.clips.isEmpty {
                    stitchActionBar
                }
            }
            .overlay(alignment: .top) {
                if sortBannerVisible {
                    Text(sortBanner)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("stitchSortBanner")
                }
            }
            .animation(.easeInOut(duration: 0.3), value: sortBannerVisible)
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

    // MARK: - Aspect-mode picker

    @ViewBuilder
    private var aspectModePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "aspectratio")
                    .foregroundStyle(.secondary)
                Text("Output Aspect")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            Picker("Output Aspect", selection: $project.aspectMode) {
                ForEach(StitchAspectMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(aspectCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("stitchAspectPicker")
    }

    private var aspectCaption: String {
        switch project.aspectMode {
        case .auto:      return "Picks orientation from your clips. Mismatched clips show with black bars instead of being cropped."
        case .portrait:  return "9:16 canvas. Landscape clips will pillarbox (black bars on top/bottom)."
        case .landscape: return "16:9 canvas. Portrait clips will pillarbox (black bars on left/right)."
        case .square:    return "1:1 canvas. Mismatched clips show with black bars."
        }
    }

    // MARK: - Transition (FX) picker

    @ViewBuilder
    private var transitionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Transitions")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            Picker("Transition", selection: $project.transition) {
                ForEach(StitchTransition.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(transitionCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("stitchTransitionPicker")
    }

    private var transitionCaption: String {
        switch project.transition {
        case .none:        return "Hard cuts between clips."
        case .crossfade:   return "1-second crossfade — outgoing fades out as incoming fades in."
        case .fadeToBlack: return "Half-second fade to black, then half-second fade in."
        case .wipeLeft:    return "Right-to-left wipe over 1 second."
        case .random:      return "Cycles through Crossfade / Fade Black / Wipe per gap (deterministic)."
        }
    }

    // MARK: - Bottom action bar

    private var stitchActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 6) {
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
                if !project.canExport, !project.clips.isEmpty {
                    // Cluster 2.5 audit: single-clip dead-end was the most
                    // likely 1-star review trigger. The disabled button alone
                    // gave new users no signal what they needed to do next.
                    Text("Add at least one more clip to stitch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("stitchAddMoreHint")
                }
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
            // 1. Try video Transferable first; fall back to photo.
            var transferableURL: URL?
            var transferableName: String?
            var pickedKind: ClipKind = .video

            do {
                if let v = try await item.loadTransferable(type: VideoTransferable.self) {
                    transferableURL = v.url
                    transferableName = v.suggestedName
                    pickedKind = .video
                }
            } catch { /* fall through */ }

            if transferableURL == nil {
                do {
                    if let p = try await item.loadTransferable(type: PhotoTransferable.self) {
                        transferableURL = p.url
                        transferableName = p.suggestedName
                        pickedKind = .still
                    }
                } catch {
                    await MainActor.run {
                        project.lastImportError = .fileSystem(message: error.localizedDescription)
                    }
                    continue
                }
            }
            guard let srcURL = transferableURL else { continue }

            do {
                // 2. Copy into a stable directory so sourceURL survives picker scope exit.
                let stableURL = try stageToStitchInputs(
                    source: srcURL,
                    suggestedName: transferableName,
                    into: stitchInputs
                )

                // 3. Probe duration + natural size + preferredTransform.
                // preferredTransform is captured here so the stitch composition
                // can rotate iPhone portrait video upright AND aspect-fit it
                // onto the canvas without crop. Defaults to .identity for
                // stills + fallback paths.
                let duration: CMTime
                let naturalSize: CGSize
                var preferredTransform: CGAffineTransform = .identity
                switch pickedKind {
                case .video:
                    let asset = AVURLAsset(url: stableURL)
                    do {
                        duration = try await asset.load(.duration)
                    } catch {
                        try? FileManager.default.removeItem(at: stableURL)
                        await MainActor.run {
                            project.lastImportError = .fileSystem(
                                message: "Could not read \(stableURL.lastPathComponent): \(error.localizedDescription)"
                            )
                        }
                        continue
                    }
                    if let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let size = try? await track.load(.naturalSize),
                       size.width > 0, size.height > 0 {
                        naturalSize = size
                        if let t = try? await track.load(.preferredTransform) {
                            preferredTransform = t
                        }
                    } else {
                        try? FileManager.default.removeItem(at: stableURL)
                        await MainActor.run {
                            project.lastImportError = .fileSystem(
                                message: "Could not read video dimensions for \(stableURL.lastPathComponent)."
                            )
                        }
                        continue
                    }
                case .still:
                    // Stills: fixed default duration (3 s); pull pixel size from CGImageSource.
                    duration = CMTime(seconds: 3.0, preferredTimescale: 600)
                    let stillSize: CGSize = await Task.detached(priority: .userInitiated) {
                        guard let src = CGImageSourceCreateWithURL(stableURL as CFURL, nil),
                              CGImageSourceGetCount(src) > 0,
                              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
                        else { return CGSize(width: 1920, height: 1080) }
                        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 1920
                        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 1080
                        return CGSize(width: w, height: h)
                    }.value
                    naturalSize = stillSize
                }

                let displayName = transferableName
                    ?? stableURL.deletingPathExtension().lastPathComponent

                var edits: ClipEdits = .identity
                if pickedKind == .still {
                    edits.stillDuration = 3.0
                }

                // Capture Photos asset ID at import (cheap, in-memory).
                // The expensive PHAsset → creationDate lookup is deferred
                // to sortByCreationDate's batch fetch, which is N×faster
                // than N synchronous fetches here. (Red-team H-2.)
                let assetID = item.itemIdentifier

                let clip = StitchClip(
                    id: UUID(),
                    sourceURL: stableURL,
                    displayName: displayName,
                    naturalDuration: duration,
                    naturalSize: naturalSize,
                    kind: pickedKind,
                    preferredTransform: preferredTransform,
                    originalAssetID: assetID,
                    creationDate: nil,
                    edits: edits
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
        await Self.finalizeImportOrdering(project: project)
    }

    /// Moves the picker-staged temp file into `StitchInputs/`.
    private func stageToStitchInputs(
        source: URL,
        suggestedName: String?,
        into dir: URL
    ) throws -> URL {
        try Self.stageToStitchInputs(
            source: source,
            suggestedName: suggestedName,
            into: dir
        )
    }

    /// Static so tests can invoke staging without instantiating SwiftUI state.
    static func stageToStitchInputs(
        source: URL,
        suggestedName: String?,
        into dir: URL
    ) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let base = (suggestedName ?? "clip-\(UUID().uuidString.prefix(8))")
            .replacingOccurrences(of: "/", with: "_")
            .deletingSuffix(".\(ext)")
        let prefix = UUID().uuidString.prefix(6).lowercased()
        let target = dir.appendingPathComponent("\(prefix)-\(base).\(ext)")
        try FileManager.default.moveItem(at: source, to: target)

        // Clean up the Picks-* wrapper directory left by VideoTransferable.
        let parent = source.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("Picks-") {
            try? FileManager.default.removeItem(at: parent)
        }
        return target
    }

    static func testHook_stageToStitchInputs(
        source: URL,
        suggestedName: String?,
        into dir: URL
    ) throws -> URL {
        try stageToStitchInputs(
            source: source,
            suggestedName: suggestedName,
            into: dir
        )
    }

    @discardableResult
    @MainActor
    static func finalizeImportOrdering(project: StitchProject) async -> Bool {
        await project.sortByCreationDateAsync().didChange
    }

    @discardableResult
    @MainActor
    static func testHook_finalizeImportOrdering(project: StitchProject) async -> Bool {
        await finalizeImportOrdering(project: project)
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
