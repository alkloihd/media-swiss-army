//
//  VideoLibrary.swift
//  VideoCompressor
//
//  Single source of truth for the video list. Owned by `VideoCompressorApp`
//  as a `@StateObject`, injected into the view tree as an EnvironmentObject.
//
//  Responsibilities:
//  - Copy PhotosPicker URLs into a stable working directory (PhotosPicker
//    URLs vanish on scope exit).
//  - Load metadata for each newly imported video.
//  - Run compression jobs serially for now (concurrency = 1 on device to
//    avoid thermal throttling — the web app can afford 4 because it runs on
//    a Mac).
//  - Save finished outputs to the Photos library on demand.
//

import Foundation
import SwiftUI
import PhotosUI
import UIKit

@MainActor
final class VideoLibrary: ObservableObject {
    @Published private(set) var videos: [VideoFile] = []
    @Published var selectedSettings: CompressionSettings = .balanced
    /// Photo equivalent of `selectedSettings`. The PresetPickerView decides
    /// which one to display based on the current selection's media kinds.
    @Published var selectedPhotoSettings: PhotoCompressionSettings = .balanced
    @Published var lastError: LibraryError?

    /// Convenience accessor for SwiftUI alert bindings.
    var lastErrorMessage: String? { lastError?.displayMessage }

    private var activeTask: Task<Void, Never>?
    // No shared CompressionService — each runJob creates its own instance so
    // concurrent calls don't serialize on a single actor. See Phase 3 commit 8.
    /// Shared photo compression service — photo encodes are fast (~100 ms)
    /// so serialization on the actor is acceptable; no per-call instance needed.
    private let photoService = PhotoCompressionService()
    /// Single shared MetadataService for auto-fingerprint-strip across
    /// Compress + Stitch + (future) Share Extension paths.
    fileprivate static let metadataService = MetadataService()
    fileprivate static let photoMetadataService = PhotoMetadataService()
    /// Public alias so StitchProject can call into the same instance
    /// without exposing the fileprivate name.
    static var metadataServiceShared: MetadataService { metadataService }
    static var photoMetadataServiceShared: PhotoMetadataService { photoMetadataService }

    init() {
        Self.markDirectoriesAsNonBackup()
    }

    private static func markDirectoriesAsNonBackup() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // All 6 working dirs are transient; exclude from iCloud/iTunes backup.
        // Was ["Inputs", "Outputs"] in v1.x — extended to all 6 dirs per
        // Phase 3 audit (closes iCloud-backup gap for StitchInputs/Outputs +
        // CleanInputs/Cleaned).
        for sub in CacheSweeper.allDirs {
            let dir = docs.appendingPathComponent(sub, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = dir
            try? url.setResourceValues(values)
        }
    }

    static func preview() -> VideoLibrary {
        let lib = VideoLibrary()
        return lib
    }

    // MARK: - Importing

