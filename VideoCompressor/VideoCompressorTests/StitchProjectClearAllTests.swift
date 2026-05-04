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
import CoreMedia
import CoreGraphics
@testable import VideoCompressor_iOS

@MainActor
final class StitchProjectClearAllTests: XCTestCase {

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

    /// 1 + 2: clearAll empties the array and removes the on-disk files
    /// for every clip whose sourceURL is under StitchInputs/.
    func testClearAllEmptiesClipsAndDeletesStagedFiles() throws {
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

        project.clearAll()

        XCTAssertTrue(project.clips.isEmpty, "clips array must be empty after clearAll")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip1.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip2.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip3.sourceURL.path))
    }

    /// 3: a clip whose sourceURL is OUTSIDE inputsDir (e.g. someone hands
    /// the project a Photos-library URL through a future API misuse) must
    /// have its in-memory entry removed but its on-disk file PRESERVED.
    /// Same safety guarantee as `remove(at:)`.
    func testClearAllNeverDeletesFilesOutsideInputsDir() throws {
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

        project.clearAll()

        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: foreign.path),
            "clearAll must NEVER delete files outside StitchInputs/ — the foreign URL must survive"
        )
    }

    /// 4a: calling clearAll on an already-empty project is a no-op (no
    /// throw, no spurious state change).
    func testClearAllOnEmptyProjectIsNoOp() {
        let project = StitchProject()
        XCTAssertTrue(project.clips.isEmpty)
        project.clearAll()
        XCTAssertTrue(project.clips.isEmpty)
    }

    /// 4b: calling clearAll twice in a row produces no error and leaves
    /// the project in the same empty state.
    func testClearAllIsIdempotent() throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)

        project.clearAll()
        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.sourceURL.path))

        project.clearAll()
        XCTAssertTrue(project.clips.isEmpty)
    }

    /// 5: exportState resets to .idle even if clearAll is invoked while a
    /// previous export had finished or failed (defense-in-depth).
    func testClearAllResetsExportState() throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)
        // Force a non-idle exportState. .cancelled is a leaf case from the
        // public StitchExportState enum that doesn't require building a real
        // CompressedOutput, so it's safe to set in a unit test.
        project.exportState = .cancelled

        project.clearAll()

        XCTAssertEqual(
            project.exportState,
            .idle,
            "exportState must drop back to .idle after clearAll"
        )
    }
}
