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

@MainActor
final class VideoLibrary: ObservableObject {
    @Published private(set) var videos: [VideoFile] = []
    @Published var selectedSettings: CompressionSettings = .balanced
    @Published var lastError: LibraryError?

    /// Convenience accessor for SwiftUI alert bindings.
    var lastErrorMessage: String? { lastError?.displayMessage }

    private var activeTask: Task<Void, Never>?
    private let service = CompressionService()
    /// Single shared MetadataService for auto-fingerprint-strip across
    /// Compress + Stitch + (future) Share Extension paths.
    fileprivate static let metadataService = MetadataService()
    /// Public alias so StitchProject can call into the same instance
    /// without exposing the fileprivate name.
    static var metadataServiceShared: MetadataService { metadataService }

    init() {
        Self.markDirectoriesAsNonBackup()
    }

    private static func markDirectoriesAsNonBackup() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for sub in ["Inputs", "Outputs"] {
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
            do {
                guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                    continue
                }
                let stableURL = try copyToWorkingDir(movie.url, originalName: movie.suggestedName)
                let displayName = movie.suggestedName ?? stableURL.lastPathComponent
                let placeholder = VideoFile(
                    sourceURL: stableURL,
                    displayName: displayName
                )
                videos.append(placeholder)
                await loadMetadata(for: placeholder.id)
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
        do {
            let meta = try await VideoMetadataLoader.load(from: url)
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

        activeTask = Task { [weak self] in
            for id in pendingIDs {
                guard !Task.isCancelled else { return }
                await self?.runJob(for: id, settings: settings)
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
        videos[idx].jobState = .running(progress: .zero)
        let inputURL = videos[idx].sourceURL

        do {
            let outputURL = try await service.compress(
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

    // MARK: - Saving

    func saveOutputToPhotos(for id: UUID) async {
        guard let video = videos.first(where: { $0.id == id }),
              let url = video.output?.url else { return }
        do {
            try await PhotosSaver.saveVideo(at: url)
        } catch {
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