    func importPickedItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            // Try video first; if that fails (the item is a still), try photo.
            // PhotosPickerItem has supportedContentTypes which we could check
            // up front, but the empirical "load video, fall back to photo"
            // pattern is simpler and gives the same result.
            do {
                if let movie = try await item.loadTransferable(type: VideoTransferable.self) {
                    let stableURL = try copyToWorkingDir(movie.url, originalName: movie.suggestedName)
                    let displayName = movie.suggestedName ?? stableURL.lastPathComponent
                    let placeholder = VideoFile(
                        sourceURL: stableURL,
                        displayName: displayName,
                        kind: .video
                    )
                    videos.append(placeholder)
                    await loadMetadata(for: placeholder.id)
                    continue
                }
            } catch {
                // fall through to still attempt
            }
            do {
                if let photo = try await item.loadTransferable(type: PhotoTransferable.self) {
                    let stableURL = try copyToWorkingDir(photo.url, originalName: photo.suggestedName)
                    let displayName = photo.suggestedName ?? stableURL.lastPathComponent
                    let placeholder = VideoFile(
                        sourceURL: stableURL,
                        displayName: displayName,
                        kind: .still
                    )
                    videos.append(placeholder)
                    await loadMetadata(for: placeholder.id)
                    continue
                }
            } catch {
                lastError = .fileSystem(message: error.localizedDescription)
            }
        }
    }

    private func copyToWorkingDir(_ source: URL, originalName: String?) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inputs = docs.appendingPathComponent("Inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)

        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let baseName = originalName?.replacingOccurrences(of: "/", with: "_")
            ?? "video-\(UUID().uuidString.prefix(8))"
        let target = inputs.appendingPathComponent("\(baseName).\(ext)")

        // If the destination already exists (re-imported same picker item),
        // remove it so the move doesn't fail.
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: source, to: target)

        // Clean up the picker tmp wrapper if it's our Picks-* dir.
        let parent = source.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("Picks-") {
            try? FileManager.default.removeItem(at: parent)
        }
        return target
    }

    private func loadMetadata(for id: UUID) async {
        guard let idx = videos.firstIndex(where: { $0.id == id }) else { return }
        let url = videos[idx].sourceURL
        let kind = videos[idx].kind
        do {
            let meta: VideoMetadata
            switch kind {
            case .video:
                meta = try await VideoMetadataLoader.load(from: url)
            case .still:
                meta = try await PhotoMetadataLoader.load(from: url)
            }
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].metadata = meta
            }
        } catch {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .failed(error: .metadata(asMetadataError(error)))
            }
        }
    }

    // MARK: - Removing

    func remove(_ id: UUID) {
        videos.removeAll { $0.id == id }
    }

    func removeAll() {
        videos.removeAll()
    }

    // MARK: - Compression

    func compressAll() {
        // Cancel any in-flight task before starting a new run.
        activeTask?.cancel()
        let settings = selectedSettings
        let pendingIDs = videos
            .filter { !$0.jobState.isTerminal && !$0.jobState.isActive }
            .map(\.id)

        // Mark all as queued so the UI shows correct state for waiting clips
        // before their encode slot opens up.
        for id in pendingIDs {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .queued
            }
        }

        // On Pro iPhones (13 Pro – 17 Pro) we have 2 dedicated video encoder
        // engines; use both. Non-Pro or thermally stressed devices fall back to
        // serial (concurrency = 1). See DeviceCapabilities.swift.
        let concurrency = DeviceCapabilities.currentSafeConcurrency()

        activeTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Bounded concurrency: at most `concurrency` jobs in flight.
                // Feed the queue from the main loop, blocking when the group
                // is full via `await group.next()`.
                var fed = 0
                for id in pendingIDs {
                    if Task.isCancelled { break }
                    if fed < concurrency {
                        group.addTask { [weak self] in
                            await self?.runJob(for: id, settings: settings)
                        }
                        fed += 1
                    } else {
                        // Wait for one slot to free before adding the next.
                        _ = await group.next()
                        if Task.isCancelled { break }
                        group.addTask { [weak self] in
                            await self?.runJob(for: id, settings: settings)
                        }
                        // fed stays the same — we consumed one and added one.
                    }
                }
                // Drain any remaining in-flight tasks.
                for await _ in group {}
            }
        }
    }

    func compress(_ id: UUID) {
        activeTask?.cancel()
        let settings = selectedSettings
        activeTask = Task { [weak self] in
            await self?.runJob(for: id, settings: settings)
        }
    }

    private func runJob(for id: UUID, settings: CompressionSettings) async {
        guard let idx = videos.firstIndex(where: { $0.id == id }) else { return }
        // Branch on kind: stills go through the photo pipeline.
        if videos[idx].kind == .still {
            await runPhotoJob(for: id, settings: selectedPhotoSettings)
            return
        }
        // Transition from .queued → .running.  (compressAll pre-marks as
        // .queued; compress() single-clip path may still be .idle here.)
        videos[idx].jobState = .running(progress: .zero)
        let inputURL = videos[idx].sourceURL

        // Declare a UIBackgroundTask so iOS keeps the export running for up
        // to ~30 s after the user locks the screen or backgrounds the app.
        // Without this, AVAssetExportSession is killed mid-export with
        // AVErrorOperationInterrupted (-11847) on long encodes — the bug
        // reported on Build 9 for 3-min videos. Apple's hard ceiling is
        // ~30 s of background time; longer encodes still need the user to
        // keep the app foregrounded, but we cover the common screen-lock
        // case cleanly.
        let bgTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "VideoCompressor.compress.\(id.uuidString.prefix(8))"
        )
        AudioBackgroundKeeper.shared.begin()
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
            AudioBackgroundKeeper.shared.end()
        }

        // Fresh actor instance per job — prevents a shared CompressionService
        // actor from serializing concurrent encodes on Pro devices.
        let perJobService = CompressionService()

        do {
            let outputURL = try await perJobService.compress(
                input: inputURL,
                settings: settings
            ) { [weak self] progress in
                guard let self else { return }
                if let i = self.videos.firstIndex(where: { $0.id == id }) {
                    self.videos[i].jobState = .running(progress: progress)
                }
            }

            let bytes: Int64
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                if let i = videos.firstIndex(where: { $0.id == id }) {
                    videos[i].jobState = .failed(
                        error: .fileSystem(message: "Output written but unreadable: \(error.localizedDescription)")
                    )
                }
                return
            }
            guard bytes > 0 else {
                if let i = videos.firstIndex(where: { $0.id == id }) {
                    videos[i].jobState = .failed(
                        error: .compression(.exportFailed("Compressor produced an empty file. Try a different preset."))
                    )
                }
                try? FileManager.default.removeItem(at: outputURL)
                return
            }

            // Auto-strip Meta-glasses fingerprint atoms from the output
            // so any user export is privacy-clean by default. Fail-soft:
            // a failure here leaves the (still valid) compressed file
            // alone. Per user direction 2026-05-03.
            await Self.metadataService.stripMetaFingerprintInPlace(at: outputURL)
            // Re-read size in case the remux changed it slightly.
            let finalBytes: Int64 = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? bytes

            // Post-flight size guard. AVAssetExportSession's curated presets
            // are fixed-bitrate; for source files that are already
            // efficiently encoded (typically iPhone HEVC at 1080p) the
            // output can be the SAME size or LARGER. Don't punish the user
            // with a worse file — discard and report as "already optimized".
            //
            // BUG FIX (Build 13 → 14): the previous fallback to Int64.max
            // when metadata.fileSizeBytes was missing or 0 caused the guard
            // to NEVER trip — because `Int64.max * 0.95` overflows and the
            // `>=` check is meaningless. Also, the multi-second import path
            // can complete the encode before VideoMetadataLoader reports
            // the size. Now reads the source file's size DIRECTLY from disk
            // as the source-of-truth, falling back to metadata only if disk
            // read fails. Phase 3 AVAssetWriter migration replaces this
            // safety net with true source-aware bitrate caps.
            let sourceBytes: Int64 = {
                let onDisk = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                if onDisk > 0 { return onDisk }
                return videos.first(where: { $0.id == id })?.metadata?.fileSizeBytes ?? 0
            }()
            if sourceBytes > 0, finalBytes >= Int64(Double(sourceBytes) * 0.95) {
                try? FileManager.default.removeItem(at: outputURL)
                if let i = videos.firstIndex(where: { $0.id == id }) {
                    let pct = Int(Double(finalBytes) / Double(sourceBytes) * 100)
                    videos[i].jobState = .skipped(
                        reason: "Already optimized (\(pct)% of source) — kept original"
                    )
                }
                return
            }

            guard let i = videos.firstIndex(where: { $0.id == id }) else {
                // User removed the row mid-flight; clean up orphan.
                try? FileManager.default.removeItem(at: outputURL)
                return
            }
            videos[i].jobState = .finished
            videos[i].output = CompressedOutput(
                url: outputURL,
                bytes: finalBytes,
                createdAt: Date(),
                settings: settings
            )
        } catch is CancellationError {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .cancelled
            }
        } catch {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .failed(error: .compression(asCompressionError(error)))
            }
        }
    }

    // MARK: - Photo job

    /// Photo-side equivalent of `runJob`. Drives the ImageIO encoder via
    /// `PhotoCompressionService`, applies the same auto-fingerprint-strip,
    /// and reports the same `CompressionJobState` transitions so the row UI
    /// is identical regardless of media kind.
    private func runPhotoJob(for id: UUID, settings: PhotoCompressionSettings) async {
        guard let idx = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[idx].jobState = .running(progress: .zero)
        let inputURL = videos[idx].sourceURL

        // No background-task ceremony for photos — encode is sub-second on
        // every modern device. AVFoundation's screen-lock killer doesn't
        // apply here.

        do {
            let outputURL = try await photoService.compress(
                input: inputURL,
                settings: settings
            ) { [weak self] progress in
                guard let self else { return }
                if let i = self.videos.firstIndex(where: { $0.id == id }) {
                    self.videos[i].jobState = .running(progress: progress)
                }
            }

            let bytes: Int64 = (try? FileManager.default
                .attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard bytes > 0 else {
                if let i = videos.firstIndex(where: { $0.id == id }) {
                    videos[i].jobState = .failed(
                        error: .compression(.exportFailed("Photo compressor produced an empty file."))
                    )
                }
                try? FileManager.default.removeItem(at: outputURL)
                return
            }

            // Auto-strip Meta fingerprint for stills (XMP / MakerApple).
            await Self.photoMetadataService.stripMetaFingerprintInPlace(at: outputURL)
            let finalBytes: Int64 = (try? FileManager.default
                .attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? bytes

            // Skip-if-not-smaller guard mirrors the video path. HEIC at quality
            // 1.0 on a HEIC source is a near-no-op; same threshold (95%).
            let sourceBytes: Int64 = {
                let onDisk = (try? FileManager.default
                    .attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                if onDisk > 0 { return onDisk }
                return videos.first(where: { $0.id == id })?.metadata?.fileSizeBytes ?? 0
            }()
            if sourceBytes > 0, finalBytes >= Int64(Double(sourceBytes) * 0.95) {
                try? FileManager.default.removeItem(at: outputURL)
                if let i = videos.firstIndex(where: { $0.id == id }) {
                    let pct = Int(Double(finalBytes) / Double(sourceBytes) * 100)
                    videos[i].jobState = .skipped(
                        reason: "Already optimized (\(pct)% of source) — kept original"
                    )
                }
                return
            }

            guard let i = videos.firstIndex(where: { $0.id == id }) else {
                try? FileManager.default.removeItem(at: outputURL)
                return
            }
            videos[i].jobState = .finished
            // Photo settings don't currently fit `CompressedOutput.settings`
            // (which is typed `CompressionSettings`). v1: store nil; the row
            // UI renders savings purely from bytes.
            videos[i].output = CompressedOutput(
                url: outputURL,
                bytes: finalBytes,
                createdAt: Date(),
                settings: nil
            )
        } catch is CancellationError {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .cancelled
            }
        } catch {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .failed(
                    error: .compression(.exportFailed(error.localizedDescription))
                )
            }
        }
    }

    // MARK: - Saving

    func saveOutputToPhotos(for id: UUID) async {
        guard let video = videos.first(where: { $0.id == id }),
              let url = video.output?.url else { return }
        if let i = videos.firstIndex(where: { $0.id == id }) {
            videos[i].saveStatus = .saving
        }
        do {
            try await PhotosSaver.saveVideo(at: url)
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].saveStatus = .saved
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // Opportunistic delete: the compressed output is now safely in the
            // Photos library. Delete our sandbox copy of the source from
            // Inputs/ — it's a redundant copy of what the user already has in
            // Photos. The Photos library original is never touched.
            let sourceURL = video.sourceURL
            Task.detached(priority: .utility) {
                await CacheSweeper.shared.deleteIfInWorkingDir(sourceURL)
            }
        } catch {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].saveStatus = .saveFailed(reason: error.localizedDescription)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            lastError = .photos(asPhotosError(error))
        }
    }

    // MARK: - Error casting helpers

    private func asMetadataError(_ error: Error) -> VideoMetadataError {
        error as? VideoMetadataError ?? .loadFailed(error.localizedDescription)
    }

    private func asCompressionError(_ error: Error) -> CompressionError {
        error as? CompressionError ?? .exportFailed(error.localizedDescription)
    }

    private func asPhotosError(_ error: Error) -> PhotosSaverError {
        error as? PhotosSaverError ?? .saveFailed(error.localizedDescription)
    }
}

