# AUDIT-01: iOS Concurrency Safety

**Date:** 2026-05-03
**Auditor:** subagent/opus (read-only)
**Scope:** `VideoCompressor/ios/Services/`, `VideoCompressor/ios/Models/`, plus tightly coupled Views (`StitchTimelineView`, `TrimEditorView`)

**Mandate:** Find real concurrency bugs that ship in days. Skip cosmetic concerns.

---

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 2 |
| HIGH | 4 |
| MEDIUM | 5 |
| LOW | 2 |

---

## CRITICAL

### C1. `StillVideoBaker.FrameCounter.markDoneIfPossible()` short-circuits after the first frame
**File:** `VideoCompressor/ios/Services/StillVideoBaker.swift:172, 250-255`

The function unconditionally sets `_done = true` on every call, then returns the prior value:

```swift
func markDoneIfPossible() -> Bool {
    let wasDone = _done
    _done = true   // sets true on EVERY call, not just at completion
    return wasDone
}
```

It is called at the TOP of the `while inputRef.isReadyForMoreMediaData` loop on line 172. Trace through:
- Iteration 1 of invocation 1: `wasDone=false`, sets `_done=true`, returns false → appends 1 frame, increments counter.
- Iteration 2 of invocation 1: `wasDone=true`, returns true → exits loop.
- All subsequent re-invocations (AVFoundation re-entry): first check returns true → return immediately, no work.

Net result: still-image bakes produce a one-frame `.mov` instead of `duration * 30` frames. Stitching with a still clip would render a single frozen frame for the still's whole duration window — but only because the trim window is `[0, clamped]` and AVFoundation extends the lone sample. If AVFoundation behaves differently (e.g. on devices that stop early), the still appears for a fraction of a frame. Either way, the intended frame stream isn't produced.

There is no test covering this path.

**Fix:** delete the `markDoneIfPossible()` short-circuit at the top of the loop entirely (or move `_done = true` into ONLY the two terminal branches: `frame >= totalFrames` and append failure). Once `markAsFinished()` has been called, AVFoundation does not re-invoke the callback in practice — `_resumed`/`tryClaimResume()` already provides the once-only resume guard. The `_done` flag is doing nothing useful and is actively breaking the loop.

---

### C2. `MetadataService.strip` lacks the CancelCoordinator pattern → crash on cancel-during-registration
**File:** `VideoCompressor/ios/Services/MetadataService.swift:232-278`

`CompressionService.encode` documents (lines 561-583) two crash windows when `withTaskCancellationHandler.onCancel` runs concurrently with `requestMediaDataWhenReady` registration:
1. Pre-registration cancel: onCancel fires synchronously, marks inputs finished, body then registers `requestMediaDataWhenReady` on a finished input → `NSInternalInconsistencyException`.
2. Mid-registration cancel: body is mid-loop, onCancel marks all inputs finished, body's next iteration registers on a finished input → same crash.

`CompressionService` solves this with `CancelCoordinator`. **`MetadataService.strip` does NOT.** The body at lines 232-274 plainly walks `for pair in pumpInputs { input.requestMediaDataWhenReady(...) }` with no cancellation guard, and onCancel at lines 275-278 unconditionally calls `markAsFinished()` on every input. Same race, same crash.

This is reachable: user taps Cancel on the MetaClean progress sheet (`MetaCleanQueue.cleanTask?.cancel()`) the instant a strip job starts.

**Fix:** copy the `CancelCoordinator` pattern from `CompressionService` into `MetadataService.strip`. ~25 lines of mechanical change.

---

## HIGH

### H1. NotificationCenter observer leak in `ClipLongPressPreview`
**File:** `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift:305-312`

```swift
NotificationCenter.default.addObserver(
    forName: .AVPlayerItemDidPlayToEndTime,
    object: p.currentItem,
    queue: .main
) { _ in
    p.seek(to: .zero)
    p.play()
}
```

The block-form `addObserver` returns an `NSObjectProtocol` token that must be passed to `removeObserver` at teardown. The closure also captures `p` strongly. `onDisappear` sets `player = nil` but never removes the observer, so:
- The observer block (and the `p` it captures) lives in NotificationCenter forever.
- Every long-press-preview opens leaks one player + observer.
- After ~50 previews, you have 50 retained `AVPlayer`s decoding nothing.

**Fix:** capture the token (`let token = NotificationCenter.default.addObserver(...)`), store it in `@State`, call `NotificationCenter.default.removeObserver(token)` in `onDisappear`. Use `[weak p]` capture to break the cycle if AVFoundation hangs onto the observer beyond the deinit.

---

### H2. `StitchExporter.runPassthrough` resumes the continuation from a non-Sendable context AND ignores cancellation atomicity
**File:** `VideoCompressor/ios/Services/StitchExporter.swift:925-933`

