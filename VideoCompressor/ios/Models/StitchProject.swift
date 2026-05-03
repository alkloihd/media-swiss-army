//
//  StitchProject.swift
//  VideoCompressor
//
//  @MainActor ObservableObject that owns the timeline state for the Stitch
//  feature. Manages the ordered clip array, per-clip edit mutations, and
//  export-lifecycle state. Export logic ships in commit 4 (StitchExporter).
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

@MainActor
final class StitchProject: ObservableObject {
    @Published private(set) var clips: [StitchClip] = []
    @Published var exportProgress: BoundedProgress = .zero
    @Published var exportState: StitchExportState = .idle

    private let inputsDir: URL

    init() {
        self.inputsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StitchInputs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: inputsDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Derived state

    /// Export is only meaningful with at least two clips.
    var canExport: Bool { clips.count >= 2 }

    // MARK: - Clip mutations

    /// Appends a clip and ensures the StitchInputs/ working directory exists.
    func append(_ clip: StitchClip) {
        try? FileManager.default.createDirectory(
            at: inputsDir,
            withIntermediateDirectories: true
        )
        clips.append(clip)
    }

    /// Removes clips at the given offsets and deletes their source files.
    func remove(at offsets: IndexSet) {
        let toDelete = offsets.map { clips[$0] }
        clips.remove(atOffsets: offsets)
        for clip in toDelete {
            try? FileManager.default.removeItem(at: clip.sourceURL)
        }
    }

    /// Pure array reorder — no IO.
    func move(from src: IndexSet, to dst: Int) {
        clips.move(fromOffsets: src, toOffset: dst)
    }

    /// Mutates `ClipEdits` for the clip with the given id in place, triggering
    /// `objectWillChange` via the `@Published clips` array write.
    func updateEdits(for id: StitchClip.ID, _ apply: (inout ClipEdits) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        apply(&clips[index].edits)
    }

    // MARK: - Export

    // TODO(commit-4): Replace stub with real StitchExporter integration.
    func export() {
        exportState = .failed(error: .fileSystem(message: "StitchExporter not implemented yet"))
    }
}

// MARK: - Export state

enum StitchExportState: Hashable, Sendable {
    case idle
    case building
    case encoding(BoundedProgress)
    case finished(CompressedOutput)
    case cancelled
    case failed(error: LibraryError)
}
