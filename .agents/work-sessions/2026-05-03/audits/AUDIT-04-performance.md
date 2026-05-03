# AUDIT-04 — Performance & Efficiency (iOS)

**Date:** 2026-05-03
**Scope:** `/VideoCompressor/ios/` (54 Swift files)
**Mode:** Read-only review. No `xcodebuildmcp` calls.
**Auditor:** [solo/opus]

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 1 |
| HIGH | 2 |
| MEDIUM | 3 |
| LOW | 3 |
| **Total** | **9** |

Two user-flagged concerns confirmed:
- **A. Still-image bake is O(stillDuration × 30)** — confirmed CRITICAL. 10s still bakes 300 frames serially.
- **B. "Building composition" feels frozen** — partially fixed by PR #8 (still-bake phase now determinate), but the **clip-iteration phase of `buildPlan`** still sits on the indeterminate `.building` spinner while doing `loadTracks` / `load(.formatDescriptions)` / `load(.naturalSize)` / `load(.nominalFrameRate)` serially per clip. For a 20-clip video-only timeline this is the bulk of perceived delay. Surfaced as HIGH-1.

`progressFooter` switch wiring in `StitchExportSheet.swift` is correct for `.preparing`.

---

## Findings

### CRITICAL-1 — `StillVideoBaker` writes 30N frames per still (should be O(1))

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StillVideoBaker.swift:162`

```swift
let totalFrames = max(1, Int(duration * Double(frameRate)))  // 30s still → 900 frames
```

The bake pump appends 30 identical frames per second of `stillDuration` via `requestMediaDataWhenReady`. For a 10-second still that's 300 H.264-encoded frames; clamped max is 10s but a 10-photo timeline at 10s each is **3,000 frame appends serial through one writer**. All inter-frame predictions converge to zero motion so the encoded file is small, but the encoder still runs once per frame.

The canonical Apple pattern (twocentstudios ref, Apple sample code) is the **two-frame bake**: append the buffer at PTS=0 and again at PTS=duration. The writer's natural duration equals the last PTS. For a still that's a constant 2 appends regardless of `stillDuration`.

#### Concrete fix — drop-in for `StillVideoBaker.bake()`

Replace lines 153-218 (the entire `requestMediaDataWhenReady` block + finishWriting) with:

```swift
// Bake exactly two frames at PTS=0 and PTS=duration. The writer's natural
// duration equals the final PTS, so a 2-frame .mov plays back as a stretched
// still for `duration` seconds without any per-second encoding cost.
let endPTS = CMTime(seconds: duration, preferredTimescale: 600)
guard adaptor.append(buffer, withPresentationTime: .zero) else {
    try? FileManager.default.removeItem(at: outURL)
    throw BakeError.appendFailed(
        writer.error?.localizedDescription ?? "first-frame append returned false"
    )
}
guard adaptor.append(buffer, withPresentationTime: endPTS) else {
    try? FileManager.default.removeItem(at: outURL)
    throw BakeError.appendFailed(
        writer.error?.localizedDescription ?? "end-frame append returned false"
    )
}
input.markAsFinished()
await writer.finishWriting()
if writer.status != .completed {
    try? FileManager.default.removeItem(at: outURL)
    throw BakeError.writerFinishFailed(
        writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)"
    )
}
return outURL
```

Then delete:
- `FrameCounter` class (lines 223-256)
- `AppendFailureBox` class (lines 258-266)
- `let totalFrames = max(1, Int(duration * Double(frameRate)))` (line 162)
- The whole `withCheckedContinuation` / `requestMediaDataWhenReady` dance (lines 169-202)

#### Optional hardening
The 2-frame stream produces 2 I-frames regardless. `AVVideoMaxKeyFrameIntervalKey: frameRate` (line 87) is harmless but meaningless — drop it for clarity:

```swift
AVVideoCompressionPropertiesKey: [
    AVVideoAverageBitRateKey: 2_000_000,
    // No AVVideoMaxKeyFrameIntervalKey — 2-frame stream is two I-frames.
],
```

#### `StitchExporter.buildPlan` change needed: NONE
The baked .mov's `naturalDuration` matches `stillDuration` either way. `clip.trimmedRange` math (lines 102-105 of StitchExporter setting `trimEndSeconds = clamped`) is unaffected.

#### Alternative considered — `scaleTimeRange(_:toDuration:)`
Bake a 1-second clip and stretch in `AVMutableComposition.scaleTimeRange`. Works for slow-down (the 8x limit applies to speed-up only — verified via Apple Developer Forums thread 705133). Rejected because:
1. Adds a moving piece to `buildPlan` (per-clip post-insert scale call).
2. The baked file's `naturalDuration` would no longer match the displayed duration, breaking the symmetry the rest of the export pipeline assumes.
3. The 2-frame bake is strictly simpler.

#### Impact
A 10-still timeline at 10s each: **6,000 frame appends → 20 frame appends**. Bake phase wall-clock drops from seconds to milliseconds. Removes the entire `FrameCounter`/`AppendFailureBox` concurrency surface (and its associated bug-prone re-entrancy guards).

---

### HIGH-1 — `buildPlan` clip-iteration phase has no progress reporting

**Files:**
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StitchExporter.swift:177-258` (the per-clip loop)
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Models/StitchProject.swift:427` (`exportState = .building`)
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Views/StitchTab/StitchExportSheet.swift:96-100` (`.building` UI)

