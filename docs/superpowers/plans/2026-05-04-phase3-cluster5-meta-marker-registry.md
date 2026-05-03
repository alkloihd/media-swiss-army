# Phase 3 Cluster 5 — Adaptive Meta-Marker Registry

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. All steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hard-coded string blocklists in `MetadataService.isMetaGlassesFingerprint` (line 485) and `PhotoMetadataService.xmpContainsFingerprint` (line 322) with a JSON-driven, schema-versioned registry shipped in the app bundle. Adds Oakley Meta and RB-1/RB-2/OM-1 device hints (the headline scope expansion), plus a false-positive guard that prevents user-typed text containing "meta" from triggering a strip. The registry is structured for a future remote refresh, but **v1.0 ships bundled JSON only** — no `URLSession`, no signature verification, no analytics (locked decision #7 in `2026-05-04-PHASES-1-3-INDEX.md`).

**Why now:** Today every Meta hardware refresh quietly breaks the core promise — the headline feature regresses to a no-op against the very files it's named for. The user has flagged this as the headline product feature.

**Branch:** `feat/codex-cluster5-meta-marker-registry` off `feat/phase-2-features-may3`.

**Tech Stack:** Swift, `JSONDecoder`, `actor MetaMarkerRegistry`, `Bundle.main.url(forResource:withExtension:)`, XCTest. No new dependencies.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Resources/MetaMarkers.json` | Create | Bundled JSON registry. Schema v1, version 1, includes legacy markers + Oakley Meta + RB-1/RB-2/OM-1 device hints + false-positive guards. |
| `VideoCompressor/ios/Services/MetaMarkerRegistry.swift` | Create | `actor MetaMarkerRegistry` with `static let shared`, async `load()`, `defaultBundled()` strict-legacy fallback, `Markers` `Decodable` struct mirroring schema. |
| `VideoCompressor/ios/Services/MetadataService.swift` | Modify | `isMetaGlassesFingerprint` becomes `async`, gains `isBinarySource: Bool` + `atomByteCount: Int?` params, reads from registry, applies false-positive + min-length guards. Caller at line 437 updated to compute `isBinarySource` from which decode branch (lines 411-426) was taken. |
| `VideoCompressor/ios/Services/PhotoMetadataService.swift` | Modify | `xmpContainsFingerprint` becomes `async`, reads `xmpFingerprints` array from registry. `isFingerprintTag` reads `makerAppleSoftware` array. Min-length guard applied to XMP packet size. |
| `VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift` | Create | 10+ tests: bundle load, parse-failure fallback, every category (binaryAtomMarkers/xmpFingerprints/makerAppleSoftware/deviceModelHints), false-positive guard, min-length guard, Oakley Meta detection, regression. |
| `VideoCompressor/VideoCompressorTests/MetadataTagTests.swift` | Modify | 5 existing call sites at lines 119/129/142/151/160 get `await` + `async throws` — assertions unchanged. |
| `VideoCompressor/VideoCompressorTests/PhotoMediaTests.swift` | Modify | 7 existing call sites at lines 121-127 get `await` + `async throws` on the test method — assertions unchanged. |

---

## Pre-flight: Record baseline test count

The user's branch `feat/phase-2-features-may3` may have moved past the 138-test baseline cited elsewhere in MASTER-PLAN. Before any work:

- [ ] **Step 0: Snapshot baseline**

```
mcp__xcodebuildmcp__test_sim
```

Record the printed `Total: N, Passed: N` as `BASELINE_N` (a number you'll reuse below — likely ≥138). All "expected" lines below use `BASELINE_N + X` notation; resolve `X` by tasking-step accumulation.

---

## Task 1: Resource file — `MetaMarkers.json` in the bundle

The schema is **v1**. The registry **version** is 1 (independent of schema; bumps when markers are added in app updates). Decision: a strict superset of current hardcoded markers + Oakley Meta family.

- [ ] **Step 1: Failing test — bundle resource exists and parses**

Create `VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift` with the bundle-presence test (full file expanded in Task 5; for now just this stub so we can red-green Task 1 in isolation):

```swift
//
//  MetaMarkerRegistryTests.swift
//  VideoCompressorTests
//
//  Pins the JSON-driven Meta-glasses fingerprint registry (Phase 3 Cluster 5 / TASK-02).
//

import XCTest
@testable import VideoCompressor_iOS

final class MetaMarkerRegistryTests: XCTestCase {

    // MARK: - Task 1 stub (bundle resource present)

    func testBundleContainsMetaMarkersJSON() {
        let url = Bundle(for: type(of: self))
            .url(forResource: "MetaMarkers", withExtension: "json")
            ?? Bundle.main.url(forResource: "MetaMarkers", withExtension: "json")
        XCTAssertNotNil(url, "MetaMarkers.json must be present in the app bundle.")
    }
}
```

Run: `mcp__xcodebuildmcp__test_sim` — expect `testBundleContainsMetaMarkersJSON` **fails** (`url` is nil; resource file does not yet exist).

- [ ] **Step 2: Create `MetaMarkers.json`**

Create `VideoCompressor/ios/Resources/MetaMarkers.json` with the following content **exactly**:

```json
{
  "schemaVersion": 1,
  "version": 1,
  "lastUpdated": "2026-05-04",
  "deviceFamily": "Meta wearables (Ray-Ban Meta, Oakley Meta, future)",

  "binaryAtomMarkers": {
    "comment": [
      "ray-ban",
      "rayban",
      "ray ban",
      "meta wearable",
      "meta ai",
      "captured with meta"
    ],
    "description": [
      "ray-ban",
      "rayban",
      "ray ban",
      "meta wearable",
      "captured with meta",
      "shot with meta"
    ]
  },

  "xmpFingerprints": [
    "xmp.metaai",
    "meta:",
    "ray-ban",
    "rayban",
    "meta wearable",
    "meta ai",
    "c2pa",
    "manifeststore"
  ],

  "makerAppleSoftware": [
    "Ray-Ban Stories",
    "Ray-Ban Meta",
    "Oakley Meta"
  ],

  "deviceModelHints": [
    "RB-1",
    "RB-2",
    "OM-1"
  ],

  "falsePositiveGuards": {
    "rejectIfMarkerInUserTypedText": [
      "comment",
      "description"
    ],
    "minimumMarkerLengthBytes": 8
  }
}
```

**Schema annotations (binding for the implementation):**

- `schemaVersion`: parser version. Bumping this is a breaking change (would require a code update). Stays `1` for v1.0.
- `version`: registry payload version. Bumps with every new bundled marker set in an app update.
- `binaryAtomMarkers`: maps the *atom suffix* (lowercased — `comment`, `description`) to the list of substrings the detector looks for inside that atom's decoded bytes.
- `xmpFingerprints`: substrings the still-photo path looks for inside the XMP packet's decoded bytes.
- `makerAppleSoftware`: case-INSENSITIVE substrings to match against the `MakerApple → Software` value.
- `deviceModelHints`: short device-model identifiers (RB-1 = first-gen Ray-Ban Stories, RB-2 = Ray-Ban Meta, OM-1 = Oakley Meta). Used in any future EXIF `Model` matcher; in v1.0 the registry exposes them but no detector consumes them yet — kept here so the next app update can add the matcher without a schema bump.
- `falsePositiveGuards.rejectIfMarkerInUserTypedText`: list of atom suffixes for which a match is rejected if the source bytes came from `stringValue` (user-typed) rather than `dataValue` (binary atom). The Ray-Ban detector hits binary atoms; user-typed XMP descriptions like "Meta-data backup" hit `stringValue`.
- `falsePositiveGuards.minimumMarkerLengthBytes`: minimum **atom payload** size below which the detector skips the match entirely. **Strict less-than: `atomByteCount < minimumMarkerLengthBytes` short-circuits to `false`.** Default `8` — chosen so that the user's worked examples ("binary `meta` in 800-byte atom DOES trigger; same in 4-byte atom does NOT") both satisfy with a single comparator.

- [ ] **Step 3: Run tests — bundle test now passes**

```
mcp__xcodebuildmcp__clean
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE_N + 1, Passed: BASELINE_N + 1`. The new `testBundleContainsMetaMarkersJSON` is green.

If the bundle test still fails, see **"Notes for the executing agent"** at the bottom — synchronized root group should auto-include the .json, but a manual `PBXFileSystemSynchronizedBuildFileExceptionSet` may be needed.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Resources/MetaMarkers.json \
        VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift
git commit -m "feat(metaclean): add MetaMarkers.json bundled registry (Phase 3.6 / TASK-02)

Schema v1, registry version 1. Carries every legacy hardcoded marker
plus Oakley Meta + RB-1/RB-2/OM-1 device hints. Includes
falsePositiveGuards (rejectIfMarkerInUserTypedText +
minimumMarkerLengthBytes=8) used by the registry actor in the next
commit. Bundled-only — no remote refresh in v1.0 per locked decision #7.

Reference: docs/superpowers/plans/2026-05-04-phase3-cluster5-meta-marker-registry.md"
```

**Effort: ~30min. ~1 commit cumulatively.**

---

## Task 2: `MetaMarkerRegistry` actor

- [ ] **Step 1: Failing tests — actor loads from bundle and falls back when JSON is unparseable**

Append to `VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift`:

```swift

    // MARK: - Task 2 — actor load + fallback

    func testRegistryLoadsFromBundle() async {
        let m = await MetaMarkerRegistry.shared.load()
        XCTAssertEqual(m.schemaVersion, 1, "Schema must match the parser version.")
        XCTAssertGreaterThanOrEqual(m.version, 1)
        XCTAssertFalse(m.binaryAtomMarkers.isEmpty)
        XCTAssertFalse(m.xmpFingerprints.isEmpty)
    }

    func testRegistryDefaultBundledIsStrictLegacySubset() {
        // The fallback used when JSON parse fails. Must NOT contain the
        // post-registry additions (Oakley Meta, RB-1, OM-1) — those exist
        // only in the JSON. Otherwise the "fallback was used" assertion is
        // unobservable.
        let d = MetaMarkerRegistry.defaultBundled()
        XCTAssertFalse(
            d.makerAppleSoftware.contains(where: { $0.lowercased().contains("oakley") }),
            "defaultBundled() must be a strict legacy subset — no Oakley."
        )
        XCTAssertFalse(
            d.deviceModelHints.contains("OM-1"),
            "defaultBundled() must not contain OM-1 (post-registry addition)."
        )
        // But the legacy markers must still be present.
        XCTAssertTrue(d.xmpFingerprints.contains("ray-ban"))
        XCTAssertTrue(d.xmpFingerprints.contains("c2pa"))
    }

    func testParseOrFallbackReturnsDefaultWhenDataIsNil() {
        // The "JSON resource missing" branch.
        let result = MetaMarkerRegistry.parseOrFallback(data: nil)
        XCTAssertEqual(result, MetaMarkerRegistry.defaultBundled())
    }

    func testParseOrFallbackReturnsDefaultOnGarbageData() {
        // The "decode failure" branch.
        let garbage = Data("{ not json".utf8)
        let result = MetaMarkerRegistry.parseOrFallback(data: garbage)
        XCTAssertEqual(result, MetaMarkerRegistry.defaultBundled())
    }

    func testParseOrFallbackReturnsDefaultOnSchemaVersionMismatch() {
        // The "future parser version" branch — payload decodes but
        // schemaVersion ≠ 1, so we refuse to apply it.
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
        XCTAssertEqual(result, MetaMarkerRegistry.defaultBundled(),
                       "schemaVersion ≠ 1 must trigger the legacy fallback.")
    }
```

Run `mcp__xcodebuildmcp__test_sim` — expect both new tests **fail to compile** (`MetaMarkerRegistry` doesn't exist yet). That's the TDD red.

- [ ] **Step 2: Implementation — `MetaMarkerRegistry.swift`**

Create `VideoCompressor/ios/Services/MetaMarkerRegistry.swift`:

```swift
//
//  MetaMarkerRegistry.swift
//  VideoCompressor_iOS
//
//  Phase 3 Cluster 5 / TASK-02. JSON-driven registry for Meta-glasses
//  fingerprint detection. Replaces the hard-coded string blocklists
//  in MetadataService.isMetaGlassesFingerprint and
//  PhotoMetadataService.xmpContainsFingerprint.
//
//  v1.0 is bundle-only; remote refresh is a post-launch concern.
//

import Foundation

actor MetaMarkerRegistry {

    static let shared = MetaMarkerRegistry()

    /// Mirrors `MetaMarkers.json`. Property names match the JSON keys
    /// 1:1; no custom CodingKeys needed.
    struct Markers: Decodable, Equatable {
        var schemaVersion: Int
        var version: Int
        var lastUpdated: String?
        var deviceFamily: String?
        var binaryAtomMarkers: [String: [String]]
        var xmpFingerprints: [String]
        var makerAppleSoftware: [String]
        var deviceModelHints: [String]
        var falsePositiveGuards: Guards

        struct Guards: Decodable, Equatable {
            var rejectIfMarkerInUserTypedText: [String]
            var minimumMarkerLengthBytes: Int
        }
    }

    private var cached: Markers?

    private init() {}

    /// Loads the bundled registry, parses, and memoises. If the JSON is
    /// missing, fails to decode, or carries an unfamiliar `schemaVersion`,
    /// returns `defaultBundled()` (the legacy hardcoded subset) so the
    /// detector never crashes on a corrupt bundle. The decode/fallback
    /// branch is delegated to `parseOrFallback(data:)` so unit tests can
    /// exercise it without touching `Bundle.main`.
    func load() async -> Markers {
        if let c = cached { return c }
        let url = Bundle.main.url(forResource: "MetaMarkers", withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let result = Self.parseOrFallback(data: data)
        cached = result
        return result
    }

    /// Internal seam used by `load()` and exposed for unit testing. Pass
    /// `nil` (resource missing), garbage bytes (decode failure), or a
    /// schemaVersion ≠ 1 payload to exercise the three fallback paths.
    /// Returns the parsed `Markers` on success or `defaultBundled()` on
    /// any of the three failure modes.
    static func parseOrFallback(data: Data?) -> Markers {
        guard let data = data,
              let parsed = try? JSONDecoder().decode(Markers.self, from: data),
              parsed.schemaVersion == 1
        else { return defaultBundled() }
        return parsed
    }

    /// Strict legacy subset used iff the bundled JSON is missing or
    /// unparseable. Intentionally does NOT contain the Oakley / RB-1 /
    /// OM-1 additions — those live only in the JSON, so a "fallback was
    /// used" branch is observable in tests.
    static func defaultBundled() -> Markers {
        Markers(
            schemaVersion: 1,
            version: 0,
            lastUpdated: nil,
            deviceFamily: "legacy hardcoded fallback",
            binaryAtomMarkers: [
                "comment":     ["ray-ban", "rayban", "meta"],
                "description": ["ray-ban", "rayban", "meta"]
            ],
            xmpFingerprints: [
                "xmp.metaai", "meta:", "ray-ban", "rayban", "c2pa", "manifeststore"
            ],
            makerAppleSoftware: ["Ray-Ban Stories"],
            deviceModelHints: [],
            falsePositiveGuards: .init(
                rejectIfMarkerInUserTypedText: ["comment", "description"],
                minimumMarkerLengthBytes: 8
            )
        )
    }

    // MARK: - Detection helpers (used by MetadataService + PhotoMetadataService)

    /// Returns the binary-atom marker list for the given key, picking the
    /// first matching atom suffix. Key matching is substring on the
    /// lowercased key (e.g., `com.apple.quicktime.comment` → `comment`).
    func markersForBinaryAtom(key: String) async -> [String] {
        let m = await load()
        let k = key.lowercased()
        for (suffix, list) in m.binaryAtomMarkers where k.contains(suffix) {
            return list
        }
        return []
    }

    func xmpFingerprintList() async -> [String] {
        await load().xmpFingerprints
    }

    func makerAppleSoftwareList() async -> [String] {
        await load().makerAppleSoftware
    }

    func guards() async -> Markers.Guards {
        await load().falsePositiveGuards
    }
}
```

- [ ] **Step 3: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE_N + 6, Passed: BASELINE_N + 6` (Task 1 stub + 5 new in this task). All new tests pass.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Services/MetaMarkerRegistry.swift \
        VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift
git commit -m "feat(metaclean): MetaMarkerRegistry actor with bundle-or-default load

Pure registry — no detector wire-in yet. Loads MetaMarkers.json on first
access, memoises on the actor; falls back to defaultBundled() (strict
legacy subset, no Oakley/RB-1/OM-1) on resource-missing, decode-failure,
or schemaVersion-mismatch. parseOrFallback(data:) is the testable seam
for those three failure modes. Helpers markersForBinaryAtom /
xmpFingerprintList / makerAppleSoftwareList / guards expose the
categories the detectors will read in Tasks 3-4.

5 new tests (load-from-bundle, defaultBundled-is-legacy-subset,
parseOrFallback nil/garbage/schema-mismatch)."
```

**Effort: ~1h. ~2 commits cumulatively.**

---

## Task 3: Wire the registry into `MetadataService.isMetaGlassesFingerprint`

The current detector is `static func isMetaGlassesFingerprint(key: String, decodedText: String?) -> Bool` at line 485. It must become `async` and gain two parameters so the false-positive guard is implementable:

- `isBinarySource: Bool` — true if the decoded text came from `dataValue` (binary atom payload). False if from `stringValue` (user-typed / type-coded string atom). Computed at the caller (line 411-426) from which `if let` branch fired.
- `atomByteCount: Int?` — the byte length of the source `Data` blob, used by the `minimumMarkerLengthBytes` guard. Nil for non-binary atoms (the guard is skipped — by definition non-binary text is the user-typed false-positive surface, gated separately).

- [ ] **Step 1: Failing tests — false-positive guard + min-length guard**

Append to `VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift`:

```swift

    // MARK: - Task 3 — MetadataService wire-in + guards

    func testFalsePositiveGuardRejectsMetaInUserTypedDescription() async {
        // The motivating real-world bug: a vacation photo titled
        // "Meta-data backup" in the EXIF Description should NOT be
        // flagged as a Meta-glasses fingerprint.
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.description",
            decodedText: "Meta-data backup",
            isBinarySource: false,         // user-typed → string-value path
            atomByteCount: nil
        )
        XCTAssertFalse(hit, "User-typed text containing 'meta' must not trigger.")
    }

    func testBinaryAtomMetaMarkerInLargePayloadDoesTrigger() async {
        // The bundled JSON `binaryAtomMarkers.comment` does NOT contain
        // bare "meta" — it has the multi-word "meta wearable", "meta ai",
        // "captured with meta". Use one of those so the assertion matches
        // reality. (Bare "meta" lives only in defaultBundled() — the
        // legacy fallback used iff the JSON fails to load.)
        // 786 + 14 chars of "meta wearable" = 800 total; matches
        // atomByteCount exactly.
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: String(repeating: "x", count: 786) + "meta wearable",
            isBinarySource: true,
            atomByteCount: 800
        )
        XCTAssertTrue(hit, "Binary 800-byte atom containing 'meta wearable' must trigger.")
    }

    func testBinaryAtomMetaMarkerInShortPayloadDoesNotTrigger() async {
        // Use a real marker present in the bundled JSON; below the
        // minimumMarkerLengthBytes guard (8) we expect a short-circuit
        // even when the marker substring is genuinely present.
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: "meta ai",  // 7 chars; present in bundled JSON
            isBinarySource: true,
            atomByteCount: 7   // strictly less than minimumMarkerLengthBytes (8)
        )
        XCTAssertFalse(hit, "Below minimumMarkerLengthBytes (8) must short-circuit to false.")
    }

    func testUserTypedMetaInDescriptionDoesNotTrigger() async {
        // Validates the rejectIfMarkerInUserTypedText guard: a user-typed
        // description containing 'meta' (in any form) must NOT trigger,
        // because non-binary sources for the listed atom suffixes
        // (comment/description) are rejected by the false-positive guard.
        // Use "meta wearable" — a real marker from the bundled JSON — so
        // the marker WOULD match if the guard didn't fire.
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.description",
            decodedText: "My meta wearable backup from yesterday's hike",
            isBinarySource: false,  // user-typed, not binary atom
            atomByteCount: nil
        )
        XCTAssertFalse(hit, "User-typed text containing a real marker must NOT trigger when isBinarySource is false.")
    }

    func testRegistryDetectsLegacyRayBanMarker() async {
        // Regression: the case web-app commit a3ad413 originally fixed.
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: "Ray-Ban Stories",
            isBinarySource: true,
            atomByteCount: 32
        )
        XCTAssertTrue(hit)
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
```

Run: `mcp__xcodebuildmcp__test_sim` — expect compile failure (`isMetaGlassesFingerprint` does not have the new signature). TDD red.

- [ ] **Step 2: Implementation — replace the detector body**

In `VideoCompressor/ios/Services/MetadataService.swift`, replace the existing `isMetaGlassesFingerprint` (lines 485-490) with:

```swift
    /// Web app fingerprint detection (commits `a3ad413`, `be6e360`),
    /// rebuilt on the JSON-driven MetaMarkerRegistry (Phase 3.6 / TASK-02).
    ///
    /// `decodedText` is the UTF-8 / ASCII / printable-ASCII decode of the
    /// atom's bytes. The display `value` (e.g. "<binary, 32 bytes>") is
    /// NOT what we match against — that placeholder would never contain
    /// a marker.
    ///
    /// `isBinarySource` is `true` iff the bytes came from `dataValue`
    /// (binary atom payload). `false` for `stringValue` and for the
    /// number/date/unreadable fallbacks. The registry's
    /// `rejectIfMarkerInUserTypedText` guard rejects matches against
    /// non-binary sources for the listed atom suffixes — kills the
    /// "Meta-data backup" false positive without weakening the binary
    /// match path Ray-Ban relies on.
    ///
    /// `atomByteCount` is the byte length of the source data blob (nil
    /// for non-binary). The registry's `minimumMarkerLengthBytes` guard
    /// short-circuits when `atomByteCount < minimumMarkerLengthBytes`
    /// (strict less-than). Default 8 — defends against incidental ASCII
    /// "meta" in tiny atoms while keeping legitimate Ray-Ban payloads
    /// (always > 32 bytes) in scope.
    static func isMetaGlassesFingerprint(
        key: String,
        decodedText: String?,
        isBinarySource: Bool,
        atomByteCount: Int?
    ) async -> Bool {
        guard let text = decodedText?.lowercased() else { return false }

        let registry = MetaMarkerRegistry.shared
        let markers = await registry.markersForBinaryAtom(key: key)
        guard !markers.isEmpty else { return false }

        let g = await registry.guards()
        let k = key.lowercased()

        // Guard 1 (false-positive): non-binary atoms whose suffix is in
        // the rejection list never trigger.
        if !isBinarySource {
            for suffix in g.rejectIfMarkerInUserTypedText where k.contains(suffix) {
                return false
            }
        }

        // Guard 2 (min length): binary atoms below the threshold short-circuit.
        if isBinarySource,
           let n = atomByteCount,
           n < g.minimumMarkerLengthBytes
        {
            return false
        }

        for needle in markers where text.contains(needle.lowercased()) {
            return true
        }
        return false
    }
```

- [ ] **Step 3: Update the single caller (line 437) to compute & pass the new params**

Replace lines 411-449 in `VideoCompressor/ios/Services/MetadataService.swift` with:

```swift
        let value: String
        var decodedTextForMatching: String?
        var atomByteCount: Int?
        var isBinarySource = false
        if let s = (try? await item.load(.stringValue)) ?? nil {
            value = s
            decodedTextForMatching = s
            // isBinarySource stays false — stringValue is the user-typed /
            // type-coded string path.
        } else if let d = (try? await item.load(.dataValue)) ?? nil {
            value = "<binary, \(d.count) bytes>"
            atomByteCount = d.count
            isBinarySource = true
            // Try UTF-8 then ASCII-tolerant decode for fingerprint match.
            if let utf8 = String(data: d, encoding: .utf8) {
                decodedTextForMatching = utf8
            } else if let ascii = String(data: d, encoding: .ascii) {
                decodedTextForMatching = ascii
            } else {
                // Some Meta atoms are UTF-16 / mixed binary. Strip
                // non-printable bytes and try once more.
                let printable = d.filter { (0x20...0x7E).contains($0) }
                decodedTextForMatching = String(data: printable, encoding: .ascii)
            }
        } else if let n = (try? await item.load(.numberValue)) ?? nil {
            value = "\(n)"
            decodedTextForMatching = value
        } else if let date = (try? await item.load(.dateValue)) ?? nil {
            value = ISO8601DateFormatter().string(from: date)
            decodedTextForMatching = value
        } else {
            value = "(unreadable)"
        }
        let category = Self.categoryFor(key: key)
        let isFingerprint = await Self.isMetaGlassesFingerprint(
            key: key,
            decodedText: decodedTextForMatching,
            isBinarySource: isBinarySource,
            atomByteCount: atomByteCount
        )
        return MetadataTag(
            id: UUID(),
            key: key,
            displayName: Self.displayNameFor(key: key),
            value: value,
            category: category,
            isMetaFingerprint: isFingerprint
        )
```

(`classify` is already `async`; the new `await` slots in cleanly.)

- [ ] **Step 4: Update the 5 existing call sites in `MetadataTagTests.swift`**

The existing tests at `MetadataTagTests.swift:114-166` call the detector synchronously. Their assertions are unchanged; only the call-site signatures get `await` + the two new params. The pre-fix signature took just `(key:decodedText:)` — these calls now need `isBinarySource:` and `atomByteCount:`. Pick parameter values that preserve each test's intent.

Before/after diff for the first one (lines 114-125), as the canonical pattern for the other four:

```swift
    // BEFORE
    func testFingerprintMatchesRayBanInDecodedText() {
        XCTAssertTrue(
            MetadataService.isMetaGlassesFingerprint(
                key: "com.apple.quicktime.comment",
                decodedText: "Ray-Ban Stories"
            ),
            "Fingerprint detector must match decoded binary text containing 'Ray-Ban'"
        )
    }

    // AFTER
    func testFingerprintMatchesRayBanInDecodedText() async {
        let hit = await MetadataService.isMetaGlassesFingerprint(
            key: "com.apple.quicktime.comment",
            decodedText: "Ray-Ban Stories",
            isBinarySource: true,
            atomByteCount: 16
        )
        XCTAssertTrue(hit,
            "Fingerprint detector must match decoded binary text containing 'Ray-Ban'"
        )
    }
```

Apply the same `await + (isBinarySource: true, atomByteCount: 32)` shape to the calls at lines **129, 142, 151, 160**, marking each test method `async`. The "binary placeholder" test at line 142 (`<binary, 32 bytes>`) keeps its expected `XCTAssertFalse` — the placeholder string doesn't contain a registry marker, so the result is still false. The "unreadable nil" test at line 151 keeps `XCTAssertFalse` (decodedText nil → early return). The "non-comment key" test at line 160 keeps `XCTAssertFalse` (no marker list for `location.ISO6709`). All assertions are preserved; only call shape changes.

- [ ] **Step 5: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE_N + 12, Passed: BASELINE_N + 12` (6 from Tasks 1-2 + 6 new from Task 3). Existing 5 fingerprint tests in `MetadataTagTests.swift` still pass after their `await` upgrade.

- [ ] **Step 6: Commit**

```bash
git add VideoCompressor/ios/Services/MetadataService.swift \
        VideoCompressor/VideoCompressorTests/MetadataTagTests.swift \
        VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift
git commit -m "feat(metaclean): wire MetaMarkerRegistry into MetadataService detector

isMetaGlassesFingerprint becomes async and gains isBinarySource +
atomByteCount params so the registry's falsePositiveGuards
(rejectIfMarkerInUserTypedText + minimumMarkerLengthBytes) are
implementable. Caller in classify() computes both params from which
decode branch (stringValue vs dataValue) fired.

6 new tests (false-positive guard, large-payload trigger, min-length
guard, user-typed marker rejection, legacy Ray-Ban, key-scope). 5
existing fingerprint tests in MetadataTagTests upgraded to async;
assertions unchanged."
```

**Effort: ~1.5h. ~3 commits cumulatively.**

---

## Task 4: Wire the registry into `PhotoMetadataService.xmpContainsFingerprint`

`xmpContainsFingerprint` at line 322 is the still-photo path. The XMP packet is *always* a binary blob (`kCGImagePropertyXMPData` is `Data`), so `isBinarySource` is always true here — no false-positive guard needed at the caller, but the min-length guard still applies (a tiny XMP packet of 4 bytes shouldn't trigger).

`isFingerprintTag` at line 310 reads MakerApple → Software. The hardcoded `meta`/`ray-ban`/`rayban` substring check becomes a registry lookup against `makerAppleSoftware`.

- [ ] **Step 1: Failing tests — XMP and MakerApple from registry, min-length applies to XMP**

Append to `VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift`:

```swift

    // MARK: - Task 4 — PhotoMetadataService wire-in

    func testXMPFingerprintTriggersOnRegistryMarker() async {
        let hit = await PhotoMetadataService.xmpContainsFingerprint(
            "<x:xmpmeta>...xmp.MetaAI...</x:xmpmeta>",
            packetByteCount: 256
        )
        XCTAssertTrue(hit)
    }

    func testXMPFingerprintRejectsBelowMinimumLength() async {
        let hit = await PhotoMetadataService.xmpContainsFingerprint(
            "meta:",
            packetByteCount: 5
        )
        XCTAssertFalse(hit, "Tiny XMP packets below minimumMarkerLengthBytes short-circuit.")
    }

    func testMakerAppleSoftwareDetectsOakleyMeta() async {
        // Headline scope expansion: the registry adds Oakley Meta to
        // makerAppleSoftware. Pre-registry detector would also match
        // "meta" substring; the regression test below proves the
        // registry path doesn't drop existing coverage.
        let hit = await PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple", key: "Software", value: "Oakley Meta v1.0"
        )
        XCTAssertTrue(hit, "Oakley Meta must be detected via registry expansion.")
    }

    func testMakerAppleSoftwareRejectsIPhone() async {
        let hit = await PhotoMetadataService.isFingerprintTag(
            namespace: "MakerApple", key: "Software", value: "iPhone 15 Pro"
        )
        XCTAssertFalse(hit)
    }
```

Run: `mcp__xcodebuildmcp__test_sim` — expect compile failures (signatures don't match). TDD red.

- [ ] **Step 2: Implementation — replace `xmpContainsFingerprint` and `isFingerprintTag`**

In `VideoCompressor/ios/Services/PhotoMetadataService.swift`, replace the body of `xmpContainsFingerprint` (lines 322-330) with:

```swift
    /// XMP packet fingerprint detection backed by `MetaMarkerRegistry`
    /// (Phase 3.6 / TASK-02). The packet is always a binary blob
    /// (`kCGImagePropertyXMPData` is `Data`), so `isBinarySource` is
    /// implicit — only the `minimumMarkerLengthBytes` guard applies.
    static func xmpContainsFingerprint(
        _ packet: String,
        packetByteCount: Int
    ) async -> Bool {
        let g = await MetaMarkerRegistry.shared.guards()
        if packetByteCount < g.minimumMarkerLengthBytes { return false }
        let p = packet.lowercased()
        let needles = await MetaMarkerRegistry.shared.xmpFingerprintList()
        for needle in needles where p.contains(needle.lowercased()) {
            return true
        }
        return false
    }
```

Replace `isFingerprintTag` (lines 310-320) with:

```swift
    /// Fingerprint detection for stills' MakerApple → Software value.
    /// Reads the substring list from `MetaMarkerRegistry`
    /// (`makerAppleSoftware`); case-insensitive.
    static func isFingerprintTag(
        namespace: String?,
        key: String,
        value: String
    ) async -> Bool {
        guard namespace == "MakerApple",
              key.lowercased().contains("software")
        else { return false }
        let v = value.lowercased()
        let needles = await MetaMarkerRegistry.shared.makerAppleSoftwareList()
        for needle in needles where v.contains(needle.lowercased()) {
            return true
        }
        return false
    }
```

**Internal-caller propagation.** `isFingerprintTag` is also called inside the private helper `makeTag` (line 272). That helper must become async too, and its two call sites (lines 82 and 107, both inside the already-`async` `read(from:)`) need `await`. Apply this exact change to `makeTag`:

```swift
    private func makeTag(namespace: String?, key: String, value: String) async -> MetadataTag {
        let fullKey = namespace.map { "\($0).\(key)" } ?? key
        let category = Self.categoryFor(namespace: namespace, key: key)
        let display = Self.displayNameFor(namespace: namespace, key: key)
        let isFp = await Self.isFingerprintTag(namespace: namespace, key: key, value: value)
        return MetadataTag(
            id: UUID(),
            key: fullKey,
            displayName: display,
            value: value,
            category: category,
            isMetaFingerprint: isFp
        )
    }
```

Then both `makeTag(...)` call sites (lines 82, 107) become `await makeTag(...)`. Confirm via:

```
grep -n "makeTag(" VideoCompressor/ios/Services/PhotoMetadataService.swift
```

Should show 3 hits — the definition + 2 call sites; both call sites need `await`.

Update the XMP call site in `PhotoMetadataService.swift` at line 123 (the XMP read pass, inside `read(from:)`):

```swift
        if let xmpData = props[kCGImagePropertyXMPData] as? Data {
            let decoded = String(data: xmpData, encoding: .utf8)
                ?? String(data: xmpData, encoding: .ascii)
                ?? ""
            let isFingerprint = await Self.xmpContainsFingerprint(
                decoded,
                packetByteCount: xmpData.count
            )
            let preview = "<XMP packet, \(xmpData.count) bytes>"
            tags.append(MetadataTag(
                id: UUID(),
                key: "XMP",
                displayName: "XMP",
                value: preview,
                category: .custom,
                isMetaFingerprint: isFingerprint
            ))
        }
```

Verify (and update if needed) any other caller of `isFingerprintTag` or `xmpContainsFingerprint` in `PhotoMetadataService.swift` — `read(from:)` is already `async`, so awaits add cleanly. Search:

```
grep -n "isFingerprintTag(\|xmpContainsFingerprint(" VideoCompressor/ios/Services/PhotoMetadataService.swift
```

If `isFingerprintTag` is called inside the `MakerApple` namespace loop in `read(from:)`, mirror the same `await` upgrade.

- [ ] **Step 2.5: Exhaustive async-cascade pre-walk**

The `xmpContainsFingerprint` change to `async` cascades through every caller. Before editing the test files in Step 3, enumerate ALL hits:

```bash
grep -rn 'isFingerprintTag\|xmpContainsFingerprint\|isMetaGlassesFingerprint' VideoCompressor/
```

Expected output: ~7 production sites + ~11 test sites. For each PRODUCTION hit, classify:
- (a) Caller is already `async` — just add `await`
- (b) Caller is `sync` — caller must also become `async`, recursively up to the nearest already-`async` parent

Build a list before editing:
- Site 1: `MetadataService.swift:437` — `isMetaGlassesFingerprint(...)` called from inside the already-`async` `classify(...)` flow (`await item.load(...)` calls precede it on lines 411-432). Just add `await` (Task 3 Step 3 already does this).
- Site 2: `PhotoMetadataService.swift:82` — `makeTag(...)` called from the top-level scalar-props loop inside `read(url:)` (already `async throws`). After `makeTag` becomes `async`, just add `await`.
- Site 3: `PhotoMetadataService.swift:107` — `makeTag(...)` called from the nested-namespaces loop, same `read(url:)` parent. After `makeTag` becomes `async`, just add `await`.
- Site 4: `PhotoMetadataService.swift:123` — direct `Self.xmpContainsFingerprint(decoded)` call from inside the XMP block of `read(url:)` (already `async`). Just add `await` (Task 4 Step 2 already does this).
- Site 5: `PhotoMetadataService.swift:272` — `Self.isFingerprintTag(...)` called from inside the **sync** `private func makeTag(...)`. The `makeTag` helper itself must become `async`; that cascade then bubbles to Sites 2 and 3 above.
- Site 6: `PhotoMetadataService.swift:310` — `static func isFingerprintTag` definition (sync today). Becomes `async` per Task 4 Step 2.
- Site 7: `PhotoMetadataService.swift:322` — `static func xmpContainsFingerprint` definition (sync today). Becomes `async` per Task 4 Step 2.

(Re-grep before editing — line numbers may have drifted from the values captured here. The structure is what matters: 4 production callers + 3 definitions = 7 production hits.)

For each TEST hit, the test's `func` declaration must become `async` (and `throws` if needed) and call sites add `await` (or use the `XCTAssertTrueAsync` / `XCTAssertFalseAsync` helpers introduced in Step 3 below):
- `MetadataTagTests.swift:119, 129, 142, 151, 160` — 5 sync calls inside currently-sync `func test…()` methods. Tests get `async`, calls get `await` + the new `isBinarySource:` / `atomByteCount:` params (Task 3 Step 4 already covers this).
- `PhotoMediaTests.swift:121, 122, 123, 124, 125, 126, 127` — 7 sync `xmpContainsFingerprint(...)` calls inside `testXMPFingerprintDetection` (Task 4 Step 3 covers this with the `XCTAssert*Async` helpers).
- `PhotoMediaTests.swift:131, 134, 137, 140` — 4 sync `isFingerprintTag(...)` calls inside `testMakerAppleSoftwareFingerprintDetection` (Task 4 Step 3 covers this — same `await` upgrade pattern).

**Do NOT proceed to Step 3 until this enumeration is complete and you have a written list of changes** (paste the grep output into your scratch notes or a deviation-log entry, classify each hit, then start editing). A half-applied async cascade is the worst kind of bug for Codex to debug — the build will go red somewhere unexpected and the cause will be far from the failing line.

- [ ] **Step 3: Update the 7 existing call sites in `PhotoMediaTests.swift`**

`PhotoMediaTests.swift:120-128` and `:130-141` call both helpers synchronously. Each test method becomes `async`; each call adds `await` + the new `packetByteCount:` arg (use 256 — large enough to clear the 8-byte guard for non-empty payloads). The empty-string test at line 127 takes `packetByteCount: 0` and the assertion stays `XCTAssertFalse` (0 < 8 → short-circuit, same outcome).

Before/after for `testXMPFingerprintDetection` (lines 120-128):

```swift
    // BEFORE
    func testXMPFingerprintDetection() {
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("...xmp.MetaAI..."))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("blah meta: hello"))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("Ray-Ban Stories"))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("Rayban marker"))
        XCTAssertTrue(PhotoMetadataService.xmpContainsFingerprint("c2pa.ManifestStore"))
        XCTAssertFalse(PhotoMetadataService.xmpContainsFingerprint("plain photo metadata"))
        XCTAssertFalse(PhotoMetadataService.xmpContainsFingerprint(""))
    }

    // AFTER
    func testXMPFingerprintDetection() async {
        let svc = PhotoMetadataService.self
        await XCTAssertTrueAsync(svc.xmpContainsFingerprint("...xmp.MetaAI...", packetByteCount: 256))
        await XCTAssertTrueAsync(svc.xmpContainsFingerprint("blah meta: hello", packetByteCount: 256))
        await XCTAssertTrueAsync(svc.xmpContainsFingerprint("Ray-Ban Stories", packetByteCount: 256))
        await XCTAssertTrueAsync(svc.xmpContainsFingerprint("Rayban marker", packetByteCount: 256))
        await XCTAssertTrueAsync(svc.xmpContainsFingerprint("c2pa.ManifestStore", packetByteCount: 256))
        await XCTAssertFalseAsync(svc.xmpContainsFingerprint("plain photo metadata", packetByteCount: 256))
        await XCTAssertFalseAsync(svc.xmpContainsFingerprint("", packetByteCount: 0))
    }
