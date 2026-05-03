//
//  ClipEditorSheet.swift
//  VideoCompressor
//
//  Three-tab editor sheet (Trim / Crop / Rotate) for a single stitch clip.
//  Draft pattern: local @State holds in-progress edits; changes are only
//  committed to the project on Done, so Cancel is a true no-op.
//

import SwiftUI

struct ClipEditorSheet: View {
    @ObservedObject var project: StitchProject
    let clipID: StitchClip.ID

    @Environment(\.dismiss) private var dismiss
    @State private var draftEdits: ClipEdits = .identity

    var body: some View {
        // Guard against stale clipID (clip removed while sheet was open).
        guard let clip = project.clips.first(where: { $0.id == clipID }) else {
            // SwiftUI body must return a View — emit an empty one and dismiss.
            return AnyView(
                Color.clear
                    .onAppear {
                        print("[ClipEditorSheet] clip \(clipID) not found in project — dismissing")
                        dismiss()
                    }
            )
        }

        return AnyView(
            NavigationStack {
                TabView {
                    TrimEditorView(clip: clip, edits: $draftEdits)
                        .tabItem { Label("Trim", systemImage: "scissors") }

                    CropEditorView(clip: clip, edits: $draftEdits)
                        .tabItem { Label("Crop", systemImage: "crop") }

                    RotateEditorView(edits: $draftEdits)
                        .tabItem { Label("Rotate", systemImage: "rotate.right") }
                }
                .navigationTitle("Edit Clip")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            project.updateEdits(for: clipID) { $0 = draftEdits }
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    draftEdits = clip.edits
                }
            }
            .presentationDetents([.large])
        )
    }
}