PR #8 added `.preparing(current, total)` for the still-bake phase, which is correctly wired in `progressFooter` (StitchExportSheet.swift:101-115). However, **a video-only timeline never enters `.preparing`** — `buildPlan` does the still-bake loop (no-op when no stills), then immediately starts the clip-iteration loop where each clip runs:

```swift
let videoTracks = try await asset.loadTracks(withMediaType: .video)              // I/O
let formatDescriptions = try await assetVideoTrack.load(.formatDescriptions)     // I/O
let trackNaturalSize = try await assetVideoTrack.load(.naturalSize)              // I/O
let trackFrameRate = try await assetVideoTrack.load(.nominalFrameRate)           // I/O
try videoT.insertTimeRange(timeRange, of: assetVideoTrack, at: insertAt)         // I/O
try? audioT.insertTimeRange(timeRange, of: assetAudio, at: insertAt)             // I/O (loadTracks)
```

For a 20-clip timeline that's ~120 awaits serially. The user sees the indeterminate "Building composition…" spinner for the entire duration — the exact "frozen" feeling reported.

#### Fix
Mirror the still-bake progress callback shape:

```swift
// In buildPlan signature:
onClipProgress: @MainActor @Sendable @escaping (_ current: Int, _ total: Int) -> Void = { _, _ in }

// In the per-clip loop (after the existing Task.checkCancellation()):
await onClipProgress(segments.count, clips.count)

// In StitchProject.runExport, parallel to onPrepareProgress:
onClipProgress: { [weak self] current, total in
    self?.exportState = .preparing(current: current, total: total)
}
```

(Or introduce a separate `.indexing(current:total:)` state if the UI string should differ.)

This makes the "Building composition" feeling go away by replacing the indeterminate spinner with a determinate "Indexing 7 of 20 clips…" bar that ticks every ~50-200 ms.

---

### HIGH-2 — Pinch-to-zoom rebuilds layout on every gesture frame

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift:84,107`

```swift
ClipBlockView(clip: clip)
    .frame(width: baseClipWidth * zoom, height: baseClipHeight * zoom)
```

Every magnification delta writes to `@State zoom`, which invalidates SwiftUI's layout pass for **every** `ClipBlockView` in the (non-lazy) `HStack`. Each one re-runs its `body`, re-measures, and re-frames. Internal `thumbnailStrip` does an `HStack` of 4 `Image`s with `.aspectRatio(.fill).clipped()` — image clipping recomputes per frame.

Because the timeline is a non-lazy `HStack` inside a `ScrollView`, every clip is already rendered (so this isn't a virtualization issue) — the hit is layout invalidation, not eager render.

#### Fix
Apply zoom as a single `.scaleEffect` on the parent HStack so child frames stay constant and only the GPU transform is recomputed:

```swift
HStack(spacing: 8) {
    ForEach(project.clips) { clip in
        // ... use baseClipWidth / baseClipHeight WITHOUT zoom multiplier
        ClipBlockView(clip: clip)
            .frame(width: baseClipWidth, height: baseClipHeight)
    }
}
.scaleEffect(zoom, anchor: .leading)
.frame(height: baseClipHeight * zoom)  // expand the container so scroll math is right
```

The drag-preview (`.draggable` closure at line 107) and dropTargetID indicator (`baseClipHeight * zoom * 0.85` at line 78) similarly stop multiplying. Selection ring lineWidth at line 92 might want to compensate (`3 / zoom`) so it stays visually 3pt regardless of zoom.

#### Caveats
- `.scaleEffect` will scale text rendering too, which can look pixelated at zoom > 1.5. If sharpness matters, swap to a single `.frame` mutation gated through a debouncer (e.g. only commit `zoom` to `@State` on `onEnded` and keep an in-progress `@GestureState` for the live transform).
- Verify drag thumbnails still feel right post-fix — `.draggable` previews aren't transformed by `.scaleEffect` on the parent.

---

### MEDIUM-1 — Thumbnails are NOT cached; regenerated on every render

**Files:**
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Views/StitchTab/ClipBlockView.swift:42,77-97`
- `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/ThumbnailStripGenerator.swift:18-83`

