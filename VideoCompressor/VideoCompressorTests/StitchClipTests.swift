//
//  StitchClipTests.swift
//  VideoCompressorTests
//
//  Tests for StitchClip value type: trimmedDurationSeconds, trimmedRange,
//  and isEdited derived properties.
//

import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class StitchClipTests: XCTestCase {

    func testTrimmedDurationDefaultIsNatural() throws {
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 10, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: .identity
        )
        XCTAssertEqual(clip.trimmedDurationSeconds, 10, accuracy: 0.001)
        XCTAssertFalse(clip.isEdited)
    }

    func testTrimmedDurationWithTrim() {
        var edits: ClipEdits = .identity
        edits.trimStartSeconds = 2
        edits.trimEndSeconds = 5
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 10, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: edits
        )
        XCTAssertEqual(clip.trimmedDurationSeconds, 3, accuracy: 0.001)
        XCTAssertTrue(clip.isEdited)
    }

    func testTrimmedDurationClampsNegative() {
        var edits: ClipEdits = .identity
        edits.trimEndSeconds = -1
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 10, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: edits
        )
        XCTAssertEqual(clip.trimmedDurationSeconds, 0, accuracy: 0.001)
    }

    func testTrimmedDurationClampsToNatural() {
        var edits: ClipEdits = .identity
        edits.trimEndSeconds = 999
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 10, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            edits: edits
        )
        XCTAssertEqual(clip.trimmedDurationSeconds, 10, accuracy: 0.001)
    }

    func testIsEditedFalseForIdentity() {
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 5, preferredTimescale: 600),
            naturalSize: CGSize(width: 1280, height: 720),
            edits: .identity
        )
        XCTAssertFalse(clip.isEdited)
    }

    func testIsEditedTrueAfterRotation() {
        var edits: ClipEdits = .identity
        edits.rotationDegrees = 90
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 5, preferredTimescale: 600),
            naturalSize: CGSize(width: 1280, height: 720),
            edits: edits
        )
        XCTAssertTrue(clip.isEdited)
    }

    func testIsEditedTrueAfterCrop() {
        var edits: ClipEdits = .identity
        edits.cropNormalized = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let clip = StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/dev/null"),
            displayName: "test.mov",
            naturalDuration: CMTime(seconds: 5, preferredTimescale: 600),
            naturalSize: CGSize(width: 1280, height: 720),
            edits: edits
        )
        XCTAssertTrue(clip.isEdited)
    }
}
