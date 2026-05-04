# Phase 3 Cluster 4 — App Store Hardening

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. All steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Media Swiss Army from "engineering-grade" to "App Store submission-ready." Five tasks land in one PR:
- 3.1 (TASK-34) — Add the Apple-required `PrivacyInfo.xcprivacy` manifest declaring the three Required-Reason API categories the app actually uses.
- 3.2 (TASK-35) — Gate `StitchClipFetcher`'s two `PHAsset.fetchAssets` call sites on `PHPhotoLibrary.authorizationStatus(for: .readWrite)` so the silent-elevation bug from `AUDIT-03` HIGH-2 is closed.
- 3.3 (TASK-18) — Extend `.github/workflows/ci.yml` with an `ios-tests` job that runs `xcodebuild test` on `macos-26`. Becomes a required PR check.
- 3.4 (TASK-07) — Publish the privacy policy as static HTML on GitHub Pages and link to it from the Settings tab.
- 3.5 (TASK-09) — Add an `SKStoreReviewController` review prompt fired after the user's third successful clean (Apple-approved gate).

**Branch:** `feat/codex-cluster4-appstore-hardening` off `feat/phase-2-features-may3` (NOT off `main` — cluster 4 lands on top of cluster 3's UX polish so the Settings tab already has the structure for the new Privacy Policy row).

**Tech Stack:** Swift, plist (XML), GitHub Actions YAML, HTML, StoreKit (`SKStoreReviewController`), XCTest.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/PrivacyInfo.xcprivacy` | **Create** | Plist declaring `NSPrivacyAccessedAPITypes` (UserDefaults `CA92.1`, FileTimestamp `C617.1`, DiskSpace `E174.1`), `NSPrivacyTracking=false`, empty tracking domains, empty data collected. Auto-included by `PBXFileSystemSynchronizedRootGroup`. |
| `VideoCompressor/ios/Services/StitchClipFetcher.swift` | Modify | Inject `authStatusProvider` closure (default = real `PHPhotoLibrary.authorizationStatus`). Both `creationDate(forAssetID:)` (line 32) and `creationDates(forAssetIDs:)` (line 50) early-return when status is `.denied` / `.restricted` / `.notDetermined`. |
| `.github/workflows/ci.yml` | Modify | Append `ios-tests` job: `runs-on: macos-26`, runs `xcodebuild test -scheme VideoCompressor_iOS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:VideoCompressorTests`. |
| `docs/privacy/index.html` | **Create** | Static HTML page hosting the privacy policy verbatim from `.agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md` Part 8. |
| `VideoCompressor/ios/Views/SettingsTabView.swift` | Modify | Add a "Privacy Policy" row that opens `https://alkloihd.github.io/media-swiss-army/privacy/` via `Link` (Safari View Controller / system browser). |
| `VideoCompressor/ios/Services/ReviewPrompter.swift` | **Create** | Pure-logic actor with `@AppStorage("successfulCleanCount")` + `@AppStorage("lastReviewPromptVersion")`. Exposes `shouldPrompt(count:lastVersion:currentVersion:) -> Bool` (testable) and `requestReviewIfReady()` (calls `SKStoreReviewController.requestReview(in: scene)`). |
| `VideoCompressor/ios/Services/MetaCleanQueue.swift` | Modify | On `completion(.success(...))` (line ~128), call `ReviewPrompter.shared.recordSuccessAndMaybePrompt()`. |
| `VideoCompressor/VideoCompressorTests/PrivacyManifestTests.swift` | **Create** | Loads `PrivacyInfo.xcprivacy` from the bundle, asserts it parses, contains all three reason codes, and `NSPrivacyTracking == false`. |
| `VideoCompressor/VideoCompressorTests/StitchClipFetcherAuthTests.swift` | **Create** | Injects a fake auth-status closure → asserts both `creationDate` and `creationDates` return nil/empty for `.denied`, `.restricted`, `.notDetermined`. |
| `VideoCompressor/VideoCompressorTests/ReviewPrompterTests.swift` | **Create** | Pure-logic tests for `shouldPrompt(count:lastVersion:currentVersion:)`. |

**Test count baseline:** cluster 1 lands +11 tests, cluster 2 lands +4 tests, cluster 3 lands ~+5 tests. Use `BASELINE` as the prior cluster's final passing count and add the cluster-4 deltas (`+8` total: 1 manifest + 2 stitch-fetcher + 5 review-prompter). Don't pin to absolute numbers — see "Notes for the executing agent" below.

---

## Task 1: PrivacyInfo.xcprivacy manifest (Phase 3.1 / TASK-34)

**Why:** Apple has required a `PrivacyInfo.xcprivacy` manifest since spring 2024 for any app that uses **Required Reason APIs**. The audit (`AUDIT-03` HIGH-1) catalogued our three:

| API category | Apple reason code | Our usage |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (access info from same app) | `Services/AudioBackgroundKeeper.swift:30`, `Views/SettingsTabView.swift:14`, `Views/PresetPickerView.swift:17` |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` (display content to person using device) | `Services/CacheSweeper.swift:109,113` |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` (write or delete file on user's device) | `Services/VideoLibrary.swift:281,307,325`, `CompressionService.swift` (file-size reads) |

Without the manifest, App Store Connect surfaces a privacy-manifest warning during submission and Apple may auto-reject in the future.

- [ ] **Step 1: Write a failing test that asserts the manifest exists, parses, and contains all three reason codes**

Create `VideoCompressor/VideoCompressorTests/PrivacyManifestTests.swift`:

```swift
//
//  PrivacyManifestTests.swift
//  VideoCompressorTests
//
//  Pins the contract Apple requires for App Store privacy review:
//  the bundled PrivacyInfo.xcprivacy plist must declare reason codes
//  for every Required-Reason API the app uses, plus NSPrivacyTracking=false.
//

import XCTest
@testable import VideoCompressor_iOS

final class PrivacyManifestTests: XCTestCase {

    /// Loads and parses the bundled PrivacyInfo.xcprivacy plist.
    private func loadManifest() throws -> [String: Any] {
        // The .xcprivacy is auto-bundled into the app target via the
        // PBXFileSystemSynchronizedRootGroup. The test target hosts the
        // app, so Bundle(for: VideoLibrary.self) resolves to the app
        // bundle that contains the manifest.
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
            from: data, options: [], format: nil
        ) as? [String: Any]
        return plist ?? [:]
    }

    func testManifestExistsAndParses() throws {
        let m = try loadManifest()
        XCTAssertFalse(m.isEmpty, "Manifest must parse to a non-empty plist.")
    }

    func testManifestDeclaresNoTracking() throws {
        let m = try loadManifest()
        XCTAssertEqual(
            m["NSPrivacyTracking"] as? Bool, false,
            "App does not track users — manifest must declare NSPrivacyTracking=false."
        )
        let domains = m["NSPrivacyTrackingDomains"] as? [String] ?? []
        XCTAssertTrue(domains.isEmpty, "Tracking domains must be empty.")
        let collected = m["NSPrivacyCollectedDataTypes"] as? [Any] ?? []
        XCTAssertTrue(collected.isEmpty, "Collected data types must be empty.")
    }

    func testManifestDeclaresAllRequiredReasonAPIs() throws {
        let m = try loadManifest()
        let entries = m["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let pairs = entries.compactMap { entry -> (String, [String])? in
            guard
                let type = entry["NSPrivacyAccessedAPIType"] as? String,
                let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
            else { return nil }
            return (type, reasons)
        }
        let map = Dictionary(uniqueKeysWithValues: pairs)

        XCTAssertEqual(
            map["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"],
            "UserDefaults must declare CA92.1 (access info from same app)."
        )
        XCTAssertEqual(
            map["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"],
            "FileTimestamp must declare C617.1 (display content to user)."
        )
        XCTAssertEqual(
            map["NSPrivacyAccessedAPICategoryDiskSpace"], ["E174.1"],
            "DiskSpace must declare E174.1 (write or delete file on user's device)."
        )
    }
}
```

Run:

```
mcp__xcodebuildmcp__test_sim
```

Expected: 3 new tests **fail** (manifest not present yet). That is the TDD red.

- [ ] **Step 2: Create the privacy manifest**

Create `VideoCompressor/ios/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>E174.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

The file is auto-included in the app target by `PBXFileSystemSynchronizedRootGroup` (no `pbxproj` edit needed). If the new file doesn't show up in the bundle on first build, run `mcp__xcodebuildmcp__clean` then re-test.

- [ ] **Step 3: Run tests**

```
mcp__xcodebuildmcp__clean
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE+3, Passed: BASELINE+3, Failed: 0`. The three privacy-manifest tests now pass.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/PrivacyInfo.xcprivacy \
        VideoCompressor/VideoCompressorTests/PrivacyManifestTests.swift
git commit -m "feat(privacy): add PrivacyInfo.xcprivacy manifest (Phase 3.1 / TASK-34)

Resolves AUDIT-03 HIGH-1. Apple has required a privacy manifest since
spring 2024 for any app using Required Reason APIs. The app uses three:
- UserDefaults (CA92.1 — access info from same app)
- FileTimestamp (C617.1 — display content to person using device)
- DiskSpace (E174.1 — write or delete file on user's device)

NSPrivacyTracking=false; tracking domains and collected data types both
empty (zero analytics, zero network, zero third-party SDKs).

The file is auto-bundled via PBXFileSystemSynchronizedRootGroup; no
pbxproj change required.

Three new XCTests parse the bundled plist and pin the reason codes."
```

**Effort: ~1h. ~1 commit cumulatively.**

---

## Task 2: Photos auth gate in StitchClipFetcher (Phase 3.2 / TASK-35)

**Why:** `AUDIT-03` HIGH-2. `StitchClipFetcher.creationDate(forAssetID:)` (line 32) and `creationDates(forAssetIDs:)` (line 50) both call `PHAsset.fetchAssets(withLocalIdentifiers:options:)` directly with no preceding `PHPhotoLibrary.authorizationStatus(for: .readWrite)` check. If a user has previously authorised `.readWrite` for the delete-original flow (see canonical pattern in `Services/PhotosSaver.swift:88-90`), this code reads `localIdentifier`s the user did not consent to expose to the Stitch flow specifically — and on iOS 16+ this is a silent elevation surprise.

The fix gates both call sites on the read-write authorisation status, returning the safe "no Photos data" answer (`nil` or `[:]`) when the user hasn't consented.

The design choice for testability: inject an `authStatusProvider` closure with a default that calls the real `PHPhotoLibrary.authorizationStatus(for: .readWrite)`. Tests pass a fake closure to drive every branch; production keeps zero behavioural change for already-authorised users.

- [ ] **Step 1: Write failing tests for both fetch paths and three denied-status states**

Create `VideoCompressor/VideoCompressorTests/StitchClipFetcherAuthTests.swift`:

```swift
//
//  StitchClipFetcherAuthTests.swift
//  VideoCompressorTests
//
//  Pins AUDIT-03 HIGH-2 fix: both fetch paths must early-return the
//  "no data" answer when Photos read-write authorisation is anything
//  other than .authorized or .limited.
//

import XCTest
import Photos
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
        XCTAssertNil(result, "Not-determined auth must NOT trigger a silent prompt; return nil.")
    }

    func testBatchCreationDatesReturnsEmptyWhenAuthDenied() async {
        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B", "FAKE-C"],
            authStatusProvider: { .denied }
        )
        XCTAssertEqual(result, [:],
            "Denied auth must short-circuit batch fetch to empty dict.")
    }

    func testBatchCreationDatesReturnsEmptyWhenAuthNotDetermined() async {
        let result = await StitchClipFetcher.creationDates(
            forAssetIDs: ["FAKE-A", "FAKE-B"],
            authStatusProvider: { .notDetermined }
        )
        XCTAssertEqual(result, [:],
            "Not-determined auth must NOT trigger a silent prompt; return empty dict.")
    }
}
```

These reference an `authStatusProvider:` parameter that doesn't exist yet. Build fails at compile time — that's the TDD red.

- [ ] **Step 2: Refactor `StitchClipFetcher` to accept the injectable status closure**

Replace the body of `VideoCompressor/ios/Services/StitchClipFetcher.swift` with:

```swift
//
//  StitchClipFetcher.swift
//  VideoCompressor
//
//  Looks up Photos library metadata (creation date primarily) for a
//  given asset identifier. Used at import time to capture each clip's
//  date so the user can later "Sort by date taken" without re-picking.
//
//  Phase 3.2 (TASK-35 / AUDIT-03 HIGH-2): every call site is now gated
//  on PHPhotoLibrary.authorizationStatus(for: .readWrite). The previous
//  code called PHAsset.fetchAssets unconditionally, which on iOS 16+
//  silently consumed any prior .readWrite grant the user gave for the
//  delete-original flow — surprising elevation. Now both paths return
//  the safe "no data" answer (nil or [:]) when the user has not
//  consented to .readWrite. The auth status is passed in as a closure
//  so tests can drive every branch without touching real Photos state.
//

import Foundation
import Photos

enum StitchClipFetcher {

    /// Default provider closure used by production callers. Tests inject
    /// a fake to drive `.denied` / `.restricted` / `.notDetermined` paths.
    static let liveAuthStatusProvider: @Sendable () -> PHAuthorizationStatus = {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private static func authorizedToRead(
        _ provider: @Sendable () -> PHAuthorizationStatus
    ) -> Bool {
        let status = provider()
        return status == .authorized || status == .limited
    }

    /// Best-effort lookup of `PHAsset.creationDate` for the given asset
    /// identifier. Returns nil when:
    /// - assetID is nil (not a Photos-library import)
    /// - Photos read-write auth is not .authorized or .limited
    /// - the user has limited Photos access and didn't grant this asset
    /// - the asset was deleted between import and lookup
    /// - any other Photos error
    static func creationDate(
        forAssetID assetID: String?,
        authStatusProvider: @Sendable () -> PHAuthorizationStatus = liveAuthStatusProvider
    ) async -> Date? {
        guard let assetID = assetID else { return nil }
        guard authorizedToRead(authStatusProvider) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetID],
                options: nil
            )
            guard let asset = result.firstObject else { return nil as Date? }
            return asset.creationDate
        }.value
    }

    /// BATCH variant — single Photos fetch resolves N asset IDs in one go.
    /// Used by `StitchProject.sortByCreationDate` so a 50-clip sort doesn't
    /// fire 50 separate Photos lookups. Returns a [assetID: Date] dict.
    /// Missing / inaccessible assets map to absent (caller treats them as
    /// "no date"). nil-valued asset IDs in input are skipped. Empty dict
    /// when Photos read-write auth is not .authorized or .limited.
    static func creationDates(
        forAssetIDs assetIDs: [String],
        authStatusProvider: @Sendable () -> PHAuthorizationStatus = liveAuthStatusProvider
    ) async -> [String: Date] {
        let unique = Array(Set(assetIDs.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }
        guard authorizedToRead(authStatusProvider) else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: unique,
                options: nil
            )
            var out: [String: Date] = [:]
            result.enumerateObjects { asset, _, _ in
                if let date = asset.creationDate {
                    out[asset.localIdentifier] = date
                }
            }
            return out
        }.value
    }
}
```

Note: the call sites in `StitchProject.swift` (line ~162 per AUDIT-03) continue to compile because the new parameter has a default value. No call-site edit needed.

- [ ] **Step 3: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE+8, Passed: BASELINE+8, Failed: 0` (5 new auth-gate tests + 3 manifest tests from Task 1).

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Services/StitchClipFetcher.swift \
        VideoCompressor/VideoCompressorTests/StitchClipFetcherAuthTests.swift
git commit -m "fix(stitch): gate Photos fetch on .readWrite auth (Phase 3.2 / TASK-35)

Resolves AUDIT-03 HIGH-2. Both creationDate(forAssetID:) and the
batch creationDates(forAssetIDs:) variant now early-return nil / [:]
when PHPhotoLibrary.authorizationStatus(for: .readWrite) is not
.authorized or .limited.

Mirrors the existing pattern in PhotosSaver.swift:88-90 (canonical
.readWrite gate). The auth lookup is injected as a closure with a
production default so XCTests can drive .denied / .restricted /
.notDetermined branches without touching real Photos state.

5 new tests pin all three denied paths across both fetch variants."
```

**Effort: ~30 min. ~2 commits cumulatively.**

---

## Task 3: ReviewPrompter + integration with MetaCleanQueue (Phase 3.5 / TASK-09)

**Why:** Apple-approved gating pattern: prompt for an App Store review only after the user successfully completes a meaningful interaction (per Apple HIG: "Don't interrupt users who are engaged in a task"). The de-facto industry threshold is 3 successful uses of the headline feature; the lock is per-version (so a user who declined for v1.0 isn't re-prompted on v1.0, but IS eligible on v1.1).

The design splits **pure-logic eligibility** (testable) from **the UIKit/StoreKit side-effect** (untestable in unit context).

- [ ] **Step 1: Write failing tests for the eligibility logic**

Create `VideoCompressor/VideoCompressorTests/ReviewPrompterTests.swift`:

```swift
//
//  ReviewPrompterTests.swift
//  VideoCompressorTests
//
//  Pure-logic tests for ReviewPrompter.shouldPrompt(...). The actual
//  SKStoreReviewController.requestReview(in: scene) call is not unit-
//  testable; this suite covers the gating logic behind it.
//

import XCTest
@testable import VideoCompressor_iOS

final class ReviewPrompterTests: XCTestCase {

    func testDoesNotPromptWhenCountBelowThreshold() {
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 0, lastVersion: nil, currentVersion: "1.0"
        ))
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 1, lastVersion: nil, currentVersion: "1.0"
        ))
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 2, lastVersion: nil, currentVersion: "1.0"
        ))
    }

    func testPromptsAtThresholdOnFirstEligibleVersion() {
        XCTAssertTrue(ReviewPrompter.shouldPrompt(
            count: 3, lastVersion: nil, currentVersion: "1.0"
        ))
    }

    func testPromptsBeyondThresholdWhenStillSameVersion() {
        XCTAssertTrue(ReviewPrompter.shouldPrompt(
            count: 5, lastVersion: nil, currentVersion: "1.0"
        ))
    }

    func testDoesNotRePromptOnSameVersion() {
        XCTAssertFalse(ReviewPrompter.shouldPrompt(
            count: 4, lastVersion: "1.0", currentVersion: "1.0"
        ))
    }

    func testRePromptsOnNewVersion() {
        XCTAssertTrue(ReviewPrompter.shouldPrompt(
            count: 4, lastVersion: "1.0", currentVersion: "1.1"
        ))
    }
}
```

Build fails (no `ReviewPrompter` type yet). TDD red.

- [ ] **Step 2: Implement `ReviewPrompter`**

Create `VideoCompressor/ios/Services/ReviewPrompter.swift`:

```swift
//
//  ReviewPrompter.swift
//  VideoCompressor
//
//  Phase 3.5 (TASK-09): Apple-approved review prompt via
//  SKStoreReviewController, gated behind 3 successful MetaClean
//  completions and not-yet-prompted-on-this-version. iOS 17+ uses
//  the (in: scene) overload; iOS 18 introduced StoreKit 2's
//  `AppStore.requestReview`, but our deployment target is 17 so we
//  stay on the SKStoreReviewController path.
//

import SwiftUI
import StoreKit
import UIKit

@MainActor
final class ReviewPrompter {

    static let shared = ReviewPrompter()

    /// Number of successful cleans required before the first prompt.
    /// Apple's HIG suggests "after a meaningful interaction"; 3 is the
    /// industry standard for utility apps.
    static let promptThreshold = 3

    @AppStorage("successfulCleanCount") private var successfulCleanCount = 0
    @AppStorage("lastReviewPromptVersion") private var lastReviewPromptVersion = ""

    private init() {}

    /// Pure-logic eligibility check. Exposed static so XCTests can drive
    /// every branch without touching @AppStorage / UIKit.
    static func shouldPrompt(
        count: Int,
        lastVersion: String?,
        currentVersion: String
    ) -> Bool {
        guard count >= promptThreshold else { return false }
        return (lastVersion ?? "") != currentVersion
    }

    /// Increment the success counter and, if eligible, fire the system
    /// review prompt. Safe to call from any MainActor context after a
    /// successful MetaClean.
    func recordSuccessAndMaybePrompt() {
        successfulCleanCount += 1
        let version = Self.appVersion()
        let last = lastReviewPromptVersion.isEmpty ? nil : lastReviewPromptVersion
        guard Self.shouldPrompt(
            count: successfulCleanCount,
            lastVersion: last,
            currentVersion: version
        ) else { return }

        guard let scene = Self.foregroundScene() else { return }
        SKStoreReviewController.requestReview(in: scene)
        lastReviewPromptVersion = version
    }

    private static func appVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    private static func foregroundScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }
}
```

- [ ] **Step 3: Wire into `MetaCleanQueue.runClean` success completion**

In `VideoCompressor/ios/Services/MetaCleanQueue.swift`, around line 127–128:

```swift
            cleanState = .finished(result)
            completion(.success(result))
```

Replace with:

```swift
            cleanState = .finished(result)
            // Phase 3.5 (TASK-09): record the successful clean and, if
            // the user has now reached the prompt threshold AND we
            // haven't asked them on this app version yet, fire the
            // SKStoreReviewController prompt. Safe no-op otherwise.
            // Note: MetaCleanQueue is @MainActor at the class level (line 18),
            // so runClean is already main-actor-isolated. ReviewPrompter is also
            // @MainActor. This is a direct call — no await MainActor.run wrapper needed.
            ReviewPrompter.shared.recordSuccessAndMaybePrompt()
            completion(.success(result))
```

- [ ] **Step 4: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE+13, Passed: BASELINE+13, Failed: 0` (5 new ReviewPrompter tests + 5 from Task 2 + 3 from Task 1).

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Services/ReviewPrompter.swift \
        VideoCompressor/ios/Services/MetaCleanQueue.swift \
        VideoCompressor/VideoCompressorTests/ReviewPrompterTests.swift
git commit -m "feat(review): SKStoreReviewController prompt after 3 cleans (Phase 3.5 / TASK-09)

Apple-approved gating pattern: prompt only after a meaningful
interaction (3 successful MetaClean completions) and at most once
per app version (@AppStorage(\"lastReviewPromptVersion\") clamps).

ReviewPrompter splits pure-logic eligibility (shouldPrompt static
helper, fully unit-tested across 5 cases) from the UIKit/StoreKit
side-effect (requestReview(in: scene), iOS-17 overload). The
foreground-scene lookup mirrors the existing UIApplication.shared
pattern used elsewhere in the codebase.

Wired into MetaCleanQueue.runClean's success completion."
```

**Effort: ~30 min. ~3 commits cumulatively.**

---

## Task 4: Privacy policy on GitHub Pages + Settings link (Phase 3.4 / TASK-07)

> ✅ **H6 RESOLVED 2026-05-04** — repo renamed from `video-compressor-FUCKMETA` → `media-swiss-army`. Privacy policy URL is now `https://alkloihd.github.io/media-swiss-army/privacy/` — clean, no profanity, App Review safe. The only remaining manual step is **enabling GitHub Pages** in repo Settings → Pages → Source: `main` branch, `/docs` folder. Codex may now execute Task 4 in full.

**Why:** Apple App Store Connect requires a privacy policy URL before submission (App Store Review Guideline 5.1.1). The reference doc `.agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md` Part 8 has the verbatim policy template. We host it on GitHub Pages on the existing repo (`alkloihd/media-swiss-army`) and link to it from the Settings tab so the in-app surface and the App Store Connect entry both point to the same canonical URL.

**Locked URL:** `https://alkloihd.github.io/media-swiss-army/privacy/`. (The reference doc has a stale `alkloihd.github.io/metaclean/privacy` URL — ignore; the locked decision wins, and matches the actual repo name from `AGENTS.md` 16.2.)

- [ ] **Step 1: Create the static HTML page**

Create `docs/privacy/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Media Swiss Army &mdash; Privacy Policy</title>
<style>
  :root {
    color-scheme: light dark;
    --fg: #1c1c1e;
    --bg: #ffffff;
    --accent: #007aff;
  }
  @media (prefers-color-scheme: dark) {
    :root { --fg: #f2f2f7; --bg: #1c1c1e; --accent: #0a84ff; }
  }
  html, body {
    margin: 0; padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif;
    color: var(--fg);
    background: var(--bg);
    line-height: 1.55;
  }
  main {
    max-width: 720px;
    margin: 0 auto;
    padding: 2.5rem 1.25rem 4rem;
  }
  h1 { font-size: 1.875rem; margin-top: 0; }
  h2 { font-size: 1.25rem; margin-top: 2rem; }
  p, ul { font-size: 1rem; }
  ul { padding-left: 1.25rem; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .updated { color: #8e8e93; font-size: 0.9rem; margin-top: 0.25rem; }
  footer { margin-top: 3rem; font-size: 0.85rem; color: #8e8e93; }
</style>
</head>
<body>
<main>
  <h1>Media Swiss Army &mdash; Privacy Policy</h1>
  <p class="updated"><strong>Last updated: 2026-05-04</strong></p>

  <p>Media Swiss Army (the &ldquo;App&rdquo;) does not collect, store, transmit, or share your data. We do not have a server.</p>

  <h2>What the App accesses</h2>
  <ul>
    <li><strong>Your Photos library</strong>, after you grant permission, so you can pick photos and videos to clean. We use Apple&rsquo;s standard PhotosPicker, which is &ldquo;out-of-process&rdquo; &mdash; meaning we only receive the specific items you choose, not your entire library.</li>
  </ul>

  <h2>What the App does with that access</h2>
  <ul>
    <li><strong>Reads metadata</strong> from the items you picked.</li>
    <li><strong>Writes a cleaned copy</strong> back to your Photos library when you tap &ldquo;Clean &amp; Save.&rdquo;</li>
    <li><strong>Optionally deletes the original</strong> (recoverable from Recently Deleted for 30 days), only if you explicitly enable that toggle.</li>
  </ul>
  <p>That&rsquo;s it.</p>

  <h2>What the App does NOT do</h2>
  <ul>
    <li>No analytics. No tracking. No ad networks.</li>
    <li>No accounts. No login.</li>
    <li>No internet calls except App Store update checks (handled by iOS, not by us).</li>
    <li>No data sold or shared with third parties &mdash; ever.</li>
  </ul>

  <h2>Data linked to you</h2>
  <p>The Photos and Videos you process are inherently linked to your identity (it&rsquo;s your library). They are processed exclusively on your device and never transmitted anywhere. Per Apple&rsquo;s own definition, &ldquo;data processed only on-device is not collected.&rdquo;</p>

  <h2>Changes to this policy</h2>
  <p>If anything here ever changes, the updated date at the top will be edited and the change will be announced in the app&rsquo;s release notes.</p>

  <h2>Contact</h2>
  <p>Issues, questions, or feedback: <a href="https://github.com/alkloihd/media-swiss-army/issues">GitHub Issues</a>.</p>

  <footer>&copy; 2026 alkloihd. Hosted on GitHub Pages.</footer>
</main>
</body>
</html>
```

- [ ] **Step 2: Add the Privacy Policy row to Settings**

In `VideoCompressor/ios/Views/SettingsTabView.swift`, after the existing `Section("Storage")` block (around line 119) and BEFORE the `.navigationTitle("Settings")` modifier (line 121), add a new section:

```swift
                // MARK: About / Privacy
                Section("About") {
                    Link(
                        destination: URL(string: "https://alkloihd.github.io/media-swiss-army/privacy/")!
                    ) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(
                        "Opens the latest privacy policy in Safari. " +
                        "Media Swiss Army does not collect, transmit, or store any of your data."
                    )
                    .font(.caption)
                }
```

(`Link` defers to the system browser, which on iOS opens the URL in Safari. Visually consistent with other Settings rows.)

**Note:** The URL above is a real, parseable string — `URL(string:)` will return non-nil and the force-unwrap is safe. (Until the user enables GitHub Pages it will return 404 from Safari, but the app won't crash.)

- [ ] **Step 3: Run tests**

No new tests for this task (UI link is verified manually + the URL is a string literal — a unit test would only assert a tautology). Just confirm nothing regressed:

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE+13, Passed: BASELINE+13, Failed: 0`. Same count as Task 3.

- [ ] **Step 4: Commit**

```bash
git add docs/privacy/index.html \
        VideoCompressor/ios/Views/SettingsTabView.swift
git commit -m "feat(privacy): publish privacy policy + Settings link (Phase 3.4 / TASK-07)

docs/privacy/index.html will serve from
https://alkloihd.github.io/media-swiss-army/privacy/ once
GitHub Pages is enabled on the repo (manual user step — see
plan's 'Notes for the executing agent' section).

Settings tab gains an About section with a Privacy Policy row that
opens the URL in Safari. App Store Connect's Privacy Policy URL
field points to the same canonical URL.

Policy text matches the verbatim template in
.agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md
Part 8."
```

**Effort: ~1h. ~4 commits cumulatively.**

---

## Task 5: Apple-specific cloud CI job (Phase 3.3 / TASK-18)

**Why:** Today, `.github/workflows/ci.yml` runs only Node-side checks (ESLint / Prettier / Syntax / Security). The 138-test iOS XCTest target runs only locally on the lead's machine via `mcp__xcodebuildmcp__test_sim` and on the TestFlight pipeline (`testflight.yml`, after merge to main). That means an iOS regression can land on `main` and only get caught by the TestFlight build — wasting an Apple build credit and an iteration cycle.

The fix adds an `ios-tests` job to the PR-side workflow so iOS test failures gate merges. We re-use the macOS runner (`macos-26`) and Xcode/cache patterns from `testflight.yml`.

**Critical:** the `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` invocation **boots the simulator itself**. Do NOT add a separate `xcrun simctl boot` step — it's redundant and can race against xcodebuild's own boot logic.

- [ ] **Step 1: Append the `ios-tests` job to `.github/workflows/ci.yml`**

Edit `.github/workflows/ci.yml`. After the existing `security:` job, add:

```yaml

  ios-tests:
    name: iOS XCTest
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Show Xcode version
        run: |
          xcodebuild -version
          xcrun --show-sdk-path --sdk iphonesimulator

      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: ${{ runner.os }}-derived-tests-${{ hashFiles('VideoCompressor/**/*.swift', 'VideoCompressor/**/*.pbxproj') }}
          restore-keys: |
            ${{ runner.os }}-derived-tests-

      - name: Run XCTests on iPhone 16 Pro simulator
        run: |
          xcodebuild test \
            -project VideoCompressor/VideoCompressor_iOS.xcodeproj \
            -scheme VideoCompressor_iOS \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
            -only-testing:VideoCompressorTests \
            -resultBundlePath build/TestResults.xcresult \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify --renderer github-actions || exit 1

      - name: Upload test results on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: ios-test-results
          path: build/TestResults.xcresult
          retention-days: 7
```

Notes:
- `CODE_SIGNING_ALLOWED=NO` is safe for simulator tests (no provisioning profile needed).
- `xcbeautify` ships with the macOS-26 runner. If the runner image changes and it's missing, swap to `| cat` and accept the verbose log.
- The iPhone 16 Pro simulator is preinstalled on `macos-26`. If a future runner update removes it, swap to `'platform=iOS Simulator,OS=latest'` (Apple-supplied) but verify locally first.

- [ ] **Step 2: Mark the new job as a required PR check**

This is a **manual user step** in the GitHub UI (no API for the change in the standard `gh` CLI):

1. GitHub repo → Settings → Branches → Branch protection rules → `main`.
2. Edit the rule. Under "Require status checks to pass before merging", add `iOS XCTest` (the `name:` of the new job).
3. Save.

Document this in the PR body so the user does it before merging this PR. (The new job runs on the PR itself — once it goes green, the user marks it required and merges.)

- [ ] **Step 3: Validate locally first (catches YAML / xcodebuild typos before the cloud round-trip)**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE+13, Passed: BASELINE+13, Failed: 0`. Identical to Task 4 — this task only adds CI plumbing, no Swift code.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(ios): add macos-26 ios-tests job to PR workflow (Phase 3.3 / TASK-18)

Today the 138-test iOS XCTest target runs only locally and on the
post-merge TestFlight pipeline. Regressions waste an Apple build
credit before being caught.

This commit adds an 'ios-tests' job to .github/workflows/ci.yml that
runs on every PR. It uses macos-26, the same runner as testflight.yml,
caches DerivedData by Swift+pbxproj content hash, and runs
'xcodebuild test -only-testing:VideoCompressorTests' on the iPhone 16
Pro simulator. xcodebuild boots the sim itself; no separate simctl
step (redundant + race-prone).

Manual follow-up after this PR's CI goes green: mark 'iOS XCTest' as
a required status check on main in the GitHub branch-protection UI.

Adds ~3-5 minutes to PR CI."
```

**Effort: ~2h. ~5 commits cumulatively.**

---

## Task 6: Push, PR, watch CI, merge

- [ ] **Step 1: Final local test pass**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE+13, Passed: BASELINE+13, Failed: 0`. The 13 new tests = 3 manifest + 5 stitch-fetcher auth + 5 review-prompter.

- [ ] **Step 2: Build sim**

```
mcp__xcodebuildmcp__build_sim
```

Expected: `iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.`

- [ ] **Step 3: Push branch + open PR**

```bash
git push -u origin feat/codex-cluster4-appstore-hardening
gh pr create --base main --head feat/codex-cluster4-appstore-hardening \
  --title "feat: Phase 3 cluster 4 — App Store hardening" \
  --body "Closes MASTER-PLAN tasks 3.1 (TASK-34 PrivacyInfo manifest), 3.2 (TASK-35 Photos auth gate), 3.3 (TASK-18 cloud CI), 3.4 (TASK-07 privacy policy), 3.5 (TASK-09 review prompt).

- PrivacyInfo.xcprivacy declares UserDefaults (CA92.1), FileTimestamp (C617.1), DiskSpace (E174.1).
- StitchClipFetcher gates both fetch paths on PHPhotoLibrary.authorizationStatus(for: .readWrite).
- ci.yml gains an 'ios-tests' job on macos-26 (NEW required PR check — see manual follow-up below).
- docs/privacy/index.html will serve at https://alkloihd.github.io/media-swiss-army/privacy/ once GitHub Pages is enabled on the repo.
- ReviewPrompter fires SKStoreReviewController.requestReview(in: scene) after 3 successful cleans, once per app version.

13 new tests passing. Cluster 3 baseline + 13 = current pass count.

### Manual follow-up by user (cannot be automated)
1. Enable GitHub Pages: Repo Settings → Pages → Source: 'main' branch, '/docs' folder. Save. Verify the URL resolves.
2. Add 'iOS XCTest' as a required status check on main: Repo Settings → Branches → main rule → require status checks → add 'iOS XCTest'.
3. Paste the privacy policy URL into App Store Connect → App Information → Privacy Policy URL when preparing for submission.

🤖 Generated with [Codex](https://openai.com/codex)"
```

- [ ] **Step 4: Watch CI — note the new ios-tests job will gate THIS PR**

```bash
gh pr checks <num> --watch
```

The new `ios-tests` job runs on this PR (it lives in the workflow file added by this PR). Wait for ALL jobs to go green: ESLint / Prettier / Syntax / Security / **iOS XCTest**. Total CI time ~5-8 minutes (was ~2 min before).

- [ ] **Step 5: Merge**

```bash
gh pr merge <num> --merge
```

This triggers `testflight.yml` and produces TestFlight build #4 in the cluster sequence.

- [ ] **Step 6: Append session log**

```bash
echo "[$(date '+%Y-%m-%d %H:%M IST')] [APP-STORE-HARDENING] Phase 3 cluster 4 — privacy manifest + auth gate + ios-tests CI + privacy policy + review prompt (PR #<num>)" \
  >> .agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md
```

---

## Acceptance criteria

- [ ] `VideoCompressor/ios/PrivacyInfo.xcprivacy` exists, parses, and `xcrun altool --validate-app` (during the next TestFlight cycle) reports zero privacy-manifest warnings in App Store Connect.
- [ ] `StitchClipFetcher.creationDate` and `.creationDates` both return `nil` / `[:]` for `.denied`, `.restricted`, `.notDetermined` Photos auth states.
- [ ] `.github/workflows/ci.yml` has an `ios-tests` job that runs successfully on this PR (visible in the PR checks list as "iOS XCTest").
- [ ] `https://alkloihd.github.io/media-swiss-army/privacy/` renders the policy after GitHub Pages is enabled (manual user step).
- [ ] The Settings tab has an About section with a "Privacy Policy" row that opens the URL in Safari.
- [ ] The in-app review prompt (`SKStoreReviewController.requestReview(in:)`) is requested after the 3rd successful MetaClean, only once per app version.
- [ ] All baseline (cluster 3 final) + 13 new tests pass on the PR's `ios-tests` job.
- [ ] Privacy policy URL contains no profanity (Apple App Review compliance) — ✅ RESOLVED via repo rename to `media-swiss-army`.
- [ ] Cluster 4 PR merges; TestFlight build #4 reaches testers.

---

## Manual iPhone test prompts

Run these on a tethered iPhone via `mcp__xcodebuildmcp__build_run_device` after the PR merges (or on the TestFlight build):

1. **Force-clean app data.** iPhone Settings → General → iPhone Storage → Media Swiss Army → Offload App, then re-install. Resets `@AppStorage` so the review-prompt counter starts at zero.
2. **Open the MetaClean tab.** Confirm the empty-state UI loads.
3. **Trigger the Photos picker → choose 1 photo for MetaClean.** Verify the auth prompt is the **`.readWrite`** one (it appears the first time the user hits the delete-original toggle path); previously the Stitch tab's "Sort by date taken" flow could implicitly elevate to `.readWrite` without a fresh prompt. After the fix, the Stitch flow no longer reads Photos data when the user hasn't already authorised `.readWrite`.
4. **Open Settings → tap Privacy Policy.** Verify Safari opens to `https://alkloihd.github.io/media-swiss-army/privacy/` and the page renders the dark-mode-aware policy text. (Step requires GitHub Pages enabled — see Notes below.)
5. **Clean 3 photos in a row.** After the 3rd successful save, verify the iOS-system review prompt sheet appears. (In DEBUG / sideloaded builds, `SKStoreReviewController.requestReview` is a no-op or shows a fake prompt; the real prompt only fires for App Store / TestFlight builds.) Re-launch the app and clean a 4th photo — confirm NO second prompt fires (per-version lock).
6. **Submit a TestFlight build → check App Store Connect → My Apps → Media Swiss Army → TestFlight → Build details.** Confirm the "Privacy Manifest" warning that previously appeared is now gone.

---

## Notes for the executing agent

- **GitHub Pages enablement is a one-time manual user step.** The `docs/privacy/index.html` file lands in the repo via this PR, but Pages must be turned on: GitHub repo → Settings → Pages → Source: "Deploy from a branch" → Branch: `main` → Folder: `/docs`. Save. URL becomes live within ~60 seconds. Until then, the in-app Privacy Policy link 404s — flag this in the PR description as a manual follow-up.
- **The reference doc `.agents/work-sessions/2026-05-03/reference/PUBLISHING-AND-MONETIZATION.md` Part 8 still references `alkloihd.github.io/metaclean/privacy` — that URL is stale.** The locked URL for this work is `https://alkloihd.github.io/media-swiss-army/privacy/` (matches the actual repo name from `AGENTS.md` 16.2). Use the locked URL throughout; do not "fix" code to match the reference doc.
- **Apple Small Business Program is OUT OF SCOPE for this PR.** That's a one-time manual user enrolment in App Store Connect (5 minutes). It has nothing to do with the code in this cluster.
- **The new `ios-tests` job adds ~3-5 minutes to PR CI.** Was ~2 min for Node-only checks; now ~5-7 min. Acceptable trade for catching iOS regressions before merge.
- **Baseline test count drift.** Cluster 1 lands +11 tests (149 if it merged first), cluster 2 lands +4 (153), cluster 3 lands ~+5 (158). After cluster 4's +13 the count is ~171. Don't pin to absolute numbers in a PR description — name the deltas and let the green-CI screen confirm.
- **PBXFileSystemSynchronizedRootGroup gotcha.** New `PrivacyInfo.xcprivacy` and the three new test files auto-include via the synchronized root group. If the manifest test fails with "PrivacyInfo.xcprivacy not found in app bundle", run `mcp__xcodebuildmcp__clean` then `mcp__xcodebuildmcp__test_sim`.
- **Don't re-run `mcp__xcodebuildmcp__session_set_defaults`** (per AGENTS.md Part 16.3). The defaults are correct for this workspace.
- **`SKStoreReviewController` review prompt is a no-op in DEBUG / non-App-Store builds.** Don't expect to see a UI sheet during local sim runs — only TestFlight + App Store builds surface it. The unit tests cover the eligibility logic; manual tester verification covers the actual sheet on TestFlight.
- **≤10 commits total.** Currently planned: 5 (one per Task 1-5) + zero from Task 6 (push/merge does not commit). Headroom for any forced amend.
- **Branch parent is `feat/phase-2-features-may3` (cluster 3), NOT `main`.** This is a deliberate stack so the Settings About section sits cleanly atop cluster 3's UX polish.
