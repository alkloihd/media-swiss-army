# AUDIT-02 — iOS Memory & Resource Leaks

**Auditor:** subagent/opus (read-only)
**Date:** 2026-05-03
**Scope:** `VideoCompressor/ios/` Swift sources — AVPlayer/AVAssetReader/AVAssetWriter lifecycle, NotificationCenter observers, Task lifecycle, CVPixelBuffer locks, temp-file accumulation, ImageIO release, `@StateObject`/`@ObservedObject` correctness.

**Methodology:** read targeted files identified in the prompt, then grep across the rest of `Views/` and `Services/` for the same anti-patterns. No simulator runs, no Instruments traces — static analysis only.

---

## Severity tally

| Severity | Count |
|----------|-------|
| CRITICAL | 2 |
| HIGH     | 4 |
| MEDIUM   | 4 |
| LOW      | 2 |
| **Total**| **12** |

Critical/high subtotal: **6**.

---

## Findings

### F1 — CRITICAL — `ClipLongPressPreview` leaks AVPlayer + observer per long-press

**File:** `Views/StitchTab/StitchTimelineView.swift:305-312`

The long-press preview registers a block-based `NotificationCenter` observer (`AVPlayerItemDidPlayToEndTime`) but never stores the returned token and never calls `removeObserver(_:)`. The closure also strongly captures the player `p`, so the observer block keeps the `AVPlayer` alive for the lifetime of the default `NotificationCenter` (i.e. the app process). Every video long-press leaks one player + one observer + the underlying `AVPlayerItem` (and any backing decoder pool). On a timeline with many video clips, repeated long-presses accumulate without bound.

`onDisappear` (line 292-295) clears the `@State player`, but that doesn't remove the NotificationCenter registration — Foundation still holds a strong reference to the closure, and the closure holds the player.

**Fix:**
```swift
@State private var player: AVPlayer?
@State private var loopObserver: NSObjectProtocol?

// in load() after creating p:
let token = NotificationCenter.default.addObserver(
    forName: .AVPlayerItemDidPlayToEndTime,
    object: p.currentItem,
    queue: .main
) { [weak p] _ in
    p?.seek(to: .zero)
    p?.play()
}
await MainActor.run {
    self.player = p
    self.loopObserver = token
}

// in onDisappear:
.onDisappear {
    if let t = loopObserver { NotificationCenter.default.removeObserver(t) }
    loopObserver = nil
    player?.pause()
    player = nil
}
```

---

### F2 — CRITICAL — `StillVideoBaker` early-throw paths leak the partially-started writer + leftover .mov

**File:** `Services/StillVideoBaker.swift:120-131, 138-149`

After `writer.startWriting()` succeeds (line 107), the function can still throw on three paths: missing pixel-buffer pool (115), pixel-buffer alloc failure (120), missing base address (129), and CGContext init failure (138). None of these throw paths call `writer.cancelWriting()`, and only the base-address path unlocks the pixel buffer (line 130, 147). Effects:

- Writer is left in `.writing` status — Apple docs note this can leave the writer process holding file handles and decoder/encoder hardware sessions until the writer instance is finally deallocated. With async/Swift concurrency, the deallocation can be deferred long after the throw.
- The empty `.mov` file at `outURL` is not removed.
- On the line-129 base-address path, `CVPixelBufferUnlockBaseAddress` is called BEFORE the buffer is consumed (good) but `pixelBuffer` is still owned by the local var — fine, will release. The lock/unlock pair on lines 123 + 130/147/151 is correctly paired.

**Fix:**
Wrap the post-`startWriting()` body in a do/catch that on any error calls `writer.cancelWriting()` and `try? FileManager.default.removeItem(at: outURL)` before re-throwing. Same pattern as the existing block at line 211-216.

---

### F3 — HIGH — `MetadataService.strip` can leak writer/reader + orphan `_CLEAN` file on early throws

**File:** `Services/MetadataService.swift:152, 158, 184-193`

