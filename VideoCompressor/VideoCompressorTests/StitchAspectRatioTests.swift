//
//  StitchAspectRatioTests.swift
//  VideoCompressorTests
//
//  Pin the canvas + transform math for the no-crop stitch fix.
//
//  Tests are pure — they call `StitchExporter.computeRenderSize` and
//  `StitchExporter.allClipsMatchCanvas` (both static) without spinning up
//  an actual AVAssetWriter. The transform-composition test verifies that
//  CGAffineTransform.concatenating produces the expected scale-to-fit
//  result for landscape-into-portrait and portrait-into-landscape cases.
//

import XCTest
import CoreGraphics
import CoreMedia
@testable import VideoCompressor_iOS

final class StitchAspectRatioTests: XCTestCase {

    // MARK: - Fixtures

    private func makeClip(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform = .identity
    ) -> StitchClip {
        StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/test.mov"),
            displayName: "test",
            naturalDuration: CMTime(seconds: 5, preferredTimescale: 600),
            naturalSize: naturalSize,
            kind: .video,
            preferredTransform: preferredTransform,
            edits: .identity
        )
    }

    /// AVAssetTrack.preferredTransform for an iPhone portrait video — a 90°
    /// rotation. NaturalSize reports as (1920, 1080) but the displayed video
    /// is (1080, 1920).
    private var iphonePortraitTransform: CGAffineTransform {
        CGAffineTransform(rotationAngle: .pi / 2)
            .translatedBy(x: 0, y: -1080)
    }

    // MARK: - displaySize

    func testDisplaySizeIdentityMatchesNatural() {
        let clip = makeClip(naturalSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clip.displaySize, CGSize(width: 1920, height: 1080))
    }

    func testDisplaySizeRotated90SwapsDimensions() {
        let clip = makeClip(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        // Rotated 90° → display is 1080×1920 (swap, abs).
        XCTAssertEqual(clip.displaySize.width, 1080, accuracy: 0.5)
        XCTAssertEqual(clip.displaySize.height, 1920, accuracy: 0.5)
    }

    func testDisplayOrientationLandscape() {
        let clip = makeClip(naturalSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clip.displayOrientation, .landscape)
    }

    func testDisplayOrientationPortraitFromTransform() {
        let clip = makeClip(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        XCTAssertEqual(clip.displayOrientation, .portrait)
    }

    func testDisplayOrientationSquare() {
        let clip = makeClip(naturalSize: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(clip.displayOrientation, .square)
    }

    // MARK: - computeRenderSize

    func testFixedPortraitMode() {
        let clips = [makeClip(naturalSize: CGSize(width: 1920, height: 1080))]
        let size = StitchExporter.computeRenderSize(aspectMode: .portrait, clips: clips)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920))
    }

    func testFixedLandscapeMode() {
        let clips = [makeClip(naturalSize: CGSize(width: 1080, height: 1920))]
        let size = StitchExporter.computeRenderSize(aspectMode: .landscape, clips: clips)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
    }

    func testFixedSquareMode() {
        let clips = [makeClip(naturalSize: CGSize(width: 1920, height: 1080))]
        let size = StitchExporter.computeRenderSize(aspectMode: .square, clips: clips)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1080))
    }

    func testAutoMajorityLandscape() {
        let clips = [
            makeClip(naturalSize: CGSize(width: 1920, height: 1080)),
            makeClip(naturalSize: CGSize(width: 1920, height: 1080)),
            makeClip(naturalSize: CGSize(width: 1080, height: 1920)),
        ]
        let size = StitchExporter.computeRenderSize(aspectMode: .auto, clips: clips)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
    }

    func testAutoMajorityPortrait() {
        let clips = [
            makeClip(naturalSize: CGSize(width: 1080, height: 1920)),
            makeClip(naturalSize: CGSize(width: 1080, height: 1920)),
            makeClip(naturalSize: CGSize(width: 1920, height: 1080)),
        ]
        let size = StitchExporter.computeRenderSize(aspectMode: .auto, clips: clips)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920))
    }

    func testAutoTieGoesLandscape() {
        // 1 portrait + 1 landscape — landscape wins ties (most common case).
        let clips = [
            makeClip(naturalSize: CGSize(width: 1920, height: 1080)),
            makeClip(naturalSize: CGSize(width: 1080, height: 1920)),
        ]
        let size = StitchExporter.computeRenderSize(aspectMode: .auto, clips: clips)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
    }

    func testAutoRespectsPreferredTransform() {
        // iPhone portrait video: naturalSize (1920×1080), but preferred
        // transform makes display 1080×1920. Two of these should vote
        // PORTRAIT, not landscape.
        let clip = makeClip(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        let size = StitchExporter.computeRenderSize(aspectMode: .auto, clips: [clip, clip])
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920),
                       "displaySize must drive auto vote, not naturalSize.")
    }

    // MARK: - allClipsMatchCanvas

    func testAllClipsMatchCanvasTrue() {
        let canvas = CGSize(width: 1920, height: 1080)
        let clips = [
            makeClip(naturalSize: canvas),
            makeClip(naturalSize: canvas),
        ]
        XCTAssertTrue(StitchExporter.allClipsMatchCanvas(clips: clips, renderSize: canvas))
    }

    func testAllClipsMatchCanvasFalseOnSizeMismatch() {
        let canvas = CGSize(width: 1920, height: 1080)
        let clips = [
            makeClip(naturalSize: canvas),
            makeClip(naturalSize: CGSize(width: 1080, height: 1920)),
        ]
        XCTAssertFalse(StitchExporter.allClipsMatchCanvas(clips: clips, renderSize: canvas))
    }

    // MARK: - End-to-end transform math (no AVFoundation needed)

    /// Mirror of `buildInstruction`'s transform math for verification.
    /// Order: preferredTransform → scale-to-fit → translate-to-centre.
    private func aspectFitTransform(
        clip: StitchClip,
        canvas: CGSize
    ) -> CGAffineTransform {
        var t = clip.preferredTransform
        let display = clip.displaySize
        guard display.width > 0, display.height > 0,
              canvas.width > 0, canvas.height > 0 else { return t }
        let scale = min(canvas.width / display.width, canvas.height / display.height)
        let scaledW = display.width * scale
        let scaledH = display.height * scale
        let dx = (canvas.width - scaledW) / 2
        let dy = (canvas.height - scaledH) / 2
        t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        t = t.concatenating(CGAffineTransform(translationX: dx, y: dy))
        return t
    }

    func testLandscapeIntoPortraitCanvasLetterboxes() {
        // 1920×1080 clip into 1080×1920 canvas → scale = 1080/1920 = 0.5625
        // → scaled to 1080×607.5 → letterbox top+bottom of (1920-607.5)/2 ≈ 656.25
        let clip = makeClip(naturalSize: CGSize(width: 1920, height: 1080))
        let canvas = CGSize(width: 1080, height: 1920)
        let t = aspectFitTransform(clip: clip, canvas: canvas)

        // Apply transform to the clip's display rect and check the result
        // fits inside the canvas with no negative bounds.
        let rect = CGRect(origin: .zero, size: clip.displaySize).applying(t)
        XCTAssertGreaterThanOrEqual(rect.minX, -0.5)
        XCTAssertGreaterThanOrEqual(rect.minY, -0.5)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width + 0.5)
        XCTAssertLessThanOrEqual(rect.maxY, canvas.height + 0.5)
        // And: width should equal canvas width (the limiting dimension).
        XCTAssertEqual(rect.width, canvas.width, accuracy: 1.0)
        // And: height should be LESS than canvas (letterbox bars exist).
        XCTAssertLessThan(rect.height, canvas.height - 100)
    }

    func testPortraitIntoLandscapeCanvasPillarboxes() {
        // 1080×1920 clip into 1920×1080 canvas → scale = 1080/1920 = 0.5625
        // → scaled to 607.5×1080 → pillarbox left+right.
        let clip = makeClip(naturalSize: CGSize(width: 1080, height: 1920))
        let canvas = CGSize(width: 1920, height: 1080)
        let t = aspectFitTransform(clip: clip, canvas: canvas)

        let rect = CGRect(origin: .zero, size: clip.displaySize).applying(t)
        XCTAssertGreaterThanOrEqual(rect.minX, -0.5)
        XCTAssertGreaterThanOrEqual(rect.minY, -0.5)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width + 0.5)
        XCTAssertLessThanOrEqual(rect.maxY, canvas.height + 0.5)
        // Height should equal canvas height (the limiting dimension).
        XCTAssertEqual(rect.height, canvas.height, accuracy: 1.0)
        // Width should be LESS than canvas (pillarbox bars exist).
        XCTAssertLessThan(rect.width, canvas.width - 100)
    }

    func testMatchedAspectFillsCanvas() {
        let clip = makeClip(naturalSize: CGSize(width: 1920, height: 1080))
        let canvas = CGSize(width: 1920, height: 1080)
        let t = aspectFitTransform(clip: clip, canvas: canvas)
        let rect = CGRect(origin: .zero, size: clip.displaySize).applying(t)
        XCTAssertEqual(rect.width, canvas.width, accuracy: 1.0)
        XCTAssertEqual(rect.height, canvas.height, accuracy: 1.0)
    }

    func testNeverCropsContent() {
        // Across many random clip sizes + canvases, every transformed clip
        // must fit inside the canvas. (Property test.)
        let canvases = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1080, height: 1920),
            CGSize(width: 1080, height: 1080),
        ]
        let clipSizes = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1080, height: 1920),
            CGSize(width: 4032, height: 3024),  // 4:3
            CGSize(width: 3024, height: 4032),
            CGSize(width: 1080, height: 1080),
            CGSize(width: 2560, height: 1440),  // 16:9 1440p
        ]
        for canvas in canvases {
            for clipSize in clipSizes {
                let clip = makeClip(naturalSize: clipSize)
                let t = aspectFitTransform(clip: clip, canvas: canvas)
                let rect = CGRect(origin: .zero, size: clip.displaySize).applying(t)
                let tolerance: CGFloat = 1.0
                XCTAssertGreaterThanOrEqual(
                    rect.minX, -tolerance,
                    "clip \(clipSize) into canvas \(canvas): minX out of bounds"
                )
                XCTAssertGreaterThanOrEqual(
                    rect.minY, -tolerance,
                    "clip \(clipSize) into canvas \(canvas): minY out of bounds"
                )
                XCTAssertLessThanOrEqual(
                    rect.maxX, canvas.width + tolerance,
                    "clip \(clipSize) into canvas \(canvas): maxX overflow (would crop)"
                )
                XCTAssertLessThanOrEqual(
                    rect.maxY, canvas.height + tolerance,
                    "clip \(clipSize) into canvas \(canvas): maxY overflow (would crop)"
                )
            }
        }
    }
}