```

(The `XCTAssertTrueAsync` / `XCTAssertFalseAsync` are tiny test-only helpers. Add at the bottom of `PhotoMediaTests.swift` if not already present:)

```swift
private func XCTAssertTrueAsync(
    _ expression: @autoclosure () async -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let result = await expression()
    XCTAssertTrue(result, message(), file: file, line: line)
}

private func XCTAssertFalseAsync(
    _ expression: @autoclosure () async -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let result = await expression()
    XCTAssertFalse(result, message(), file: file, line: line)
}
```

For `testMakerAppleSoftwareFingerprintDetection` (lines 130-141), do the same `await` upgrade — each `isFingerprintTag(...)` call gets prefixed with `await`, and the test method gets `async`. Assertions are unchanged.

- [ ] **Step 4: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE_N + 16, Passed: BASELINE_N + 16` (12 from Tasks 1-3 + 4 new). Pre-existing tests in `PhotoMediaTests.swift` still pass after their async upgrade.

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Services/PhotoMetadataService.swift \
        VideoCompressor/VideoCompressorTests/PhotoMediaTests.swift \
        VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift
git commit -m "feat(metaclean): wire MetaMarkerRegistry into PhotoMetadataService

xmpContainsFingerprint and isFingerprintTag both become async and read
their needle lists from the registry. xmpContainsFingerprint also
honours minimumMarkerLengthBytes (XMP packet is binary by definition).

