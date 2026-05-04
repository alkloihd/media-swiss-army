//
//  ReviewPrompterTests.swift
//  VideoCompressorTests
//
//  Pure-logic and dependency-injected tests for review prompt eligibility.
//

import XCTest
@testable import VideoCompressor_iOS

@MainActor
final class ReviewPrompterTests: XCTestCase {

    func testDoesNotPromptWhenCountBelowThreshold() {
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 0,
            lastVersion: nil,
            currentVersion: "1.0"
        ))
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 1,
            lastVersion: nil,
            currentVersion: "1.0"
        ))
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 2,
            lastVersion: nil,
            currentVersion: "1.0"
        ))
    }

    func testPromptsAtThresholdOnFirstEligibleVersion() {
        XCTAssertTrue(ReviewPrompter.shouldPrompt(
            count: 3,
            lastVersion: nil,
            currentVersion: "1.0"
        ))
    }

    func testPromptsBeyondThresholdWhenStillSameVersion() {
        XCTAssertTrue(ReviewPrompter.shouldPrompt(
            count: 5,
            lastVersion: nil,
            currentVersion: "1.0"
        ))
    }

    func testDoesNotRePromptOnSameVersion() {
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 4,
            lastVersion: "1.0",
            currentVersion: "1.0"
        ))
    }

    func testRePromptsOnNewVersion() {
        XCTAssertTrue(ReviewPrompter.shouldPrompt(
            count: 4,
            lastVersion: "1.0",
            currentVersion: "1.1"
        ))
    }

    func testRecordSuccessesPromptsWhenCrossingThreshold() {
        let defaults = makeDefaults()
        var requestCount = 0
        let prompter = ReviewPrompter(
            defaults: defaults,
            currentVersionProvider: { "1.0" },
            reviewRequester: {
                requestCount += 1
                return true
            }
        )

        prompter.recordSuccessesAndMaybePrompt(2)
        XCTAssertEqual(requestCount, 0)

        prompter.recordSuccessesAndMaybePrompt(1)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(defaults.integer(forKey: ReviewPrompter.successCountKey), 3)
        XCTAssertEqual(defaults.string(forKey: ReviewPrompter.lastPromptVersionKey), "1.0")
    }

    func testRecordSuccessesDoesNotRePromptSameVersion() {
        let defaults = makeDefaults()
        var requestCount = 0
        let prompter = ReviewPrompter(
            defaults: defaults,
            currentVersionProvider: { "1.0" },
            reviewRequester: {
                requestCount += 1
                return true
            }
        )

        prompter.recordSuccessesAndMaybePrompt(3)
        prompter.recordSuccessesAndMaybePrompt(5)

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(defaults.integer(forKey: ReviewPrompter.successCountKey), 8)
    }

    func testRecordSuccessesRePromptsOnNewVersion() {
        let defaults = makeDefaults()
        var version = "1.0"
        var requestCount = 0
        let prompter = ReviewPrompter(
            defaults: defaults,
            currentVersionProvider: { version },
            reviewRequester: {
                requestCount += 1
                return true
            }
        )

        prompter.recordSuccessesAndMaybePrompt(3)
        version = "1.1"
        prompter.recordSuccessesAndMaybePrompt(1)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(defaults.string(forKey: ReviewPrompter.lastPromptVersionKey), "1.1")
    }

    func testRecordSuccessesIgnoresNonPositiveCounts() {
        let defaults = makeDefaults()
        var requestCount = 0
        let prompter = ReviewPrompter(
            defaults: defaults,
            currentVersionProvider: { "1.0" },
            reviewRequester: {
                requestCount += 1
                return true
            }
        )

        prompter.recordSuccessesAndMaybePrompt(0)
        prompter.recordSuccessesAndMaybePrompt(-4)

        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(defaults.integer(forKey: ReviewPrompter.successCountKey), 0)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "ReviewPrompterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
