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
import os

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
        case .building, .preparing, .encoding: return true
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

    /// Wipes the entire project: cancels any in-flight export, removes every
    /// clip and its on-disk source file (scoped to `inputsDir`, same safety
    /// semantics as `remove(at:)`), resets export state to `.idle`, clears
    /// edit histories. Idempotent — calling on an empty project is a no-op.
    /// Used by the "Start Over" toolbar action and the post-save
    /// "Done — start a new project" CTA.
    ///
    /// **Cancel-and-await contract** (Cluster 2.5 audit follow-up): if an
    /// export task is in flight, we cancel it and await completion BEFORE
    /// touching any state. Without this, the live `runExport` task continues
    /// to read from `inputsDir` while `remove(at:)` deletes those files,
    /// surfaces opaque `-11800` "Read failed" alerts, and (worst) writes a
    /// phantom `_STITCH.mp4` into `outputsDir` that the user never asked
    /// for. Three independent audits flagged this; this is the fix.
    func clearAll() async {
        if let task = exportTask {
            task.cancel()
            _ = await task.value
            exportTask = nil
        }
        // Re-audit 6 finding: prior version left aspectMode/transition
        // pinned from the previous project, so users who exported portrait
        // + crossfade once and then "Started Over" got unexpected
        // pillarboxing on landscape clips. Reset to factory defaults so
        // the next project starts at a known state.
        //
        // NOT touching `lastImportError` here: it's already cleared by the
        // alert's own dismiss-binding setter, and pre-emptively nulling it
        // would mask a recently-surfaced import failure the user hasn't
        // acknowledged yet (re-audit 3 wave-3 catch).
        aspectMode = .auto
        transition = .none
        guard !clips.isEmpty || exportState != .idle else { return }
        let allOffsets = IndexSet(integersIn: 0..<clips.count)
        if !allOffsets.isEmpty {
            remove(at: allOffsets)
        }
        histories.removeAll()
        exportState = .idle
    }

    /// Inserts a clip immediately after the given index. Used by the
    /// "Duplicate" context-menu action so the duplicate sits next to its
    /// source in the timeline. The duplicate's `sourceURL` typically
    /// matches an existing clip's URL — `remove(at:)` reference-counts
    /// before deleting on-disk files so duplicates are safe to delete.
    func insert(_ clip: StitchClip, after index: Int) {
        let safeIdx = max(0, min(index + 1, clips.count))
        clips.insert(clip, at: safeIdx)
    }

    /// Re-orders the timeline so clips with the earliest `creationDate`
    /// come first. Clips without a captured date (drag-drop, share extension,
    /// limited Photos auth) sort to the END, preserving their relative order.
    /// The sort is stable. Returns true if the order actually changed.
    ///
    /// Pure / synchronous variant — uses dates that were captured at clip
    /// construction time. Useful for tests and when the caller has already
    /// populated dates. Production UI uses the async variant.
    @discardableResult
    func sortByCreationDate() -> Bool {
        let before = clips.map(\.id)
        let indexed = clips.enumerated().map { (offset: $0.offset, clip: $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            switch (lhs.clip.creationDate, rhs.clip.creationDate) {
            case let (.some(l), .some(r)) where l != r: return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }
        let newClips = sorted.map(\.clip)
        let after = newClips.map(\.id)
        guard before != after else { return false }
        clips = newClips
        return true
    }

    /// Result of a `sortByCreationDateAsync()` call. Lets the UI distinguish
    /// "actually re-ordered the timeline" from "couldn't read N dates so
    /// nothing changed" — Cluster 2.5 audit found these were collapsed into
    /// one outcome, producing identical haptics for both states.
    struct SortByDateOutcome: Equatable, Sendable {
        let didChange: Bool
        /// Number of clips for which we couldn't resolve a creation date —
        /// these were parked at the end of the timeline in import order.
        /// Limited Photos auth, drag-drop sources, and Share-Extension
        /// inputs all surface here.
        let unresolvedCount: Int
    }

    /// Fetches missing creation dates from Photos in a single batch call
    /// (cheaper than N×serial), populates the in-memory cache on each clip,
    /// then runs the sync sort. Used by the toolbar "Sort by Date Taken"
    /// action. Returns a structured outcome the caller can surface to the
    /// user when some clips lacked dates.
    @discardableResult
    func sortByCreationDateAsync() async -> SortByDateOutcome {
        // Collect asset IDs for clips that don't already have a cached date.
        let missingIDs = clips.compactMap { clip -> String? in
            guard clip.creationDate == nil, let id = clip.originalAssetID
            else { return nil }
            return id
        }
        if !missingIDs.isEmpty {
            let dates = await StitchClipFetcher.creationDates(forAssetIDs: missingIDs)
            // Rewrite clips with newly-resolved dates. Preserve all other fields.
            clips = clips.map { clip in
                guard clip.creationDate == nil,
                      let id = clip.originalAssetID,
                      let date = dates[id]
                else { return clip }
                return StitchClip(
                    id: clip.id,
                    sourceURL: clip.sourceURL,
                    displayName: clip.displayName,
                    naturalDuration: clip.naturalDuration,
                    naturalSize: clip.naturalSize,
                    kind: clip.kind,
                    preferredTransform: clip.preferredTransform,
                    originalAssetID: clip.originalAssetID,
                    creationDate: date,
                    edits: clip.edits
                )
            }
        }
        // After the date-resolution pass, count clips still missing a date.
        // Anything still missing was parked at the end of the timeline by
        // sortByCreationDate's "Photos-less clips sort last" rule.
        let unresolvedCount = clips.reduce(into: 0) { count, clip in
            if clip.creationDate == nil { count += 1 }
        }
        let didChange = sortByCreationDate()
        return SortByDateOutcome(didChange: didChange, unresolvedCount: unresolvedCount)
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
            originalAssetID: clip.originalAssetID,
            creationDate: clip.creationDate,
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
            originalAssetID: clip.originalAssetID,
            creationDate: clip.creationDate,
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
            originalAssetID: firstHalf.originalAssetID,
            creationDate: firstHalf.creationDate,
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

        // Cluster 2.5 audit: pre-flight disk-space check. Multi-cam HEVC at
        // 1080p is ~80–120 MB/min/camera; a 20-clip stitch can pump 8–12 GB
        // while reader-decode + writer-encode + post-strip-rewrite all hold
        // bytes simultaneously. Running out mid-encode used to surface as a
        // generic "Encode failed" with NSError detail. Now we surface a
        // specific friendly error before any work starts.
        let freeBytes = Self.freeDiskBytesForOutput()
        let estimatedMaxBytes = Self.estimatedExportBytes(for: clipsSnapshot, settings: settings)
        if freeBytes > 0, estimatedMaxBytes > 0, freeBytes < estimatedMaxBytes {
            let neededMB = max(1, estimatedMaxBytes / 1_048_576)
            let freeMB = max(0, freeBytes / 1_048_576)
            exportState = .failed(error: .compression(.exportFailed(
                "Not enough free space to export this stitch. Need ~\(neededMB) MB, only \(freeMB) MB free. Clear storage in Settings → General → iPhone Storage and try again."
            )))
            return
        }

        let exporter = StitchExporter()
        let aspect = self.aspectMode
        let transition = self.transition
        do {
            let plan = try await exporter.buildPlan(
                from: clipsSnapshot,
                aspectMode: aspect,
                transition: transition,
                onPrepareProgress: { [weak self] current, total in
                    // Surface still-baking progress so users don't sit on a
                    // mute "Building composition…" for several seconds when
                    // their timeline has photos. Encode progress takes over
                    // immediately after.
                    self?.exportState = .preparing(current: current, total: total)
                }
            )
            try Task.checkCancellation()

            // Clean up baked-still temp .movs after the export finishes (or
            // throws). Without this, NSTemporaryDirectory accumulates orphaned
            // bakes — iOS does NOT reliably reap that dir on its own.
            let bakedURLs = plan.bakedStillURLs
            defer {
                for url in bakedURLs {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            let result = try await exporter.export(
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
            await VideoLibrary.metadataServiceShared.stripMetaFingerprintInPlace(at: result.url)

            let bytes: Int64 = ((try? FileManager.default
                .attributesOfItem(atPath: result.url.path)[.size]) as? NSNumber)?.int64Value ?? 0
            exportState = .finished(CompressedOutput(
                url: result.url,
                bytes: bytes,
                createdAt: Date(),
                settings: result.settings,
                note: result.fallbackMessage
            ))
        } catch is CancellationError {
            exportState = .cancelled
        } catch CompressionError.cancelled {
            // Cluster 2.5 audit: CompressionService.encode throws a domain
            // CompressionError.cancelled when its writer notices Task is
            // cancelled, which is NOT Swift's CancellationError — without
            // this arm, user-cancel rendered as a red "Compression was
            // cancelled" failure banner instead of the silent .cancelled
            // state. Treat both cancellation flavours identically.
            exportState = .cancelled
        } catch let err as CompressionError {
            exportState = .failed(error: .compression(err))
        } catch {
            exportState = .failed(error: .compression(.exportFailed(error.localizedDescription)))
        }
    }

    /// Free space (bytes) on the volume containing Documents/. Returns 0
    /// when the resource value can't be read — caller should treat 0 as
    /// "unknown, skip the preflight check". Logs a warning when the read
    /// fails so support can correlate later "no space left" reports with
    /// the preflight having silently bypassed (re-audit 1 follow-up).
    static func freeDiskBytesForOutput() -> Int64 {
        let log = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "ca.nextclass.VideoCompressor",
            category: "StitchProject.preflight"
        )
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            log.warning("Documents directory unavailable; preflight will skip")
            return 0
        }
        guard let values = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else {
            log.warning("volumeAvailableCapacityForImportantUsage unreadable; preflight will skip and any mid-encode out-of-space failure will surface as raw NSError")
            return 0
        }
        return bytes
    }

    /// Worst-case byte estimate for a stitch export. Sum of source clip
    /// sizes × 3 to cover (a) post-strip rewrite, (b) baked stills,
    /// (c) safety margin for AVFoundation's internal buffering. Returns 0
    /// when no clip has a measurable file size — preflight then skips.
    static func estimatedExportBytes(for clips: [StitchClip], settings: CompressionSettings) -> Int64 {
        var sum: Int64 = 0
        for clip in clips {
            let attrs = try? FileManager.default.attributesOfItem(atPath: clip.sourceURL.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            sum += size
        }
        // 3× headroom: composition output + post-strip rewrite + Photos
        // save copy. Underestimating is the failure mode we're protecting
        // against, so prefer over-estimating.
        return sum > 0 ? sum * 3 : 0
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
    /// Pre-encode preparation phase (currently: still-image baking). Progress
    /// is fraction of stills baked so far. Surfaced separately from
    /// `.encoding` because the bake step has different perceptual feel
    /// (no streaming progress, just N→N+1 transitions per still).
    case preparing(current: Int, total: Int)
    case encoding(BoundedProgress)
    case finished(CompressedOutput)
    case cancelled
    case failed(error: LibraryError)
}
