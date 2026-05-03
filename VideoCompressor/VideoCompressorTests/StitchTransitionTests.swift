//
//  StitchTransitionTests.swift
//  VideoCompressorTests
//
//  Pin the per-gap transition resolution + display metadata for the
//  StitchTransition enum.
//

import XCTest
@testable import VideoCompressor_iOS

final class StitchTransitionTests: XCTestCase {

    // MARK: - Display metadata

    func testEveryTransitionHasNonEmptyDisplayName() {
        for t in StitchTransition.allCases {
            XCTAssertFalse(t.displayName.isEmpty, "\(t.rawValue) needs a display name")
        }
    }

    func testEveryTransitionHasSystemImage() {
        for t in StitchTransition.allCases {
            XCTAssertFalse(t.systemImage.isEmpty, "\(t.rawValue) needs an SF Symbol")
        }
    }

    func testCaseSetIsExhaustive() {
        // Pinned so adding a new case forces the exporter switch + UI
        // caption updates.
        XCTAssertEqual(StitchTransition.allCases.count, 5)
        XCTAssertTrue(StitchTransition.allCases.contains(.none))
        XCTAssertTrue(StitchTransition.allCases.contains(.crossfade))
        XCTAssertTrue(StitchTransition.allCases.contains(.fadeToBlack))
        XCTAssertTrue(StitchTransition.allCases.contains(.wipeLeft))
        XCTAssertTrue(StitchTransition.allCases.contains(.random))
    }

    func testStandardDuration() {
        XCTAssertEqual(StitchTransition.durationSeconds, 1.0,
                       "Default transition is 1.0s. Changing this is a behaviour change requiring sign-off.")
    }

    // MARK: - Resolve

    func testResolveNoneStaysNone() {
        XCTAssertEqual(StitchExporter.resolveTransition(.none, gapIndex: 0), .none)
        XCTAssertEqual(StitchExporter.resolveTransition(.none, gapIndex: 5), .none)
    }

    func testResolveConcreteVariantPassesThrough() {
        XCTAssertEqual(StitchExporter.resolveTransition(.crossfade, gapIndex: 0), .crossfade)
        XCTAssertEqual(StitchExporter.resolveTransition(.fadeToBlack, gapIndex: 7), .fadeToBlack)
        XCTAssertEqual(StitchExporter.resolveTransition(.wipeLeft, gapIndex: 99), .wipeLeft)
    }

    func testResolveRandomCyclesDeterministically() {
        // Round-robin: gap 0 → crossfade, 1 → fadeToBlack, 2 → wipeLeft,
        // 3 → crossfade, ...
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 0), .crossfade)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 1), .fadeToBlack)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 2), .wipeLeft)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 3), .crossfade)
        XCTAssertEqual(StitchExporter.resolveTransition(.random, gapIndex: 4), .fadeToBlack)
    }

    func testResolveRandomNeverReturnsNoneOrRandom() {
        // Defensive: random should never resolve back to .none or .random.
        for i in 0..<20 {
            let resolved = StitchExporter.resolveTransition(.random, gapIndex: i)
            XCTAssertNotEqual(resolved, .none)
            XCTAssertNotEqual(resolved, .random)
        }
    }

    // MARK: - Project plumbing

    @MainActor
    func testProjectDefaultsToNone() {
        let project = StitchProject()
        XCTAssertEqual(project.transition, .none)
    }
}
