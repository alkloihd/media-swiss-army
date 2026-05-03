//
//  CacheSweeper.swift
//  VideoCompressor
//
//  Manages the app's six working directories under Documents/.
//  Sweeps stale files at app launch and provides a manual "clear cache"
//  path for the Settings UI.
//
//  NOTE: sweep() and folderSize() enumerate only the top-level of each
//  working dir (no subdirectories). All working dirs store flat file lists
//  today; if nested subdirs are added in future, update these helpers.
//

import Foundation

/// Actor managing the six working directories under Documents/.
///
/// Six directories tracked:
///   Documents/Inputs           (Compress picker imports)
///   Documents/Outputs          (Compress encoder outputs)
///   Documents/StitchInputs     (Stitch picker imports)
///   Documents/StitchOutputs    (Stitch encoder outputs)
///   Documents/CleanInputs      (MetaClean picker imports)
///   Documents/Cleaned          (MetaClean remux outputs)
actor CacheSweeper {
    static let shared = CacheSweeper()

    static let allDirs: [String] = [
        "Inputs", "Outputs",
        "StitchInputs", "StitchOutputs",
        "CleanInputs", "Cleaned",
    ]

    private let documents: URL =
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    // MARK: - Public API

    /// Sum of bytes across all 6 dirs.
    func totalCacheBytes() -> Int64 {
        Self.allDirs.reduce(0) { acc, name in
            acc + folderSize(documents.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// Per-folder size breakdown for the Settings UI.
    struct FolderStat: Hashable, Sendable {
        let name: String
        let bytes: Int64

        var displayName: String {
            switch name {
            case "Inputs":        return "Imported videos"
            case "Outputs":       return "Compressed outputs"
            case "StitchInputs":  return "Stitch imports"
            case "StitchOutputs": return "Stitch outputs"
            case "CleanInputs":   return "MetaClean imports"
            case "Cleaned":       return "MetaClean outputs"
            default:              return name
            }
        }
    }

    func breakdown() -> [FolderStat] {
        Self.allDirs.map { name in
            FolderStat(name: name, bytes: folderSize(documents.appendingPathComponent(name)))
        }
    }

    /// Sweep on app launch: remove files older than `daysOld` days from all
    /// 6 directories. Default 7 days. Fail-soft per file.
    func sweepOnLaunch(daysOld: Int = 7) {
        let threshold = Date().addingTimeInterval(-Double(daysOld) * 86_400)
        for name in Self.allDirs {
            let dir = documents.appendingPathComponent(name, isDirectory: true)
            sweep(dir: dir, olderThan: threshold)
        }
    }

    /// Manual full wipe (Settings "Clear cache" button).
    func clearAll() {
        for name in Self.allDirs {
            let dir = documents.appendingPathComponent(name, isDirectory: true)
            sweep(dir: dir, olderThan: .distantFuture)
        }
    }

    /// Targeted delete — called from VideoLibrary after a successful
    /// save-to-Photos. Only removes the file if it lives under one of our
    /// working directories; never touches Photos library originals.
    func deleteIfInWorkingDir(_ url: URL) {
        let path = url.standardizedFileURL.path
        let docsPath = documents.standardizedFileURL.path
        for name in Self.allDirs {
            let dirPath = "\(docsPath)/\(name)/"
            if path.hasPrefix(dirPath) {
                try? FileManager.default.removeItem(at: url)
                return
            }
        }
    }

    // MARK: - Private helpers

    private func sweep(dir: URL, olderThan threshold: Date) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries {
            let mtime =
                (try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date()
            if mtime < threshold {
                try? fm.removeItem(at: entry)
            }
        }
    }

    // nonisolated so callers don't need an await just to read sizes.
    nonisolated private func folderSize(_ dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return entries.reduce(0) { acc, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return acc + Int64(size)
        }
    }
}
