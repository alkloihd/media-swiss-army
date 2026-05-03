//
//  ClipEditorSheet.swift
//  VideoCompressor
//
//  Phase 3 commit 6 — live-apply edits.
//  Binds directly to project.updateEdits so every thumb drag updates
//  the timeline immediately. Cancel reverts to the on-appear snapshot;
//  Done just dismisses (no commit step needed).
//

import SwiftUI

struct ClipEditorSheet: View {
    @ObservedObject var project: StitchProject
    let clipID: StitchClip.ID

    @Environment(\.dismiss) private var dismiss
    /// Snapshot taken on appear — used by Cancel to revert live changes.
    @State private var initialSnapshot: ClipEdits = .identity

    // MARK: - Live edits binding

    /// Every write goes straight through to the project so the timeline
    /// and TrimEditorView player stay in sync during dragging.
    private func editsBinding() -> Binding<ClipEdits> {
        Binding(
            get: { project.clips.first(where: { $0.id == clipID })?.edits ?? .identity },
            set: { newEdits in
                project.updateEdits(for: clipID) { $0 = newEdits }
            }
        )
    }

    var body: some View {
        // Guard against stale clipID (clip removed while sheet was open).
        guard let clip = project.clips.first(where: { $0.id == clipID }) else {
            return AnyView(
                Color.clear
                    .onAppear {
                        print("[ClipEditorSheet] clip \(clipID) not found — dismissing")
                        dismiss()
                    }
            )
        }

        return AnyView(
            NavigationStack {
                TabView {
                    TrimEditorView(clip: clip, edits: editsBinding(), project: project)
                        .tabItem { Label("Trim", systemImage: "scissors") }

                    CropEditorView(clip: clip, edits: editsBinding())
                        .tabItem { Label("Crop", systemImage: "crop") }

                    RotateEditorView(edits: editsBinding())
                        .tabItem { Label("Rotate", systemImage: "rotate.right") }
                }
                .navigationTitle("Edit Clip")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            // Revert live changes back to the on-appear snapshot
                            project.updateEdits(for: clipID) { $0 = initialSnapshot }
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            // Edits already live in the project — just dismiss
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    initialSnapshot = project.clips.first(where: { $0.id == clipID })?.edits ?? .identity
                }
            }
            .presentationDetents([.large])
        )
    }
}