/// SwiftUI's `PhotosPicker` returns `Transferable` objects. We need both the
/// URL and the original filename, so we wrap the system `Movie` type.
struct VideoTransferable: Transferable {
    let url: URL
    let suggestedName: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { transferable in
            SentTransferredFile(transferable.url)
        } importing: { received in
            // PhotosPicker delivers a temp file. Move it into our temp dir so
            // it survives the picker's lifecycle. The caller (VideoLibrary)
            // will then copy it to Documents/Inputs.
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Picks-\(UUID().uuidString.prefix(6))", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let suggestedName = received.file.lastPathComponent
            let target = tmpDir.appendingPathComponent(suggestedName)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: received.file, to: target)
            return VideoTransferable(url: target, suggestedName: suggestedName)
        }
    }
}

/// Photo equivalent of `VideoTransferable`. Same lifecycle: PhotosPicker
/// hands us a scoped temp file, we move it into our `Picks-*` wrapper dir,
/// caller copies into the real working directory and tears down the wrapper.
///
/// Phase 3 commit 5 (2026-05-03).
struct PhotoTransferable: Transferable {
    let url: URL
    let suggestedName: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { transferable in
            SentTransferredFile(transferable.url)
        } importing: { received in
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Picks-\(UUID().uuidString.prefix(6))", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let suggestedName = received.file.lastPathComponent
            let target = tmpDir.appendingPathComponent(suggestedName)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: received.file, to: target)
            return PhotoTransferable(url: target, suggestedName: suggestedName)
        }
    }
}
