//
//  MetaMarkerRegistryTests.swift
//  VideoCompressorTests
//
//  Pins the JSON-driven Meta-glasses fingerprint registry.
//

import XCTest
@testable import VideoCompressor_iOS

final class MetaMarkerRegistryTests: XCTestCase {

    func testBundleContainsMetaMarkersJSON() {
        let url = Bundle(for: type(of: self))
            .url(forResource: "MetaMarkers", withExtension: "json")
            ?? Bundle.main.url(forResource: "MetaMarkers", withExtension: "json")

        XCTAssertNotNil(url, "MetaMarkers.json must be present in the app bundle.")
    }
}
