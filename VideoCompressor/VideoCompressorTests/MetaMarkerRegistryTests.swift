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

    func testFalsePositiveGuardRejectsMetaInUserTypedDescription() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.description",
            decodedText: "Meta-data backup",
            isBinarySource: false,
            atomByteCount: nil
        )

        XCTAssertFalse(hit, "User-typed text containing 'meta' must not trigger.")
    }

    func testBinaryAtomBareMetaMarkerInLargePayloadDoesTrigger() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: String(repeating: "x", count: 796) + "meta",
            isBinarySource: true,
            atomByteCount: 800
        )

        XCTAssertTrue(hit, "Binary 800-byte atom containing bare 'meta' must trigger.")
    }

    func testBinaryAtomMetaMarkerInShortPayloadDoesNotTrigger() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: "meta",
            isBinarySource: true,
            atomByteCount: 4
        )

        XCTAssertFalse(hit, "Below minimumMarkerLengthBytes must short-circuit.")
    }

    func testUserTypedMetaWearableInDescriptionDoesNotTrigger() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.description",
            decodedText: "My meta wearable backup from yesterday's hike",
            isBinarySource: false,
            atomByteCount: nil
        )

        XCTAssertFalse(hit, "User-typed text containing a real marker must not trigger.")
    }

    func testRegistryDetectsLegacyRayBanMarker() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: "Ray-Ban Stories",
            isBinarySource: true,
            atomByteCount: 32
        )

        XCTAssertTrue(hit)
    }

    func testStringBackedLegacyRayBanDescriptionStillTriggers() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.description",
            decodedText: "Ray-Ban Stories",
            isBinarySource: false,
            atomByteCount: nil
        )

        XCTAssertTrue(hit, "String-backed legacy Ray-Ban tags must still trigger.")
    }

    func testRegistryRejectsKeyOutsideCommentDescription() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.location.ISO6709",
            decodedText: "Ray-Ban",
            isBinarySource: true,
            atomByteCount: 32
        )

        XCTAssertFalse(hit, "Detector only matches comment/description atoms.")
    }

    func testXMPFingerprintTriggersOnRegistryMarker() async {
        let hit = await PhotoMetadataService.xmpContainsFingerprint(
            "<x:xmpmeta>...xmp.MetaAI...</x:xmpmeta>",
            packetByteCount: 256
        )

        XCTAssertTrue(hit)
    }

    func testXMPFingerprintTriggersOnMetaAiMarker() async {
        let hit = await PhotoMetadataService.xmpContainsFingerprint(
            "<x:xmpmeta>Meta AI capture marker</x:xmpmeta>",
            packetByteCount: 256
        )

        XCTAssertTrue(hit)
    }

    func testXMPFingerprintTriggersOnMetaWearableMarker() async {
        let hit = await PhotoMetadataService.xmpContainsFingerprint(
            "<x:xmpmeta>Meta wearable capture marker</x:xmpmeta>",
            packetByteCount: 256
        )

        XCTAssertTrue(hit)
    }

    func testXMPFingerprintRejectsBelowMinimumLength() async {
        let hit = await PhotoMetadataService.xmpContainsFingerprint(
            "meta:",
            packetByteCount: 5
        )

        XCTAssertFalse(hit, "Tiny XMP packets below the minimum length must not trigger.")
    }

    func testMakerAppleSoftwareDetectsOakleyMeta() async {
        let hit = await PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple",
            key: "Software",
            value: "Oakley Meta v1.0"
        )

        XCTAssertTrue(hit, "Oakley Meta must be detected via registry expansion.")
    }

    func testMakerAppleSoftwareRejectsIPhone() async {
        let hit = await PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple",
            key: "Software",
            value: "iPhone 15 Pro"
        )

        XCTAssertFalse(hit)
    }

    // MARK: - Task 5 - category coverage + Oakley regression

    func testRegistryExposesDeviceModelHints() async {
        let markers = await MetaMarkerRegistry.shared.load()

        XCTAssertTrue(markers.deviceModelHints.contains("RB-1"))
        XCTAssertTrue(markers.deviceModelHints.contains("RB-2"))
        XCTAssertTrue(markers.deviceModelHints.contains("OM-1"))
    }

    func testRegistryHasOakleyInMakerAppleSoftware() async {
        let markers = await MetaMarkerRegistry.shared.load()

        XCTAssertTrue(
            markers.makerAppleSoftware.contains(where: { $0.lowercased() == "oakley meta" }),
            "Oakley Meta must be in the bundled registry's makerAppleSoftware list."
        )
    }

    func testBinaryAtomMarkersCoverCommentAndDescription() async {
        let markers = await MetaMarkerRegistry.shared.load()

        XCTAssertNotNil(markers.binaryAtomMarkers["comment"])
        XCTAssertNotNil(markers.binaryAtomMarkers["description"])
        XCTAssertTrue(markers.binaryAtomMarkers["comment"]?.contains("ray-ban") ?? false)
    }

    func testGuardsAreParsedFromJSON() async {
        let guards = await MetaMarkerRegistry.shared.guards()

        XCTAssertEqual(guards.minimumMarkerLengthBytes, 8)
        XCTAssertTrue(guards.rejectIfMarkerInUserTypedText.contains("comment"))
        XCTAssertTrue(guards.rejectIfMarkerInUserTypedText.contains("description"))
    }

    func testRegistryIsCachedAcrossLoads() async {
        let firstLoad = await MetaMarkerRegistry.shared.load()
        let secondLoad = await MetaMarkerRegistry.shared.load()

        XCTAssertEqual(firstLoad, secondLoad)
    }
}
