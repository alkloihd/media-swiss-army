//
//  StitchTimelineView.swift
//  VideoCompressor
//
//  iMovie-style horizontal drag-anywhere reorder (Phase 3 commit 6).
//  Replaces the vertical List + .onMove with a horizontal ScrollView +
//  HStack, where each clip block is .draggable and the strip is the
//  .dropDestination. Tap a clip to open ClipEditorSheet; long-press
//  context menu for delete (swipeActions don't fire inside HStack).
//

import SwiftUI
import AVKit
import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// MARK: - ClipID — Transferable wrapper around UUID
// ---------------------------------------------------------------------------
// We cannot retroactively conform UUID to Transferable (it lives in Foundation
// and is already used by system drag machinery), so we wrap it in a lightweight
// struct with a plain-text transfer representation.

struct ClipID: Transferable, Hashable, Sendable {
    let value: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { $0.value.uuidString },
            importing: { raw in ClipID(value: UUID(uuidString: raw) ?? UUID()) }
        )
    }
}

// ---------------------------------------------------------------------------
// MARK: - StitchTimelineView
// ---------------------------------------------------------------------------

struct StitchTimelineView: View {
    @ObservedObject var project: StitchProject
    /// Lifted up to `StitchTabView` so the parent can render the inline
    /// editor below the timeline. Tap a clip to select; tap again to
    /// deselect. nil = no clip currently being edited.
    @Binding var selectedClipID: StitchClip.ID?
    @State private var draggedID: StitchClip.ID?
    /// Which clip's gap is currently a valid drop target. Used to render
    /// a visible insertion indicator BETWEEN clips so the user can see
    /// where the dragged clip will land. iOS Photos / Files use this
    /// pattern; without it the drop is a guess.
    @State private var dropTargetID: StitchClip.ID?
    /// User-controlled pinch-to-zoom on the timeline strip. 1.0 = default
    /// 200pt clip width; clamped to [0.5, 2.5] so clips never get unusably
    /// small or absurdly large. Persisted across re-renders only — not
    /// across launches (intentional; users typically want default zoom).
    @State private var zoom: CGFloat = 1.0
    @State private var pinchAnchor: CGFloat? = nil

    private let baseClipWidth: CGFloat = 200
    private let baseClipHeight: CGFloat = 140
    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 2.5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.clips) { clip in
                    HStack(spacing: 0) {
                        // Drop-target indicator — a 6pt-wide accent-colored
                        // pill on the LEFT of the clip when this is the
                        // current drop target and the dragged clip is being
                        // moved into this position.
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(
                                width: dropTargetID == clip.id && draggedID != clip.id ? 6 : 0,
                                height: baseClipHeight * zoom * 0.85
                            )
                            .padding(.trailing, dropTargetID == clip.id && draggedID != clip.id ? 4 : 0)
                            .animation(.easeInOut(duration: 0.15), value: dropTargetID)

                    ClipBlockView(clip: clip)
                        .frame(width: baseClipWidth * zoom, height: baseClipHeight * zoom)
                        .opacity(draggedID == clip.id ? 0.4 : 1.0)
                        .overlay(
                            // Selection ring — visible when this clip is the
                            // one being edited inline.
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedClipID == clip.id ? Color.accentColor : Color.clear,
                                    lineWidth: 3
                                )
                        )
                        .onTapGesture {
                            // Confirmation tick when picking a clip to edit.
                            Haptics.tapLight()
                            if selectedClipID == clip.id {
                                selectedClipID = nil
                            } else {
                                selectedClipID = clip.id
                            }
                        }
                        .draggable(ClipID(value: clip.id)) {
                            // Drag preview — semi-transparent thumbnail
                            ClipBlockView(clip: clip)
                                .frame(width: 160 * zoom, height: 110 * zoom)
                                .opacity(0.85)
                                .onAppear {
                                    draggedID = clip.id
                                    Haptics.tapMedium()
                                }
                        }
                        .dropDestination(for: ClipID.self) { items, _ in
                            guard
                                let droppedClipID = items.first?.value,
                                let from = project.clips.firstIndex(where: { $0.id == droppedClipID }),
                                let to = project.clips.firstIndex(where: { $0.id == clip.id }),
                                from != to
                            else {
                                dropTargetID = nil
                                return false
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                // Match the semantic of List.onMove: inserting after the
                                // target when dragging forward, before when dragging back.
                                let dst = to > from ? to + 1 : to
                                project.move(from: IndexSet(integer: from), to: dst)
                            }
                            draggedID = nil
                            dropTargetID = nil
                            Haptics.tapMedium()
                            return true
                        } isTargeted: { isTargeted in
                            // Light up the insertion indicator + selection-tick
                            // a haptic so the user FEELS where the clip would
                            // land before they release.
                            if isTargeted {
                                if dropTargetID != clip.id {
                                    dropTargetID = clip.id
                                    Haptics.selectionTick()
                                }
                            } else if dropTargetID == clip.id {
                                dropTargetID = nil
                            }
                        }
                        // iOS-native long-press lift + haptic + larger preview
                        // pane that auto-plays the clip (or shows the still).
                        // The standard `.contextMenu(menuItems:preview:)` API
                        // (iOS 16+) supplies the lift haptic for free, so we
                        // don't add an extra `Haptics` call here.
                        .contextMenu(menuItems: {
                            clipContextMenu(for: clip)
                        }, preview: {
                            ClipLongPressPreview(clip: clip)
                                .frame(width: 360, height: 220)
                        })
                    }  // end inner HStack(spacing: 0) wrapping indicator + clip
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // Pinch-to-zoom — multiplicative on a per-gesture-cycle basis. We
        // capture the zoom value when the gesture begins (`pinchAnchor`)
        // so subsequent magnification deltas are applied relative to that
        // baseline and the timeline doesn't fly off-scale.
        .gesture(
            MagnificationGesture()
                .onChanged { magnitude in
                    let anchor = pinchAnchor ?? zoom
                    if pinchAnchor == nil { pinchAnchor = anchor }
                    let proposed = anchor * magnitude
                    zoom = min(maxZoom, max(minZoom, proposed))
                }
                .onEnded { _ in
                    pinchAnchor = nil
                    Haptics.tapRigid()
                }
        )
    }

    // MARK: - Context menu

    @ViewBuilder
    private func clipContextMenu(for clip: StitchClip) -> some View {
        Button {
            duplicate(clip: clip)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            moveToStart(clip: clip)
        } label: {
            Label("Move to Start", systemImage: "arrow.left.to.line")
        }
        Button {
            moveToEnd(clip: clip)
        } label: {
            Label("Move to End", systemImage: "arrow.right.to.line")
        }
        Divider()
        Button(role: .destructive) {
            deleteClip(clip)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func duplicate(clip: StitchClip) {
        guard let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let copy = StitchClip(
            id: UUID(),
            sourceURL: clip.sourceURL,
            displayName: clip.displayName + " (copy)",
            naturalDuration: clip.naturalDuration,
            naturalSize: clip.naturalSize,
            kind: clip.kind,
            preferredTransform: clip.preferredTransform,
            originalAssetID: clip.originalAssetID,
            creationDate: clip.creationDate,
            edits: clip.edits
        )
        // Insert immediately after the original. Note: source file is now
        // referenced by both clips — `remove(at:)` ref-counts deletions
        // (split file-safety fix from PR #6 covers this case).
        project.insert(copy, after: idx)
        Haptics.tapMedium()
    }

    private func moveToStart(clip: StitchClip) {
        guard let idx = project.clips.firstIndex(where: { $0.id == clip.id }), idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            project.move(from: IndexSet(integer: idx), to: 0)
        }
        Haptics.tapMedium()
    }

    private func moveToEnd(clip: StitchClip) {
        guard let idx = project.clips.firstIndex(where: { $0.id == clip.id }),
              idx < project.clips.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            project.move(from: IndexSet(integer: idx), to: project.clips.count)
        }
        Haptics.tapMedium()
    }

    private func deleteClip(_ clip: StitchClip) {
        guard let i = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        if selectedClipID == clip.id {
            selectedClipID = nil
        }
        project.remove(at: IndexSet(integer: i))
        Haptics.notifyWarning()
    }
}

