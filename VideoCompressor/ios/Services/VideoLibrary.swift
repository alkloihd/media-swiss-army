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
    @Published var selectedPreset: CompressionPreset = .balanced
    @Published var lastErrorMessage: String?

    private var activeTask: Task<Void, Never>?

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
                lastErrorMessage = error.localizedDescription
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
        // remove it so the copy doesn't fail.
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
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
                videos[i].jobState = .failed(message: error.localizedDescription)
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
        let preset = selectedPreset
        let pendingIDs = videos.filter { !$0.jobState.isTerminal && $0.jobState != .running(progress: 0) }.map(\.id)

        activeTask = Task { [weak self] in
            for id in pendingIDs {
                guard !Task.isCancelled else { return }
                await self?.runJob(for: id, preset: preset)
            }
        }
    }

    func compress(_ id: UUID) {
        let preset = selectedPreset
        Task { [weak self] in
            await self?.runJob(for: id, preset: preset)
        }
    }

    private func runJob(for id: UUID, preset: CompressionPreset) async {
        guard let idx = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[idx].jobState = .running(progress: 0)
        let inputURL = videos[idx].sourceURL

        let service = CompressionService()
        do {
            let outputURL = try await service.compress(
                input: inputURL,
                preset: preset
            ) { [weak self] progress in
                guard let self else { return }
                if let i = self.videos.firstIndex(where: { $0.id == id }) {
                    self.videos[i].jobState = .running(progress: progress)
                }
            }

            let bytes: Int64 = {
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            }()

            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .finished
                videos[i].outputURL = outputURL
                videos[i].outputBytes = bytes
            }
        } catch is CancellationError {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .cancelled
            }
        } catch {
            if let i = videos.firstIndex(where: { $0.id == id }) {
                videos[i].jobState = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Saving

    func saveOutputToPhotos(for id: UUID) async {
        guard let video = videos.first(where: { $0.id == id }),
              let url = video.outputURL else { return }
        do {
            try await PhotosSaver.saveVideo(at: url)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
