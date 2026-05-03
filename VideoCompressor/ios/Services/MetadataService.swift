//
//  MetadataService.swift
//  VideoCompressor
//
//  Reads metadata from a video file and produces a cleaned remux with
//  selected tags removed. Pure remux — `outputSettings: nil` on every
//  reader output and writer input means CMSampleBuffers flow through the
//  pipeline byte-identical; only the container is rewritten without the
//  filtered atoms. No re-encode → no quality loss → fast.
//
//  Concurrency notes (mirrors `CompressionService`):
//  - The reader/writer pump runs on per-track DispatchQueues. Progress is
//    written into a lock-protected `latestPTS` and a single 10 Hz
//    main-actor poller emits `BoundedProgress`. We do NOT spawn a
//    `Task { @MainActor }` per sample — at 4K60 that's hundreds of hops
//    per second per track and the poller pattern is already proven in
//    `CompressionService`.
//  - Cancellation is wired through `withTaskCancellationHandler` →
//    `reader.cancelReading()` so a `Task.cancel()` from the UI actually
//    halts the on-disk write within one sample-buffer cycle.
//  - Metadata gathering uses the SAME 4 keyspaces in both `read` and
//    `strip`. Earlier draft only loaded `.metadata` (the curated common
//    view) for strip — atoms living in `quickTimeUserData` / `iTunesMetadata`
//    would have been displayed in the inspector but never filtered out.
//

import Foundation
import AVFoundation

enum MetadataServiceError: Error, LocalizedError, Hashable, Sendable {
    case noVideoTrack
    case readerSetupFailed(String)
    case writerSetupFailed(String)
    case writeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:               return "Source has no video track."
        case .readerSetupFailed(let m):   return "Could not read source: \(m)"
        case .writerSetupFailed(let m):   return "Could not create cleaned file: \(m)"
        case .writeFailed(let m):         return "Failed during write: \(m)"
        case .cancelled:                  return "Cleaning was cancelled."
        }
    }
}

