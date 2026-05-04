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

    func testCreationDateReturnsNilWhenAuthDenied() async {
        let result = await StitchClipFetcher.creationDate(
            forAssetID: "FAKE-IDENTIFIER",
            authStatusProvider: { .denied }
        )

        XCTAssertNil(result, "Denied auth must short-circuit to nil.")
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
        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B", "FAKE-C"],
            authStatusProvider: { .denied }
        )

        XCTAssertEqual(result, [:], "Denied auth must short-circuit batch fetch.")
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
}
