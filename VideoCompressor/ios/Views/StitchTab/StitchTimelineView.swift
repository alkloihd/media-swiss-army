//
//  StitchTimelineView.swift
//  VideoCompressor
//
//  The clip list for the Stitch tab. Press-and-hold to reorder; swipe left
//  to delete. Always-on edit mode means the reorder handle is always visible
//  so the gesture is discoverable without an Edit button.
//
//  Tap-to-edit (ClipEditorSheet) ships in commit 3.
//

import SwiftUI

struct StitchTimelineView: View {
    @ObservedObject var project: StitchProject

    var body: some View {
        List {
            ForEach(project.clips) { clip in
                ClipBlockView(clip: clip)
            }
            .onMove(perform: project.move(from:to:))
            .onDelete(perform: project.remove(at:))
        }
        .listStyle(.plain)
        // Phase 1: always-on edit mode so press-and-hold reorder works without
        // the user first tapping an Edit button. Can be made toggleable in v2.
        .environment(\.editMode, .constant(.active))
    }
}
