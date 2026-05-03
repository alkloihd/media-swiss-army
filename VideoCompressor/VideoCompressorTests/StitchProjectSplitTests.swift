//
//  StitchProjectSplitTests.swift
//  VideoCompressorTests
//
//  Pure (no AVFoundation) tests for `StitchProject.split` and `removeRange`.
//  Verify that splits partition the trim window correctly, that no-op cases
//  behave as expected, and that the internal state stays consistent.
//

import XCTest
import CoreMedia
import CoreGraphics
@testable import VideoCompressor_iOS

@MainActor
final class StitchProjectSplitTests: XCTestCase {

    private func makeClip(
        durationSeconds: Double = 10,
        trimStart: Double? = nil,
        trimEnd: Double? = nil
    ) -> StitchClip {
        var edits = ClipEdits.identity
        edits.trimStartSeconds = trimStart
        edits.trimEndSeconds = trimEnd
        return StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/clip.mov"),
            displayName: "clip",
            naturalDuration: CMTime(seconds: durationSeconds, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: edits
        )
    }

    // MARK: - Basic split

    func testSplitInMiddleProducesTwoClips() {
        let project = StitchProject()
        let clip = makeClip()
        project.append(clip)

        let ok = project.split(clipID: clip.id, atSeconds: 5)
        XCTAssertTrue(ok)
        XCTAssertEqual(project.clips.count, 2)
    }

    func testSplitFirstHalfRetainsOriginalID() {
        let project = StitchProject()
        let clip = makeClip()
        project.append(clip)
        _ = project.split(clipID: clip.id, atSeconds: 5)
        XCTAssertEqual(project.clips.first?.id, clip.id)
    }

    func testSplitSecondHalfHasFreshID() {
        let project = StitchProject()
        let clip = makeClip()
        project.append(clip)
        _ = project.split(clipID: clip.id, atSeconds: 5)
        XCTAssertNotEqual(project.clips.last?.id, clip.id)
    }

    func testSplitTrimRangesPartition() {
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10, trimStart: nil, trimEnd: nil)
        project.append(clip)

        _ = project.split(clipID: clip.id, atSeconds: 4)
        let first = project.clips[0]
        let second = project.clips[1]

        XCTAssertEqual(first.edits.trimEndSeconds, 4)
        XCTAssertEqual(second.edits.trimStartSeconds, 4)
        XCTAssertEqual(second.edits.trimEndSeconds, 10)
    }

    func testSplitRespectsExistingTrim() {
        // Source 10s, trimmed to [2..8]. Split at 5 → [2..5] + [5..8].
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10, trimStart: 2, trimEnd: 8)
        project.append(clip)

        let ok = project.split(clipID: clip.id, atSeconds: 5)
        XCTAssertTrue(ok)

        let first = project.clips[0]
        let second = project.clips[1]
        XCTAssertEqual(first.edits.trimStartSeconds, 2)
        XCTAssertEqual(first.edits.trimEndSeconds, 5)
        XCTAssertEqual(second.edits.trimStartSeconds, 5)
        XCTAssertEqual(second.edits.trimEndSeconds, 8)
    }

    // MARK: - No-op cases

    func testSplitAtTrimStartIsNoOp() {
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10)
        project.append(clip)
        let ok = project.split(clipID: clip.id, atSeconds: 0)
        XCTAssertFalse(ok)
        XCTAssertEqual(project.clips.count, 1)
    }

    func testSplitAtTrimEndIsNoOp() {
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10)
        project.append(clip)
        let ok = project.split(clipID: clip.id, atSeconds: 10)
        XCTAssertFalse(ok)
        XCTAssertEqual(project.clips.count, 1)
    }

    func testSplitTooCloseToBoundaryIsNoOp() {
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10)
        project.append(clip)
        // Within the 0.1s sliver guard.
        let ok = project.split(clipID: clip.id, atSeconds: 0.05)
        XCTAssertFalse(ok)
        XCTAssertEqual(project.clips.count, 1)
    }

    func testSplitOnUnknownClipIsNoOp() {
        let project = StitchProject()
        let ok = project.split(clipID: UUID(), atSeconds: 5)
        XCTAssertFalse(ok)
    }

    func testSplitClipInheritsMetadata() {
        // preferredTransform, naturalSize, sourceURL all carry through.
        let project = StitchProject()
        let transform = CGAffineTransform(rotationAngle: .pi / 2)
        var clip = makeClip(durationSeconds: 10)
        // Replace via constructor so transform is present.
        clip = StitchClip(
            id: clip.id,
            sourceURL: clip.sourceURL,
            displayName: clip.displayName,
            naturalDuration: clip.naturalDuration,
            naturalSize: clip.naturalSize,
            kind: .video,
            preferredTransform: transform,
            edits: clip.edits
        )
        project.append(clip)

        _ = project.split(clipID: clip.id, atSeconds: 5)
        XCTAssertEqual(project.clips[0].preferredTransform, transform)
        XCTAssertEqual(project.clips[1].preferredTransform, transform)
        XCTAssertEqual(project.clips[0].naturalSize, project.clips[1].naturalSize)
        XCTAssertEqual(project.clips[0].sourceURL, project.clips[1].sourceURL)
    }

    // MARK: - removeRange

    func testRemoveRangeProducesTwoClips() {
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10)
        project.append(clip)
        let ok = project.removeRange(clipID: clip.id, fromSeconds: 3, toSeconds: 7)
        XCTAssertTrue(ok)
        XCTAssertEqual(project.clips.count, 2)
    }

    func testRemoveRangePartitionsCorrectly() {
        // Source 10s → remove [3..7]. Survivors: [0..3] + [7..10].
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10)
        project.append(clip)
        _ = project.removeRange(clipID: clip.id, fromSeconds: 3, toSeconds: 7)

        let first = project.clips[0]
        let second = project.clips[1]
        XCTAssertEqual(first.edits.trimEndSeconds, 3)
        XCTAssertEqual(second.edits.trimStartSeconds, 7)
        XCTAssertEqual(second.edits.trimEndSeconds, 10)
    }

    func testRemoveRangeReversedIsNoOp() {
        let project = StitchProject()
        let clip = makeClip(durationSeconds: 10)
        project.append(clip)
        let ok = project.removeRange(clipID: clip.id, fromSeconds: 7, toSeconds: 3)
        XCTAssertFalse(ok)
        XCTAssertEqual(project.clips.count, 1)
    }
}
