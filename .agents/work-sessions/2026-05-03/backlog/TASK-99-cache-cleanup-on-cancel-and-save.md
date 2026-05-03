# TASK-99 — Aggressive cache cleanup on cancel + after save

**Priority:** HIGH — user-reported.
**Estimated effort:** 2-3 hours.
**Branch:** `feat/aggressive-cache-cleanup` off `main`.

## User concern (verbatim, 2026-05-03)

> "If I press cancel it should clear the cache of those temp files. Also if a video is exported and saved how do we clear the cache of that stuff automatically? To not clog up the space the app takes."

## Problem

Today, several disk areas accumulate orphaned files because cleanup only runs on launch via `CacheSweeper.sweepOnLaunch(daysOld: 7)` — a 7-day window means files persist across MANY user sessions before being purged.

Specifically:
- **Cancel mid-export**: partial output stays in `Documents/Outputs/` or `Documents/StitchOutputs/`
- **Save to Photos succeeds**: the local copy in our sandbox is duplicated (Photos copy + sandbox copy). User wants the sandbox copy removed after confirmed save.
- **Stitch baked-stills**: `.mov` files in `NSTemporaryDirectory()/StillBakes/` get cleaned (PR #8 added a defer block) — verify this still works.
- **PhotosPicker wrappers**: `NSTemporaryDirectory()/Picks-*/` dirs from `loadTransferable` — currently not swept.

## Audit reference

Read `.agents/work-sessions/2026-05-03/audits/AUDIT-09-cache-cleanup-on-cancel-and-export.md` for the full file:line breakdown of every cleanup gap (agent ran 2026-05-03).

## Goals

1. **On Cancel of any operation**: immediately remove the partial output file + any operation-specific temp dirs.
2. **On successful save to Photos**: schedule a 30-second post-save sweep that removes our sandbox copy IF the save genuinely succeeded.
3. **On app launch**: tighten `daysOld: 7` to `daysOld: 1` for working dirs (Documents/{Inputs, Outputs, Cleaned, StitchInputs, StitchOutputs}). NSTemporaryDirectory swept aggressively (any age — iOS doesn't reliably reap).

## Implementation sketch

### `CacheSweeper.swift` extensions

```swift
extension CacheSweeper {
    /// Remove a specific file or dir from any tracked working dir.
    /// Idempotent + safe — checks the path is inside our sandbox first.
    func deleteIfInWorkingDir(_ url: URL) async { /* already exists */ }

    /// Aggressive sweep — runs after every successful save-to-Photos.
    /// Scoped to just our copy of the saved file (caller passes the URL).
    func sweepAfterSave(_ savedSandboxURL: URL) async {
        // 30-second delay so the user can re-share if they want, then nuke.
        try? await Task.sleep(for: .seconds(30))
        await deleteIfInWorkingDir(savedSandboxURL)
    }

    /// Cancel-time sweep — removes the partial output AT the predicted URL.
    /// Called from CompressionService.encode + StitchExporter on cancel.
    func sweepOnCancel(predictedOutputURL: URL) async {
        try? FileManager.default.removeItem(at: predictedOutputURL)
    }

    /// Add NSTemporaryDirectory subdirs to the sweep set.
    /// Currently only Documents/* are swept on launch.
    static let allDirs: [URL] = { /* extend with tmp/StillBakes, tmp/Picks-*, tmp/PhotoClean-* */ }()
}
```

### Wire in

- `CompressionService.encode` cancellation paths (lines ~213, 405-407): call `CacheSweeper.sweepOnCancel(predictedOutputURL:)`
- `StitchExporter` runReencode + runPassthrough cancellation paths
- `MetadataService.strip` failure paths
- `StillVideoBaker.bake` early-throw paths (after writer.startWriting)
- `VideoLibrary.saveOutputToPhotos` success path: call `CacheSweeper.sweepAfterSave(savedURL)`
- `MetaCleanQueue.runClean` success path: call sweepAfterSave
- `StitchProject.runExport` success path: same

### Settings UI

Add a Settings row "Cache: 12.4 MB · Clear" already exists (CacheSweeper.totalCacheBytes / .breakdown). After this PR the breakdown should reflect the new tmp/ dirs we sweep.

## Acceptance criteria

- [ ] After cancelling a compress export, no partial output file in Documents/Outputs/
- [ ] After cancelling a stitch export, no baked .movs in tmp/StillBakes/, no partial output in Documents/StitchOutputs/
- [ ] After successful save-to-Photos, sandbox copy is removed within 30 seconds
- [ ] Settings cache breakdown reflects tmp/ contributions
- [ ] Settings "Clear cache" wipes EVERY working dir (Documents AND tmp)
- [ ] App launch sweep runs on all working dirs, not just Documents/
- [ ] No new tests fail; ideally add `CacheSweeperTests` covering sweepOnCancel + sweepAfterSave
