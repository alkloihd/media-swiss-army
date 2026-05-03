//
//  PhotoMetadataService.swift
//  VideoCompressor
//
//  Photo equivalent of `MetadataService`. Reads, classifies, and strips
//  metadata from HEIC / JPEG / PNG files via ImageIO. Reuses the typed
//  `MetadataTag`, `MetadataCategory`, `StripRules`, `MetadataCleanResult`
//  model from MetadataTag.swift so the inspector UI is identical.
//
//  Read pipeline:
//   - `CGImageSourceCopyPropertiesAtIndex` returns the top-level props dict
//     containing nested EXIF / TIFF / GPS / MakerApple / IPTC / XMP dicts.
//   - We walk each nested dict and emit one `MetadataTag` per atom.
//   - Categorization mirrors the video service:
//       GPS keys              → .location
//       DateTime / Original   → .time
//       Make / Model / Software / LensMake / LensModel → .device
//       Pixel dims / orient.  → .technical
//       everything else       → .custom
//
//  Strip pipeline:
//   - `CGImageDestinationCreateWithURL` to a temp file using the source's UTI.
//   - `CGImageDestinationAddImageFromSource` with a properties dict that
//     replaces the offending sub-dicts with `kCFNull` (per Apple docs, this
//     deletes the key on the destination).
//   - `CGImageDestinationFinalize`, then `FileManager.replaceItemAt` for an
//     atomic in-place replacement.
//
//  Phase 3 commit 5 (2026-05-03).
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

// `kCGImagePropertyXMPData` exists only on macOS (not in iOS ImageIO headers).
// Declare a local constant using the raw key string so the code compiles on iOS.
// On write, passing kCFNull for this key omits the XMP packet from the destination.
private let kCGImagePropertyXMPData = "kCGImagePropertyXMPData" as CFString

enum PhotoMetadataServiceError: Error, LocalizedError, Hashable, Sendable {
    case sourceUnreadable(String)
    case destinationFailed(String)
    case writeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceUnreadable(let m): return "Could not read photo: \(m)"
        case .destinationFailed(let m): return "Could not create cleaned photo: \(m)"
        case .writeFailed(let m):      return "Failed during photo write: \(m)"
        case .cancelled:               return "Cleaning was cancelled."
        }
    }
}

