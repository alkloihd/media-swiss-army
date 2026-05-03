//
//  MetaCleanQueue.swift
//  VideoCompressor
//
//  @MainActor ObservableObject that owns the list of MetaCleanItems,
//  orchestrates background scans via MetadataService.read, and fires
//  MetadataService.strip when the user taps "Clean & Save".
//
//  Mirrors StitchProject's shape: Published arrays, typed state enum,
//  BoundedProgress for the progress view, and a cleanTask that can be
//  cancelled from the UI.
//
//  See `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` task M3.
//

import Foundation

@MainActor
final class MetaCleanQueue: ObservableObject {
    @Published private(set) var items: [MetaCleanItem] = []
    @Published var rules: StripRules = .autoMetaGlasses
    @Published var lastImportError: LibraryError?
    @Published private(set) var cleanProgress: BoundedProgress = .zero
    @Published private(set) var cleanState: MetaCleanState = .idle
    @Published var deleteOriginalAfterSave: Bool = false

    private let service = MetadataService()
    private var cleanTask: Task<Void, Never>?

    // MARK: - Import / append

    /// Appends a new item and immediately kicks off a background scan.
    func append(_ item: MetaCleanItem) async {
        items.append(item)
        await scan(item.id)
    }

    // MARK: - Scan

    private func scan(_ id: UUID) async {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let url = items[i].sourceURL
        do {
            let tags = try await service.read(url: url)
            if let j = items.firstIndex(where: { $0.id == id }) {
                items[j].tags = tags
            }
        } catch {
            if let j = items.firstIndex(where: { $0.id == id }) {
                items[j].scanError = error.localizedDescription
            }
        }
    }

    // MARK: - Remove

    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        // Clean up the staged file if it lives in our CleanInputs sandbox.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cleanInputs = docs.appendingPathComponent("CleanInputs", isDirectory: true)
        if item.sourceURL.standardizedFileURL.path
            .hasPrefix(cleanInputs.standardizedFileURL.path + "/") {
            try? FileManager.default.removeItem(at: item.sourceURL)
        }
    }

    // MARK: - Clean

    /// Starts a clean job for the given item. The completion closure is
    /// called on the main actor when done (success or failure).
    func clean(
        _ id: UUID,
        completion: @MainActor @escaping (Result<MetadataCleanResult, Error>) -> Void = { _ in }
    ) {
        cleanTask?.cancel()
        cleanState = .cleaning
        cleanProgress = .zero
        let rules = self.rules
        cleanTask = Task { [weak self] in
            await self?.runClean(id: id, rules: rules, completion: completion)
        }
    }

    private func runClean(
        id: UUID,
        rules: StripRules,
        completion: @MainActor @escaping (Result<MetadataCleanResult, Error>) -> Void
    ) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        do {
            let result = try await service.strip(
                url: item.sourceURL,
                rules: rules
            ) { [weak self] progress in
                // onProgress is @MainActor @Sendable — we're already on @MainActor here.
                self?.cleanProgress = progress
            }
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].cleanResult = result
            }
            cleanState = .finished(result)
            completion(.success(result))
        } catch is CancellationError {
            cleanState = .cancelled
        } catch {
            cleanState = .failed(error: .compression(.exportFailed(error.localizedDescription)))
            completion(.failure(error))
        }
    }
}

// MARK: - State enum

enum MetaCleanState: Hashable, Sendable {
    case idle
    case cleaning
    case finished(MetadataCleanResult)
    case cancelled
    case failed(error: LibraryError)
}
