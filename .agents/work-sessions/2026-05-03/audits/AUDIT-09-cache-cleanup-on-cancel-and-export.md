# AUDIT-09: Cache Cleanup on Cancel, Export, and Launch

**Auditor:** subagent/opus (READ-ONLY)
**Date:** 2026-05-03
**Scope:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/`
**Question:** Does the app clean up temp / staging / output files when (A) the user cancels mid-operation, (B) export + save-to-Photos succeeds, (C) the app is killed mid-flight?

## TL;DR

13 findings. **Two CRITICAL** (user-visible storage bloat after every successful save), **five HIGH** (zombie temp files that accumulate over many runs), **three MEDIUM**, **three LOW**. The single most user-visible defect: after a successful Stitch save-to-Photos, the entire stitched output (often 600 MB+) sits in `Documents/StitchOutputs/` indefinitely. The compress equivalent (`Documents/Outputs/`) has the same defect. CacheSweeper's only safety net is a 7-day stale-file launch sweep that touches **only** the six `Documents/` subdirs, never `NSTemporaryDirectory()`.

---

## Recommended cleanup policy (proposed for confirmation)

| Pipeline               | On cancel                                  | On save-to-Photos success                           | On next launch (fallback)                  |
|------------------------|--------------------------------------------|-----------------------------------------------------|--------------------------------------------|
| Compress               | Remove partial output **+ Inputs copy**    | Remove **Outputs copy** after confirmable delay     | Sweep Inputs + Outputs older than N days   |
| Stitch                 | Remove partial output, baked stills, clips | Remove **StitchOutputs copy** after delay           | Sweep Stitch dirs + StillBakes/            |
| MetaClean (single)     | Remove partial `_CLEAN`, PhotoClean-* dir  | Remove cleaned + CleanInputs source after delay     | Sweep CleanInputs + Cleaned + PhotoClean-* |
| MetaClean (batch)      | Stop, leave processed items intact         | Same as single per-item                             | Same                                       |
| Still bake (in stitch) | Remove partial .mov                        | (subsumed by stitch policy)                         | Sweep StillBakes/                          |
| PhotosPicker (Picks-*) | (cleanup happens at copy-into-Inputs)      | n/a                                                 | Sweep Picks-* on launch                    |

**Open design decision:** "Confirmable delay" implementation. Two viable options (user picks):
- (a) 30-second toast with **Undo** button after save; auto-deletes when toast dismisses.
- (b) Saved-files badge persists in UI; user clears manually with a "Clear saved" button. Auto-cleared after 7 days.

Avoid silent immediate-delete on save — user wants explicit confirmation per scenario B.

---

## Findings

### F1 — CRITICAL: Compressed output never deleted after save-to-Photos succeeds

**File:** `Services/VideoLibrary.swift:454-482` (`saveOutputToPhotos`)

**Current behavior:** On successful save, `Task.detached` calls `CacheSweeper.shared.deleteIfInWorkingDir(sourceURL)` — but `sourceURL` is the **Inputs/** copy (line 471), NOT the **Outputs/** copy. The compressed output at `video.output.url` (in Documents/Outputs/) stays on disk forever. This is "wrong-direction" cleanup: the recoverable Photos-original-redundant input is deleted, the unique compressed result is leaked.

**User wants:** After save-to-Photos success, the **output** copy should be cleaned (with confirmable delay). The Inputs copy is correct to remove (Photos has the original).

**Fix sketch (~6 LOC):**
```swift
// In saveOutputToPhotos, after the existing detached delete of sourceURL:
let outputURL = url  // already in scope from line 456
Task.detached(priority: .utility) {
    try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30 s confirm window
    await CacheSweeper.shared.deleteIfInWorkingDir(outputURL)
}
// Plus a UI toast with Undo to cancel that detached task.
```

---

### F2 — CRITICAL: Stitched output never deleted after save-to-Photos succeeds

**File:** `Views/StitchTab/StitchExportSheet.swift:206-223` (`runSaveToPhotos`)

**Current behavior:** After `PhotosSaver.saveVideo` succeeds, the function sets `saveStatus = .saved` and exits. The 200–800 MB stitched .mp4 in `Documents/StitchOutputs/<name>_STITCH.mp4` is never touched. User must delete it manually via Files.app or wait for the 7-day launch sweep.

**User wants:** Same delayed-confirmable cleanup as F1. The stitched output is the largest single file the app produces — leaking it doubles storage cost on every successful stitch save.

**Fix sketch (~8 LOC):** Mirror F1's pattern in StitchExportSheet:
```swift
case .saved:
    // ... existing UI ...
    .task(id: saveStatus) {
        // Schedule delayed cleanup on transition into .saved
        if case .saved = saveStatus {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await CacheSweeper.shared.deleteIfInWorkingDir(url)
        }
    }
