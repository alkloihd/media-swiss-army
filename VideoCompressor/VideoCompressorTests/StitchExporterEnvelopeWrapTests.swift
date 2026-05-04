//
//  StitchExporterEnvelopeWrapTests.swift
//  VideoCompressorTests
//
//  Cluster 2.5 regression coverage for the encoder envelope wrap added
//  to `StitchExporter`. Two contracts:
//
//  1. `wrapEncoderEnvelopeIfTerminal` swaps any AVError -11841 (or
//     CompressionError carrying `-11841` in its message) for the new
//     friendly `CompressionError.encoderEnvelopeRejected(message:)`.
//     Other errors pass through untouched.
//
//  2. `stitchDownshift` returns a usable fallback for every named preset
//     except the explicit terminal `.sd540 + .balanced` case. Custom /
//     unmapped presets fall to `.small` instead of `nil` so the user
//     never sees the raw AVFoundation alert.
//

import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class StitchExporterEnvelopeWrapTests: XCTestCase {

    // MARK: - wrapEncoderEnvelopeIfTerminal

    func testWrapEncoderEnvelopeRewrapsAVError11841() {
        let raw = NSError(
            domain: AVFoundationErrorDomain,
            code: -11841,
            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed."]
        )
        let wrapped = StitchExporter.wrapEncoderEnvelopeIfTerminal(raw)
        guard case CompressionError.encoderEnvelopeRejected(let message) = wrapped else {
            XCTFail("Expected encoderEnvelopeRejected, got \(wrapped)")
            return
        }
        XCTAssertEqual(
            message,
            StitchExporter.envelopeExhaustedMessage,
            "Wrap must use the canonical envelope-exhausted message so the UI renders one consistent string"
        )
    }

    func testWrapEncoderEnvelopeRewrapsCompressionExportFailedWith11841() {
        let raw = CompressionError.exportFailed(
            "[AVFoundationErrorDomain -11841] The operation could not be completed."
        )
        let wrapped = StitchExporter.wrapEncoderEnvelopeIfTerminal(raw)
        guard case CompressionError.encoderEnvelopeRejected = wrapped else {
            XCTFail("Expected encoderEnvelopeRejected, got \(wrapped)")
            return
        }
    }

    func testWrapEncoderEnvelopePassesThroughCancelled() {
        let raw = CompressionError.cancelled
        let wrapped = StitchExporter.wrapEncoderEnvelopeIfTerminal(raw)
        guard case CompressionError.cancelled = wrapped else {
            XCTFail("Cancelled must pass through untouched, got \(wrapped)")
            return
        }
    }

    func testWrapEncoderEnvelopePassesThroughUnrelatedError() {
        let raw = NSError(
            domain: NSCocoaErrorDomain,
            code: 256,
            userInfo: [NSLocalizedDescriptionKey: "File not found."]
        )
        let wrapped = StitchExporter.wrapEncoderEnvelopeIfTerminal(raw) as NSError
        XCTAssertEqual(wrapped.domain, NSCocoaErrorDomain, "Non-encoder errors must pass through")
        XCTAssertEqual(wrapped.code, 256)
    }

    func testWrapEncoderEnvelopePassesThroughUnrelatedAVError() {
        // -11847 is AVErrorOperationInterrupted (background lock) — different
        // class of failure, do not rewrap.
        let raw = NSError(domain: AVFoundationErrorDomain, code: -11847)
        let wrapped = StitchExporter.wrapEncoderEnvelopeIfTerminal(raw) as NSError
        XCTAssertEqual(wrapped.code, -11847, "AVError other than -11841 must pass through")
    }

    // MARK: - envelopeExhaustedMessage shape

    func testEnvelopeExhaustedMessageMentionsKeyRecoveryPaths() {
        let msg = StitchExporter.envelopeExhaustedMessage
        // The user-facing string must point at all three recovery paths so
        // they have something to try, in plain English. Non-empty + mentions
        // each lever.
        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(msg.lowercased().contains("transition"),
                      "Message should mention transitions as a lever to remove")
        XCTAssertTrue(msg.lowercased().contains("shorter") || msg.lowercased().contains("split"),
                      "Message should suggest splitting/shortening clips")
        XCTAssertTrue(msg.lowercased().contains("small"),
                      "Message should mention the Small preset by name")
    }

    // MARK: - stitchDownshift table coverage

    func testStitchDownshiftFromMaxYieldsBalanced() {
        let next = StitchExporter.stitchDownshift(from: .max)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.resolution, .fhd1080)
        XCTAssertEqual(next?.quality, .high)
    }

    func testStitchDownshiftFromBalancedYieldsSmall() {
        let next = StitchExporter.stitchDownshift(from: .balanced)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.resolution, .hd720)
        XCTAssertEqual(next?.quality, .balanced)
    }

    func testStitchDownshiftFromSmallYieldsStreaming() {
        let next = StitchExporter.stitchDownshift(from: .small)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.resolution, .sd540)
        XCTAssertEqual(next?.quality, .balanced)
    }

    /// The terminal of the named-preset chain. After Streaming, the wrapper
    /// at `export()` should kick in and convert the next throw into the
    /// friendly encoderEnvelopeRejected.
    func testStitchDownshiftFromStreamingIsTerminal() {
        let next = StitchExporter.stitchDownshift(from: .streaming)
        XCTAssertNil(next, "Streaming's downshift must be nil — terminal of the chain")
    }

    /// Cluster 2.5 specifically extended this: any preset NOT in the named
    /// chain falls to `.small` so there is always at least one fallback step
    /// before the terminal wrap. Previously this returned nil and surfaced
    /// raw -11841.
    // MARK: - StitchExportResult.merging (Cluster 2.5 audit follow-up)

    func testMergingNotesPreservesUrlAndSettings() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let r = StitchExportResult(url: url, settings: .balanced, fallbackMessage: nil)
        let merged = r.merging(note: "added")
        XCTAssertEqual(merged.url, url)
        XCTAssertEqual(merged.settings, .balanced)
        XCTAssertEqual(merged.fallbackMessage, "added")
    }

    func testMergingNotesJoinsBothMessages() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let r = StitchExportResult(url: url, settings: .small, fallbackMessage: "first.")
        let merged = r.merging(note: "second.")
        // Joined with paragraph break so the export sheet renders each
        // fallback as its own line instead of a wall of text.
        XCTAssertEqual(merged.fallbackMessage, "first.\n\nsecond.")
    }

    func testMergingNilNotePreservesExisting() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let r = StitchExportResult(url: url, settings: .small, fallbackMessage: "existing")
        let merged = r.merging(note: nil)
        XCTAssertEqual(merged.fallbackMessage, "existing")
    }

    func testMergingBothNilProducesNil() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let r = StitchExportResult(url: url, settings: .max, fallbackMessage: nil)
        let merged = r.merging(note: nil)
        XCTAssertNil(merged.fallbackMessage)
    }

    func testStitchDownshiftFromUnmappedCustomPresetFallsToSmall() {
        // (.source, .high) is not one of the four named factory cells —
        // exactly the kind of "custom" combination that pre-2.5 surfaced
        // raw -11841 with no fallback path.
        let custom = CompressionSettings(resolution: .source, quality: .high)
        let next = StitchExporter.stitchDownshift(from: custom)
        XCTAssertNotNil(next, "Custom / unmapped presets must have a Small fallback floor")
        XCTAssertEqual(next?.resolution, .hd720)
        XCTAssertEqual(next?.quality, .balanced)
    }
}
