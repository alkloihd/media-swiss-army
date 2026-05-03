//
//  StitchProjectRemoveSafetyTests.swift
//  VideoCompressorTests
//
//  Critical regression tests for the split + remove file-deletion safety
//  invariant. After `split`, two clips share `sourceURL`. Removing one half
//  must NOT delete the on-disk file because the other half still needs it.
//

import XCTest
import CoreMedia
import CoreGraphics
@testable import VideoCompressor_iOS

@MainActor
final class StitchProjectRemoveSafetyTests: XCTestCase {

    private func makeStagedClip(in dir: URL) throws -> StitchClip {
        let url = dir.appendingPathComponent("clip-\(UUID().uuidString.prefix(6)).mov")
        // Write a tiny placeholder file — we only care about file existence
        // for the safety check, not content.
        try Data("placeholder".utf8).write(to: url)
        return StitchClip(
            id: UUID(),
            sourceURL: url,
            displayName: url.lastPathComponent,
            naturalDuration: CMTime(seconds: 10, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
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

    func testRemoveSingleClipDeletesSourceFile() throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.sourceURL.path))

        project.remove(at: IndexSet(integer: 0))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: clip.sourceURL.path),
            "Source file should be deleted when no other clip references it."
        )
    }

    func testRemoveOneHalfOfSplitPreservesSourceFile() throws {
        // CRITICAL — without the reference-count guard, this test fails:
        // remove(0) would delete the file the surviving half needs.
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)
        XCTAssertTrue(project.split(clipID: clip.id, atSeconds: 5))
        XCTAssertEqual(project.clips.count, 2)
        let sourcePath = clip.sourceURL.path

        // Remove the first half. The second half still references the same source.
        project.remove(at: IndexSet(integer: 0))
        XCTAssertEqual(project.clips.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sourcePath),
            "Source file MUST survive when another clip still references it (split second half)."
        )

        // Now remove the second half — file should be deleted.
        project.remove(at: IndexSet(integer: 0))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourcePath),
            "Source file should be deleted once the last reference is removed."
        )
    }

    func testRemoveBothSplitHalvesAtOnceDeletesSourceOnce() throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)
        XCTAssertTrue(project.split(clipID: clip.id, atSeconds: 5))
        let sourcePath = clip.sourceURL.path

        // Remove BOTH halves in one call.
        project.remove(at: IndexSet([0, 1]))
        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourcePath),
            "All references gone in one remove call → file deleted."
        )
    }

    func testHistoriesClearedOnRemove() throws {
        let project = StitchProject()
        let clip = try makeStagedClip(in: inputsDir())
        project.append(clip)
        project.commitHistory(for: clip.id)
        project.updateEdits(for: clip.id) { $0.trimStartSeconds = 1.5 }
        XCTAssertTrue(project.canUndo(for: clip.id))

        project.remove(at: IndexSet(integer: 0))
        // History entry should be gone (no leak across deleted clips).
        XCTAssertFalse(project.canUndo(for: clip.id))
    }
}