actor MetadataService {

    // MARK: - Read

    /// Read all metadata tags from a video file, classifying by category
    /// and flagging Meta Ray-Ban / glasses fingerprint atoms.
    ///
    /// Loads from the four QuickTime/MP4 keyspaces — `.metadata`
    /// (common curated view), `.quickTimeMetadata` (newer atoms),
    /// `.quickTimeUserData` (legacy `udta` atoms — where Meta glasses
    /// stash their fingerprint Comment), and `.iTunesMetadata`. Atoms
    /// that appear in multiple keyspaces are de-duplicated by `(key,
    /// value)` to keep the inspector readable.
    func read(url: URL) async throws -> [MetadataTag] {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])
        let items = await Self.gatherAllItems(asset: asset)
        var tags: [MetadataTag] = []
        var seen = Set<String>()
        for item in items {
            guard let tag = await classify(item) else { continue }
            let dedupeKey = "\(tag.key)|\(tag.value)"
            if seen.contains(dedupeKey) { continue }
            seen.insert(dedupeKey)
            tags.append(tag)
        }
        return tags
    }

    // MARK: - Strip (remux)

    /// Remux the source to a `_CLEAN.mp4` next to the app's `Cleaned/`
    /// directory, filtering out tags per `rules`. Pure passthrough — the
    /// pixel and audio bytes are bit-identical to the source.
    ///
    /// `onProgress` fires on the main actor at ~10 Hz (PTS / duration).
    /// Returns a `MetadataCleanResult` with what was kept vs stripped so
    /// the inspector can show a before/after count.
    func strip(
        url sourceURL: URL,
        rules: StripRules,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> MetadataCleanResult {
        let asset = AVURLAsset(url: sourceURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])

        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw MetadataServiceError.noVideoTrack
        }

        let outputURL = Self.cleanedURL(for: sourceURL)
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw MetadataServiceError.writerSetupFailed(error.localizedDescription)
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw MetadataServiceError.readerSetupFailed(error.localizedDescription)
        }

        // Pass-through video and audio tracks. `outputSettings: nil`
        // tells AVFoundation: hand me the raw CMSampleBuffers exactly as
        // they came off disk; do not decode, do not re-encode. The
        // writer input with the same `outputSettings: nil` writes them
        // back into the new container untouched. Result: pixel-perfect,
        // bit-identical media; the only diff vs source is the removed
        // metadata atoms.
        //
        // Timed-metadata tracks (`.metadata` mediaType, e.g. embedded
        // GPS streams) are intentionally dropped here. For the
        // autoMetaGlasses preset that's the desired behaviour. If a
        // future "preserve track-level GPS" preset is added, route
        // those tracks through the same passthrough pattern.
        struct PumpPair {
            let input: AVAssetWriterInput
            let output: AVAssetReaderTrackOutput
        }
        var inputs: [PumpPair] = []
        for track in tracks where track.mediaType == .video || track.mediaType == .audio {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw MetadataServiceError.readerSetupFailed("Cannot add reader output for track \(track.trackID)")
            }
            reader.add(output)
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw MetadataServiceError.writerSetupFailed("Cannot add writer input for track \(track.trackID)")
            }
            writer.add(input)
            inputs.append(PumpPair(input: input, output: output))
        }

        // Filter metadata using the SAME keyspace gather as `read`.
        // Earlier sketch only loaded `.metadata` for strip while `read`
        // queried 4 keyspaces — the inspector would show a fingerprint
        // atom from `quickTimeUserData` and the strip would leave it on
        // disk. Using one helper guarantees the two stay in sync.
        let allItems = await Self.gatherAllItems(asset: asset)
        var stripped: [MetadataTag] = []
        var kept: [MetadataTag] = []
        var keptItems: [AVMetadataItem] = []
        for item in allItems {
            guard let tag = await classify(item) else { continue }
            if shouldStrip(tag: tag, rules: rules) {
                stripped.append(tag)
            } else {
                kept.append(tag)
                keptItems.append(item)
            }
        }
        writer.metadata = keptItems

        guard reader.startReading() else {
            throw MetadataServiceError.readerSetupFailed(
                reader.error?.localizedDescription ?? "Unknown reader error"
            )
        }
        guard writer.startWriting() else {
            throw MetadataServiceError.writerSetupFailed(
                writer.error?.localizedDescription ?? "Unknown writer error"
            )
        }
        writer.startSession(atSourceTime: .zero)

        // Total seconds for progress denominator. Zero is possible for
        // pathological assets — guard the divide before reporting.
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        // Shared mutable state across the per-track pump closures lives
        // on a `final class` reference so the closures all see the same
        // instance — Sendable-correct without `nonisolated(unsafe)` on
        // captured vars.
        let pumpState = PumpState(remaining: inputs.count)
        let totalInputs = inputs.count

        // Single 10 Hz main-actor poller emits BoundedProgress from the
        // shared latest PTS. Avoids the `Task { @MainActor }`-per-sample
        // storm (hundreds of main-actor hops/sec on 4K60).
        let progressTask = Task { @MainActor [totalSeconds, pumpState] in
            while !Task.isCancelled {
                let pts = pumpState.latestPTS()
                if totalSeconds > 0, pts.isFinite {
                    onProgress(BoundedProgress(pts / totalSeconds))
                }
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
            }
        }

        // Pump samples per track. Each track owns a dispatch queue.
        // Completion fires when all per-track pumps have signalled
        // `finishOnePump()` on the shared state.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let bridge = ContinuationBridge(continuation: cont)
                pumpState.setBridge(bridge)

                if totalInputs == 0 {
                    pumpState.tryResume()
                    return
                }

                for pair in inputs {
                    let queue = DispatchQueue(label: "metaclean.pump.\(pair.input.mediaType.rawValue)")
                    let input = pair.input
                    let output = pair.output
                    let state = pumpState
                    input.requestMediaDataWhenReady(on: queue) {
                        while input.isReadyForMoreMediaData {
                            if Task.isCancelled {
                                input.markAsFinished()
                                state.finishOnePump()
                                return
                            }
                            if let sample = output.copyNextSampleBuffer() {
                                if !input.append(sample) {
                                    input.markAsFinished()
                                    state.finishOnePump()
                                    return
                                }
                                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                                let ptsSec = CMTimeGetSeconds(pts)
                                if ptsSec.isFinite {
                                    state.recordPTS(ptsSec)
                                }
                            } else {
                                // EOF for this track.
                                input.markAsFinished()
                                state.finishOnePump()
                                return
                            }
                        }
                    }
                }
            }
        } onCancel: {
            reader.cancelReading()
            for pair in inputs { pair.input.markAsFinished() }
        }

        // Stop the poller before emitting the final 1.0 — same reason
        // as `CompressionService`, otherwise the poller can race in and
        // overwrite the terminal value.
        progressTask.cancel()

        if Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw MetadataServiceError.cancelled
        }

        await writer.finishWriting()
        if writer.status != .completed {
            let detail = writer.error?.localizedDescription
                ?? "Writer ended with status \(writer.status.rawValue)"
            throw MetadataServiceError.writeFailed(detail)
        }

        await MainActor.run { onProgress(.complete) }

        let bytes: Int64 = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        return MetadataCleanResult(
            cleanedURL: outputURL,
            bytes: bytes,
            tagsStripped: stripped,
            tagsKept: kept
        )
    }

    // MARK: - File system

    /// Builds an output URL like `Documents/Cleaned/<stem>_CLEAN.mp4`.
    /// Mirrors `CompressionService.outputURL`'s shape so users can find
    /// cleaned files in Files.app alongside compressed ones.
    static func cleanedURL(for source: URL) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Cleaned", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)_CLEAN.mp4")
    }

    // MARK: - Keyspace gather

    /// Loads metadata items from all four keyspaces we care about.
    /// Used by both `read` and `strip` to keep their views consistent.
    private static func gatherAllItems(asset: AVURLAsset) async -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        if let common = try? await asset.load(.metadata) {
            items.append(contentsOf: common)
        }
        if let qt = try? await asset.loadMetadata(for: .quickTimeMetadata) {
            items.append(contentsOf: qt)
        }
        if let user = try? await asset.loadMetadata(for: .quickTimeUserData) {
            items.append(contentsOf: user)
        }
        if let isoUser = try? await asset.loadMetadata(for: .iTunesMetadata) {
            items.append(contentsOf: isoUser)
        }
        return items
    }

    // MARK: - Classification

    /// Maps an `AVMetadataItem` to one of our typed `MetadataTag`
    /// categories. Returns nil if the item has no usable identifier.
    private func classify(_ item: AVMetadataItem) async -> MetadataTag? {
        guard let identifier = item.identifier else { return nil }
        let key = identifier.rawValue
        // `load(.stringValue)` and friends return `T?` directly (the
        // accessor itself is non-optional but the underlying value may
        // be nil). One `try?` per access; chain via fallback.
        // Display value (shown in inspector). For binary blobs we
        // substitute a `<binary, N bytes>` placeholder so the UI never
        // dumps raw bytes.
        //
        // Decoded text (used ONLY for fingerprint matching). Web app
        // commit `a3ad413` ("Fix MetaClean: strip binary Comment
        // containing Meta device fingerprint") established that Meta
        // Ray-Ban glasses stash their fingerprint in a binary `Comment`
        // atom whose bytes ARE printable ASCII like "Ray-Ban Stories".
        // `stringValue` returns nil for those (the type-coded atom is
        // not a string), so we have to UTF-8 decode the data ourselves
        // to match. Decoded text is computed lazily and never shown to
        // the user.
        let value: String
        var decodedTextForMatching: String?
        if let s = (try? await item.load(.stringValue)) ?? nil {
            value = s
            decodedTextForMatching = s
        } else if let d = (try? await item.load(.dataValue)) ?? nil {
            value = "<binary, \(d.count) bytes>"
            // Try UTF-8 then ASCII-tolerant decode for fingerprint match.
            if let utf8 = String(data: d, encoding: .utf8) {
                decodedTextForMatching = utf8
            } else if let ascii = String(data: d, encoding: .ascii) {
                decodedTextForMatching = ascii
            } else {
                // Some Meta atoms are UTF-16 / mixed binary. Strip
                // non-printable bytes and try once more.
                let printable = d.filter { (0x20...0x7E).contains($0) }
                decodedTextForMatching = String(data: printable, encoding: .ascii)
            }
        } else if let n = (try? await item.load(.numberValue)) ?? nil {
            value = "\(n)"
            decodedTextForMatching = value
        } else if let date = (try? await item.load(.dateValue)) ?? nil {
            value = ISO8601DateFormatter().string(from: date)
            decodedTextForMatching = value
        } else {
            value = "(unreadable)"
        }
        let category = Self.categoryFor(key: key)
        let isFingerprint = Self.isMetaGlassesFingerprint(
            key: key,
            decodedText: decodedTextForMatching
        )
        return MetadataTag(
            id: UUID(),
            key: key,
            displayName: Self.displayNameFor(key: key),
            value: value,
            category: category,
            isMetaFingerprint: isFingerprint
        )
    }

    private static func categoryFor(key: String) -> MetadataCategory {
        let k = key.lowercased()
        if k.contains("location") || k.contains("gps") { return .location }
        if k.contains("creationdate") || k.contains("modificationdate") || k.contains("time") || k.contains("date") {
            return .time
        }
        if k.contains("make") || k.contains("model") || k.contains("software")
            || k.contains("encoder") || k.contains("device") || k.contains("manufacturer")
            || k.contains("lens") {
            return .device
        }
        if k.contains("codec") || k.contains("duration") || k.contains("framerate")
            || k.contains("samplerate") || k.contains("bitrate") || k.contains("colorspace") {
            return .technical
        }
        return .custom
    }

    private static func displayNameFor(key: String) -> String {
        // e.g. "com.apple.quicktime.location.ISO6709" → "Location ISO6709"
        let last = key.split(separator: ".").last.map(String.init) ?? key
        return last.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Web app fingerprint detection (commits `a3ad413`, `be6e360`):
    /// Meta Ray-Ban glasses leave a "Comment" or "Description" atom —
    /// often binary-typed despite containing printable ASCII — with
    /// marker bytes "Ray-Ban", "Rayban", or "Meta".
    ///
    /// `decodedText` is the UTF-8 / ASCII decode of the atom's bytes
    /// when `stringValue` was nil. The display `value` (e.g. "<binary,
    /// 32 bytes>") is NOT what we match against — that placeholder
    /// would never contain the marker and `autoMetaGlasses` would
    /// silently no-op against the very files it's named for.
    static func isMetaGlassesFingerprint(key: String, decodedText: String?) -> Bool {
        let k = key.lowercased()
        guard k.contains("comment") || k.contains("description") else { return false }
        guard let text = decodedText?.lowercased() else { return false }
        return text.contains("ray-ban") || text.contains("rayban") || text.contains("meta")
    }

    private func shouldStrip(tag: MetadataTag, rules: StripRules) -> Bool {
        // .technical is intrinsic — never strip even if requested.
        if tag.category == .technical { return false }
        if tag.isMetaFingerprint && rules.stripMetaFingerprintAlways {
            return true
        }
        return rules.stripCategories.contains(tag.category)
    }

    // MARK: - Auto fingerprint strip (used by Compress + Stitch flows)

    /// Scans `url` for Meta-glasses fingerprint atoms. If any are present,
    /// runs a `.autoMetaGlasses` remux pass and atomically replaces the
    /// file at `url` with the cleaned version. The original (with the
    /// fingerprint) is discarded.
    ///
    /// Returns `true` if the file was rewritten, `false` if no fingerprint
    /// was found (file untouched). Failures are silenced and treated as
    /// "no change" — the privacy gain matters but a failure here must not
    /// cause the user's compression / stitch result to disappear. The URL
    /// the caller passed in always points at a valid file on return.
    ///
    /// Per user direction 2026-05-03: every output of the app should be
    /// automatically de-fingerprinted (Compress, Stitch, MetaClean), with
    /// no user action required.
    @discardableResult
    func stripMetaFingerprintInPlace(at url: URL) async -> Bool {
        do {
            let tags = try await read(url: url)
            guard tags.contains(where: { $0.isMetaFingerprint }) else {
                return false
            }
            let result = try await strip(url: url, rules: .autoMetaGlasses) { _ in }
            // Atomically replace the original. `replaceItemAt` handles the
            // backup + move-into-place + cleanup dance.
            _ = try FileManager.default.replaceItemAt(url, withItemAt: result.cleanedURL)
            return true
        } catch {
            // Fail-soft. The output remains valid even if scrubbing fails.
            return false
        }
    }
}

