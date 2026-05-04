//
//  MetaMarkerRegistry.swift
//  VideoCompressor
//
//  Bundle-only registry for Meta-glasses fingerprint markers.
//

import Foundation

actor MetaMarkerRegistry {
    static let shared = MetaMarkerRegistry()

    struct Markers: Decodable, Equatable, Sendable {
        var schemaVersion: Int
        var version: Int
        var lastUpdated: String?
        var deviceFamily: String?
        var binaryAtomMarkers: [String: [String]]
        var xmpFingerprints: [String]
        var makerAppleSoftware: [String]
        var deviceModelHints: [String]
        var falsePositiveGuards: Guards

        struct Guards: Decodable, Equatable, Sendable {
            var rejectIfMarkerInUserTypedText: [String]
            var minimumMarkerLengthBytes: Int
        }
    }

    private var cached: Markers?

    private init() {}

    func load() async -> Markers {
        if let cached { return cached }

        let url = Bundle.main.url(
            forResource: "MetaMarkers",
            withExtension: "json"
        )
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let markers = Self.parseOrFallback(data: data)
        cached = markers
        return markers
    }

    static func parseOrFallback(data: Data?) -> Markers {
        guard let data,
              let parsed = try? JSONDecoder().decode(Markers.self, from: data),
              parsed.schemaVersion == 1,
              parsed.falsePositiveGuards.minimumMarkerLengthBytes >= 1,
              !parsed.binaryAtomMarkers.isEmpty,
              !parsed.xmpFingerprints.isEmpty,
              !parsed.makerAppleSoftware.isEmpty
        else {
            return defaultBundled()
        }
        return parsed
    }

    static func defaultBundled() -> Markers {
        Markers(
            schemaVersion: 1,
            version: 0,
            lastUpdated: nil,
            deviceFamily: "legacy hardcoded fallback",
            binaryAtomMarkers: [
                "comment": ["ray-ban", "rayban", "meta"],
                "description": ["ray-ban", "rayban", "meta"]
            ],
            xmpFingerprints: [
                "xmp.metaai",
                "meta:",
                "ray-ban",
                "rayban",
                "c2pa",
                "manifeststore"
            ],
            makerAppleSoftware: ["meta", "ray-ban", "rayban"],
            deviceModelHints: [],
            falsePositiveGuards: .init(
                rejectIfMarkerInUserTypedText: ["comment", "description"],
                minimumMarkerLengthBytes: 8
            )
        )
    }

    func markersForBinaryAtom(key: String) async -> [String] {
        let markers = await load()
        let loweredKey = key.lowercased()
        for (suffix, list) in markers.binaryAtomMarkers
            where loweredKey.contains(suffix.lowercased()) {
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
