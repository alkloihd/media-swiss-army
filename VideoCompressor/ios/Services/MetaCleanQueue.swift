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
//  See `.agents/work-sessions/2026-05-03/plans/PLAN-stitch-metaclean.md` task M3.
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

/// Progress shape for the batch clean flow. UI binds to this for a
/// user-facing label + a determinate bar across the whole queue.
struct BatchCleanProgress: Hashable, Sendable {
    var current: Int           // completed items, 0 means not yet started
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
        return min(1.0, max(0.0, Double(current) / Double(total)))
    }

    func userFacingLabel(kind: MediaKind) -> String {
        let noun = kind == .still ? "photo" : "video"
        let nounPlural = kind == .still ? "photos" : "videos"

        if !isRunning {
            return total == 1
                ? "Cleaned 1 \(noun)"
                : "Cleaned \(total) \(nounPlural)"
        }

        if total <= 1 {
            return "Cleaning your \(noun)..."
        }
        let displayedCurrent = min(total, max(1, current))
        return "Cleaning your \(nounPlural) · \(displayedCurrent) of \(total)"
    }
}

// MARK: - Batch clean

extension MetaCleanQueue {
    /// Batch concurrency for cleanAll. Pro phones get N=2 under nominal/fair
    /// thermal state; everyone else stays serial. Cap at 2 to match the
    /// current device policy and avoid AVFoundation/Photos contention.
    nonisolated static func batchConcurrency(
        deviceClass: DeviceCapabilities.DeviceClass,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        min(2, max(1, DeviceCapabilities.safeConcurrency(
            deviceClass: deviceClass,
            thermalState: thermalState
        )))
    }

    /// Cleans every item in `items`, calling `onItemDone` per item so the UI
    /// can refresh row state. Metadata stripping is bounded-concurrent on Pro
    /// phones; save/delete remains serial in the result drain so Photos writes
    /// do not contend with each other.
    func cleanAll(
        onItemDone: @MainActor @escaping (UUID, Result<MetadataCleanResult, Error>) -> Void = { _, _ in },
        onAllDone: @MainActor @escaping () -> Void = {},
        onBatchSaveComplete: @MainActor @escaping (SaveBatchResult) -> Void = { _ in }
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
                onAllDone: onAllDone,
                onBatchSaveComplete: onBatchSaveComplete
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
        onAllDone: @MainActor @escaping () -> Void,
        onBatchSaveComplete: @MainActor @escaping (SaveBatchResult) -> Void
    ) async {
        let idToItem = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            ids.contains(item.id) ? (item.id, item) : nil
        })
        let orderedIDs = ids.filter { idToItem[$0] != nil }
        guard !orderedIDs.isEmpty else {
            batchProgress.isRunning = false
            onAllDone()
            return
        }

        if orderedIDs.count != batchProgress.total {
            batchProgress.total = orderedIDs.count
        }

        let dominantKind = Self.dominantKind(for: orderedIDs.compactMap { idToItem[$0]?.kind })
        let concurrency = min(
            orderedIDs.count,
            Self.batchConcurrency(
                deviceClass: DeviceCapabilities.deviceClass,
                thermalState: ProcessInfo.processInfo.thermalState
            )
        )
        let metadataService = service
        let photoMetadataService = photoService
        var savedCount = 0
        var saveFailureCount = 0
        var wasCancelled = false

        await withTaskGroup(of: BatchCleanOutcome.self) { group in
            var inFlight = 0
            var iterator = orderedIDs.makeIterator()

            while inFlight < concurrency, let nextID = iterator.next() {
                guard let item = idToItem[nextID] else { continue }
                inFlight += 1
                group.addTask { [rules, metadataService, photoMetadataService] in
                    await Self.cleanOne(
                        item: item,
                        rules: rules,
                        service: metadataService,
                        photoService: photoMetadataService
                    )
                }
            }

            while let outcome = await group.next() {
                inFlight -= 1
                if Task.isCancelled {
                    wasCancelled = true
                    group.cancelAll()
                    break
                }

                batchProgress.current += 1
                batchProgress.perItem = .zero

                switch outcome {
                case .cleaned(let id, let result):
                    guard let item = idToItem[id] else { continue }
                    if let i = items.firstIndex(where: { $0.id == id }) {
                        items[i].cleanResult = result
                    }

                    if replaceOriginals {
                        do {
                            try await PhotosSaver.saveAndOptionallyDeleteOriginal(
                                cleanedURL: result.cleanedURL,
                                originalAssetID: item.originalAssetID
                            )
                            savedCount += 1
                            let outputURL = result.cleanedURL
                            let inputURL = item.sourceURL
                            Task.detached(priority: .utility) {
                                await CacheSweeper.shared.sweepAfterSave(outputURL)
                                await CacheSweeper.shared.deleteIfInWorkingDir(inputURL)
                            }
                        } catch {
                            saveFailureCount += 1
                            batchProgress.failed += 1
                            batchProgress.lastError = error.localizedDescription
                        }
                    }

                    onItemDone(id, .success(result))
                case .failed(let id, let error):
                    batchProgress.failed += 1
                    batchProgress.lastError = error.localizedDescription
                    onItemDone(id, .failure(error))
                }

                while inFlight < concurrency, let nextID = iterator.next() {
                    if Task.isCancelled {
                        wasCancelled = true
                        group.cancelAll()
                        break
                    }
                    guard let item = idToItem[nextID] else { continue }
                    inFlight += 1
                    group.addTask { [rules, metadataService, photoMetadataService] in
                        await Self.cleanOne(
                            item: item,
                            rules: rules,
                            service: metadataService,
                            photoService: photoMetadataService
                        )
                    }
                }
            }
        }

        batchProgress.perItem = .complete
        batchProgress.isRunning = false
        if replaceOriginals, !wasCancelled, (savedCount > 0 || saveFailureCount > 0) {
            onBatchSaveComplete(SaveBatchResult(
                saved: savedCount,
                failed: saveFailureCount,
                kind: dominantKind,
                at: Date()
            ))
        }
        onAllDone()
    }

    private nonisolated static func dominantKind(for kinds: [MediaKind]) -> MediaKind {
        let stills = kinds.filter { $0 == .still }.count
        let videos = kinds.count - stills
        return stills >= videos ? .still : .video
    }

    private nonisolated static func cleanOne(
        item: MetaCleanItem,
        rules: StripRules,
        service: MetadataService,
        photoService: PhotoMetadataService
    ) async -> BatchCleanOutcome {
        do {
            let result: MetadataCleanResult
            switch item.kind {
            case .video:
                result = try await service.strip(url: item.sourceURL, rules: rules) { _ in }
            case .still:
                result = try await photoService.strip(url: item.sourceURL, rules: rules) { _ in }
            }
            return .cleaned(id: item.id, result: result)
        } catch is CancellationError {
            return .failed(
                id: item.id,
                error: BatchCleanFailure(message: "Cleaning was cancelled.")
            )
        } catch {
            return .failed(
                id: item.id,
                error: BatchCleanFailure(message: error.localizedDescription)
            )
        }
    }
}

private enum BatchCleanOutcome: Sendable {
    case cleaned(id: UUID, result: MetadataCleanResult)
    case failed(id: UUID, error: BatchCleanFailure)
}

private struct BatchCleanFailure: Error, LocalizedError, Hashable, Sendable {
    let message: String

    var errorDescription: String? { message }
}
