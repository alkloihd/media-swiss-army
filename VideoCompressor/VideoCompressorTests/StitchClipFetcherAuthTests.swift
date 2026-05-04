//
//  StitchClipFetcherAuthTests.swift
//  VideoCompressorTests
//
//  Pins AUDIT-03 HIGH-2: Photos fetches must not run unless Stitch has
//  passive read-write authorization already available.
//

import Photos
import XCTest
@testable import VideoCompressor_iOS

final class StitchClipFetcherAuthTests: XCTestCase {

    private actor FetchProbe {
        private(set) var singleCalls = 0
        private(set) var batchCalls = 0
        private var lastBatchIDs: [String] = []

        func recordSingle(_ date: Date?) -> Date? {
            singleCalls += 1
            return date
        }

        func recordBatch(ids: [String], dates: [String: Date]) -> [String: Date] {
            batchCalls += 1
            lastBatchIDs = ids
            return dates
        }

        func snapshot() -> (singleCalls: Int, batchCalls: Int, lastBatchIDs: [String]) {
            (singleCalls, batchCalls, lastBatchIDs)
        }
    }

    func testCreationDateReturnsNilWhenAuthDenied() async {
        let probe = FetchProbe()
        let result = await StitchClipFetcher.creationDate(
            forAssetID: "FAKE-IDENTIFIER",
            authStatusProvider: { .denied },
            assetCreationDateProvider: { _ in
                await probe.recordSingle(Date(timeIntervalSince1970: 1))
            }
        )
        let calls = await probe.snapshot().singleCalls

        XCTAssertNil(result, "Denied auth must short-circuit to nil.")
        XCTAssertEqual(calls, 0, "Denied auth must not touch the Photos fetch seam.")
    }

    func testCreationDateReturnsNilWhenAuthRestricted() async {
        let result = await StitchClipFetcher.creationDate(
            forAssetID: "FAKE-IDENTIFIER",
            authStatusProvider: { .restricted }
        )

        XCTAssertNil(result, "Restricted auth must short-circuit to nil.")
    }

    func testCreationDateReturnsNilWhenAuthNotDetermined() async {
        let result = await StitchClipFetcher.creationDate(
            forAssetID: "FAKE-IDENTIFIER",
            authStatusProvider: { .notDetermined }
        )

        XCTAssertNil(result, "Not-determined auth must not prompt; return nil.")
    }

    func testBatchCreationDatesReturnsEmptyWhenAuthDenied() async {
        let probe = FetchProbe()
        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B", "FAKE-C"],
            authStatusProvider: { .denied },
            assetCreationDatesProvider: { ids in
                await probe.recordBatch(
                    ids: ids,
                    dates: ["FAKE-A": Date(timeIntervalSince1970: 1)]
                )
            }
        )
        let calls = await probe.snapshot().batchCalls

        XCTAssertEqual(result, [:], "Denied auth must short-circuit batch fetch.")
        XCTAssertEqual(calls, 0, "Denied auth must not touch the batch Photos fetch seam.")
    }

    func testBatchCreationDatesReturnsEmptyWhenAuthRestricted() async {
        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B"],
            authStatusProvider: { .restricted }
        )

        XCTAssertEqual(result, [:], "Restricted auth must short-circuit batch fetch.")
    }

    func testBatchCreationDatesReturnsEmptyWhenAuthNotDetermined() async {
        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B"],
            authStatusProvider: { .notDetermined }
        )

        XCTAssertEqual(result, [:], "Not-determined auth must not prompt; return empty.")
    }

    func testCreationDateInvokesFetchWhenAuthAuthorized() async {
        let expected = Date(timeIntervalSince1970: 123)
        let probe = FetchProbe()

        let result = await StitchClipFetcher.creationDate(
            forAssetID: "FAKE-IDENTIFIER",
            authStatusProvider: { .authorized },
            assetCreationDateProvider: { assetID in
                XCTAssertEqual(assetID, "FAKE-IDENTIFIER")
                return await probe.recordSingle(expected)
            }
        )
        let calls = await probe.snapshot().singleCalls

        XCTAssertEqual(result, expected)
        XCTAssertEqual(calls, 1, "Authorized auth should continue to fetch.")
    }

    func testBatchCreationDatesInvokesFetchWhenAuthLimited() async {
        let expected = ["FAKE-A": Date(timeIntervalSince1970: 321)]
        let probe = FetchProbe()

        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B", "FAKE-A"],
            authStatusProvider: { .limited },
            assetCreationDatesProvider: { ids in
                await probe.recordBatch(ids: ids, dates: expected)
            }
        )
        let snapshot = await probe.snapshot()

        XCTAssertEqual(result, expected)
        XCTAssertEqual(snapshot.batchCalls, 1, "Limited auth should continue to fetch.")
        XCTAssertEqual(Set(snapshot.lastBatchIDs), ["FAKE-A", "FAKE-B"])
    }
}
