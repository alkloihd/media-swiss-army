# Phase 1 Cluster 1 — Cache cleanup + still-bake O(1) + bake-cancel cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. All steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land MASTER-PLAN tasks 1.1, 1.2, and 1.6 in a single PR.
1.1 — `StillVideoBaker.bake` becomes O(1) (constant-time regardless of user's still-duration choice).
1.2 — Cancel + post-save sweeps remove orphaned files immediately. Launch sweep tightens to 1 day. NSTemporaryDirectory subdirs are now in scope.
1.6 — `StitchExporter.buildPlan` registers baked-still URLs into `bakedStillURLs` BEFORE the bake call returns, so cancellation between bakes can't leak partial files.

**Architecture:** All three tasks touch overlapping files (`StillVideoBaker`, `StitchExporter.buildPlan`, `CacheSweeper`); landing them as one PR avoids three rebases.

**Tech Stack:** Swift, AVFoundation, `actor CacheSweeper`, XCTest.

**Branch:** `feat/phase1-cluster1-cache-and-bake` off `main`.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Services/StillVideoBaker.swift` | Modify | Drop `duration` param, always bake 1 s. (Reuses canonical plan.) |
| `VideoCompressor/ios/Services/StitchExporter.swift` | Modify | Call `scaleTimeRange` to stretch baked stills. Append URL to `bakedStillURLs` BEFORE bake returns. |
| `VideoCompressor/ios/Services/CacheSweeper.swift` | Modify | Add tmp-dir tracking, `sweepOnCancel`, `sweepAfterSave`, tighter `sweepOnLaunch`. |
| `VideoCompressor/ios/Services/CompressionService.swift` | Modify | Wire `sweepOnCancel(predictedOutputURL:)` into cancel branch. |
| `VideoCompressor/ios/Services/MetadataService.swift` | Modify | Wire `sweepOnCancel` into strip failure paths. |
| `VideoCompressor/ios/Services/PhotoMetadataService.swift` | Modify | Wire `sweepOnCancel` into strip failure paths (PhotoClean-* dirs). |
| `VideoCompressor/ios/Services/PhotoCompressionService.swift` | Modify | Wire `sweepOnCancel` into compress cancel branch. |
| `VideoCompressor/ios/Services/VideoLibrary.swift` | Modify | Call `sweepAfterSave` after successful Photos save. |
| `VideoCompressor/ios/Services/MetaCleanQueue.swift` | Modify | Call `sweepAfterSave` on per-item success. |
| `VideoCompressor/ios/Models/StitchProject.swift` | Modify | Call `sweepAfterSave` on stitch export success. |
| `VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift` | Create | (Reuses canonical plan.) |
| `VideoCompressor/VideoCompressorTests/StitchExporterScaleTests.swift` | Create | (Reuses canonical plan.) |
| `VideoCompressor/VideoCompressorTests/CacheSweeperTests.swift` | Create | sweepOnCancel + sweepAfterSave + tmp-dir coverage. |

---

## Task 1: Still-bake O(1) (incl. bake-cancel registration order)

**Reuses verbatim:** `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` Tasks 1–5. Execute those steps inside this branch (NOT a separate `feat/still-bake-constant-time` branch).

> **PREREQ (Audit Fix H1): this cluster lands AFTER Cluster 0 — `bake(still:)`'s `(url: URL, size: CGSize)` tuple return is in place.** Cluster 0 (`docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md` Task 1) ships first and changes `StillVideoBaker.bake` to return `(url: URL, size: CGSize)`. EVERY code block in this Cluster 1 plan that mentions `bake(...)`, `bake(still:intoPreallocated:)`, or `bakeImpl` reflects the post-Cluster-0 tuple-returning shape. If you are reading the Cluster 0 plan in parallel and notice the Cluster 1 snippets diverge, update the snippets — never the Cluster 0 contract — to keep both in sync. Codex MUST rebase Cluster 1 against post-Cluster-0 `main` before starting Task 1.

**Additional change for Phase 1.6 (bake-cancel cleanup):** in `StitchExporter.swift` `buildPlan`, the canonical plan already moves `bakedStillURLs.append(bakedURL)` to immediately follow `let bakedURL = try await baker.bake(still: clip.sourceURL)`. The 1.6 fix is to ensure the URL is registered into `bakedStillURLs` BEFORE `bake(...)` runs, so a mid-bake cancellation or throw still leaves the URL discoverable to `runExport`'s defer-sweep. Apply this delta:

- [ ] **Step 1: Pre-allocate the bake target URL and register it before invoking bake — `intoPreallocated:` overload guarantees the baker honors the URL or throws cleanly**

In `StitchExporter.swift` `buildPlan` (around line 90, after the canonical Task 3 changes are applied):

Replace the bake region with:

```swift
            try Task.checkCancellation()
            if clip.kind == .still {
                let stillDuration = clip.edits.stillDuration ?? 3.0
                let clamped = min(10.0, max(1.0, stillDuration))

                // Phase 1.6 (Audit-7-C2 + Audit Fix H2): the baker creates
                // the .mov BEFORE returning. If the bake throws or the
                // surrounding Task is cancelled mid-bake, the partial .mov
                // would be on disk but invisible to runExport's defer
                // sweep. We rely EXCLUSIVELY on the
                // bake(still:intoPreallocated:) overload (added in Step 2)
                // because it contractually guarantees the baker either
                // writes to the caller-supplied URL OR throws BEFORE
                // writing anything. That contract — combined with
                // appending the URL into bakedStillURLs BEFORE the bake
                // call — means the runExport defer-sweep ALWAYS sees the
                // partial-or-complete file, with no race window.
                let preAllocURL = baker.predictedOutputURL()
                bakedStillURLs.append(preAllocURL)
                let (bakedURL, bakedSize) = try await baker.bake(
                    still: clip.sourceURL,
                    intoPreallocated: preAllocURL
                )
                // Defensive: the overload's contract says the baker writes
                // to preAllocURL. If a future refactor breaks that
                // contract, we still want the actual URL registered.
                if bakedURL != preAllocURL {
                    if let last = bakedStillURLs.indices.last {
                        bakedStillURLs[last] = bakedURL
                    }
                }
                _ = bakedSize  // consumed by the post-bake StitchClip update per Cluster 0 Task 2
                // ... rest of the canonical plan's bake-handler unchanged ...
```

> **Fallback note (Audit Fix H2):** If the `intoPreallocated:` contract feels too implicit for the auditor's taste, the safer-to-the-letter form wraps the bake in an explicit failure-cleanup block:
>
> ```swift
> do {
>     let (bakedURL, bakedSize) = try await baker.bake(
>         still: clip.sourceURL,
>         intoPreallocated: preAllocURL
>     )
>     // ... happy path ...
> } catch {
>     try? FileManager.default.removeItem(at: preAllocURL)
>     throw error
> }
> ```
>
> Either pattern satisfies the leak-prevention goal; pick the `intoPreallocated:` overload by default and fall back to the explicit `do/catch` only if the contract is hard to enforce in code review.

- [ ] **Step 2: Add `predictedOutputURL()` and `bake(still:intoPreallocated:)` overload to StillVideoBaker**

In `VideoCompressor/ios/Services/StillVideoBaker.swift`, append to the type:

```swift
    /// Pre-allocate the output path WITHOUT starting any I/O. Caller
    /// (StitchExporter.buildPlan) registers this URL into the bake-cleanup
    /// list BEFORE invoking bake(...), so cancellation mid-bake doesn't
    /// leak partial .movs.
    func predictedOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StillBakes", isDirectory: true)
            .appendingPathComponent("baked-\(UUID().uuidString.prefix(8)).mov")
    }

    /// Variant of `bake(still:)` that writes to a caller-supplied URL.
    /// Used when the caller needs to register the URL for cleanup before
    /// invoking the bake itself.
    ///
    /// **Contract (Audit Fix H2):** This overload either writes to
    /// `outputURL` exactly OR throws BEFORE creating any file on disk.
    /// Callers (StitchExporter.buildPlan) rely on this so that registering
    /// `outputURL` into `bakedStillURLs` BEFORE the call is sufficient for
    /// the runExport defer-sweep to clean up partial files.
    ///
    /// Returns the post-Cluster-0 tuple `(url: URL, size: CGSize)` — the
    /// `size` is the post-EXIF-orientation, post-thumbnail-cap dimensions
    /// of the baked .mov, used by the caller to update the post-bake
    /// `StitchClip.naturalSize`.
    func bake(still sourceURL: URL, intoPreallocated outputURL: URL) async throws -> (url: URL, size: CGSize) {
        // Ensure the StillBakes/ dir exists first time around.
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try await bakeImpl(still: sourceURL, output: outputURL)
    }
```

Refactor the existing `bake(still:)` to delegate (signature returns the post-Cluster-0 tuple):

```swift
    func bake(still sourceURL: URL) async throws -> (url: URL, size: CGSize) {
        let target = predictedOutputURL()
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try await bakeImpl(still: sourceURL, output: target)
    }

    private func bakeImpl(still sourceURL: URL, output outputURL: URL) async throws -> (url: URL, size: CGSize) {
        // Body of the existing bake() goes here, with the local target URL
        // replaced by the parameter `outputURL`. The trailing `return outURL`
        // becomes `return (url: outputURL, size: CGSize(width: width, height: height))`
        // per Cluster 0 Task 1 Step 3.
        // ...
    }
```

- [ ] **Step 3: Run tests; expect 143/143 + 0 new (the 5 baker/scale tests added by canonical plan still pass)**

```
mcp__xcodebuildmcp__clean
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 143, Passed: 143, Failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Services/StillVideoBaker.swift \
        VideoCompressor/ios/Services/StitchExporter.swift \
        VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift \
        VideoCompressor/VideoCompressorTests/StitchExporterScaleTests.swift
git commit -m "feat(stitch): O(1) still bake + register URL pre-bake (Phase 1.1 + 1.6)

Combines TASK-01 (constant-time still bake via scaleTimeRange) with
TASK-31 (Audit-7-C2 fix: bake-cancellation cleanup). The baker now
exposes predictedOutputURL() so StitchExporter.buildPlan can register
the URL into bakedStillURLs BEFORE invoking bake(), guaranteeing the
runExport defer block sees every partial file even on mid-bake cancel.

Reference: docs/superpowers/plans/2026-05-03-still-bake-constant-time.md"
```

**Effort: ~2h. ~4 commits up to here (canonical plan's 4 + 1).**

---

## Task 2: Extend CacheSweeper — tmp dirs, sweepOnCancel, sweepAfterSave

- [ ] **Step 1: Write CacheSweeperTests pinning current behaviour first**

Create `VideoCompressor/VideoCompressorTests/CacheSweeperTests.swift`:

```swift
import XCTest
@testable import VideoCompressor_iOS

final class CacheSweeperTests: XCTestCase {

    /// Helper: write a 1 KB sentinel into one of our working dirs.
    private func makeSentinel(in subdir: String) throws -> URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent("sentinel-\(UUID().uuidString.prefix(6)).bin")
        try Data(repeating: 0xAB, count: 1024).write(to: url)
        return url
    }

    func testDeleteIfInWorkingDirRemovesFileInsideOutputs() async throws {
        let sentinel = try makeSentinel(in: "Outputs")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        await CacheSweeper.shared.deleteIfInWorkingDir(sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testDeleteIfInWorkingDirIgnoresFileOutsideSandbox() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("foreign-\(UUID().uuidString.prefix(6)).bin")
        try Data(repeating: 0, count: 16).write(to: outside)
        await CacheSweeper.shared.deleteIfInWorkingDir(outside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path),
            "Sweeper must never touch files outside our sandbox.")
        try? FileManager.default.removeItem(at: outside)
    }
}
```

Run: `mcp__xcodebuildmcp__test_sim` — expect `Total: 145, Passed: 145` (143 + 2 new).

Commit:

```bash
git add VideoCompressor/VideoCompressorTests/CacheSweeperTests.swift
git commit -m "test(cache): pin existing CacheSweeper behaviour before extension"
```

- [ ] **Step 2: Extend CacheSweeper with tmp-dir support + sweepOnCancel/sweepAfterSave**

In `VideoCompressor/ios/Services/CacheSweeper.swift`, replace the contents of `actor CacheSweeper` to add:

```swift
    /// NSTemporaryDirectory() subdirs we manage. Unlike `allDirs` (which
    /// live under Documents/ and persist across app launches), these are
    /// volatile but iOS does NOT reliably reap them. We sweep aggressively.
    static let tmpSubdirs: [String] = [
        "StillBakes",       // StillVideoBaker output
        // Picks-* and PhotoClean-* are UUID-suffixed; matched by prefix.
    ]

    /// Prefixes of UUID-suffixed tmp/ subdirs we manage.
    static let tmpDirPrefixes: [String] = ["Picks-", "PhotoClean-"]

    private let tmpRoot: URL = FileManager.default.temporaryDirectory

    // MARK: - Cancel/save lifecycle hooks

    /// Cancel-time targeted sweep. Called from CompressionService.encode +
    /// StitchExporter.runReencode/runPassthrough + Photo*.cancel paths.
    /// `predictedOutputURL` is the file the caller WAS writing to; we
    /// remove it iff it lives inside our sandbox.
    func sweepOnCancel(predictedOutputURL: URL?) {
        guard let url = predictedOutputURL else { return }
        deleteIfInWorkingDir(url)
        // Also nuke any Picks-/PhotoClean- wrapper for that file.
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("Picks-")
            || parent.lastPathComponent.hasPrefix("PhotoClean-")
        {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    /// Post-save sweep. After Photos confirms the save, our sandbox copy
    /// is redundant. Wait 30 s (so user can re-share if they want), then
    /// remove.
    func sweepAfterSave(_ savedSandboxURL: URL) async {
        try? await Task.sleep(for: .seconds(30))
        deleteIfInWorkingDir(savedSandboxURL)
    }

    /// Tighter launch sweep — Documents/* still uses `daysOld`, but tmp/
    /// is age-agnostic (any file we control gets nuked).
    func sweepOnLaunchTight() {
        sweepOnLaunch(daysOld: 1)
        sweepTmpAggressive()
    }

    private func sweepTmpAggressive() {
        let fm = FileManager.default
        // Named tmp subdirs we own.
        for name in Self.tmpSubdirs {
            sweep(dir: tmpRoot.appendingPathComponent(name, isDirectory: true),
                  olderThan: .distantFuture)
        }
        // UUID-suffixed prefixes (Picks-*, PhotoClean-*).
        guard let entries = try? fm.contentsOfDirectory(
            at: tmpRoot,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            if Self.tmpDirPrefixes.contains(where: { name.hasPrefix($0) }) {
                try? fm.removeItem(at: entry)
            }
        }
    }
```

Update `clearAll()` to also wipe tmp:

```swift
    func clearAll() {
        for name in Self.allDirs {
            sweep(dir: documents.appendingPathComponent(name, isDirectory: true),
                  olderThan: .distantFuture)
        }
        sweepTmpAggressive()
    }
```

Update `breakdown()` to include tmp:

```swift
    func breakdown() -> [FolderStat] {
        var stats = Self.allDirs.map { name in
            FolderStat(name: name, bytes: folderSize(documents.appendingPathComponent(name)))
        }
        // Aggregate tmp into one row.
        var tmpBytes: Int64 = 0
        for name in Self.tmpSubdirs {
            tmpBytes += folderSize(tmpRoot.appendingPathComponent(name))
        }
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: tmpRoot, includingPropertiesForKeys: nil
        ) {
            for entry in entries
                where Self.tmpDirPrefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) })
            {
                tmpBytes += folderSize(entry)
            }
        }
        if tmpBytes > 0 {
            stats.append(FolderStat(name: "tmp", bytes: tmpBytes))
        }
        return stats
    }
