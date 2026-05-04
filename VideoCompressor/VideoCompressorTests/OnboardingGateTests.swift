//
//  OnboardingGateTests.swift
//  VideoCompressorTests
//
//  Pure-logic tests for first-launch onboarding.
//

import XCTest
@testable import VideoCompressor_iOS

final class OnboardingGateTests: XCTestCase {

    func testFreshInstallShouldPresent() {
        let gate = OnboardingGate(hasSeen: false)
        XCTAssertTrue(gate.shouldPresent)
    }

    func testAfterMarkSeenShouldNotPresent() {
        var gate = OnboardingGate(hasSeen: false)
        XCTAssertTrue(gate.shouldPresent)
        gate.markSeen()
        XCTAssertFalse(gate.shouldPresent)
    }

    func testRehydrationFromSeenStateShouldNotPresent() {
        let gate = OnboardingGate(hasSeen: true)
        XCTAssertFalse(gate.shouldPresent)
    }

    func testGetStartedRoutesToMetaClean() {
        let gate = OnboardingGate(hasSeen: false)
        XCTAssertEqual(gate.landingTab, .metaClean)
    }
}
