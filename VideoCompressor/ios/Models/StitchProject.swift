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
import UIKit

@MainActor
final class StitchProject: ObservableObject {
    @Published private(set) var clips: [StitchClip] = []
    @Published var exportProgress: BoundedProgress = .zero
    @Published var exportState: StitchExportState = .idle
    @Published var lastImportError: LibraryError?
    /// Output canvas aspect mode. `.auto` decides from majority clip
    /// orientation; explicit modes pin a 9:16 / 16:9 / 1:1 canvas. Mismatched
    /// clips render with black bars rather than being cropped.
    @Published var aspectMode: StitchAspectMode = .auto
    /// Global transition between adjacent clips. `.none` is the legacy
    /// hard-cut behaviour; `.random` picks per-gap among the three real
    /// effects (crossfade, fadeToBlack, wipeLeft). Render-time only —
    /// cheap GPU compositor work, no impact on encode bitrate.
    @Published var transition: StitchTransition = .none
    /// Per-clip undo/redo history for the inline editor. Keyed by clip ID.
    /// Lookup returns a fresh empty history if the clip is new.
    @Published private(set) var histories: [UUID: EditHistory] = [:]

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
    ///
    /// Split-clip safety: after `split`, both halves share `sourceURL`.
    /// We only delete the source file when NO surviving clip still
    /// references it. Otherwise the surviving half's playback / export
    /// would break (CRITICAL bug surfaced in red team — May 2026).
    func remove(at offsets: IndexSet) {
        let toDelete = offsets.map { clips[$0] }
        clips.remove(atOffsets: offsets)
        let inputsPath = inputsDir.standardizedFileURL.path
        // Also clear histories for removed clips — they can't be reached
        // via undo/redo anymore. Avoids slow leaks across long edit sessions.
        for clip in toDelete {
            histories.removeValue(forKey: clip.id)
        }
        for clip in toDelete {
            let path = clip.sourceURL.standardizedFileURL.path
            guard path.hasPrefix(inputsPath + "/") else { continue }
            // Reference-count check: don't delete a source still in use by
            // a surviving clip (split halves, or any future copy).
            let stillReferenced = clips.contains { surviving in
                surviving.sourceURL.standardizedFileURL.path == path
            }
            if stillReferenced { continue }
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

    // MARK: - Undo / Redo

    /// Snapshot the clip's current edits onto its undo stack. Call this
    /// AT THE START of a user-initiated edit interaction (e.g. drag began)
    /// or when a discrete action is committed (e.g. drag ended on a value
    /// different from the start). Idempotent if the snapshot equals the
    /// last entry already on the stack.
    func commitHistory(for id: StitchClip.ID) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        var history = histories[id] ?? EditHistory()
        history.commit(previous: clip.edits)
        histories[id] = history
    }

    /// Push an explicit pre-edit snapshot onto the clip's undo stack. Use
    /// this when the caller has captured the edits BEFORE the user mutated
    /// them (e.g. snapshot at drag start, commit at drag end with the
    /// snapshot). Idempotent for equal snapshots — won't bloat the stack
    /// with no-op drags.
    func commitHistorySnapshot(for id: StitchClip.ID, previous: ClipEdits) {
        var history = histories[id] ?? EditHistory()
        history.commit(previous: previous)
        histories[id] = history
    }

    /// Pop one entry from the clip's undo stack and apply it. The current
    /// edits are pushed to the redo stack so a subsequent Redo round-trips.
    /// No-op if there is nothing to undo.
    func undo(for id: StitchClip.ID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var history = histories[id] ?? EditHistory()
        guard let previous = history.popUndo() else { return }
        let current = clips[index].edits
        history.pushRedo(current: current)
        clips[index].edits = previous
        histories[id] = history
    }

    /// Mirror of `undo`. Pops a redo entry and pushes the current to the
    /// undo stack.
    func redo(for id: StitchClip.ID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var history = histories[id] ?? EditHistory()
        guard let next = history.popRedo() else { return }
        let current = clips[index].edits
        history.pushUndo(current: current)
        clips[index].edits = next
        histories[id] = history
    }

    /// Resets a clip's edits to `.identity` and clears history. The pre-reset
    /// state is committed to the undo stack first so the user can recover
    /// via Cmd+Z (or our Undo button).
    func resetEdits(for id: StitchClip.ID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var history = histories[id] ?? EditHistory()
        history.commit(previous: clips[index].edits)
        clips[index].edits = .identity
        histories[id] = history
    }

    func canUndo(for id: StitchClip.ID) -> Bool {
        histories[id]?.canUndo ?? false
    }

    func canRedo(for id: StitchClip.ID) -> Bool {
        histories[id]?.canRedo ?? false
    }

    // MARK: - Split & remove (structural edits)

    /// Splits a clip into two clips at `seconds` (source-clip seconds, NOT
    /// composition seconds). The first half retains the original `id`; the
    /// second half gets a fresh UUID and inherits the source / metadata /
    /// preferredTransform. The trim ranges are partitioned so the visible
    /// content is preserved exactly.
    ///
    /// Clamping rules:
    /// - `seconds` is clamped to `(currentTrimStart, currentTrimEnd)`. Splitting
    ///   exactly at a trim boundary is a no-op (returns false) — there's no
    ///   meaningful split there.
    /// - Splitting where the resulting halves would be < 0.1s also no-ops to
    ///   avoid producing useless slivers.
    ///
    /// Returns true when a split occurred.
    @discardableResult
    func split(clipID: StitchClip.ID, atSeconds seconds: Double) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return false }
        let clip = clips[index]
        let natural = CMTimeGetSeconds(clip.naturalDuration)
        let currentStart = clip.edits.trimStartSeconds ?? 0
        let currentEnd = clip.edits.trimEndSeconds ?? natural

