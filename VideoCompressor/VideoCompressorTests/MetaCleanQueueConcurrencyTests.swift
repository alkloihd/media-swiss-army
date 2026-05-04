//
//  MetaCleanQueueConcurrencyTests.swift
//  VideoCompressorTests
//
//  Pins Cluster 3 MetaClean batch policy: bounded concurrency and one
//  user-facing end-of-batch save result.
//

import XCTest
@testable import VideoCompressor_iOS

@MainActor
final class MetaCleanQueueConcurrencyTests: XCTestCase {

    func testConcurrencyHelperBoundedAtLeastOne() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .unknown,
            thermalState: .nominal
        )

        XCTAssertGreaterThanOrEqual(safe, 1)
        XCTAssertLessThanOrEqual(safe, 2)
    }

    func testConcurrencyHelperPro() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .pro,
            thermalState: .nominal
        )

        XCTAssertEqual(safe, 2)
    }

    func testConcurrencyHelperFallsBackUnderThermalStress() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .pro,
            thermalState: .serious
        )

        XCTAssertEqual(safe, 1)
    }

    func testConcurrencyHelperStandard() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .standard,
            thermalState: .nominal
        )

        XCTAssertEqual(safe, 1)
    }

    func testBatchFractionUsesCompletedCount() {
        let progress = BatchCleanProgress(
            current: 3,
            total: 4,
            failed: 0,
            perItem: .zero,
            isRunning: true,
            lastError: nil
        )

        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.001)
    }

    func testSaveBatchResultMessageForSuccessfulPhotoBatch() {
        let result = SaveBatchResult(
            saved: 3,
            failed: 0,
            kind: .still,
            at: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.displayMessage, "Saved 3 photos to your library")
    }

    func testSaveBatchResultSurfacesSaveFailures() {
        let result = SaveBatchResult(
            saved: 2,
            failed: 1,
            kind: .video,
            at: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.displayMessage, "Saved 2 videos to your library · 1 failed to save")
    }
}
