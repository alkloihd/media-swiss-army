//
//  StitchTimelineView.swift
//  VideoCompressor
//
//  The clip list for the Stitch tab. Press-and-hold to reorder; swipe left
//  to delete. Always-on edit mode means the reorder handle is always visible
//  so the gesture is discoverable without an Edit button.
//
//  Tap a clip to open ClipEditorSheet (commit 3).
//

import SwiftUI

struct StitchTimelineView: View {
    @ObservedObject var project: StitchProject
    @State private var editingClipID: StitchClip.ID?

    var body: some View {
        List {
            ForEach(project.clips) { clip in
                ClipBlockView(clip: clip)
                    .contentShape(Rectangle())
                    .onTapGesture { editingClipID = clip.id }
            }
            .onMove(perform: project.move(from:to:))
            .onDelete(perform: project.remove(at:))
        }
        .listStyle(.plain)
        // Phase 1: always-on edit mode so press-and-hold reorder works without
        // the user first tapping an Edit button. Can be made toggleable in v2.
        .environment(\.editMode, .constant(.active))
        // sheet(item:) requires the item to be Identifiable; StitchClip is.
        .sheet(item: Binding(
            get: { project.clips.first(where: { $0.id == editingClipID }) },
            set: { newValue in editingClipID = newValue?.id }
        )) { clip in
            ClipEditorSheet(project: project, clipID: clip.id)
        }
    }
}