4 new tests (XMP marker, XMP min-length, MakerApple Oakley Meta,
MakerApple iPhone reject). 7 existing assertions in PhotoMediaTests
upgraded to async via local XCTAssert*Async helpers; assertions
unchanged."
```

**Effort: ~1h. ~4 commits cumulatively.**

---

## Task 5: Comprehensive registry tests + regression sweep

The remaining MetaMarkerRegistryTests cases. Bring the new-test count to **≥10** (TASK-02 acceptance criterion) and pin every JSON category.

- [ ] **Step 1: Append the remaining tests to `MetaMarkerRegistryTests.swift`**

```swift

    // MARK: - Task 5 — category coverage + Oakley regression

    func testRegistryExposesDeviceModelHints() async {
        let m = await MetaMarkerRegistry.shared.load()
        XCTAssertTrue(m.deviceModelHints.contains("RB-1"))
        XCTAssertTrue(m.deviceModelHints.contains("RB-2"))
        XCTAssertTrue(m.deviceModelHints.contains("OM-1"))
    }

    func testRegistryHasOakleyInMakerAppleSoftware() async {
        let m = await MetaMarkerRegistry.shared.load()
        XCTAssertTrue(
            m.makerAppleSoftware.contains(where: { $0.lowercased() == "oakley meta" }),
            "Oakley Meta must be in the bundled registry's makerAppleSoftware list."
        )
    }

    func testBinaryAtomMarkersCoverCommentAndDescription() async {
        let m = await MetaMarkerRegistry.shared.load()
        XCTAssertNotNil(m.binaryAtomMarkers["comment"])
        XCTAssertNotNil(m.binaryAtomMarkers["description"])
        XCTAssertTrue(m.binaryAtomMarkers["comment"]?.contains("ray-ban") ?? false)
    }

    func testGuardsAreParsedFromJSON() async {
        let g = await MetaMarkerRegistry.shared.guards()
        XCTAssertEqual(g.minimumMarkerLengthBytes, 8)
        XCTAssertTrue(g.rejectIfMarkerInUserTypedText.contains("comment"))
        XCTAssertTrue(g.rejectIfMarkerInUserTypedText.contains("description"))
    }

    func testRegistryIsCachedAcrossLoads() async {
        // Two consecutive loads must return the same Markers value;
        // proves the actor's memoisation works (cheap correctness check).
        let m1 = await MetaMarkerRegistry.shared.load()
        let m2 = await MetaMarkerRegistry.shared.load()
        XCTAssertEqual(m1, m2)
    }