```
Better: extract a shared `SavedFileCleanupCoordinator` actor that all three save paths call, with a single Undo banner managed at app level.

---

### F3 — HIGH: MetaClean leaves cleaned output AND CleanInputs source after save

**File:** `Views/MetaCleanTab/MetaCleanExportSheet.swift:118-148` (`run`)

**Current behavior:** After `PhotosSaver.saveAndOptionallyDeleteOriginal` succeeds, `onDone()` and `dismiss()` fire. Neither `metaResult.cleanedURL` (in Documents/Cleaned/) nor `item.sourceURL` (in Documents/CleanInputs/) is deleted. Both stay until 7-day sweep. Compounds across batch runs — user cleans 50 photos and now has 50 cleaned + 50 staged copies in Documents.

**User wants:** Both Cleaned and CleanInputs files removed after successful save with confirmable delay.

**Fix sketch (~10 LOC):** Inside the `case .success` block, after `onDone() / dismiss()`:
```swift
let cleanedURL = metaResult.cleanedURL
let staged = item.sourceURL
Task.detached(priority: .utility) {
    try? await Task.sleep(nanoseconds: 30_000_000_000)
    await CacheSweeper.shared.deleteIfInWorkingDir(cleanedURL)
    await CacheSweeper.shared.deleteIfInWorkingDir(staged)
}
```
Plus shared Undo banner per F2.

---

### F4 — HIGH: Cancelled stitch passthrough leaks partial output file

**File:** `Services/StitchExporter.swift:925-955` (`runPassthrough`)

**Current behavior:** When the user cancels mid-passthrough, `withTaskCancellationHandler.onCancel` calls `exporter.cancelExport()`. Switch falls through to `case .cancelled: throw CompressionError.cancelled` (line 941-942). **No `try? FileManager.default.removeItem(at: outputURL)` is performed**. The half-written .mp4 in `Documents/StitchOutputs/` stays on disk.

Compare with `CompressionService.encode` (line 456-457): it correctly removes the partial output on cancel. The passthrough path was missed.

**Fix sketch (~3 LOC):**
```swift
case .cancelled:
    try? FileManager.default.removeItem(at: outputURL)
    throw CompressionError.cancelled
case .failed:
    try? FileManager.default.removeItem(at: outputURL)  // also missing here
    // ... existing error handling