```swift
await withTaskCancellationHandler {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        exporter.exportAsynchronously {
            continuation.resume()
        }
    }
} onCancel: {
    exporter.cancelExport()
}
```

Two issues:
1. **No once-only guard on the continuation.** `AVAssetExportSession.exportAsynchronously` is documented to fire the callback exactly once. So this resume is once-only in practice. But:
2. **Cancel race.** If the surrounding Task is already cancelled when this code runs, `withTaskCancellationHandler` invokes `onCancel` synchronously — `cancelExport()` is called BEFORE `exportAsynchronously` is called. Calling `cancelExport()` on a session that hasn't started typically does nothing; the export then proceeds normally and `continuation.resume()` fires after a successful encode. Result: user tapped Cancel, the encode ran to completion anyway, and the file ends up on disk + the post-flight `Self.metadataService.stripMetaFingerprintInPlace` runs on it, etc.

**Fix:** check `Task.isCancelled` immediately inside the body before `exportAsynchronously` and short-circuit (resume + throw cancelled). Mirror the `CancelCoordinator` shape used in `CompressionService`. Lower priority than C2 because passthrough only fires when all clips match exactly, which is rare in practice.

---

### H3. `runPassthrough` calls `onProgress(.complete)` regardless of terminal status
**File:** `VideoCompressor/ios/Services/StitchExporter.swift:935-942`

```swift
progressTask.cancel()
await MainActor.run { onProgress(.complete) }

switch exporter.status {
case .completed: return outputURL
case .cancelled: throw CompressionError.cancelled
...
```

`onProgress(.complete)` fires unconditionally before status is checked. If the export was cancelled or failed, the UI receives a "100% complete" event right before the failure error — visually misleading and breaks the "progress can only end at .complete on success" implicit contract that `BoundedProgress.complete` carries elsewhere in the codebase.

**Fix:** move `onProgress(.complete)` into the `.completed` branch only.

---

### H4. `TrimEditorView` drag-start auto-play `Task` is fire-and-forget
**File:** `VideoCompressor/ios/Views/StitchTab/TrimEditorView.swift:88-92`

```swift
.onChange(of: isDraggingStart) { _, dragging in
    guard !dragging else { return }
    cancelAutoPlay()
    let seekTime = CMTime(seconds: currentStart, preferredTimescale: 600)
    Task { @MainActor in
        await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        guard !Task.isCancelled else { return }
        player.play()
    }
}
```

The end-handle release at line 99 stores its task in `autoPlayTask` so it can be cancelled. The start-handle release does not — it spawns an unowned `Task`. If the user releases the start handle then immediately scrubs again, the orphan task may complete `player.play()` after `seekTo` from a fresh gesture set the player elsewhere — UI flickers. Worse, on `.onDisappear`, only `autoPlayTask` gets cancelled; the orphan task may call `player.play()` against an `AVPlayer` whose owner just deallocated. Not a crash because `player` is a `@State` strong ref, but it's still rogue work.

**Fix:** assign this Task to `autoPlayTask` too, mirroring the end-handle pattern.

---

## MEDIUM

### M1. `runReencode` creates a fresh `CompressionService()` per export — fine, but the actor's `Self.metadataService` and `photoMetadataService` are shared
**File:** `VideoCompressor/ios/Services/VideoLibrary.swift:43-48`, `:305`

```swift
fileprivate static let metadataService = MetadataService()
fileprivate static let photoMetadataService = PhotoMetadataService()
```

These are shared singletons. Every concurrent compress/stitch job that completes calls `await Self.metadataService.stripMetaFingerprintInPlace(at: outputURL)`. Because `MetadataService` is an actor, those calls serialize on a single actor's mailbox. With `currentSafeConcurrency() == 2` (Pro iPhones), the second-completing job's strip blocks until the first job's strip drains.

This is correct — no race — but it's a serialization pinch the team may not be aware of: a 5-second strip on an 8-job batch costs 40s extra on Pro devices and the parallelism wins disappear. Not a correctness bug.

**Fix (if Pro-device throughput matters):** make `stripMetaFingerprintInPlace` a `static func` that creates a per-call instance, or expose a method that takes the asset's URL and runs entirely with stack-local state (no actor isolation needed — `read` and `strip` only touch the file system).

---

### M2. `StitchExporter.Plan: @unchecked Sendable` is OK in current flow but fragile
**File:** `VideoCompressor/ios/Services/StitchExporter.swift:48-61`

Comment says "no concurrent access in practice" — true today. But the `Plan` is returned from the actor (`StitchExporter`), held briefly on the MainActor (`StitchProject.runExport`), then passed BACK into the actor for `export`. That's two actor hops with the AVMutableComposition. As long as no main-actor code touches `plan.composition` in between, it's fine. Currently nothing does.

The risk: future code adds a "preview the composition" or "estimate size" call between `buildPlan` and `export` on the MainActor. The composition would be touched while the actor still holds it. No race today; flag for the team to keep `Plan` opaque to the MainActor.