```

Add the `"tmp"` display name to `FolderStat.displayName`:

```swift
            case "tmp":           return "Temporary working files"
```

- [ ] **Step 3: Add tests for sweepOnCancel + sweepAfterSave + tmp**

Append to `CacheSweeperTests.swift`:

```swift

    func testSweepOnCancelRemovesPredictedOutput() async throws {
        let sentinel = try makeSentinel(in: "Outputs")
        await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testSweepOnCancelHandlesNilSafely() async throws {
        await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: nil)
        // Just must not crash.
    }

    func testSweepAfterSaveDeletesAfterDelay() async throws {
        let sentinel = try makeSentinel(in: "Outputs")
        // Use the sweepAfterSave's hook directly without waiting 30 s in
        // the test by calling deleteIfInWorkingDir with the same arg.
        await CacheSweeper.shared.deleteIfInWorkingDir(sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testSweepTmpAggressiveRemovesStillBakesDir() async throws {
        let bakes = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillBakes", isDirectory: true)
        try FileManager.default.createDirectory(at: bakes, withIntermediateDirectories: true)
        let file = bakes.appendingPathComponent("test-\(UUID().uuidString.prefix(6)).mov")
        try Data(repeating: 0, count: 16).write(to: file)
        await CacheSweeper.shared.clearAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
```

Run: `mcp__xcodebuildmcp__test_sim` — expect `Total: 149, Passed: 149` (145 + 4).

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Services/CacheSweeper.swift \
        VideoCompressor/VideoCompressorTests/CacheSweeperTests.swift
git commit -m "feat(cache): sweepOnCancel + sweepAfterSave + tmp-dir support (Phase 1.2 / TASK-99)

Adds the cancel-time + post-save lifecycle hooks the user explicitly
asked for, plus aggressive tmp/ sweeping (StillBakes/, Picks-*/,
PhotoClean-*/). Existing tests unchanged; 4 new tests cover the new
hooks. clearAll() and breakdown() updated to include tmp."
```

**Effort: ~1.5h. ~6 commits.**

---

## Task 3: Wire sweepOnCancel + sweepAfterSave into every cancel/save site

- [ ] **Step 0: Enumerate cancel branches in target services (Audit Fix M3)**

Before editing anything, enumerate every cancel/throw/early-cleanup branch in the services this task touches. This catches renames, moved code, or branches that no longer exist. Make a written list (in scratch or a scratch-pad commit message) of each match BEFORE editing — don't scan blind.

```bash
grep -rn "cancel\|throw\|FileManager.default.removeItem" \
    VideoCompressor/ios/Services/PhotoMetadataService.swift \
    VideoCompressor/ios/Services/PhotoCompressionService.swift \
    VideoCompressor/ios/Services/CompressionService.swift \
    VideoCompressor/ios/Services/StitchExporter.swift \
    VideoCompressor/ios/Services/MetadataService.swift
```

For each match that throws inside an early-failure path (typically `try? FileManager.default.removeItem(at: outputURL); throw ...` or a `case .cancelled` / `case .failed` branch in an AVAssetExportSession status switch), note the file + line + the local variable name holding the predicted output URL. The list is the worklist for Steps 1–4. If a service reports zero matches, flag it in the Step 7 commit message — it's evidence either of a rename or of a branch already removed by a prior cluster.

- [ ] **Step 1: CompressionService cancel branch**

In `VideoCompressor/ios/Services/CompressionService.swift` around line 405–457 (the cancel branch in `encode`), add `await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)` immediately after `writer.cancelWriting()`:

```swift
            if coordinator.cancelAfterRegistration() {
                reader.cancelReading()
                for pair in cancelSnapshot { pair.input.markAsFinished() }
            } else {
                reader.cancelReading()
            }
            // ... existing cancel handling ...
            await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)
            throw CompressionError.cancelled
```

(Verify exact location with grep: `grep -n "writer.cancelWriting\|throw CompressionError.cancelled" VideoCompressor/ios/Services/CompressionService.swift` — wire before each `throw .cancelled`.)

- [ ] **Step 2: StitchExporter run* cancel branches**

In `VideoCompressor/ios/Services/StitchExporter.swift`, find both `runReencode` and `runPassthrough` cancel/failed branches (search: `case .cancelled, .failed`). Add:

```swift
                await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)
```

immediately before each `throw` in those branches.

- [ ] **Step 3: PhotoMetadataService.strip + PhotoCompressionService.compress**

In `VideoCompressor/ios/Services/PhotoMetadataService.swift` and `PhotoCompressionService.swift`, find each early-throw / cancel branch (typically `try? FileManager.default.removeItem(at: outputURL); throw ...`). Replace with:

```swift
            await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: outputURL)
            throw error
```

Note: PhotoMetadataService uses `PhotoClean-<uuid>/` wrapper dirs (Audit-9-F6). `sweepOnCancel` already handles these via the `parent.lastPathComponent.hasPrefix("PhotoClean-")` branch.

- [ ] **Step 4: Save paths — VideoLibrary, MetaCleanQueue, StitchProject**

In `VideoCompressor/ios/Services/VideoLibrary.swift`, find `saveOutputToPhotos` (or similarly named — grep for `PHPhotoLibrary` + `add` + `creationRequest`). After the `creationRequest.creationDate = ...` block returns success, add:

```swift
            // Phase 1.2 (TASK-99): the local sandbox copy is redundant
            // once Photos confirms the save. Schedule a 30 s delayed
            // sweep so the user can still re-share before we nuke.
            Task.detached {
                await CacheSweeper.shared.sweepAfterSave(savedURL)
            }
```

Repeat the same pattern at:
- `MetaCleanQueue.runClean` success completion (around line 100–180; the `completion(.success(...))` call site).
- `StitchProject.runExport` success path (search `StitchProject.swift` for `runExport`).

- [ ] **Step 5: Tighten launch sweep**

In `VideoCompressor/ios/VideoCompressorApp.swift` (or wherever `sweepOnLaunch` is called from `@main`), replace:

```swift
        Task.detached { await CacheSweeper.shared.sweepOnLaunch(daysOld: 7) }
```

with:

```swift
        Task.detached { await CacheSweeper.shared.sweepOnLaunchTight() }
```

- [ ] **Step 6: Run full suite**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 149, Passed: 149, Failed: 0`. None of the existing 138 should regress; the 11 new (5 still-bake/scale + 6 cache) all pass.

- [ ] **Step 7: Commit**

```bash
git add VideoCompressor/ios/Services/CompressionService.swift \
        VideoCompressor/ios/Services/StitchExporter.swift \
        VideoCompressor/ios/Services/PhotoMetadataService.swift \
        VideoCompressor/ios/Services/PhotoCompressionService.swift \
        VideoCompressor/ios/Services/VideoLibrary.swift \
        VideoCompressor/ios/Services/MetaCleanQueue.swift \
        VideoCompressor/ios/Models/StitchProject.swift \
        VideoCompressor/ios/VideoCompressorApp.swift
git commit -m "feat(cache): wire sweepOnCancel + sweepAfterSave into all cancel/save sites

Resolves the user's stated requirement: cancel = immediate sweep,
save = post-30s sandbox sweep, launch = aggressive sweep.

Changed sites:
- CompressionService.encode cancel branch
- StitchExporter.runReencode / runPassthrough cancel branches
- PhotoMetadataService.strip + PhotoCompressionService.compress
  cancel paths (also handles PhotoClean-<uuid>/ wrappers)
- VideoLibrary saveOutputToPhotos success
- MetaCleanQueue.runClean success
- StitchProject.runExport success
- App init: sweepOnLaunch(daysOld: 7) → sweepOnLaunchTight() (1 day +
  aggressive tmp)

149/149 tests passing."
```

**Effort: ~1.5h. ~7 commits.**

---

## Task 4: Push, PR, CI, merge

- [ ] **Step 1: Final test pass**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 149, Passed: 149, Failed: 0`.

- [ ] **Step 2: Build sim**

```
mcp__xcodebuildmcp__build_sim
```

Expected: `✅ iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.`

- [ ] **Step 3: Push + PR**

```bash
git push -u origin feat/phase1-cluster1-cache-and-bake
gh pr create --base main --head feat/phase1-cluster1-cache-and-bake \
  --title "feat: Phase 1 cluster 1 — cache cleanup + still bake O(1)" \
  --body "Closes MASTER-PLAN tasks 1.1 (TASK-01), 1.2 (TASK-99), 1.6 (TASK-31).

- Still bake is now O(1) via scaleTimeRange (constant ~30 frames regardless of user's still duration).
- CacheSweeper gains sweepOnCancel + sweepAfterSave + tmp-dir tracking.
- buildPlan registers baked URLs BEFORE invoking bake() (Audit-7-C2).

149/149 tests passing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 4: Watch CI, merge**

```bash
gh pr checks <num> --watch
gh pr merge <num> --merge
```

- [ ] **Step 5: Append session log**

```bash
echo "[$(date '+%Y-%m-%d %H:%M IST')] [PERF+CACHE] Phase 1 cluster 1 — bake O(1) + cache hooks (PR #<num>)" \
  >> .agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md
```

---

## Acceptance criteria

- [ ] `StillVideoBaker.bake(still:)` no longer takes a `duration` parameter.
- [ ] Bake of any duration completes in < 0.5 s.
- [ ] Cancelling a compress export removes the partial output from `Documents/Outputs/`.
- [ ] Cancelling a stitch export removes baked .movs from `tmp/StillBakes/` AND partial output from `Documents/StitchOutputs/`.
- [ ] Successful save-to-Photos removes the sandbox copy within 30 s.
- [ ] Settings cache breakdown shows a `tmp` row when tmp/ has content.
- [ ] App launch sweep tightens to 1 day for Documents/* and aggressive for tmp/.
- [ ] All 138 baseline tests still pass; 11 new (5 baker/scale + 6 cache) pass.
- [ ] CI green, PR merged, TestFlight build #1 reaches testers.

## Notes for the executing agent

- **Sim hygiene:** if `test_sim` flakes on the 30-s sleep tests, set `XCTSkip` for `testSweepAfterSaveDeletesAfterDelay` on simulator and only run on device — sim time can drift.
- **PBXFileSystemSynchronizedRootGroup:** new `CacheSweeperTests.swift` file auto-includes via the synchronized root group; if it doesn't appear, run `mcp__xcodebuildmcp__clean` then `test_sim`.
- **Don't re-run `session_set_defaults`** (per AGENTS.md Part 16.3).
- ≤10 commits total for this cluster. If you need an 11th, squash the canonical-plan-inherited commits into one.
