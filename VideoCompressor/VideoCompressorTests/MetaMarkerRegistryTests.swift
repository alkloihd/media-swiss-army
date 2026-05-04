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

    func testRegistryLoadsFromBundle() async {
        let markers = await MetaMarkerRegistry.shared.load()

        XCTAssertEqual(markers.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(markers.version, 1)
        XCTAssertFalse(markers.binaryAtomMarkers.isEmpty)
        XCTAssertFalse(markers.xmpFingerprints.isEmpty)
        XCTAssertTrue(markers.makerAppleSoftware.contains("Oakley Meta"))
    }

    func testRegistryDefaultBundledIsLegacySubset() {
        let fallback = MetaMarkerRegistry.defaultBundled()

        XCTAssertFalse(
            fallback.makerAppleSoftware.contains(where: { $0.lowercased().contains("oakley") }),
            "Fallback must not contain post-registry Oakley markers."
        )
        XCTAssertFalse(
            fallback.deviceModelHints.contains("OM-1"),
            "Fallback must not contain post-registry OM-1 hints."
        )
        XCTAssertTrue(fallback.binaryAtomMarkers["comment"]?.contains("meta") ?? false)
        XCTAssertTrue(fallback.xmpFingerprints.contains("ray-ban"))
        XCTAssertTrue(fallback.xmpFingerprints.contains("c2pa"))
        XCTAssertTrue(fallback.makerAppleSoftware.contains("meta"))
    }

    func testParseOrFallbackReturnsDefaultWhenDataIsNil() {
        let result = MetaMarkerRegistry.parseOrFallback(data: nil)

        XCTAssertEqual(result, MetaMarkerRegistry.defaultBundled())
    }

    func testParseOrFallbackReturnsDefaultOnGarbageData() {
        let result = MetaMarkerRegistry.parseOrFallback(data: Data("{ not json".utf8))

        XCTAssertEqual(result, MetaMarkerRegistry.defaultBundled())
    }

    func testParseOrFallbackReturnsDefaultOnSchemaVersionMismatch() {
        let payload = """
        {
          "schemaVersion": 2,
          "version": 99,
          "binaryAtomMarkers": {"comment": ["future"]},
          "xmpFingerprints": ["future"],
          "makerAppleSoftware": ["Future Device"],
          "deviceModelHints": ["FU-1"],
          "falsePositiveGuards": {
            "rejectIfMarkerInUserTypedText": ["comment"],
            "minimumMarkerLengthBytes": 16
          }
        }
        """

        let result = MetaMarkerRegistry.parseOrFallback(data: Data(payload.utf8))

        XCTAssertEqual(result, MetaMarkerRegistry.defaultBundled())
    }
}
