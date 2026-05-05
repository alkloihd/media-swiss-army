//
//  StitchProjectClearAllTests.swift
//  VideoCompressorTests
//
//  Regression tests for `StitchProject.clearAll()` — the Start Over /
//  post-save reset path added in Cluster 2.5. The contract:
//
//  1. After `clearAll()`, `clips` is empty.
//  2. Each clip's on-disk file under `StitchInputs/` is removed.
//  3. Files outside `inputsDir` (e.g. user's Photos library — synthesised
//     here as a tmp file outside StitchInputs) are NEVER deleted by
//     `clearAll()`. Same scoping safety as `remove(at:)`.
//  4. The method is idempotent — calling on an empty project is a no-op.
//  5. exportState resets to `.idle`.
//

import XCTest
import AVFoundation
import CoreMedia
import CoreGraphics
@testable import VideoCompressor_iOS

@MainActor
final class StitchProjectClearAllTests: XCTestCase {
    private actor BoolProbe {
        private var value = false

        func set(_ newValue: Bool) {
            value = newValue
        }

        func get() -> Bool {
            value
        }
    }

    private func inputsDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("StitchInputs", isDirectory: true)
    }

    override func setUp() async throws {
        try? FileManager.default.createDirectory(
            at: inputsDir(),
            withIntermediateDirectories: true
        )
    }

    private func makeStagedClip(in dir: URL) throws -> StitchClip {
        let url = dir.appendingPathComponent("clearall-clip-\(UUID().uuidString.prefix(6)).mov")
        try Data("placeholder".utf8).write(to: url)
        return StitchClip(
            id: UUID(),
            sourceURL: url,
            displayName: url.lastPathComponent,
            naturalDuration: CMTime(seconds: 5, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
    }

    private func makeSparseClip(bytes: UInt64, durationSeconds: Double) throws -> StitchClip {
        let url = inputsDir()
            .appendingPathComponent("sparse-\(UUID().uuidString.prefix(6)).mov")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: bytes)
        try handle.close()
        return StitchClip(
            id: UUID(),
            sourceURL: url,
            displayName: url.lastPathComponent,
            naturalDuration: CMTime(seconds: durationSeconds, preferredTimescale: 600),
            naturalSize: CGSize(width: 3840, height: 2160),
            edits: .identity
        )
    }

    private func makeStillEstimateClip(bytes: UInt64, stillDuration: Double) throws -> StitchClip {
        let url = inputsDir()
            .appendingPathComponent("still-estimate-\(UUID().uuidString.prefix(6)).png")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: bytes)
        try handle.close()
        var edits = ClipEdits.identity
        edits.stillDuration = stillDuration
        return StitchClip(
            id: UUID(),
            sourceURL: url,
            displayName: url.lastPathComponent,
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 3840, height: 2160),
            kind: .still,
            edits: edits
        )
    }

    private func makeShortVideoFixture(size: Int = 32) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-project-fixture-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size,
            ]
        )
        guard writer.canAdd(videoInput) else { throw NSError(domain: "fixture", code: 2) }
        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0x7F, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for frame in 0..<30 {
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: time))
        }
        videoInput.markAsFinished()

        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        guard writer.status == .completed else {
            throw NSError(
                domain: "fixture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "writer finished with status \(writer.status.rawValue)"]
            )
        }
        return url
    }

    /// 1 + 2: clearAll empties the array and removes the on-disk files
    /// for every clip whose sourceURL is under StitchInputs/.
    func testClearAllEmptiesClipsAndDeletesStagedFiles() async throws {
        let project = StitchProject()
        let clip1 = try makeStagedClip(in: inputsDir())
        let clip2 = try makeStagedClip(in: inputsDir())
        let clip3 = try makeStagedClip(in: inputsDir())
        project.append(clip1)
        project.append(clip2)
        project.append(clip3)

        XCTAssertEqual(project.clips.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip1.sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip2.sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip3.sourceURL.path))

        await project.clearAll()

        XCTAssertTrue(project.clips.isEmpty, "clips array must be empty after clearAll")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip1.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip2.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip3.sourceURL.path))
    }

    /// 3: a clip whose sourceURL is OUTSIDE inputsDir (e.g. someone hands
    /// the project a Photos-library URL through a future API misuse) must
    /// have its in-memory entry removed but its on-disk file PRESERVED.
    /// Same safety guarantee as `remove(at:)`.
    func testClearAllNeverDeletesFilesOutsideInputsDir() async throws {
        let foreign = FileManager.default.temporaryDirectory
            .appendingPathComponent("foreign-clearall-\(UUID().uuidString.prefix(6)).mov")
        try Data("photos-library-stand-in".utf8).write(to: foreign)
        defer { try? FileManager.default.removeItem(at: foreign) }

        let project = StitchProject()
        let foreignClip = StitchClip(
            id: UUID(),
            sourceURL: foreign,
            displayName: foreign.lastPathComponent,
            naturalDuration: CMTime(seconds: 5, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
        project.append(foreignClip)

        await project.clearAll()

        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: foreign.path),
            "clearAll must NEVER delete files outside StitchInputs/ — the foreign URL must survive"
        )
    }

    /// 4a: calling clearAll on an already-empty project is a no-op (no
    /// throw, no spurious state change).
    func testClearAllOnEmptyProjectIsNoOp() async {
        let project = StitchProject()
        XCTAssertTrue(project.clips.isEmpty)
        await project.clearAll()
        XCTAssertTrue(project.clips.isEmpty)
    }

    /// 4b: calling clearAll twice in a row produces no error and leaves
    /// the project in the same empty state.
    func testClearAllIsIdempotent() async throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)

        await project.clearAll()
        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.sourceURL.path))

        await project.clearAll()
        XCTAssertTrue(project.clips.isEmpty)
    }

    /// Cluster 2.5 audit follow-up — three independent auditors flagged
    /// that the original `clearAll()` did NOT cancel an in-flight export
    /// task. If the user tapped "Start Over" or "Done — start a new
    /// project" while an export was running, the live `AVURLAsset` would
    /// keep reading from `inputsDir` while `remove(at:)` deleted those
    /// files — surfacing opaque -11800 alerts and writing phantom outputs.
    /// This test pins the post-fix contract: clearAll waits for the
    /// in-flight task to finish before mutating state.
    @MainActor
    func testClearAllAwaitsInFlightExportTaskBeforeWiping() async throws {
        let project = StitchProject()
        let clip1 = try makeStagedClip(in: inputsDir())
        let clip2 = try makeStagedClip(in: inputsDir())
        project.append(clip1)
        project.append(clip2)

        let cleanupProbe = BoolProbe()
        // Stand in for an in-flight export. It reacts to cancellation, then
        // does delayed cleanup so clearAll's cancel-and-await path is
        // observable without invoking AVFoundation.
        let started = Date()
        let fakeExport = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                let filesStillPresent = FileManager.default.fileExists(atPath: clip1.sourceURL.path)
                    && FileManager.default.fileExists(atPath: clip2.sourceURL.path)
                await cleanupProbe.set(filesStillPresent)
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.18) {
                        continuation.resume()
                    }
                }
            }
        }
        project.testHook_setExportTask(fakeExport)

        await project.clearAll()
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThanOrEqual(
            elapsed,
            0.12,
            "clearAll must await the export task's cancellation cleanup before deleting staged inputs."
        )
        let filesStillExistedDuringCleanup = await cleanupProbe.get()
        XCTAssertTrue(
            filesStillExistedDuringCleanup,
            "clearAll must not delete staged inputs until the in-flight export task has finished cancellation cleanup."
        )
        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip1.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip2.sourceURL.path))
    }

    func testExportWhileAlreadyExportingDoesNotReplaceRunningTask() async {
        let project = StitchProject()
        let cancelProbe = BoolProbe()
        let sentinel = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                await cancelProbe.set(true)
            }
        }
        project.testHook_setExportTask(sentinel)
        project.exportState = .encoding(.zero)

        project.export(settings: .small)

        XCTAssertEqual(
            project.exportState,
            .encoding(.zero),
            "Repeated export taps while encoding should be ignored instead of replacing a still-running task."
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        let wasCancelled = await cancelProbe.get()
        XCTAssertFalse(
            wasCancelled,
            "Repeated export taps while encoding must not cancel the registered in-flight export task."
        )
        sentinel.cancel()
    }

    /// 5: exportState resets to .idle even if clearAll is invoked while a
    /// previous export had finished or failed (defense-in-depth).
    func testClearAllResetsExportState() async throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)
        // Force a non-idle exportState. .cancelled is a leaf case from the
        // public StitchExportState enum that doesn't require building a real
        // CompressedOutput, so it's safe to set in a unit test.
        project.exportState = .cancelled

        await project.clearAll()

        XCTAssertEqual(
            project.exportState,
            .idle,
            "exportState must drop back to .idle after clearAll"
        )
    }

    func testEstimatedExportBytesUsesSelectedPresetBudgetInsteadOfTripleSourceBytes() throws {
        let clip1 = try makeSparseClip(bytes: 100 * 1_048_576, durationSeconds: 120)
        let clip2 = try makeSparseClip(bytes: 100 * 1_048_576, durationSeconds: 120)
        defer {
            try? FileManager.default.removeItem(at: clip1.sourceURL)
            try? FileManager.default.removeItem(at: clip2.sourceURL)
        }

        let oldTripleSourceHeuristic: Int64 = 600 * 1_048_576
        let estimate = StitchProject.estimatedExportBytes(
            for: [clip1, clip2],
            settings: .streaming
        )

        XCTAssertGreaterThan(estimate, 0)
        XCTAssertLessThan(
            estimate,
            oldTripleSourceHeuristic,
            "Preflight must not reject valid Streaming exports by requiring 3x the already-staged source bytes."
        )
    }

    func testEstimatedExportBytesUsesEditedStillDuration() throws {
        let shortStills = try (0..<20).map { _ in
            try makeStillEstimateClip(bytes: 1 * 1_048_576, stillDuration: 1)
        }
        let longStills = try (0..<20).map { _ in
            try makeStillEstimateClip(bytes: 1 * 1_048_576, stillDuration: 10)
        }
        defer {
            for clip in shortStills + longStills {
                try? FileManager.default.removeItem(at: clip.sourceURL)
            }
        }

        let shortEstimate = StitchProject.estimatedExportBytes(
            for: shortStills,
            settings: .streaming
        )
        let longEstimate = StitchProject.estimatedExportBytes(
            for: longStills,
            settings: .streaming
        )

        XCTAssertGreaterThan(
            longEstimate,
            shortEstimate,
            "Still-heavy export preflight must account for the user-edited still duration, not the baked 1s source duration."
        )
    }

    func testLateCancelAfterExporterReturnsSweepsOutputAndDoesNotPublishFinished() async throws {
        let videoA = try makeShortVideoFixture()
        defer { try? FileManager.default.removeItem(at: videoA) }
        let videoB = try makeShortVideoFixture()
        defer { try? FileManager.default.removeItem(at: videoB) }

        let project = StitchProject()
        project.append(StitchClip(
            id: UUID(),
            sourceURL: videoA,
            displayName: "A.mov",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 32),
            kind: .video,
            edits: .identity
        ))
        project.append(StitchClip(
            id: UUID(),
            sourceURL: videoB,
            displayName: "B.mov",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 32),
            kind: .video,
            edits: .identity
        ))

        var producedURL: URL?
        project.testHook_setExportRunner { _, _, settings, outputURL, _ in
            producedURL = outputURL
            try Data("encoded".utf8).write(to: outputURL)
            project.cancelExport()
            return StitchExportResult(url: outputURL, settings: settings, fallbackMessage: nil)
        }

        project.export(settings: .small)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let outputURL = try XCTUnwrap(producedURL)
        XCTAssertEqual(project.exportState, .cancelled)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.path),
            "Late cancellation after exporter returns must sweep the predicted stitched output instead of leaving a phantom file."
        )
    }
}