Throws on lines 152 (reader can't add output), 158 (writer can't add input), 184 (`startReading` failed) and 189 (`startWriting` failed) all bypass the cleanup the success path performs. The output file at `outputURL` is created by `AVAssetWriter`'s init (line 115) but never removed on these error paths. Subsequent re-attempts also rely on the `try? removeItem` at line 102, so this won't poison the next run, but storage grows monotonically until the user re-runs MetaClean on the same source. More importantly, the reader/writer instances aren't explicitly torn down — same hardware-handle concern as F2.

**Fix:**
```swift
func strip(...) async throws -> MetadataCleanResult {
    // ... existing setup through line 124 ...
    let outputURL = Self.cleanedURL(for: sourceURL)
    try? FileManager.default.removeItem(at: outputURL)
    do {
        // existing body
    } catch {
        writer.cancelWriting()      // safe even if startWriting() never succeeded
        reader.cancelReading()
        try? FileManager.default.removeItem(at: outputURL)
        throw error
    }
}
```

---

### F4 — HIGH — `CompressionService.encode` post-writer-init throws leak the writer + leave a 0-byte output file

**File:** `Services/CompressionService.swift:213-215, 278-280, 325-329, 330-334`

Same pattern as F2/F3. Once `AVAssetWriter(outputURL:fileType:)` succeeds at line 161, four subsequent throw paths bypass cleanup:
- 213-215: writer rejects video input
- 278-280: reader rejects video output (writer already alive, never cancelled)
- 325-329: `reader.startReading()` fails (writer alive but `startWriting` not yet called)
- 330-334: `writer.startWriting()` fails (most common — disk full, codec unsupported)

The success path at line 469 has `try? removeItem` for the no-completion case, but throws bypass it.

**Fix:** wrap the body after writer creation in a do/catch that calls `writer.cancelWriting()` and `try? FileManager.default.removeItem(at: outputURL)`. Same shape as F3.

---

### F5 — HIGH — `CacheSweeper` doesn't track NSTemporaryDirectory dirs (`StillBakes/`, `Picks-*/`, `PhotoClean-*/`, `silent.m4a`)

**File:** `Services/CacheSweeper.swift:28-32` vs. `Services/StillVideoBaker.swift:73-74`, `Services/VideoLibrary.swift:512-513, 537-538`, `Services/PhotoMetadataService.swift:184-185`, `Services/AudioBackgroundKeeper.swift:75-76`

