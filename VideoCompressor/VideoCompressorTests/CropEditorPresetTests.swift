//
//  CropEditorPresetTests.swift
//  VideoCompressorTests
//
//  Pins aspect-ratio preset crop math for the simplified Stitch crop editor.
//

import XCTest
import CoreGraphics
@testable import VideoCompressor_iOS

final class CropEditorPresetTests: XCTestCase {

    func testFreePresetClearsCrop() {
        let rect = CropEditorView.cropRect(
            for: .free,
            naturalSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertNil(rect)
    }

    func testInvalidSizeClearsCrop() {
        let rect = CropEditorView.cropRect(
            for: .square,
            naturalSize: .zero
        )

        XCTAssertNil(rect)
    }

    func testSquarePresetInLandscape() {
        let rect = CropEditorView.cropRect(
            for: .square,
            naturalSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.width, 0.5625, accuracy: 0.001)
        XCTAssertEqual(rect!.height, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect!.minX, (1.0 - 0.5625) / 2.0, accuracy: 0.001)
        XCTAssertEqual(rect!.minY, 0.0, accuracy: 0.001)
    }

    func testLandscape169InLandscapeSourceCollapsesToIdentity() {
        let rect = CropEditorView.cropRect(
            for: .landscape169,
            naturalSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertNil(rect)
    }

    func testPortrait916InRotatedPortraitSourceCollapsesToIdentity() {
        let rect = CropEditorView.cropRect(
            for: .portrait916,
            naturalSize: CGSize(width: 1920, height: 1080),
            displaySize: CGSize(width: 1080, height: 1920)
        )

        XCTAssertNil(rect)
    }

    func testPortrait916InLandscapeSource() {
        let rect = CropEditorView.cropRect(
            for: .portrait916,
            naturalSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.width, 0.3164, accuracy: 0.001)
        XCTAssertEqual(rect!.height, 1.0, accuracy: 0.001)
    }

    func testLandscape169InPortraitSource() {
        let rect = CropEditorView.cropRect(
            for: .landscape169,
            naturalSize: CGSize(width: 1080, height: 1920)
        )

        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect!.height, 0.3164, accuracy: 0.001)
    }
}