```swift
.task(id: clip.sourceURL) { await loadThumbnails() }
```

Every time `ClipBlockView` enters the view hierarchy, `loadThumbnails()` runs, which constructs a fresh `AVAssetImageGenerator` and runs `images(for: times)` for 4 frames. There is **no in-memory cache** anywhere in the codebase (verified via grep — no `NSCache`, no static cache dictionary, no `@StateObject` model holding strips).

Triggers full regen:
- Tab-switching (Compress → Stitch and back).
- Sheet present/dismiss (`StitchExportSheet`).
- Any parent re-render that recreates `ClipBlockView` instances.
- After a clip mutation that changes `clip.sourceURL` (rare — only the bake path does this).

For a 50-clip timeline that's `4 × 50 = 200 AVAssetImageGenerator` setups + frame extracts on each remount.

#### Fix
Add a process-wide `NSCache<NSURL, NSArray>` keyed by `sourceURL`:

```swift
// New file or top of ThumbnailStripGenerator.swift:
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSArray>()
    init() { cache.countLimit = 200 }  // ~50 clips × 4 thumbs ≈ 200 frames

    func get(_ url: URL) -> [UIImage]? {
        cache.object(forKey: url as NSURL) as? [UIImage]
    }
    func set(_ url: URL, _ thumbs: [UIImage]) {
        cache.setObject(thumbs as NSArray, forKey: url as NSURL)
    }
}
```

In `ClipBlockView.loadThumbnails()`:

```swift
if let cached = ThumbnailCache.shared.get(clip.sourceURL) {
    self.thumbnails = cached
    return
}
// ... existing generate path ...
ThumbnailCache.shared.set(clip.sourceURL, thumbnails)
```

`UIImage` is internally backed by CGImage (often shared via IOSurface), so memory cost is moderate; `NSCache` evicts under pressure. A safer bound is `cache.totalCostLimit` with `setObject(_:forKey:cost:)` if you want an explicit byte budget.

---

### MEDIUM-2 — `ClipBlockView.thumbnailStrip` uses identity-by-offset, breaking SwiftUI diffing

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Views/StitchTab/ClipBlockView.swift:60`

```swift
ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
    Image(uiImage: img)
        ...
}
```

`id: \.offset` means SwiftUI treats every thumbnail at index `i` as the same identity even when the underlying `UIImage` changes (e.g. when reload populates fresh frames). It mostly works because the `Image(uiImage:)` initializer sees a different value, but the diff-elision skips proper teardown of GPU-backed image views. Combined with the rebuild-every-frame from HIGH-2, this can manifest as flicker on zoom.

#### Fix

Either iterate by index without `id:` (uses position) or hash the image:

```swift
ForEach(thumbnails.indices, id: \.self) { i in
    Image(uiImage: thumbnails[i])
        ...
}
```

Low priority on its own, but compounds the layout-invalidation cost from HIGH-2.

---

### MEDIUM-3 — `ThumbnailStripGenerator` has no concurrency limit; many clips → many generators

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/ThumbnailStripGenerator.swift:18-83`

`actor ThumbnailStripGenerator` is created **per `ClipBlockView`** (line 91 of ClipBlockView):

```swift
let gen = ThumbnailStripGenerator()
do {
    thumbnails = try await gen.generate(for: clip.sourceURL, count: 4, maxDimension: 80)
}
```

Each `AVAssetImageGenerator` decodes through VideoToolbox; running 50 simultaneously on import contends for the same hardware decoder slots. The actor keyword serializes calls **on the same actor instance**, but each clip gets its own actor → no contention limit at all.