**Fix:** consider adding a doc comment on `Plan` warning callers not to read its fields outside the StitchExporter actor.

---

### M3. `AudioBackgroundKeeper` `audioPlayer?` is touched outside its `@MainActor` boundary on first use
**File:** `VideoCompressor/ios/Services/AudioBackgroundKeeper.swift:18, 56-60`

The class is `@MainActor`, so all access goes through the main actor — fine. But `silentTrackURL()` does synchronous `AVAudioFile.write(...)` on the main thread on first call; the file is small (~44KB AAC) but this is a blocking IO call on the main actor. Probably <50ms but could spike.

**Fix:** kick off `silentTrackURL()` lazily on a background detached task at app launch (inside `VideoCompressorApp.init` after the cache sweep) so the first encode doesn't pay the cost.

---

### M4. `MetaCleanQueue.runBatch` mutates `batchProgress` on `Task { [weak self] }` which is MainActor-bound, but the closure captures may race with a fast `cancelBatch()`
**File:** `VideoCompressor/ios/Services/MetaCleanQueue.swift:204-213, 215-218`

```swift
batchTask = Task { [weak self] in
    await self?.runBatch(...)
}

func cancelBatch() {
    batchTask?.cancel()
    batchProgress.isRunning = false
}
```

`cancelBatch()` sets `isRunning = false` immediately. `runBatch` continues running until the next `Task.isCancelled` check — and at line 273-275 it sets `batchProgress.perItem = .complete; batchProgress.isRunning = false; onAllDone()` unconditionally on exit, which can flip `isRunning` from false (set by cancelBatch) to false again (no-op) but also fire `onAllDone()` on a cancelled batch, inviting double-completion if the UI also responded to cancelBatch by dismissing.

**Fix:** in `runBatch`, distinguish `.cancelled` exit from natural exit and skip `onAllDone()` on cancel. Move the `batchProgress.isRunning = false` to a `defer` for atomicity.

---

### M5. `CompressionService.encode` post-flight reads `reader.status` and `writer.status` without an actor barrier
**File:** `VideoCompressor/ios/Services/CompressionService.swift:454-467`

After the continuation resumes (all pumps finished), the actor reads `reader.status` and may call `reader.error?.localizedDescription`. The pump dispatch queues that wrote to the reader/writer state are NOT memory-fenced relative to the actor's continuation resume. AVFoundation's reader/writer are documented thread-safe for status reads, so this is fine in practice — but if AVAssetReader were ever swapped for a different pipeline, a memory barrier would be needed. Worth a comment.

**Fix:** add a one-line comment noting the implicit barrier from AVFoundation's thread-safety guarantee.

---

## LOW

### L1. `Haptics.selectionGenerator` is a static var on a `@MainActor enum` — works, but pattern is unusual
**File:** `VideoCompressor/ios/Services/Haptics.swift:48-52`

A `static var` initializer on a `@MainActor` type runs on first access; if called from off-main during testing, it would trap. Production callers are all `@MainActor`. Cosmetic.

**Fix:** none required for ship.

---

### L2. `StitchClipFetcher` uses `Task.detached(priority:).value` — fine but spawns a transient actor per call
**File:** `VideoCompressor/ios/Services/StitchClipFetcher.swift:31-38, 49-61`

Each call to `creationDate(forAssetID:)` spawns a detached task. `PHAsset.fetchAssets` is documented synchronous and fast; the detach is to avoid main-actor stalls. For a 50-clip sort (`creationDates(forAssetIDs:)` batch path), this is a single detach — fine. The single-clip path is rarely called in tight loops, so the spawn overhead is acceptable.

**Fix:** none required for ship.

---

## What was checked and found CLEAN

- `CompressionService` `CancelCoordinator` + `PumpState` + `ContinuationBridge` — proven, correct, well-documented (lines 562-679).
- `StitchExporter.buildPlan` cancellation — `Task.checkCancellation()` at the right granularity (line 94, 181).
- `VideoLibrary.compressAll` task-group bounded concurrency — correct (lines 196-222).
- `CacheSweeper` — pure actor, all methods isolated; `nonisolated folderSize` is read-only IO.
- `ThumbnailStripGenerator` — async sequence consumed correctly; failures swallowed by design.
- `PhotoCompressionService` — synchronous ImageIO, no concurrency surface to misuse.
- `StitchProject.export` `[weak self]` capture — correct.

---

## Ship-day recommendation

**Block ship on C1, C2, H1.** These are correctness bugs reachable on real user paths:
- C1: any stitch that includes a still image
- C2: any MetaClean cancel
- H1: any user who long-press-previews >5 clips

H2/H3/H4 should fix in the same session — they're 5–15 minutes each and prevent embarrassing "I cancelled and it saved anyway" reports.

The MEDIUMs are healthy refactors but won't crash the app on ship day.
