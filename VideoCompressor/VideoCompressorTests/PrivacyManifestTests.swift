//
//  PrivacyManifestTests.swift
//  VideoCompressorTests
//
//  Pins the App Store privacy-manifest contract for Required Reason APIs.
//

import XCTest
@testable import VideoCompressor_iOS

final class PrivacyManifestTests: XCTestCase {

    private func loadManifest() throws -> [String: Any] {
        let appBundle = Bundle(for: VideoLibrary.self)
        guard let url = appBundle.url(
            forResource: "PrivacyInfo",
            withExtension: "xcprivacy"
        ) else {
            XCTFail("PrivacyInfo.xcprivacy not found in app bundle.")
            return [:]
        }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        return plist ?? [:]
    }

    func testManifestExistsAndParses() throws {
        let manifest = try loadManifest()

        XCTAssertFalse(manifest.isEmpty, "Manifest must parse to a non-empty plist.")
    }

    func testManifestDeclaresNoTracking() throws {
        let manifest = try loadManifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((manifest["NSPrivacyTrackingDomains"] as? [String] ?? []).isEmpty)
        XCTAssertTrue((manifest["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)
    }

    func testManifestDeclaresAllRequiredReasonAPIs() throws {
        let manifest = try loadManifest()
        let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let pairs = entries.compactMap { entry -> (String, [String])? in
            guard
                let type = entry["NSPrivacyAccessedAPIType"] as? String,
                let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
            else { return nil }
            return (type, reasons)
        }
        let map = Dictionary(uniqueKeysWithValues: pairs)

        XCTAssertEqual(map["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(map["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
        XCTAssertEqual(map["NSPrivacyAccessedAPICategoryDiskSpace"], ["E174.1"])
    }
}
