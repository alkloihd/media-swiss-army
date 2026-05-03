//
//  PhotoMediaTests.swift
//  VideoCompressorTests
//
//  Pins the photo-side model layer: MediaKind, PhotoFormat, and the
//  PhotoCompressionSettings factory points.
//

import XCTest
@testable import VideoCompressor_iOS

final class PhotoMediaTests: XCTestCase {

    // MARK: - PhotoFormat.detect

    func testFormatDetectsHEIC() {
        XCTAssertEqual(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.heic")), .heic)
        XCTAssertEqual(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.HEIC")), .heic)
        XCTAssertEqual(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.heif")), .heic)
    }

    func testFormatDetectsJPEG() {
        XCTAssertEqual(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.jpg")), .jpeg)
        XCTAssertEqual(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.JPEG")), .jpeg)
    }

    func testFormatDetectsPNG() {
        XCTAssertEqual(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.PNG")), .png)
    }

    func testFormatRejectsUnknown() {
        XCTAssertNil(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/x.gif")))
        XCTAssertNil(PhotoFormat.detect(from: URL(fileURLWithPath: "/tmp/no-extension")))
    }

    func testFileExtensions() {
        XCTAssertEqual(PhotoFormat.heic.fileExtension, "heic")
        XCTAssertEqual(PhotoFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(PhotoFormat.png.fileExtension, "png")
    }

    // MARK: - MediaKind round-trip

    func testMediaKindRawValues() {
        XCTAssertEqual(MediaKind.video.rawValue, "video")
        XCTAssertEqual(MediaKind.still.rawValue, "still")
    }
}

final class PhotoCompressionSettingsTests: XCTestCase {

    // MARK: - Phase-1 factory points

    func testLosslessPreset() {
        let s = PhotoCompressionSettings.lossless
        XCTAssertEqual(s.quality, 1.0)
        XCTAssertNil(s.maxDimension)
        XCTAssertEqual(s.outputFormat, .heic)
        XCTAssertEqual(s.outputSuffix, "_MAX")
    }

    func testBalancedPreset() {
        let s = PhotoCompressionSettings.balanced
        XCTAssertEqual(s.quality, 0.92, accuracy: 0.001)
        XCTAssertNil(s.maxDimension)
        XCTAssertEqual(s.outputFormat, .heic)
        XCTAssertEqual(s.outputSuffix, "_BAL")
    }

    func testSmallPreset() {
        let s = PhotoCompressionSettings.small
        XCTAssertEqual(s.quality, 0.85, accuracy: 0.001)
        XCTAssertEqual(s.maxDimension, 3264)
        XCTAssertEqual(s.outputFormat, .heic)
        XCTAssertEqual(s.outputSuffix, "_SM")
    }

    func testStreamingPreset() {
        let s = PhotoCompressionSettings.streaming
        XCTAssertEqual(s.quality, 0.80, accuracy: 0.001)
        XCTAssertEqual(s.maxDimension, 2560)
        XCTAssertEqual(s.outputFormat, .heic)
        XCTAssertEqual(s.outputSuffix, "_WEB")
    }

    func testPhase1PresetsContainsAll() {
        XCTAssertEqual(PhotoCompressionSettings.phase1Presets.count, 4)
        XCTAssertTrue(PhotoCompressionSettings.phase1Presets.contains(.lossless))
        XCTAssertTrue(PhotoCompressionSettings.phase1Presets.contains(.balanced))
        XCTAssertTrue(PhotoCompressionSettings.phase1Presets.contains(.small))
        XCTAssertTrue(PhotoCompressionSettings.phase1Presets.contains(.streaming))
    }

    func testIDIsStable() {
        // Same settings → same ID; helps Identifiable in SwiftUI lists.
        let a = PhotoCompressionSettings.balanced
        let b = PhotoCompressionSettings.balanced
        XCTAssertEqual(a.id, b.id)
    }

    func testIDsDifferAcrossPresets() {
        let ids = Set(PhotoCompressionSettings.phase1Presets.map { $0.id })
        XCTAssertEqual(ids.count, 4)
    }

    // MARK: - Display

    func testDisplayNamesAreNonEmpty() {
        for s in PhotoCompressionSettings.phase1Presets {
            XCTAssertFalse(s.displayName.isEmpty)
            XCTAssertFalse(s.subtitle.isEmpty)
            XCTAssertFalse(s.symbolName.isEmpty)
        }
    }
}

final class PhotoMetadataServiceClassificationTests: XCTestCase {
    // Static helpers — test without spinning up an actor or hitting disk.

    func testXMPFingerprintDetection() {
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("...xmp.MetaAI..."))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("blah meta: hello"))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("Ray-Ban Stories"))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("Rayban marker"))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("c2pa.ManifestStore"))
        XCTAssertFalse(PhotoMetadataService.xmpContainsFingerprint("plain photo metadata"))
        XCTAssertFalse(PhotoMetadataService.xmpContainsFingerprint(""))
    }

    func testMakerAppleSoftwareFingerprintDetection() {
        XCTAssertTrue(PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple", key: "Software", value: "Meta capture v1.2"
        ))
        XCTAssertTrue(PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple", key: "software", value: "Ray-Ban Stories"
        ))
        XCTAssertFalse(PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple", key: "Software", value: "iPhone 15 Pro"
        ))
        XCTAssertFalse(PhotoMetadataService.isFingerprintTag(
            namespace: "TIFF", key: "Software", value: "Meta"
        ))
    }
}
