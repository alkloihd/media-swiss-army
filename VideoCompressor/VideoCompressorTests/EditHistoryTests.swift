//
//  EditHistoryTests.swift
//  VideoCompressorTests
//
//  Pure-value tests for the per-clip undo/redo stack used by the inline
//  stitch editor. No SwiftUI / no AVFoundation — just snapshot semantics.
//

import XCTest
@testable import VideoCompressor_iOS

final class EditHistoryTests: XCTestCase {

    private func makeEdits(start: Double? = nil, end: Double? = nil) -> ClipEdits {
        var e = ClipEdits.identity
        e.trimStartSeconds = start
        e.trimEndSeconds = end
        return e
    }

    // MARK: - Empty state

    func testFreshHistoryIsEmpty() {
        let h = EditHistory()
        XCTAssertFalse(h.canUndo)
        XCTAssertFalse(h.canRedo)
        XCTAssertTrue(h.isEmpty)
    }

    func testCapacityHasReasonableMinimum() {
        // Even if caller asks for 1, we enforce >= 2 so a single commit
        // doesn't immediately evict itself.
        let h = EditHistory(capacity: 1)
        XCTAssertGreaterThanOrEqual(h.capacity, 2)
    }

    // MARK: - Commit

    func testCommitPushesToUndo() {
        var h = EditHistory()
        h.commit(previous: makeEdits(start: 1))
        XCTAssertTrue(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    func testCommitCoalescesEqualSnapshots() {
        var h = EditHistory()
        let snap = makeEdits(start: 1)
        h.commit(previous: snap)
        h.commit(previous: snap)
        h.commit(previous: snap)
        // Only one entry on the stack.
        XCTAssertEqual(h.undoStack.count, 1)
    }

    func testCommitClearsRedoStack() {
        var h = EditHistory()
        h.commit(previous: makeEdits(start: 1))
        _ = h.popUndo()        // simulates undo by caller
        h.pushRedo(current: makeEdits(start: 2))
        XCTAssertTrue(h.canRedo)
        // Fresh edit → redo path is invalidated.
        h.commit(previous: makeEdits(start: 3))
        XCTAssertFalse(h.canRedo)
    }

    func testCommitRespectsCapacity() {
        var h = EditHistory(capacity: 4)
        for i in 0..<10 {
            h.commit(previous: makeEdits(start: Double(i)))
        }
        XCTAssertEqual(h.undoStack.count, 4)
        // Oldest entries dropped — first surviving should be index 6 (10-4).
        XCTAssertEqual(h.undoStack.first?.trimStartSeconds, 6)
        XCTAssertEqual(h.undoStack.last?.trimStartSeconds, 9)
    }

    // MARK: - Undo / Redo round-trip

    func testUndoReturnsLastSnapshot() {
        var h = EditHistory()
        h.commit(previous: makeEdits(start: 1))
        h.commit(previous: makeEdits(start: 2))

        let popped = h.popUndo()
        XCTAssertEqual(popped?.trimStartSeconds, 2)
        XCTAssertTrue(h.canUndo) // one entry left
    }

    func testUndoRedoRoundTrip() {
        var h = EditHistory()
        h.commit(previous: makeEdits(start: 1))     // undo: [1]
        h.commit(previous: makeEdits(start: 2))     // undo: [1, 2]

        // Undo: pop 2 from undo, push current (= 3) to redo.
        let undone = h.popUndo()
        h.pushRedo(current: makeEdits(start: 3))
        XCTAssertEqual(undone?.trimStartSeconds, 2)
        XCTAssertTrue(h.canRedo)

        // Redo: pop 3 from redo, push current (= 2) to undo.
        let redone = h.popRedo()
        h.pushUndo(current: makeEdits(start: 2))
        XCTAssertEqual(redone?.trimStartSeconds, 3)
    }

    func testPopUndoOnEmptyReturnsNil() {
        var h = EditHistory()
        XCTAssertNil(h.popUndo())
    }

    func testPopRedoOnEmptyReturnsNil() {
        var h = EditHistory()
        XCTAssertNil(h.popRedo())
    }

    // MARK: - Reset

    func testResetClearsBothStacks() {
        var h = EditHistory()
        h.commit(previous: makeEdits(start: 1))
        h.pushRedo(current: makeEdits(start: 2))
        h.reset()
        XCTAssertFalse(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    // MARK: - StitchProject integration

    @MainActor
    func testProjectUndoSwapsCurrentAndPreviousEdits() {
        let project = StitchProject()
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/t.mov"),
            displayName: "t",
            naturalDuration: CMTimeMake(value: 600, timescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
        project.append(clip)

        // First edit: trim to 0.5...0.9. Snapshot the *previous* (identity)
        // before mutating.
        project.commitHistory(for: clip.id)
        project.updateEdits(for: clip.id) {
            $0.trimStartSeconds = 0.5
            $0.trimEndSeconds = 0.9
        }
        XCTAssertTrue(project.canUndo(for: clip.id))

        // Undo restores identity.
        project.undo(for: clip.id)
        XCTAssertNil(project.clips.first?.edits.trimStartSeconds)
        XCTAssertNil(project.clips.first?.edits.trimEndSeconds)
        XCTAssertTrue(project.canRedo(for: clip.id))

        // Redo restores the trim.
        project.redo(for: clip.id)
        XCTAssertEqual(project.clips.first?.edits.trimStartSeconds, 0.5)
        XCTAssertEqual(project.clips.first?.edits.trimEndSeconds, 0.9)
    }

    @MainActor
    func testHistoriesAreIsolatedPerClip() {
        let project = StitchProject()
        let clipA = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/a.mov"),
            displayName: "a",
            naturalDuration: CMTimeMake(value: 600, timescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
        let clipB = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/b.mov"),
            displayName: "b",
            naturalDuration: CMTimeMake(value: 600, timescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
        project.append(clipA)
        project.append(clipB)

        project.commitHistory(for: clipA.id)
        project.updateEdits(for: clipA.id) { $0.trimStartSeconds = 0.5 }

        XCTAssertTrue(project.canUndo(for: clipA.id))
        XCTAssertFalse(project.canUndo(for: clipB.id),
                       "Undo state must not leak across clips.")
    }
}

import CoreMedia
import CoreGraphics