actor PhotoMetadataService {

    // MARK: - Read

    /// Read all metadata atoms from a photo file. Returns one tag per atom
    /// across EXIF / TIFF / GPS / MakerApple / XMP / IPTC namespaces.
    func read(url: URL) async throws -> [MetadataTag] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PhotoMetadataServiceError.sourceUnreadable("CGImageSourceCreateWithURL nil")
        }
        guard CGImageSourceGetCount(source) > 0 else { return [] }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] ?? [:]

        var tags: [MetadataTag] = []
        var seen = Set<String>()

        // Top-level scalar props (PixelWidth/Height, Orientation, ColorModel)
        for (rawKey, rawValue) in props {
            let keyString = (rawKey as String)
            // Skip nested dicts here — handled below per-namespace.
            if rawValue is [CFString: Any] || rawValue is [String: Any] { continue }
            if rawValue is Data { continue } // XMPData handled below
            let tag = makeTag(
                namespace: nil,
                key: keyString,
                value: stringify(rawValue)
            )
            let dedupe = "\(tag.key)|\(tag.value)"
            if !seen.contains(dedupe) { seen.insert(dedupe); tags.append(tag) }
        }

        // Nested namespaces.
        let namespaces: [(prefix: String, key: CFString)] = [
            ("Exif",        kCGImagePropertyExifDictionary),
            ("ExifAux",     kCGImagePropertyExifAuxDictionary),
            ("TIFF",        kCGImagePropertyTIFFDictionary),
            ("GPS",         kCGImagePropertyGPSDictionary),
            ("IPTC",        kCGImagePropertyIPTCDictionary),
            ("MakerApple",  kCGImagePropertyMakerAppleDictionary),
            ("PNG",         kCGImagePropertyPNGDictionary),
            ("JFIF",        kCGImagePropertyJFIFDictionary),
        ]
        for ns in namespaces {
            guard let dict = props[ns.key] as? [CFString: Any] else { continue }
            for (rawKey, rawValue) in dict {
                let keyString = (rawKey as String)
                if rawValue is [CFString: Any] { continue }
                let tag = makeTag(
                    namespace: ns.prefix,
                    key: keyString,
                    value: stringify(rawValue)
                )
                let dedupe = "\(tag.key)|\(tag.value)"
                if !seen.contains(dedupe) { seen.insert(dedupe); tags.append(tag) }
            }
        }

        // XMP packet — raw binary blob; decode to UTF-8 and look for Meta /
        // C2PA / RayBan markers.
        if let xmpData = props[kCGImagePropertyXMPData] as? Data {
            let decoded = String(data: xmpData, encoding: .utf8)
                ?? String(data: xmpData, encoding: .ascii)
                ?? ""
            let isFingerprint = Self.xmpContainsFingerprint(decoded)
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

        return tags
    }

    // MARK: - Strip

    /// Re-encode the source file omitting metadata that matches `rules`.
    /// Atomically replaces the file at the source URL — the original (with
    /// the metadata) is discarded.
    ///
    /// Returns a `MetadataCleanResult` whose `cleanedURL` is the same path
    /// that was passed in (the file in place) — mirrors video's behavior
    /// from the caller's POV.
    func strip(
        url sourceURL: URL,
        rules: StripRules,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> MetadataCleanResult {
        await MainActor.run { onProgress(BoundedProgress(0.0)) }
        try Task.checkCancellation()

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw PhotoMetadataServiceError.sourceUnreadable("CGImageSourceCreateWithURL nil")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw PhotoMetadataServiceError.sourceUnreadable("Empty image source")
        }

        // Read all tags first so we can record kept vs stripped for the result.
        let allTags = try await read(url: sourceURL)
        var kept: [MetadataTag] = []
        var stripped: [MetadataTag] = []
        for tag in allTags {
            if shouldStrip(tag: tag, rules: rules) {
                stripped.append(tag)
            } else {
                kept.append(tag)
            }
        }

        // Determine source UTI; if unknown, fall back to PhotoFormat.detect.
        let utiString: CFString = {
            if let cfUTI = CGImageSourceGetType(source) { return cfUTI }
            if let fmt = PhotoFormat.detect(from: sourceURL) {
                return fmt.utType.identifier as CFString
            }
            return UTType.jpeg.identifier as CFString
        }()

        // Output to a temp URL; replace at the end.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoClean-\(UUID().uuidString.prefix(6))",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpOut = tmpDir.appendingPathComponent(sourceURL.lastPathComponent)

        guard let dest = CGImageDestinationCreateWithURL(
            tmpOut as CFURL, utiString, 1, nil
        ) else {
            throw PhotoMetadataServiceError.destinationFailed("CGImageDestinationCreateWithURL nil")
        }

        // Build a properties dict that *removes* the offending namespaces.
        // Per Apple docs, setting a property to `kCFNull` in the dict passed
        // to `CGImageDestinationAddImageFromSource` deletes that key on the
        // destination.
        let removeDict = buildRemoveDict(rules: rules)

        CGImageDestinationAddImageFromSource(
            dest, source, 0, removeDict as CFDictionary
        )

        try Task.checkCancellation()
        await MainActor.run { onProgress(BoundedProgress(0.5)) }

        guard CGImageDestinationFinalize(dest) else {
            throw PhotoMetadataServiceError.writeFailed("CGImageDestinationFinalize false")
        }

        // Atomic replace at the original URL. `replaceItemAt` handles the
        // backup + move-into-place + cleanup.
        let replaced: URL
        do {
            replaced = try FileManager.default.replaceItemAt(sourceURL, withItemAt: tmpOut) ?? sourceURL
        } catch {
            throw PhotoMetadataServiceError.writeFailed(error.localizedDescription)
        }

        // Best-effort cleanup of the temp dir wrapper.
        try? FileManager.default.removeItem(at: tmpDir)

        let bytes: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: replaced.path)[.size] as? NSNumber)?.int64Value ?? 0

        await MainActor.run { onProgress(.complete) }

        return MetadataCleanResult(
            cleanedURL: replaced,
            bytes: bytes,
            tagsStripped: stripped,
            tagsKept: kept
        )
    }

    // MARK: - Auto-fingerprint helper (parity with MetadataService)

    /// Scans `url` for Meta-glasses fingerprint atoms in stills (XMP packet
    /// markers, MakerApple software string). If any are present, runs a
    /// `.autoMetaGlasses` strip pass. Fail-soft.
    @discardableResult
    func stripMetaFingerprintInPlace(at url: URL) async -> Bool {
        do {
            let tags = try await read(url: url)
            guard tags.contains(where: { $0.isMetaFingerprint }) else {
                return false
            }
            _ = try await strip(url: url, rules: .autoMetaGlasses) { _ in }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    /// Map a key + namespace into a `MetadataTag` with category + fingerprint
    /// flag.
    private func makeTag(namespace: String?, key: String, value: String) -> MetadataTag {
        let fullKey = namespace.map { "\($0).\(key)" } ?? key
        let category = Self.categoryFor(namespace: namespace, key: key)
        let display = Self.displayNameFor(namespace: namespace, key: key)
        let isFp = Self.isFingerprintTag(namespace: namespace, key: key, value: value)
        return MetadataTag(
            id: UUID(),
            key: fullKey,
            displayName: display,
            value: value,
            category: category,
            isMetaFingerprint: isFp
        )
    }

    private static func categoryFor(namespace: String?, key: String) -> MetadataCategory {
        let k = key.lowercased()
        if namespace == "GPS" { return .location }
        if namespace == "MakerApple" { return .device }
        if k.contains("gps") || k.contains("location") { return .location }
        if k.contains("date") || k.contains("time") { return .time }
        if k.contains("make") || k.contains("model") || k.contains("software")
            || k.contains("lens") || k.contains("device") || k.contains("manufacturer") {
            return .device
        }
        if k.contains("pixel") || k.contains("orientation") || k.contains("color")
            || k.contains("dpi") || k.contains("resolution") || k.contains("profile")
            || k.contains("samplesperpixel") || k.contains("bitsper") {
            return .technical
        }
        return .custom
    }

    private static func displayNameFor(namespace: String?, key: String) -> String {
        if let ns = namespace { return "\(ns) · \(key)" }
        return key
    }

    /// Fingerprint detection for stills:
    ///   - XMP packet contents containing "xmp.MetaAI", "meta:", "RayBan",
    ///     "Ray-Ban", "c2pa", or "ManifestStore" markers
    ///   - MakerApple `Software` value containing "Meta" or "Ray-Ban"
    static func isFingerprintTag(namespace: String?, key: String, value: String) -> Bool {
        let v = value.lowercased()
        if namespace == "MakerApple" {
            if key.lowercased().contains("software") {
                if v.contains("meta") || v.contains("ray-ban") || v.contains("rayban") {
                    return true
                }
            }
        }
        return false
    }

    static func xmpContainsFingerprint(_ packet: String) -> Bool {
        let p = packet.lowercased()
        return p.contains("xmp.metaai")
            || p.contains("meta:")
            || p.contains("ray-ban")
            || p.contains("rayban")
            || p.contains("c2pa")
            || p.contains("manifeststore")
    }

    /// Predicate matching MetadataService.shouldStrip exactly.
    private func shouldStrip(tag: MetadataTag, rules: StripRules) -> Bool {
        if tag.category == .technical { return false }
        if tag.isMetaFingerprint && rules.stripMetaFingerprintAlways { return true }
        return rules.stripCategories.contains(tag.category)
    }

    /// Build the properties dictionary handed to
    /// `CGImageDestinationAddImageFromSource`. Setting a key to `kCFNull`
    /// deletes that key on the destination. We delete entire namespaces when
    /// any category they map to is requested for stripping.
    private func buildRemoveDict(rules: StripRules) -> [CFString: Any] {
        var dict: [CFString: Any] = [:]

        // Always nuke embedded thumbnails and JFIF preview when stripping
        // anything (keeps output lean — these aren't the user's "metadata"
        // in the inspector sense but they're often a few KB of stale data).
        dict[kCGImagePropertyExifAuxDictionary] = kCFNull as Any

        if rules.stripCategories.contains(.location) {
            dict[kCGImagePropertyGPSDictionary] = kCFNull as Any
        }
        if rules.stripCategories.contains(.device) {
            dict[kCGImagePropertyMakerAppleDictionary] = kCFNull as Any
            // TIFF holds Make/Model/Software — but also intrinsic resolution
            // info. Strip individual TIFF date keys via Exif below; leaving
            // TIFF as-is preserves dimensions but exposes Make/Model. For
            // user-visible "Device", null the whole TIFF dict; user can
            // pick the granular path later.
            dict[kCGImagePropertyTIFFDictionary] = kCFNull as Any
        }
        if rules.stripCategories.contains(.time) {
            // Date lives across Exif and TIFF. If device wasn't asked for,
            // we still need to strip dates; we model this by setting
            // exif.DateTimeOriginal etc. to kCFNull via a nested dict.
            // CGImageDestination merges the destination dict with the source
            // metadata; nested kCFNull deletes the nested key.
            var exifDict: [CFString: Any] = [:]
            exifDict[kCGImagePropertyExifDateTimeOriginal] = kCFNull as Any
            exifDict[kCGImagePropertyExifDateTimeDigitized] = kCFNull as Any
            dict[kCGImagePropertyExifDictionary] = exifDict
            // TIFF DateTime sits in the TIFF dict; nuke just that field.
            if dict[kCGImagePropertyTIFFDictionary] == nil {
                var tiffDict: [CFString: Any] = [:]
                tiffDict[kCGImagePropertyTIFFDateTime] = kCFNull as Any
                dict[kCGImagePropertyTIFFDictionary] = tiffDict
            }
        }
        if rules.stripMetaFingerprintAlways {
            // XMP packet is where Meta stashes its provenance. Drop it —
            // we lose any benign XMP tags too, but the user opted in.
            dict[kCGImagePropertyXMPData] = kCFNull as Any
        }
        if rules.stripCategories.contains(.custom) {
            // Strip XMP packet for custom too (where unknown app-specific
            // metadata lives).
            dict[kCGImagePropertyXMPData] = kCFNull as Any
            dict[kCGImagePropertyIPTCDictionary] = kCFNull as Any
        }
        return dict
    }

    /// Best-effort string preview for arbitrary metadata values.
    private func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let arr = value as? [Any] {
            return "[\(arr.map { stringify($0) }.joined(separator: ", "))]"
        }
        if let d = value as? Data { return "<binary, \(d.count) bytes>" }
        return "\(value)"
    }
}
