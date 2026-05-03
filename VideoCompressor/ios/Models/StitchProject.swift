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
    @Published var lastImportError: LibraryError?

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

    /// Appends a clip. The StitchInputs/ working directory is created once
    /// in `init`; we don't recreate it here (closes review {E-0503-1032} M3).
    func append(_ clip: StitchClip) {
        clips.append(clip)
    }

    /// Removes clips at the given offsets and deletes their source files.
    /// Deletion is scoped to descendants of `inputsDir` so a misconstructed
    /// `StitchClip` (e.g. one pointing at a Photos library URL) cannot be
    /// used to delete user data via this path (closes review
    /// {E-0503-1032} H2).
    func remove(at offsets: IndexSet) {
        let toDelete = offsets.map { clips[$0] }
        clips.remove(atOffsets: offsets)
        let inputsPath = inputsDir.standardizedFileURL.path
        for clip in toDelete {
            let path = clip.sourceURL.standardizedFileURL.path
            guard path.hasPrefix(inputsPath + "/") else { continue }
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