// MARK: - Long-press preview

/// The lift-preview pane shown when the user long-presses a clip tile in
/// the timeline. iOS 16+ `.contextMenu(menuItems:preview:)` renders this
/// view scaled up + behind-blurred behind the menu options. For videos
/// we auto-play (muted) so the user gets a quick scrubbable preview
/// without leaving the timeline; for stills we show the image.
private struct ClipLongPressPreview: View {
    let clip: StitchClip
    @State private var player: AVPlayer?
    @State private var stillImage: UIImage?
    /// NotificationCenter token for the loop-on-end observer. Without
    /// storing + removing this, every long-press leaks an AVPlayer +
    /// closure for the lifetime of the process (Audit-2-F1, 2026-05-03).
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            Color.black
            switch clip.kind {
            case .video:
                if let player = player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView().tint(.white)
                }
            case .still:
                if let img = stillImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: clip.id) { await load() }
        .onDisappear {
            player?.pause()
            player = nil
            // Remove the loop observer so the AVPlayer + its retained
            // closure can deallocate. Block-form addObserver returns a
            // token that MUST be passed to removeObserver to break the
            // strong reference (Audit-2-F1).
            if let token = loopObserver {
                NotificationCenter.default.removeObserver(token)
                loopObserver = nil
            }
        }
    }

    private func load() async {
        switch clip.kind {
        case .video:
            let p = AVPlayer(url: clip.sourceURL)
            p.isMuted = true  // quiet preview — long-press is exploratory
            // Loop the trimmed range so the preview keeps showing motion
            // for as long as the user holds the press. We weakly capture
            // the player to break the retain cycle (observer → closure →
            // player → observer's owner).
            let token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem,
                queue: .main
            ) { [weak p] _ in
                guard let p = p else { return }
                p.seek(to: .zero)
                p.play()
            }
            await MainActor.run {
                loopObserver = token
                player = p
            }
            p.play()
        case .still:
            let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let src = CGImageSourceCreateWithURL(clip.sourceURL as CFURL, nil),
                      CGImageSourceGetCount(src) > 0 else {
                    return nil
                }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
                else { return nil }
                return UIImage(cgImage: cg)
            }.value
            await MainActor.run { stillImage = img }
        }
    }
}