        // Must fall strictly inside the trimmed window with margin on both sides.
        let minSliverSeconds = 0.1
        guard seconds > currentStart + minSliverSeconds,
              seconds < currentEnd - minSliverSeconds else { return false }

        // First half — original ID, trim end becomes split point.
        var firstEdits = clip.edits
        firstEdits.trimEndSeconds = seconds

        // Second half — fresh ID, trim start becomes split point, end is
        // whatever the original end was.
        var secondEdits = clip.edits
        secondEdits.trimStartSeconds = seconds
        secondEdits.trimEndSeconds = currentEnd

        let firstHalf = StitchClip(
            id: clip.id,
            sourceURL: clip.sourceURL,
            displayName: clip.displayName,
            naturalDuration: clip.naturalDuration,
            naturalSize: clip.naturalSize,
            kind: clip.kind,
            preferredTransform: clip.preferredTransform,
            edits: firstEdits
        )
        let secondHalf = StitchClip(
            id: UUID(),
            sourceURL: clip.sourceURL,
            displayName: clip.displayName + " (2)",
            naturalDuration: clip.naturalDuration,
            naturalSize: clip.naturalSize,
            kind: clip.kind,
            preferredTransform: clip.preferredTransform,
            edits: secondEdits
        )

        clips.remove(at: index)
        clips.insert(contentsOf: [firstHalf, secondHalf], at: index)
        // Both halves get fresh empty histories — splits aren't undoable
        // through the per-clip stack (they're a project-level structural
        // change). Future enhancement: project-level structural undo.
        histories[clip.id] = EditHistory()
        histories[secondHalf.id] = EditHistory()
        return true
    }

    /// Remove the time range [from..to] (source-clip seconds) from `clipID`.
    /// Implemented as: split at `from`, split the resulting second half at
    /// `to`, then drop the middle clip. Result: the clip is replaced by two
    /// clips representing the surviving parts.
    ///
    /// Clamping mirrors `split`. Returns true when a removal occurred.
    @discardableResult
    func removeRange(
        clipID: StitchClip.ID,
        fromSeconds: Double,
        toSeconds: Double
    ) -> Bool {
        guard let original = clips.first(where: { $0.id == clipID }) else { return false }
        guard fromSeconds < toSeconds else { return false }

        // Split at `fromSeconds`. After this, originalID is the FIRST half.
        guard split(clipID: clipID, atSeconds: fromSeconds) else { return false }

        // The second half is at index originalIndex+1. Split it at `toSeconds`.
        guard let secondHalfIndex = clips.firstIndex(where: { $0.id == clipID }).map({ $0 + 1 }),
              secondHalfIndex < clips.count else { return false }
        let secondHalfID = clips[secondHalfIndex].id
        guard split(clipID: secondHalfID, atSeconds: toSeconds) else {
            // Couldn't make the second cut (range too narrow at end). Roll
            // back the first split by re-merging is not trivial; instead,
            // accept the partial state — user just has a single split now.
            // Return false to signal "remove didn't fully happen".
            // Note: Original clip was already split. Caller may want to
            // present an error toast.
            // For correctness, we restore the merged-back state by removing
            // the new second half and extending the first.
            _ = restoreFromPartialSplit(clipID: clipID)
            return false
        }

        // Now there are 3 clips: [first | middle | last]. Drop the middle.
        guard let middleIndex = clips.firstIndex(where: { $0.id == secondHalfID }) else {
            return false
        }
        let middleClip = clips[middleIndex]
        clips.remove(at: middleIndex)
        histories.removeValue(forKey: middleClip.id)
        return true
    }

    /// Internal helper: undoes the most-recent split for `clipID` if the
    /// next clip after it shares the same sourceURL + naturalDuration AND
    /// has trimStart equal to the original's trimEnd (the split-point
    /// invariant). Best-effort — if the timeline has been mutated since
    /// the split, this returns false and leaves clips alone.
    @discardableResult
    private func restoreFromPartialSplit(clipID: StitchClip.ID) -> Bool {
        guard let firstIdx = clips.firstIndex(where: { $0.id == clipID }) else { return false }
        let firstHalfIdx = firstIdx
        let secondHalfIdx = firstIdx + 1
        guard secondHalfIdx < clips.count else { return false }
        let firstHalf = clips[firstHalfIdx]
        let secondHalf = clips[secondHalfIdx]
        guard firstHalf.sourceURL == secondHalf.sourceURL,
              firstHalf.naturalDuration == secondHalf.naturalDuration,
              let splitPoint = firstHalf.edits.trimEndSeconds,
              abs(splitPoint - (secondHalf.edits.trimStartSeconds ?? 0)) < 0.01
        else { return false }

        var mergedEdits = firstHalf.edits
        mergedEdits.trimEndSeconds = secondHalf.edits.trimEndSeconds
        let merged = StitchClip(
            id: firstHalf.id,
            sourceURL: firstHalf.sourceURL,
            displayName: firstHalf.displayName,
            naturalDuration: firstHalf.naturalDuration,
            naturalSize: firstHalf.naturalSize,
            kind: firstHalf.kind,
            preferredTransform: firstHalf.preferredTransform,
            edits: mergedEdits
        )
        clips.remove(at: secondHalfIdx)
        clips[firstHalfIdx] = merged
        histories.removeValue(forKey: secondHalf.id)
        return true
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
        // Hold a UIBackgroundTask for the same reason VideoLibrary.runJob
        // does — multi-clip stitch encodes are even longer than single-clip
        // compress, so screen-lock-during-export is the most likely cause
        // of AVErrorOperationInterrupted (-11847) failures the user sees.
        let bgTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "VideoCompressor.stitchExport"
        )
        AudioBackgroundKeeper.shared.begin()
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
            AudioBackgroundKeeper.shared.end()
        }

        let exporter = StitchExporter()
        let aspect = self.aspectMode
        let transition = self.transition
        do {
            let plan = try await exporter.buildPlan(
                from: clipsSnapshot,
                aspectMode: aspect,
                transition: transition
            )
            try Task.checkCancellation()

            let url = try await exporter.export(
                plan: plan,
                settings: settings,
                outputURL: outputURL
            ) { [weak self] progress in
                // onProgress is @MainActor by signature.
                self?.exportState = .encoding(progress)
            }

            // Auto-strip Meta-glasses fingerprint atoms from the stitched
            // output so the result is privacy-clean by default. Fail-soft.
            // Per user direction 2026-05-03.
            await VideoLibrary.metadataServiceShared.stripMetaFingerprintInPlace(at: url)

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
