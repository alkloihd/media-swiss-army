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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.clips) { clip in
                    ClipBlockView(clip: clip)
                        .frame(width: 200, height: 140)
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
                            // Tapping the active clip closes the editor;
                            // tapping a different clip switches to it.
                            if selectedClipID == clip.id {
                                selectedClipID = nil
                            } else {
                                selectedClipID = clip.id
                            }
                        }
                        .draggable(ClipID(value: clip.id)) {
                            // Drag preview — semi-transparent thumbnail
                            ClipBlockView(clip: clip)
                                .frame(width: 160, height: 110)
                                .opacity(0.85)
                                .onAppear { draggedID = clip.id }
                        }
                        .dropDestination(for: ClipID.self) { items, _ in
                            guard
                                let droppedClipID = items.first?.value,
                                let from = project.clips.firstIndex(where: { $0.id == droppedClipID }),
                                let to = project.clips.firstIndex(where: { $0.id == clip.id }),
                                from != to
                            else { return false }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                // Match the semantic of List.onMove: inserting after the
                                // target when dragging forward, before when dragging back.
                                let dst = to > from ? to + 1 : to
                                project.move(from: IndexSet(integer: from), to: dst)
                            }
                            draggedID = nil
                            return true
                        } isTargeted: { _ in
                            // Visual feedback could be added here in a future pass
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let i = project.clips.firstIndex(where: { $0.id == clip.id }) {
                                    if selectedClipID == clip.id {
                                        selectedClipID = nil
                                    }
                                    project.remove(at: IndexSet(integer: i))
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