```

That brings new MetaMarkerRegistryTests count to: 1 (Task 1 stub) + 5 (Task 2: load/legacy-subset/parseOrFallback × 3) + 6 (Task 3) + 4 (Task 4) + 5 (Task 5) = **21 new test cases**. Comfortably above the ≥10 floor and pins every JSON category, every fallback branch, AND the user-typed false-positive guard.

- [ ] **Step 2: Run the full suite — both new and pre-existing**

```
mcp__xcodebuildmcp__clean
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: BASELINE_N + 21, Passed: BASELINE_N + 21` (21 new tests total). All pre-existing tests still pass — including the 5 `MetadataTagTests` fingerprint tests and the 7 `PhotoMediaTests` assertions, which were upgraded in-place to async without changing their assertions.

- [ ] **Step 3: Build sim — confirm no warnings introduced**

```
mcp__xcodebuildmcp__build_sim
```

Expected: `✅ iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.`

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift
git commit -m "test(metaclean): MetaMarkerRegistry category coverage + Oakley regression

Brings new test count to 21 (≥10 acceptance floor). Pins:
- deviceModelHints exposure (RB-1/RB-2/OM-1)
- Oakley Meta in makerAppleSoftware (headline scope expansion)
- binaryAtomMarkers comment/description coverage
- falsePositiveGuards parsed correctly from JSON
- actor memoisation (load() cached across calls)

Full suite green: BASELINE_N + 21 / BASELINE_N + 21."
```

