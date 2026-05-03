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
    /// Drives the batch flow: when true, `cleanAll` saves each cleaned
    /// output to Photos AND deletes the original asset (subject to the
    /// usual originalAssetID-was-captured guard). User-facing label:
    /// "Replace originals in Photos."
    @Published var replaceOriginalsOnBatch: Bool = false
    /// Aggregate batch progress across all items in `cleanAll`.
    @Published private(set) var batchProgress: BatchCleanProgress = .idle

    private let service = MetadataService()
    private let photoService = PhotoMetadataService()
    private var cleanTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?

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
        let kind = items[i].kind
        do {
            let tags: [MetadataTag]
            switch kind {
            case .video: tags = try await service.read(url: url)
            case .still: tags = try await photoService.read(url: url)
            }
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
            let result: MetadataCleanResult
            switch item.kind {
            case .video:
                result = try await service.strip(
                    url: item.sourceURL,
                    rules: rules
                ) { [weak self] progress in
                    self?.cleanProgress = progress
                }
            case .still:
                result = try await photoService.strip(
                    url: item.sourceURL,
                    rules: rules
                ) { [weak self] progress in
                    self?.cleanProgress = progress
                }
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

/// Progress shape for the batch clean flow. UI binds to this for the
/// "Cleaning 3 of 8 …" label + a determinate bar across the whole queue.
struct BatchCleanProgress: Hashable, Sendable {
    var current: Int           // 1-indexed, 0 means not yet started
    var total: Int             // total items being processed
    var failed: Int            // accumulated failures (none-fatal — keep going)
    var perItem: BoundedProgress  // current item's own progress
    var isRunning: Bool
    var lastError: String?     // most recent non-fatal error, for footer

    static let idle = BatchCleanProgress(
        current: 0, total: 0, failed: 0,
        perItem: .zero, isRunning: false, lastError: nil
    )

    var fraction: Double {
        guard total > 0 else { return 0 }
        let perItemFraction = perItem.value
        let completedFraction = Double(max(current - 1, 0))
        return min(1.0, (completedFraction + perItemFraction) / Double(total))
    }
}

// MARK: - Batch clean

extension MetaCleanQueue {
    /// Cleans every item in `items`, sequentially, calling `onItemDone` per
    /// item so the UI can refresh the row state. If `replaceOriginalsOnBatch`
    /// is on, also saves each cleaned output to Photos and deletes the
    /// original asset (when its originalAssetID was captured at import).
    ///
    /// Sequential is intentional — concurrent AVAssetReaders sharing the
    /// AVAudioSession can spawn -11800 errors and we'd rather be reliable
    /// than fast for what's usually a 3–10 file batch.
    func cleanAll(
        onItemDone: @MainActor @escaping (UUID, Result<MetadataCleanResult, Error>) -> Void = { _, _ in },
        onAllDone: @MainActor @escaping () -> Void = {}
    ) {
        // Don't double-start.
        guard !batchProgress.isRunning else { return }
        batchTask?.cancel()
        let snapshotIDs = items.map(\.id)
        guard !snapshotIDs.isEmpty else {
            onAllDone()
            return
        }
        batchProgress = BatchCleanProgress(
            current: 0,
            total: snapshotIDs.count,
            failed: 0,
            perItem: .zero,
            isRunning: true,
            lastError: nil
        )
        let rules = self.rules
        let replace = self.replaceOriginalsOnBatch
        batchTask = Task { [weak self] in
            await self?.runBatch(
                ids: snapshotIDs,
                rules: rules,
                replaceOriginals: replace,
                onItemDone: onItemDone,
                onAllDone: onAllDone
            )
        }
    }

    func cancelBatch() {
        batchTask?.cancel()
        batchProgress.isRunning = false
    }

    private func runBatch(
        ids: [UUID],
        rules: StripRules,
        replaceOriginals: Bool,
        onItemDone: @MainActor @escaping (UUID, Result<MetadataCleanResult, Error>) -> Void,
        onAllDone: @MainActor @escaping () -> Void
    ) async {
        for (idx, id) in ids.enumerated() {
            if Task.isCancelled { break }
            batchProgress.current = idx + 1
            batchProgress.perItem = .zero

            guard let item = items.first(where: { $0.id == id }) else { continue }

            do {
                let result: MetadataCleanResult
                switch item.kind {
                case .video:
                    result = try await service.strip(url: item.sourceURL, rules: rules) { [weak self] p in
                        self?.batchProgress.perItem = p
                    }
                case .still:
                    result = try await photoService.strip(url: item.sourceURL, rules: rules) { [weak self] p in
                        self?.batchProgress.perItem = p
                    }
                }
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].cleanResult = result
                }

                if replaceOriginals {
                    let assetID = item.originalAssetID
                    do {
                        try await PhotosSaver.saveAndOptionallyDeleteOriginal(
                            cleanedURL: result.cleanedURL,
                            originalAssetID: assetID
                        )
                    } catch {
                        batchProgress.failed += 1
                        batchProgress.lastError = error.localizedDescription
                        // Don't abort the batch — surface and continue.
                    }
                }

                onItemDone(id, .success(result))
            } catch is CancellationError {
                break
            } catch {
                batchProgress.failed += 1
                batchProgress.lastError = error.localizedDescription
                onItemDone(id, .failure(error))
            }
        }
        batchProgress.perItem = .complete
        batchProgress.isRunning = false
        onAllDone()
    }
}
