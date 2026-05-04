//
//  StitchExportSheetTests.swift
//  VideoCompressorTests
//
//  Pins the finished-export actions without needing a SwiftUI inspection
//  dependency.
//

import XCTest
@testable import VideoCompressor_iOS

final class StitchExportSheetTests: XCTestCase {

    func testFinishedStateOffersExportAgain() {
        let output = CompressedOutput(
            url: URL(fileURLWithPath: "/tmp/stitch-finished.mp4"),
            bytes: 1024,
            createdAt: Date(),
            settings: .small
        )

        XCTAssertTrue(
            StitchExportSheet.shouldShowExportAgain(for: .finished(output)),
            "A successful stitch export must not trap the user in saved/finished state."
        )
    }

    func testFinishedStateHidesExportAgainWhileSaveInProgress() {
        let output = CompressedOutput(
            url: URL(fileURLWithPath: "/tmp/stitch-saving.mp4"),
            bytes: 1024,
            createdAt: Date(),
            settings: .small
        )

        XCTAssertFalse(
            StitchExportSheet.shouldShowExportAgain(for: .finished(output), saveStatus: .saving),
            "Export Again must be hidden while Save to Photos is still in flight."
        )
    }

    func testMissingFinishedOutputCannotBeSavedAgain() {
        let output = CompressedOutput(
            url: URL(fileURLWithPath: "/tmp/stitch-missing-\(UUID().uuidString).mp4"),
            bytes: 1024,
            createdAt: Date(),
            settings: .small
        )

        XCTAssertFalse(
            StitchExportSheet.canSaveFinishedOutput(output, fileExists: { _ in false }),
            "A stale finished output that was swept after save must not offer Save to Photos."
        )
    }
}
