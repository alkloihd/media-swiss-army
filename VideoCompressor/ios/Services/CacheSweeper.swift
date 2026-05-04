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

    static let tmpSubdirs: [String] = [
        "StillBakes",
    ]

    static let tmpDirPrefixes: [String] = [
        "Picks-",
        "PhotoClean-",
    ]

    private let documents: URL =
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private let tmpRoot: URL = FileManager.default.temporaryDirectory

    // MARK: - Public API

    /// Sum of bytes across all managed cache dirs.
    func totalCacheBytes() -> Int64 {
        Self.allDirs.reduce(managedTmpBytes()) { acc, name in
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
            case "tmp":           return "Temporary working files"
            default:              return name
            }
        }
    }

    func breakdown() -> [FolderStat] {
        var stats = Self.allDirs.map { name in
            FolderStat(name: name, bytes: folderSize(documents.appendingPathComponent(name)))
        }
        let tmpBytes = managedTmpBytes()
        if tmpBytes > 0 {
            stats.append(FolderStat(name: "tmp", bytes: tmpBytes))
        }
        return stats
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

    /// Launch sweep for v1 cache hygiene: tighter Documents threshold plus
    /// aggressive cleanup of app-owned tmp wrappers that iOS may not reap.
    func sweepOnLaunchTight() {
        sweepOnLaunch(daysOld: 1)
        sweepTmpAggressive()
    }

    /// Manual full wipe (Settings "Clear cache" button).
    func clearAll() {
        for name in Self.allDirs {
            let dir = documents.appendingPathComponent(name, isDirectory: true)
            sweep(dir: dir, olderThan: .distantFuture)
        }
        sweepTmpAggressive()
    }

    /// Cancel-time targeted sweep. Removes only app-owned working files and
    /// app-owned tmp wrappers related to the predicted output.
    func sweepOnCancel(predictedOutputURL: URL?) {
        guard let url = predictedOutputURL else { return }
        deleteIfInWorkingDir(url)
        deleteIfInManagedTmp(url)
    }

    /// Post-save sweep. Production callers use the 30 s default so the user
    /// has a short window to re-share the sandbox copy after Photos succeeds.
    func sweepAfterSave(_ savedSandboxURL: URL) async {
        await sweepAfterSave(savedSandboxURL, delay: .seconds(30))
    }

    /// Testable overload for the delayed sweep hook.
    func sweepAfterSave(_ savedSandboxURL: URL, delay: Duration) async {
        try? await Task.sleep(for: delay)
        deleteIfInWorkingDir(savedSandboxURL)
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

    private func deleteIfInManagedTmp(_ url: URL) {
        let fm = FileManager.default
        let standardized = url.standardizedFileURL
        let path = standardized.path
        let tmpPath = tmpRoot.standardizedFileURL.path

        for name in Self.tmpSubdirs {
            let dirPath = "\(tmpPath)/\(name)/"
            if path.hasPrefix(dirPath) {
                try? fm.removeItem(at: standardized)
                return
            }
        }

        let parent = standardized.deletingLastPathComponent()
        guard parent.standardizedFileURL.path.hasPrefix("\(tmpPath)/") else { return }
        if Self.tmpDirPrefixes.contains(where: { parent.lastPathComponent.hasPrefix($0) }) {
            try? fm.removeItem(at: parent)
        }
    }

    private func sweepTmpAggressive() {
        let fm = FileManager.default
        for name in Self.tmpSubdirs {
            sweep(
                dir: tmpRoot.appendingPathComponent(name, isDirectory: true),
                olderThan: .distantFuture
            )
        }

        guard let entries = try? fm.contentsOfDirectory(
            at: tmpRoot,
            includingPropertiesForKeys: nil
        ) else { return }

        for entry in entries
            where Self.tmpDirPrefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) }) {
            try? fm.removeItem(at: entry)
        }
    }

    private func managedTmpBytes() -> Int64 {
        var bytes: Int64 = 0
        for name in Self.tmpSubdirs {
            bytes += folderSize(tmpRoot.appendingPathComponent(name, isDirectory: true))
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tmpRoot,
            includingPropertiesForKeys: nil
        ) else { return bytes }

        for entry in entries
            where Self.tmpDirPrefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) }) {
            bytes += folderSize(entry)
        }
        return bytes
    }

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