// MARK: - Pump shared state

/// Reference-typed state shared across the per-track pump closures and
/// the 10 Hz progress poller. Lock-protected to keep Swift 6 strict
/// concurrency happy without `nonisolated(unsafe)` on captured vars.
private final class PumpState: @unchecked Sendable {
    private let lock = NSLock()
    private var _latestPTS: Double = 0
    private var _remaining: Int
    private var _bridge: ContinuationBridge?

    init(remaining: Int) {
        self._remaining = remaining
    }

    func setBridge(_ bridge: ContinuationBridge) {
        lock.lock(); defer { lock.unlock() }
        self._bridge = bridge
    }

    func latestPTS() -> Double {
        lock.lock(); defer { lock.unlock() }
        return _latestPTS
    }

    func recordPTS(_ pts: Double) {
        lock.lock(); defer { lock.unlock() }
        if pts > _latestPTS { _latestPTS = pts }
    }

    /// Decrement the remaining-pumps counter. When it hits zero, resume
    /// the continuation exactly once.
    func finishOnePump() {
        lock.lock()
        _remaining -= 1
        let done = _remaining <= 0
        let bridge = _bridge
        lock.unlock()
        if done { bridge?.resume() }
    }

    /// Used for the zero-track edge case to resume immediately.
    func tryResume() {
        lock.lock()
        let bridge = _bridge
        lock.unlock()
        bridge?.resume()
    }
}

/// Wraps a `CheckedContinuation` so it can be safely resumed from any
/// thread once. `CheckedContinuation` is itself non-Sendable in strict
/// mode; this class enforces the once-only semantics with a lock.
private final class ContinuationBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}
