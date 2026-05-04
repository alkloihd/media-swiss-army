//
//  ReviewPrompter.swift
//  VideoCompressor
//
//  Apple-approved review prompt gate: ask only after successful MetaClean
//  saves, and at most once per app version.
//

import Foundation
import StoreKit
import UIKit

@MainActor
final class ReviewPrompter {
    static let shared = ReviewPrompter()
    static let promptThreshold = 3
    static let successCountKey = "successfulCleanCount"
    static let lastPromptVersionKey = "lastReviewPromptVersion"

    private let defaults: UserDefaults
    private let currentVersionProvider: @MainActor () -> String
    private let reviewRequester: @MainActor () -> Bool

    init(
        defaults: UserDefaults = .standard,
        currentVersionProvider: @escaping @MainActor () -> String = {
            ReviewPrompter.appVersion()
        },
        reviewRequester: @escaping @MainActor () -> Bool = {
            ReviewPrompter.requestReviewInForegroundScene()
        }
    ) {
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider
        self.reviewRequester = reviewRequester
    }

    static func shouldPrompt(
        count: Int,
        lastVersion: String?,
        currentVersion: String
    ) -> Bool {
        guard count >= promptThreshold else { return false }
        return (lastVersion ?? "") != currentVersion
    }

    func recordSuccessesAndMaybePrompt(_ successes: Int = 1) {
        guard successes > 0 else { return }

        let nextCount = defaults.integer(forKey: Self.successCountKey) + successes
        defaults.set(nextCount, forKey: Self.successCountKey)

        let version = currentVersionProvider()
        let lastVersion = defaults.string(forKey: Self.lastPromptVersionKey)
        guard Self.shouldPrompt(
            count: nextCount,
            lastVersion: lastVersion,
            currentVersion: version
        ) else { return }

        guard reviewRequester() else { return }
        defaults.set(version, forKey: Self.lastPromptVersionKey)
    }

    private nonisolated static func appVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    private static func requestReviewInForegroundScene() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            return false
        }

        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
        return true
    }
}