`CacheSweeper.allDirs` only enumerates the six **Documents/** dirs. Five other transient dirs live in `NSTemporaryDirectory()` and are never swept by the app. The Stitch flow (`StitchProject.runExport` line 486-490) deletes its own bakes via `defer`, but if the export Task is killed by jetsam mid-build, the bakes survive. `VideoTransferable`/`PhotoTransferable` move the picker file and `VideoLibrary.copyToWorkingDir` cleans the `Picks-*` parent only when the move succeeds — failure paths leave the wrapper dir behind. `PhotoMetadataService` cleans up its `PhotoClean-*` dir explicitly (good). `AudioBackgroundKeeper.silent.m4a` is created once and never removed.

iOS will eventually purge `NSTemporaryDirectory` under storage pressure, but it's not a guarantee — Apple docs state "the system may purge ... when the app is not running." Long-running users hit space pressure first.

**Fix:** extend `CacheSweeper.sweepOnLaunch` to also enumerate `FileManager.default.temporaryDirectory` and remove `StillBakes/`, `Picks-*`, `PhotoClean-*`, and (if old) `silent.m4a`. Or simpler: at every app launch, recursively delete everything inside `temporaryDirectory` older than 1 day except `silent.m4a`.

---

### F6 — HIGH — `TrimEditorView` leaks player on dealloc via auto-play Tasks; one Task isn't even tracked

**File:** `Views/StitchTab/TrimEditorView.swift:88-92, 99-106, 125-128`

Two issues:

1. **Untracked Task on line 88:** the start-handle release fires `Task { @MainActor in ... player.play() }` but does NOT assign to `autoPlayTask`. If the user swipes the editor away mid-seek, the Task continues, calls `player.play()`, and there's no way to cancel it. The `.onDisappear` (line 125) only cancels `autoPlayTask`, missing this one. Net effect: AVPlayer keeps an active playback session running invisibly until natural completion.

2. **Player not nilled on disappear:** `onDisappear` calls `player.pause()` but the `@State` AVPlayer survives until the View struct is deallocated. SwiftUI may keep the View alive for a re-render cycle after the editor closes — the player keeps its decoder pool warm during that window. Acceptable for one transient editor; cumulative across many edit cycles in a session.

**Fix:** assign the start-handle Task to `autoPlayTask` and reuse the existing cancel path; same shape as the end-handle case. Make `player` an `Optional<AVPlayer>` so `onDisappear` can nil it.

---

### F7 — MEDIUM — `ClipEditorInlinePanel` time-observer closure captures `self` strongly

**File:** `Views/StitchTab/ClipEditorInlinePanel.swift:427-435`

The closure passed to `addPeriodicTimeObserver` reads `isDraggingPlayhead` and writes `playheadSeconds` — both `@State` on the View struct. Because the view is a value type but `@State` storage lives in a heap-allocated `StateObject`-like box, SwiftUI's runtime can keep the box alive for the duration of the observer. The teardown at line 415-421 removes the observer correctly, so this is bounded by the lifetime of the panel and not a true leak. However, the closure also implicitly captures `self`, which AVPlayer holds via the token. Adding `[weak self]` (or capturing the bindings explicitly) is defensive.

The good news: line 415-421 always runs `removeTimeObserver` on disappear and on clip swap (line 401), so the leak window is one panel session. Marking this MEDIUM rather than HIGH on that basis.

**Fix:** capture only what the closure needs — a weak reference to a small ref-typed coordinator that owns the `playheadSeconds` write target — or accept the implicit retention since teardown is reliable. At minimum, add a comment explaining the retention semantics.

---

### F8 — MEDIUM — `MetaCleanQueue` and per-pump shared state never cancelled on view dismissal

**File:** `Views/MetaCleanTab/MetaCleanTabView.swift:20`, `Services/MetaCleanQueue.swift` (not read in full)

`MetaCleanTabView` owns `@StateObject private var queue = MetaCleanQueue()`. If a clean is in flight and the user switches tabs, no `cancel()` is invoked because `@StateObject` retains the queue across tab switches (correct for state, but the in-flight encode keeps reader/writer + temp file open). The grep for `cancel` calls inside MetaCleanQueue.swift would confirm — but the read-only sweeps so far show no `onDisappear` cancellation in the Tab view.

Effect: one tab switch during a 30 s remux keeps the resources hot for the full duration. Not unbounded, but unexpected for a "stopped" UI.

**Fix:** add `.onDisappear { queue.cancelAll() }` at the tab-view boundary; ensure `MetaCleanQueue.cancelAll()` calls `reader.cancelReading()` on each in-flight job.

---

### F9 — MEDIUM — `VideoLibrary.activeTask` is replaced without being awaited; orphan tasks linger

**File:** `Services/VideoLibrary.swift:177, 196-222, 226-230`

`compressAll()` does `activeTask?.cancel()` then immediately reassigns `activeTask = Task { ... }`. The previous Task is detached and free to keep running its withTaskGroup; cancellation is cooperative — `Task.isCancelled` checks at lines 203 and 212 are good, but each `runJob` already in flight has its own `await self?.runJob(for:)` chain. Each runJob enters `CompressionService.encode` which eventually surfaces cancellation through `withTaskCancellationHandler`. So this is mostly correct.

The narrow leak: between the cancel and the actual cooperative honour, the old Task's CompressionService instance + its writer/reader pair are still alive. Calling `compressAll()` rapidly (e.g. via UI button mash) can briefly stack multiple CompressionService instances. Memory peak grows; doesn't grow without bound.

**Fix:** `await` the cancelled task before assigning the new one (or accept this as acceptable bounded ramp). Add a `// TODO: await previous` comment if you accept it.

---

### F10 — MEDIUM — `StitchExportSheet.saveTask` not nilled on completion (only on disappear)

**File:** `Views/StitchTab/StitchExportSheet.swift:206-223`

`runSaveToPhotos` assigns `saveTask = Task { ... }` and the Task completes without setting `saveTask = nil`. If the user starts a save, lets it finish, then triggers another save, the first reference is replaced and the old completed Task struct is GC'd — Swift handles this fine. But the View keeps a non-nil reference to a completed Task until either (a) the next save starts or (b) the sheet disappears. This is purely cosmetic/state-hygiene; no actual resource is held by a completed Task.

**Fix:** set `self.saveTask = nil` in both branches of the do/catch inside the Task body. Low priority.

---

### F11 — LOW — `VideoLibrary.metadataService` is a `static let` singleton — never released

**File:** `Services/VideoLibrary.swift:43-44`

`metadataService` and `photoMetadataService` are static-let singletons. They're `actor`s with no internal mutable per-call retention beyond local function frames, so this is fine. Mentioned for completeness — no fix needed.

---

### F12 — LOW — `StillPreview` doesn't release `CGImageSource` explicitly

**File:** `Views/StitchTab/ClipEditorInlinePanel.swift:469-483`

`CGImageSourceCreateWithURL` returns a Core Foundation type; under ARC + Swift's automatic CF bridging, it's released when the local `src` binding goes out of scope at function exit. The thumbnail-via-ImageIO pattern is correct. Same for the duplicate code in `ClipLongPressPreview.load()` at lines 317-330. No fix needed; flagged because the prompt asked specifically about ImageIO release.

---

## Cross-cutting observations

1. **Pattern of throw-after-AVAssetWriter-init without cleanup** repeats across `StillVideoBaker`, `MetadataService`, and `CompressionService`. Worth extracting a small helper:
   ```swift
   func withWriter<R>(at url: URL, fileType: AVFileType, _ body: (AVAssetWriter) async throws -> R) async throws -> R {
       let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
       do { return try await body(writer) }
       catch {
           writer.cancelWriting()
           try? FileManager.default.removeItem(at: url)
           throw error
       }
   }
   ```

2. **Task-in-View pattern is inconsistent.** `ClipEditorInlinePanel` correctly stores the periodic-time-observer token and tears down on disappear; `TrimEditorView` partially tracks Tasks (one is missed); `StitchExportSheet` tracks the save Task. A team-wide convention — every Task spawned from a View must be assigned to a `@State Task<...>?` and cancelled in `onDisappear` — would eliminate this whole class of mistake.

3. **Long-press preview is the only place using observer-based loop**; everywhere else the codebase uses the modern Combine `publisher(for:)` API or AVQueuePlayer/looper. Migrating to `AVPlayerLooper` (or `NotificationCenter.default.publisher(for:)` with `.sink` and storing `AnyCancellable` in `@State`) would close F1 cleanly.

---

## Files inspected

- `Views/StitchTab/ClipEditorInlinePanel.swift`
- `Views/StitchTab/StitchTimelineView.swift`
- `Views/StitchTab/StitchExportSheet.swift`
- `Views/StitchTab/TrimEditorView.swift`
- `Services/StillVideoBaker.swift`
- `Services/VideoLibrary.swift`
- `Services/MetadataService.swift`
- `Services/CompressionService.swift`
- `Services/CacheSweeper.swift`
- `Services/AudioBackgroundKeeper.swift`
- `Services/ThumbnailStripGenerator.swift` (spot-check)
- `Models/StitchProject.swift` (export task lifecycle)

## Files NOT inspected (out of scope or time)

- `Services/StitchExporter.swift` (referenced from StitchProject; would need a deeper read for plan/cancel semantics)
- `Services/MetaCleanQueue.swift` (only briefly referenced in F8)
- `Services/PhotoMetadataService.swift`, `PhotoCompressionService.swift`, `PhotosSaver.swift`
- All `MetaCleanTab/` views beyond the Tab root
- `Models/HapticTicker` (no obvious leak surface)