**Effort: ~45min. ~5 commits cumulatively.**

---

## Task 6: Push, PR, CI, merge

- [ ] **Step 1: Final test pass + sim build**

```
mcp__xcodebuildmcp__test_sim
mcp__xcodebuildmcp__build_sim
```

Expected: green on both.

- [ ] **Step 2: Push branch**

```bash
git push -u origin feat/codex-cluster5-meta-marker-registry
```

- [ ] **Step 3: Open PR against `feat/phase-2-features-may3`**

```bash
gh pr create --base feat/phase-2-features-may3 \
  --head feat/codex-cluster5-meta-marker-registry \
  --title "feat(metaclean): adaptive Meta-marker registry (Phase 3.6 / TASK-02)" \
  --body "$(cat <<'EOF'
Closes MASTER-PLAN task 3.6 (TASK-02) — the headline product feature.

## What
Replaces the hard-coded fingerprint blocklists in MetadataService and
PhotoMetadataService with a JSON-driven registry shipped in the bundle.

- New: \`VideoCompressor/ios/Resources/MetaMarkers.json\` (schema v1, version 1)
- New: \`actor MetaMarkerRegistry\` with bundle-or-default load + memoisation
- Modified: \`isMetaGlassesFingerprint\` and \`xmpContainsFingerprint\`
  become async, read from the registry, honour \`falsePositiveGuards\`
- 21 new tests (including all three fallback branches via
  parseOrFallback); 12 existing test call-sites upgraded to async
  (assertions unchanged).

## Headline scope additions
- Oakley Meta added to \`makerAppleSoftware\`
- RB-1, RB-2, OM-1 device hints (post-launch hook for an EXIF Model
  matcher; v1.0 carries them in the registry, no consumer yet)
- False-positive guard prevents user-typed text containing 'meta' from
  triggering a strip (motivating bug: vacation photo titled "Meta-data
  backup" was getting flagged)
- Min-length guard (\`minimumMarkerLengthBytes: 8\`) defends against
  incidental ASCII matches in tiny atoms

## Locked decisions honoured
- v1.0 bundled-only — zero network, zero analytics (decision #7)
- ≤10 commits (this PR ships 5 + push)
- 138-baseline tests preserved; new tests ADD, never replace

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Watch CI**

```bash
gh pr checks <num> --watch
```

- [ ] **Step 5: Merge**

```bash
gh pr merge <num> --merge
```

- [ ] **Step 6: Append session log**

```bash
echo "[$(date '+%Y-%m-%d %H:%M IST')] [METACLEAN] Phase 3 cluster 5 — adaptive Meta-marker registry (PR #<num>)" \
  >> .agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md
