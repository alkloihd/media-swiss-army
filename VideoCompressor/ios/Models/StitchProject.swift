//
//  StitchProject.swift
//  VideoCompressor
//
//  @MainActor ObservableObject that owns the timeline state for the Stitch
//  feature. Manages the ordered clip array, per-clip edit mutations, and
//  export-lifecycle state. Export delegates to `StitchExporter` (commit 4).
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
    private let outputsDir: URL
    private var exportTask: Task<Void, Never>?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.inputsDir = docs.appendingPathComponent("StitchInputs", isDirectory: true)
        self.outputsDir = docs.appendingPathComponent("StitchOutputs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: inputsDir,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: outputsDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Derived state

    /// Export is only meaningful with at least two clips.
    var canExport: Bool { clips.count >= 2 }

    /// True while the project is mid-export. Used by the export sheet to
    /// disable the Export button and show progress.
    var isExporting: Bool {
        switch exportState {
        case .building, .encoding: return true
        default:                   return false
        }
    }

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

    /// Kicks off a new export with the given settings. Cancels any in-flight
    /// export first. Idempotent — calling repeatedly while one is running
    /// replaces the running task.
    func export(settings: CompressionSettings) {
        exportTask?.cancel()
        exportState = .building
        let snapshot = clips
        let outputURL = makeOutputURL()
        exportTask = Task { [weak self] in
            await self?.runExport(
                clipsSnapshot: snapshot,
                outputURL: outputURL,
                settings: settings
            )
        }
    }

    /// Cancels an in-flight export. Safe to call when nothing is running.
    func cancelExport() {
        exportTask?.cancel()
    }

    private func runExport(
        clipsSnapshot: [StitchClip],
        outputURL: URL,
        settings: CompressionSettings
    ) async {
        let exporter = StitchExporter()
        do {
            let plan = try await exporter.buildPlan(from: clipsSnapshot)
            try Task.checkCancellation()

            let url = try await exporter.export(
                plan: plan,
                settings: settings,
                outputURL: outputURL
            ) { [weak self] progress in
                // onProgress is @MainActor by signature.
                self?.exportState = .encoding(progress)
            }

            let bytes: Int64 = ((try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
            exportState = .finished(CompressedOutput(
                url: url,
                bytes: bytes,
                createdAt: Date(),
                settings: settings
            ))
        } catch is CancellationError {
            exportState = .cancelled
        } catch let err as CompressionError {
            exportState = .failed(error: .compression(err))
        } catch {
            exportState = .failed(error: .compression(.exportFailed(error.localizedDescription)))
        }
    }

    /// Output filename is derived from the first clip's display name plus a
    /// `_STITCH` suffix. We add a short UUID fragment when a same-named
    /// file already exists so re-exports don't clobber a previous result.
    private func makeOutputURL() -> URL {
        let stem = clips.first?.displayName.replacingOccurrences(of: "/", with: "_")
            ?? "stitch"
        var url = outputsDir.appendingPathComponent("\(stem)_STITCH.mp4")
        if FileManager.default.fileExists(atPath: url.path) {
            let suffix = UUID().uuidString.prefix(6)
            url = outputsDir.appendingPathComponent("\(stem)_STITCH-\(suffix).mp4")
        }
        return url
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