```

---

### F5 — HIGH: StillVideoBaker.bake has no cancellation handling — partial .movs orphaned

**File:** `Services/StillVideoBaker.swift:39-219` (`bake`)

**Current behavior:** `bake()` is called from `StitchExporter.buildPlan` inside a `for clip in clips` loop. The loop checks `Task.checkCancellation()` between clips (line 94), but `bake()` itself runs to completion once entered — it uses `withCheckedContinuation` (line 169) without `withTaskCancellationHandler`. There is no `Task.isCancelled` poll inside the frame-append loop.

**Two leaks:**
1. **Mid-bake cancel:** `Task.cancel()` while `bake` is running for clip N has no effect. The .mov in `NSTemporaryDirectory()/StillBakes/<uuid>.mov` is fully written, then on `bake`'s return the next iteration's `Task.checkCancellation()` throws, and the URL is appended to `bakedStillURLs` only IF baking finished. Whether the file was appended depends on the exact race with the throw point.
2. **Pre-append cancel:** The URL is `bakedStillURLs.append(bakedURL)` at StitchExporter.swift:102 ONLY AFTER `await baker.bake` returns. If cancellation throws between the bake completing and the append (line 96 `try Task.checkCancellation()` runs after the bake is fully done — but the exact path is: bake returns → next loop iteration → checkCancellation throws → defer in runExport runs cleanup, but only on `bakedStillURLs` already populated).

**Net effect:** N partial .mov files of large stills accumulate in `NSTemporaryDirectory()/StillBakes/` over the lifetime of the app. This dir is **not swept** by `CacheSweeper.sweepOnLaunch`.

**Fix sketch (~15 LOC):** Add task-cancellation honoring inside `bake`:
```swift
// At the top of bake() body:
return try await withTaskCancellationHandler {
    // existing body, with checks inside the frame-append loop:
    if Task.isCancelled {
        inputRef.markAsFinished()
        if counter.tryClaimResume() { continuation.resume() }
        return
    }
    // ... existing append code ...
} onCancel: {
    // We can't safely remove outURL here; do it after the await returns.
}
// At the end, after writer.finishWriting():
if Task.isCancelled {
    try? FileManager.default.removeItem(at: outURL)
    throw CancellationError()
}
```
Plus also clean up StillBakes/ in CacheSweeper (see F11).

---

### F6 — HIGH: PhotoMetadataService.strip leaks `PhotoClean-<uuid>/` on cancellation

**File:** `Services/PhotoMetadataService.swift:147-243` (`strip`)

**Current behavior:** A `PhotoClean-<uuid>/` temp dir is created at line 184-187. The cleanup `try? FileManager.default.removeItem(at: tmpDir)` only happens on the SUCCESS path at line 230, AFTER `replaceItemAt` succeeded. The cancellation throw points at line 153 and line 213 leak the dir.

If many large HEIC files are cancelled mid-strip, `NSTemporaryDirectory()` accumulates `PhotoClean-*` wrappers with full-resolution image copies inside. Not swept by CacheSweeper.

**Fix sketch (~8 LOC):** Use a defer for the temp dir:
```swift
// After tmpDir creation at line 187:
let tmpDirToCleanup = tmpDir
defer {
    try? FileManager.default.removeItem(at: tmpDirToCleanup)
}
// Remove the manual try? removeItem at line 230 (defer handles it).
```

---

### F7 — HIGH: PhotoCompressionService.compress leaks partial output on cancellation

**File:** `Services/PhotoCompressionService.swift:118-157`

**Current behavior:** `outputURL` (in Documents/Outputs/) is cleared at line 119, then `CGImageDestinationCreateWithURL` opens it for writing. `Task.checkCancellation()` is checked at line 112, line 148, and `CGImageDestinationFinalize` is called at line 150. If the task is cancelled at line 148 (after `CGImageDestinationAddImage`), the partial file is left on disk because `dest` is closed when it goes out of scope — the partial-state file persists.

**Fix sketch (~6 LOC):**
```swift
do {
    try Task.checkCancellation()
    // ... existing code through line 150 ...
} catch {
    try? FileManager.default.removeItem(at: outputURL)
    throw error
}
```

---

### F8 — HIGH: CacheSweeper does not sweep NSTemporaryDirectory subdirs

**File:** `Services/CacheSweeper.swift:28-32, 72-78`

**Current behavior:** `Self.allDirs` covers only the six `Documents/` subdirs. `NSTemporaryDirectory()/StillBakes/`, `NSTemporaryDirectory()/PhotoClean-*/`, and `NSTemporaryDirectory()/Picks-*/` are never enumerated or swept. iOS does NOT reliably reap NSTemporaryDirectory; the documented behavior is "reaped at OS discretion" and in practice files persist for weeks on devices with ample space.

**User wants:** Launch sweep as the fallback safety net — should cover ALL transient directories the app creates.

**Fix sketch (~12 LOC):**
```swift
// In CacheSweeper:
private static let tempSubdirs: [String] = ["StillBakes"]
private static let tempPrefixSweep: [String] = ["PhotoClean-", "Picks-"]