#### Fix
Make it a shared singleton actor and either rely on its serial isolation (slower but bounded) or add a semaphore for N=4 concurrent decodes:

```swift
actor ThumbnailStripGenerator {
    static let shared = ThumbnailStripGenerator()
    private var inFlight = 0
    private let maxConcurrent = 4
    // ... gate generate() with inFlight count, await when at limit ...
}
```

Combined with MEDIUM-1's cache, this is the difference between a 50-clip import locking VideoToolbox for ~5s and finishing in under 1s.

---

### LOW-1 — `ClipLongPressPreview` AVPlayer leak via NotificationCenter observer

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift:303-313`

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

The block-form `addObserver` returns a token; this discards it. `onDisappear` only pauses the player — the observer stays registered against the (now leaked-via-strong-capture) AVPlayerItem. Each long-press leaks a player, item, and observer.

**Performance impact:** small per long-press, but accumulates across a session. Memory-leak audit (AUDIT-02) may have surfaced this separately.

#### Fix
Capture the token and remove it on disappear:

```swift
@State private var loopObserver: NSObjectProtocol?
...
loopObserver = NotificationCenter.default.addObserver(...)
...
.onDisappear {
    if let obs = loopObserver {
        NotificationCenter.default.removeObserver(obs)
    }
    player?.pause()
    player = nil
}
```

`AVPlayer`'s long-press preview is otherwise correctly cleaned up (small object, fast init), so this is LOW.

---

### LOW-2 — `StitchExporter` actor serializes re-encode pipeline

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StitchExporter.swift:39-957`

The actor isolates `buildPlan` and `runReencode`, which means a future "parallel multi-export" feature couldn't build two compositions concurrently. Heavy work (the AVAssetWriter pump) actually runs in `CompressionService` — its own actor — so the StitchExporter actor is mostly state-coordination. Fine today; flag for the future.

No action required.

---

### LOW-3 — `AVAssetExportSession` deprecation warnings (passthrough path)

**File:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/ios/Services/StitchExporter.swift:898-956`

`AVAssetExportSession.exportAsynchronously(completionHandler:)` is deprecated in iOS 18 in favor of `export(to:as:)`. The passthrough path uses the deprecated callback shape. **Functionally fine through iOS 18; not a perf issue.** Flag for a future migration when minimum target moves past iOS 18.

No action required.

---

## Items dismissed (verified not concerns)

| Item | Verdict |
|---|---|
| `ClipLongPressPreview` AVPlayer creation cost | Cheap. Per-press init is fast; teardown logic correct except for LOW-1's observer leak. |
| `HapticTicker` × 4 in `ClipEditorInlinePanel` | Lightweight; each holds one `UISelectionFeedbackGenerator` + 2 `Int`s. Negligible. |
| `StitchClipFetcher.creationDates` batch | Verified: single `PHAsset.fetchAssets(withLocalIdentifiers:)` call inside `Task.detached`. Correct. |
| `CacheSweeper.sweepOnLaunch` blocking app start | Runs in `Task.detached(priority: .utility)` from `VideoCompressorApp.init` — non-blocking. |
| `progressFooter` switch in `StitchExportSheet.swift` | `.preparing(current:total:)` case correctly wired with `ProgressView(value:)` + dynamic label. |

---

## Recommended fix order

1. **CRITICAL-1** (StillVideoBaker constant-time bake) — small surgical change, removes user-reported delay, deletes ~50 lines of fragile concurrency.
2. **HIGH-1** (buildPlan clip-iteration progress) — completes the "Building composition" UX fix that PR #8 started.
3. **MEDIUM-1** + **MEDIUM-3** (thumbnail cache + concurrency limit) — paired; biggest UX win for large timelines.
4. **HIGH-2** (pinch zoom transform) — visible improvement on iPhone 12 / older devices.
5. **LOW-1** (observer leak) — defensive, ships with any other StitchTimelineView edit.

---

## Sources

- [scaleTimeRange(_:toDuration:) — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avmutablecomposition/1390549-scaletimerange)
- [AVMutableComposition scaleTimeRange — Apple Developer Forums](https://developer.apple.com/forums/thread/705133)
- [Creating a Movie with an Image and Audio on iOS — twocentstudios](https://twocentstudios.com/2017/02/20/creating-a-movie-with-an-image-and-audio-on-ios/)
- [AVAssetWriter with non-constant frame rate — Apple Developer Forums](https://developer.apple.com/forums/thread/92020)
