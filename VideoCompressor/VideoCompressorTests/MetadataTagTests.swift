//
//  MetadataTagTests.swift
//  VideoCompressorTests
//
//  Coverage for the MetadataTag value model + StripRules factories.
//  Integration tests for `MetadataService.read(url:)` and `strip(...)`
//  against a real fixture are deferred to commit 6 (UI) — fixture
//  bundling and resource-id wiring is fiddlier than is worth in this
//  patch and the model-level coverage here pins the public contract.
//

import XCTest
@testable import VideoCompressor_iOS

final class MetadataTagTests: XCTestCase {

    // MARK: - StripRules factories

    func testAutoMetaGlassesStripsOnlyCustom() {
        let r = StripRules.autoMetaGlasses
        XCTAssertEqual(r.stripCategories, [.custom])
        XCTAssertTrue(r.stripMetaFingerprintAlways)
    }

    func testStripAllCoversEverythingExceptTechnical() {
        let r = StripRules.stripAll
        XCTAssertTrue(r.stripCategories.contains(.location))
        XCTAssertTrue(r.stripCategories.contains(.device))
        XCTAssertTrue(r.stripCategories.contains(.time))
        XCTAssertTrue(r.stripCategories.contains(.custom))
        XCTAssertFalse(
            r.stripCategories.contains(.technical),
            ".technical is intrinsic media metadata; stripping it would corrupt the file."
        )
        XCTAssertTrue(r.stripMetaFingerprintAlways)
    }

    func testIdentityStripsNothing() {
        let r = StripRules.identity
        XCTAssertTrue(r.stripCategories.isEmpty)
        XCTAssertFalse(r.stripMetaFingerprintAlways)
    }

    // MARK: - StripRules mutation

    func testStripRulesIsValueType() {
        var r = StripRules.identity
        r.stripCategories.insert(.location)
        XCTAssertTrue(r.stripCategories.contains(.location))
        // Original factory unchanged.
        XCTAssertTrue(StripRules.identity.stripCategories.isEmpty)
    }

    // MARK: - MetadataCategory

    func testEveryCategoryHasNonEmptyDisplayName() {
        for category in MetadataCategory.allCases {
            XCTAssertFalse(
                category.displayName.isEmpty,
                "Category \(category.rawValue) should have a non-empty displayName"
            )
        }
    }

    func testEveryCategoryHasNonEmptySFSymbol() {
        for category in MetadataCategory.allCases {
            XCTAssertFalse(
                category.systemImage.isEmpty,
                "Category \(category.rawValue) should have an SF Symbol name"
            )
        }
    }

    func testCategoryAllCasesIsExhaustive() {
        // Pin the case set so adding a new one without updating consumers
        // (StripRules.stripAll, the inspector's group order) flags here.
        XCTAssertEqual(MetadataCategory.allCases.count, 5)
        XCTAssertTrue(MetadataCategory.allCases.contains(.device))
        XCTAssertTrue(MetadataCategory.allCases.contains(.location))
        XCTAssertTrue(MetadataCategory.allCases.contains(.time))
        XCTAssertTrue(MetadataCategory.allCases.contains(.technical))
        XCTAssertTrue(MetadataCategory.allCases.contains(.custom))
    }

    // MARK: - MetadataTag identity

    func testTagsWithSameKeyDifferentIdsAreNotEqual() {
        let a = MetadataTag(
            id: UUID(),
            key: "com.apple.quicktime.location.ISO6709",
            displayName: "Location ISO6709",
            value: "+12.97-077.59/",
            category: .location,
            isMetaFingerprint: false
        )
        let b = MetadataTag(
            id: UUID(),
            key: a.key,
            displayName: a.displayName,
            value: a.value,
            category: a.category,
            isMetaFingerprint: a.isMetaFingerprint
        )
        XCTAssertNotEqual(a, b, "MetadataTag identity is per-instance UUID, not per-key")
    }

    // MARK: - MetadataCleanResult

    func testCleanResultSizeLabelFormatsBytes() {
        let result = MetadataCleanResult(
            cleanedURL: URL(fileURLWithPath: "/tmp/test_CLEAN.mp4"),
            bytes: 1_500_000,
            tagsStripped: [],
            tagsKept: []
        )
        // ByteCountFormatter localises; just assert non-empty + contains
        // a unit suffix to avoid locale flakiness in CI.
        XCTAssertFalse(result.sizeLabel.isEmpty)
        XCTAssertTrue(
            result.sizeLabel.contains("MB") || result.sizeLabel.contains("KB")
                || result.sizeLabel.contains("B"),
            "Expected a byte-unit suffix in \(result.sizeLabel)"
        )
    }
}
