//
//  MetaCleanCopyTests.swift
//  VideoCompressorTests
//
//  Pins the user-facing batch progress copy.
//

import XCTest
@testable import VideoCompressor_iOS

final class MetaCleanCopyTests: XCTestCase {

    func testSinglePhotoLabel() {
        let p = BatchCleanProgress(
            current: 1,
            total: 1,
            failed: 0,
            perItem: .zero,
            isRunning: true,
            lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .still), "Cleaning your photo...")
    }

    func testSingleVideoLabel() {
        let p = BatchCleanProgress(
            current: 1,
            total: 1,
            failed: 0,
            perItem: .zero,
            isRunning: true,
            lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .video), "Cleaning your video...")
    }

    func testBatchLabel() {
        let p = BatchCleanProgress(
            current: 3,
            total: 8,
            failed: 0,
            perItem: .zero,
            isRunning: true,
            lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .still), "Cleaning your photos · 3 of 8")
    }

    func testTerminalLabelPrefersPastTense() {
        let p = BatchCleanProgress(
            current: 8,
            total: 8,
            failed: 0,
            perItem: .complete,
            isRunning: false,
            lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .still), "Cleaned 8 photos")
    }
}