func sweepOnLaunch(daysOld: Int = 7) {
    // ... existing Documents sweep ...
    let tmpRoot = FileManager.default.temporaryDirectory
    let threshold = Date().addingTimeInterval(-Double(daysOld) * 86_400)
    for sub in Self.tempSubdirs {
        sweep(dir: tmpRoot.appendingPathComponent(sub), olderThan: threshold)
    }
    // Sweep Picks-* / PhotoClean-* by prefix (they're per-session UUIDs)
    if let entries = try? FileManager.default.contentsOfDirectory(
        at: tmpRoot, includingPropertiesForKeys: [.contentModificationDateKey]
    ) {
        for entry in entries {
            let name = entry.lastPathComponent
            guard Self.tempPrefixSweep.contains(where: name.hasPrefix) else { continue }
            let mtime = (try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
            if mtime < threshold {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
```

---

### F9 — MEDIUM: Cancelled compress does not delete the Inputs/ source copy

**File:** `Services/VideoLibrary.swift:352-355` and `Services/CompressionService.swift:454-458`

**Current behavior:** When `compress` is cancelled, `CompressionService.encode` removes `outputURL` (line 456). Good. But the source copy in `Documents/Inputs/` (created by `copyToWorkingDir` at line 118-139) remains. The user may have aborted because they realized the wrong file was queued — the Inputs copy is now orphaned because the picker tmp wrapper was already cleaned at line 137.

**User-impact tradeoff:** The Inputs copy is the only on-disk handle to that asset since Photos lifecycle URLs vanish. If the user retries the compress, deleting the Inputs copy means re-importing. Probably the right behavior is to keep it on cancel and only delete on save-to-Photos success (per F1's pattern).

**Recommendation:** Document the design intent (kept on cancel for retry). Don't delete here; F1's save-success delete handles the eventual cleanup.

---

### F10 — MEDIUM: Cancelled stitch leaves baked stills (when defer doesn't run)

**File:** `Models/StitchProject.swift:444-521` (`runExport`), `Services/StitchExporter.swift:91-124`

**Current behavior:** `bakedStillURLs` is captured by `defer` only AFTER `buildPlan` returns successfully. If `buildPlan` itself throws via `try Task.checkCancellation()` at line 94 (before the defer is registered in `runExport`), each .mov bake URL that was appended in earlier loop iterations is leaked. The `bakedStillURLs` array is local to `buildPlan` and never returned in the throw path.

**Fix sketch (~6 LOC):** In `buildPlan`, add a do/catch that cleans up partial bakes on cancellation:
```swift
do {
    for clip in clips {
        try Task.checkCancellation()
        // ... bake ...
    }
} catch {
    for url in bakedStillURLs {
        try? FileManager.default.removeItem(at: url)
    }
    throw error
}
```

---

### F11 — MEDIUM: Cancelled batch metaclean does not clean partial output of in-flight item

**File:** `Services/MetaCleanQueue.swift:220-276` (`runBatch`)

**Current behavior:** When the user cancels mid-batch, the loop's `if Task.isCancelled { break }` (line 228) exits. But the currently-in-flight `service.strip` may have its partial `_CLEAN.mp4` file already started. `MetadataService.strip` correctly cleans up its own partial output on cancellation (line 287). However, for `PhotoMetadataService.strip`, the `PhotoClean-*/` dir is leaked (see F6). Also, items with `cleanResult` already populated for past iterations have their cleanedURL files still on disk — this is correct, those are real outputs.

**Recommendation:** Fix F6 (defer the temp dir cleanup), then this finding becomes a non-issue.

---

### F12 — LOW: `clearAll()` and `deleteIfInWorkingDir` use sweep semantics that don't bound NSTemporaryDirectory

**File:** `Services/CacheSweeper.swift:81-101`

**Current behavior:** The Settings "Clear cache" button via `clearAll()` only clears the six `Documents/` subdirs. If the user explicitly clicks Clear Cache after seeing high storage usage from leaked StillBakes/PhotoClean-* dirs, those temp dirs are NOT cleared. Misleading UX.

**Fix sketch (~5 LOC):** Mirror the F8 fix in clearAll — sweep `NSTemporaryDirectory()` subdirs/prefixes at threshold `.distantFuture`.

---

### F13 — LOW: `markDirectoriesAsNonBackup` runs only at init, not for new transient files

**File:** `Services/VideoLibrary.swift:54-68`

**Current behavior:** Only the 6 Documents/ subdirs are marked `isExcludedFromBackup`. `NSTemporaryDirectory()` is already excluded by iOS by default, so this is fine — but if any future code creates new top-level subdirs in `Documents/`, they'd silently start being backed up.

**Recommendation:** Add an assertion / lint helper that fails if the production code creates a Documents/ subdir not in `CacheSweeper.allDirs`. Defensive only.

---

## Scenario summary against user requirements

| Scenario                                    | Current        | Required by user                      | Gap (finding refs)         |
|---------------------------------------------|----------------|---------------------------------------|----------------------------|
| A. Cancel mid-compress encode               | Output cleaned | Output cleaned ✓                     | F9 (Inputs left, OK)       |
| A. Cancel mid-stitch re-encode              | Output cleaned | Output cleaned + bakes cleaned       | F10                        |
| A. Cancel mid-stitch passthrough            | **LEAKED**     | Output cleaned                       | F4 CRITICAL                |
| A. Cancel mid-MetaClean strip (video)       | Output cleaned | Output cleaned ✓                     | none                       |
| A. Cancel mid-MetaClean strip (photo)       | **LEAKED dir** | Temp dir cleaned                     | F6 HIGH                    |
| A. Cancel mid-still-bake                    | **LEAKED .mov**| Partial cleaned                      | F5 HIGH                    |
| A. Cancel mid-batch metaclean               | Per-item OK    | Per-item cleanup                     | F6, F11                    |
| B. Compress save-to-Photos succeeds         | **OUTPUT KEPT**| Output cleaned after delay           | F1 CRITICAL                |
| B. Stitch save-to-Photos succeeds           | **OUTPUT KEPT**| Output cleaned after delay           | F2 CRITICAL                |
| B. MetaClean save-to-Photos succeeds        | **BOTH KEPT**  | Cleaned + staged input cleaned       | F3 HIGH                    |
| C. App killed mid-export, next launch       | Partial sweep  | Full sweep incl. NSTemporaryDirectory| F8 HIGH                    |

---

## Counts

- **CRITICAL: 2** (F1, F2 — user-visible storage doubling on every save)
- **HIGH: 5**     (F3, F4, F5, F6, F8)
- **HIGH (PhotoCompress): 1** (F7 — partial-output leak on photo compress cancel)
- **MEDIUM: 3**   (F9, F10, F11)
- **LOW: 2**      (F12, F13)

**Total: 13 findings** across cancellation, post-save cleanup, and launch-fallback gaps.

## Suggested fix order (highest user-impact / smallest blast radius)

1. **F8** — Extend `CacheSweeper.sweepOnLaunch` to cover NSTemporaryDirectory. ~15 LOC, zero behavioral risk, recovers all already-leaked space on next launch.
2. **F4** — One-line fix for stitch passthrough partial-output cleanup.
3. **F6** — `defer` cleanup of `PhotoClean-*/`.
4. **F1 + F2 + F3** — Build the shared `SavedFileCleanupCoordinator` with the 30s-Undo toast (or whichever pattern user picks). All three save paths use it. ~80 LOC total including UI.
5. **F5** — Cancellation-honoring `bake()`. ~15 LOC.
6. **F7, F10, F11, F9** — Smaller per-pipeline fixups.
7. **F12, F13** — Polish.
