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
    @State private var editingClipID: StitchClip.ID?
    @State private var draggedID: StitchClip.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.clips) { clip in
                    ClipBlockView(clip: clip)
                        .frame(width: 200, height: 140)
                        .opacity(draggedID == clip.id ? 0.4 : 1.0)
                        .onTapGesture { editingClipID = clip.id }
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
        .sheet(item: Binding(
            get: { project.clips.first(where: { $0.id == editingClipID }) },
            set: { newValue in editingClipID = newValue?.id }
        )) { clip in
            ClipEditorSheet(project: project, clipID: clip.id)
        }
    }
}