```

---

## Acceptance criteria

Mirroring TASK-02:

- [ ] All current detection still fires (5 `MetadataTagTests` fingerprint tests + 7 `PhotoMediaTests` assertions all pass after async upgrade — assertions unchanged).
- [ ] Registry loads from JSON; falls back to `defaultBundled()` (strict legacy subset, no Oakley/RB-1/OM-1) on parse failure or schema-version mismatch.
- [ ] At least one new device marker added — `Oakley Meta` in `makerAppleSoftware`, `RB-1` / `RB-2` / `OM-1` in `deviceModelHints`.
- [ ] False-positive guard added: `Meta-data backup` in user-typed XMP description does NOT trigger a strip (`testFalsePositiveGuardRejectsMetaInUserTypedDescription`).
- [ ] Min-length guard short-circuits below `minimumMarkerLengthBytes` (`testBinaryAtomMetaMarkerInShortPayloadDoesNotTrigger`).
- [ ] ≥ 10 new test cases in `MetaMarkerRegistryTests.swift` (this plan ships 21, covering all categories + all three fallback branches + the user-typed false-positive guard).
- [ ] No new `URLSession`, no analytics, no third-party SDKs (locked decision #7 + privacy-first rule).
- [ ] `MetadataService.strip` (the actual stripping logic) is untouched — only the detector path changed.
- [ ] CI green; PR merged into `feat/phase-2-features-may3`; TestFlight build #5 reaches testers (per cluster-5 row in `2026-05-04-PHASES-1-3-INDEX.md`).

---

## Manual iPhone test prompts (tethered)

Run after merge, before promoting the TestFlight build:

1. **Real Ray-Ban Meta photo round-trip.** Import a photo taken on Ray-Ban Meta glasses. In MetaClean, confirm the inspector flags the Meta atom as `isMetaFingerprint = true`. Run the strip. Verify the saved output: GPS, capture date, Live Photo motion track, and any non-Meta EXIF (Make=Apple, Model=iPhone if shared) are intact; the binary `Comment`/`Description` Meta atom is gone.

2. **False-positive control.** Open Photos, pick a normal iPhone photo, edit its Description / Title to read `Meta-data backup`. Re-import into MetaClean. Confirm the inspector does NOT flag any tag as a fingerprint and the strip pass reports "no fingerprint found" (file untouched).

3. **Oakley Meta detection (if you have a sample).** If an Oakley Meta photo is available, import → confirm `MakerApple → Software` matches `Oakley Meta v*` and the inspector flags it. If no Oakley sample is on hand, this prompt is satisfied by the unit test `testMakerAppleSoftwareDetectsOakleyMeta`.

4. **No new Settings surface.** Open Settings inside the app. Confirm there is NO new "marker version" / "registry" row. v1.0 is silent about the registry by design (locked decision #7) — the registry is an internal mechanism, not a user-facing concept.

5. **Cold-launch fallback test (manual fault injection).** Build with `MetaMarkers.json` temporarily removed from the bundle (e.g., via Xcode "Build Phases → Copy Bundle Resources" exclusion in a throwaway scheme). Cold-launch and run a clean — confirm Ray-Ban detection still fires (via `defaultBundled()` legacy subset). Restore the JSON before pushing.

---

## Notes for the executing agent

- **JSON resource bundling.** The `ios/` directory is configured as a `PBXFileSystemSynchronizedRootGroup` (verified in `VideoCompressor/VideoCompressor_iOS.xcodeproj/project.pbxproj` lines 32-48; no `membershipExceptions` block). Xcode 16+ auto-categorises `.json` under that synchronized group as a bundle resource. The new `Resources/MetaMarkers.json` should auto-include after `mcp__xcodebuildmcp__clean`. **Verification:** after Task 1 Step 3, the test `testBundleContainsMetaMarkersJSON` passes iff `Bundle.main.url(forResource: "MetaMarkers", withExtension: "json")` returns non-nil.

  If the test fails (resource not found), the synchronized root group needs a `PBXFileSystemSynchronizedBuildFileExceptionSet` to explicitly include the file. Diagnostic command:

  ```bash
  grep -A2 "PBXFileSystemSynchronizedBuildFileExceptionSet" \
    VideoCompressor/VideoCompressor_iOS.xcodeproj/project.pbxproj
  ```

  If empty, open the project in Xcode, right-click `Resources/MetaMarkers.json` in the navigator, ensure "Target Membership → VideoCompressor_iOS" is checked. Save → re-run `clean + test_sim`. **Do not commit a project.pbxproj change unless the auto-include path actually fails.**

- **`MetaMarkerRegistry.shared` is `actor`-isolated state across the test suite.** Tests rely on the bundled JSON being loaded; if any test mutates registry state in the future, add a reset hook. v1.0 has no mutator — `load()` is the only entry — so no reset is needed.

- **Async test-helper ergonomics.** Swift's stock `XCTAssert*` macros don't accept async autoclosures. The `XCTAssertTrueAsync` / `XCTAssertFalseAsync` helpers in Task 4 Step 3 are private to `PhotoMediaTests.swift`. If you find them duplicated elsewhere in the test target, dedupe — but do not move them into the production target.

- **Don't touch `MetadataService.strip`.** The detector and the stripper are deliberately separable (the strip pass uses `.autoMetaGlasses` rules and operates on the inspector's output). Only the detector input changes in this PR.

- **Sim defaults.** Per `AGENTS.md` Part 16.3: don't re-run `session_set_defaults`. Use `session_show_defaults` once at session start; rely on cached project + scheme + simulator.

- **Commit budget.** 5 task commits + 1 push = within the ≤10 ceiling. If a follow-up nit lands during review, squash before merge.

- **Future-state remote refresh (post-v1.0 only).** The `schemaVersion` field exists so a future remote-refresh can refuse to apply payloads with an unfamiliar parser version. Don't add `URLSession` or signature verification in this PR — that's a separate post-launch task.
