# TASK-02 — Adaptive Meta-glasses fingerprint registry

**Priority:** HIGH — user has flagged this as the headline feature.
**Estimated effort:** 4-6 hours.
**Branch:** `feat/meta-marker-registry` off `main`.

## Problem

Currently `MetadataService.isMetaGlassesFingerprint` (~line 467) and `PhotoMetadataService.xmpContainsFingerprint` (~line 322) are hard-coded string blocklists: `ray-ban`, `rayban`, `meta`, `c2pa`, `manifeststore`. This:

1. Won't catch new Meta devices (Oakley Meta, future hypothetical Meta Vision, etc.) without a code release
2. Has zero false-positive guards — any photo with "meta" in user-typed text in EXIF Description gets flagged
3. Can't be updated quickly when Meta changes their tagging scheme

## Goal

A JSON-driven `MetaMarkers.json` shipped with the app, hot-swappable via App Store update, with structured marker categories and false-positive guards. The user flagged "Meta AI" as the broad target.

## Design

### `Resources/MetaMarkers.json`

```json
{
  "version": 7,
  "lastUpdated": "2026-05-03",
  "deviceFamily": "Meta wearables (Ray-Ban / Oakley / future)",

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
    "minimumMarkerLengthBytes": 4
  }
}
```

### New service: `MetaMarkerRegistry`

`VideoCompressor/ios/Services/MetaMarkerRegistry.swift`:

```swift
import Foundation

actor MetaMarkerRegistry {
    static let shared = MetaMarkerRegistry()

    struct Markers: Decodable {
        var version: Int
        var binaryAtomMarkers: [String: [String]]   // key → markers
        var xmpFingerprints: [String]
        var makerAppleSoftware: [String]
        var deviceModelHints: [String]
        // ... falsePositiveGuards mirroring JSON
    }

    private var cached: Markers?

    private init() {}

    func load() async -> Markers {
        if let c = cached { return c }
        guard let url = Bundle.main.url(forResource: "MetaMarkers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Markers.self, from: data)
        else {
            return defaultBundled()  // hardcoded fallback
        }
        cached = m
        return m
    }

    private func defaultBundled() -> Markers { /* current hardcoded values */ }
}
```

### Wire-in

- `MetadataService.isMetaGlassesFingerprint(key:decodedText:)` → reads from registry
- `PhotoMetadataService.xmpContainsFingerprint(_:)` → reads from registry
- Both become async (or marker registry is loaded once at app launch and kept in @MainActor singleton)

### False-positive guards

The current detector matches "meta" anywhere — flagged a user's vacation photo titled "Meta-data backup" once. Add a guard: only fire if the marker is in a BINARY atom (raw bytes that decode to text), not in user-typed strings. Effectively: require the marker to be in `kCGImagePropertyXMPData` (binary), Comment/Description QuickTime atoms with binary payload, or MakerApple namespace. Skip user-facing tags.

## Files to change

- New: `VideoCompressor/ios/Services/MetaMarkerRegistry.swift`
- New: `VideoCompressor/MetaMarkers.json` (resource file added to bundle)
- Modify: `VideoCompressor/ios/Services/MetadataService.swift` — `isMetaGlassesFingerprint`
- Modify: `VideoCompressor/ios/Services/PhotoMetadataService.swift` — `xmpContainsFingerprint`
- New tests: `VideoCompressor/VideoCompressorTests/MetaMarkerRegistryTests.swift`

## Future: opt-in feedback loop

Beyond v1.0: a UI surface where the user can submit a fingerprint sample for inclusion in the next `MetaMarkers.json` update. Strict opt-in with anonymous metadata-only payload (no pixels). For now: skip — just bundle a regularly-updated JSON.

## Acceptance criteria

- [ ] All current detection still fires (existing tests pass)
- [ ] Registry loads from JSON, falls back to hardcoded if file missing
- [ ] At least one new device marker added (e.g. Oakley Meta)
- [ ] False-positive guard added: a photo with "Meta" in user-typed XMP description does NOT trigger a strip
- [ ] 10+ test cases covering binary vs text source, multiple markers, edge cases
