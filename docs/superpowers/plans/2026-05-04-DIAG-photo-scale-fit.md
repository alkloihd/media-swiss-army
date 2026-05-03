# DIAG — Stitched photo renders as small inset instead of filling canvas

**Date:** 2026-05-04
**Reporter:** end user (real-device iPhone test, Stitch tab)
**Severity:** HIGH — visible output corruption for the most common still-import case (HEIC photos)
**Mode:** READ-ONLY diagnosis. No code modified.

---

## 1. Symptom

Verbatim user report:

> "one image did not stretch to fit and was way too small which was annoying — i thought photos would auto fit into the frame or something regardless of size or aspect ratio"

The photo rendered as a tiny inset on a much larger canvas, surrounded by black bars far wider than a normal letterbox/pillarbox. The user expected the photo to be scaled UP to fill the canvas (aspect-preserving, with thin letterbox/pillarbox bars only on the mismatched axis).

---

## 2. Pipeline trace — what actually happens to a still

### Step A: User picks a HEIC photo via PhotosPicker

`VideoCompressor/ios/Views/StitchTab/StitchTabView.swift:262-275`

`PhotoTransferable` runs. `pickedKind = .still`. The picker's tmp file is moved into `Documents/StitchInputs/`.

### Step B: Probe the still's pixel dimensions

`VideoCompressor/ios/Views/StitchTab/StitchTabView.swift:323-335`

```swift
case .still:
    duration = CMTime(seconds: 3.0, preferredTimescale: 600)
    let stillSize: CGSize = await Task.detached(priority: .userInitiated) {
        guard let src = CGImageSourceCreateWithURL(stableURL as CFURL, nil), ...
        let w = (props[kCGImagePropertyPixelWidth]  as? NSNumber)?.intValue ?? 1920
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 1080
        return CGSize(width: w, height: h)
    }.value
    naturalSize = stillSize
```

`kCGImagePropertyPixelWidth/Height` returns **PRE-orientation** pixel dimensions. A portrait iPhone HEIC stored as 4032×3024 with EXIF orientation tag 6 returns `naturalSize = (4032, 3024)` — i.e. **landscape** in raw pixel space, despite the user seeing it in portrait.

### Step C: Construct StitchClip at import

`VideoCompressor/ios/Views/StitchTab/StitchTabView.swift:352-363`

```swift
let clip = StitchClip(
    id: UUID(),
    sourceURL: stableURL,
    displayName: displayName,
    naturalDuration: duration,
    naturalSize: naturalSize,         // (4032, 3024) — pre-orientation
    kind: pickedKind,                 // .still
    preferredTransform: preferredTransform,  // .identity (line 292)
    ...
)
```

So the StitchClip carries `naturalSize=(4032, 3024)` and `preferredTransform=.identity`. Its `displaySize` derivation in `StitchClip.swift:173-177`:

```swift
var displaySize: CGSize {
    let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    return CGSize(width: abs(rect.width), height: abs(rect.height))
}
```

returns `(4032, 3024)` — landscape orientation, even though the photo is actually portrait on disk (EXIF) and on the bake.

### Step D: Bake to .mov in StitchExporter.buildPlan

`VideoCompressor/ios/Services/StitchExporter.swift:91-124`

```swift
if clip.kind == .still {
    let stillDuration = clip.edits.stillDuration ?? 3.0
    let clamped = min(10.0, max(1.0, stillDuration))
    let bakedURL = try await baker.bake(still: clip.sourceURL, duration: clamped)
    bakedStillURLs.append(bakedURL)
    var bakedEdits = clip.edits
    bakedEdits.trimStartSeconds = 0
    bakedEdits.trimEndSeconds = clamped
    let baked = StitchClip(
        id: clip.id,
        sourceURL: bakedURL,
        displayName: clip.displayName,
        naturalDuration: CMTime(seconds: clamped, preferredTimescale: 600),
        naturalSize: clip.naturalSize,         // ← BUG: still (4032, 3024) — the PRE-bake pixel size
        kind: .video,
        preferredTransform: .identity,
        ...
    )
    bakedClips.append(baked)
}
```

The bake (`StillVideoBaker.swift:39-225`) uses:

`StillVideoBaker.swift:52-62`
```swift
let thumbOpts: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,   // EXIF orientation IS applied
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: maxEdge,        // 1920
]
guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) ...
let width = (cgImage.width / 2) * 2
let height = (cgImage.height / 2) * 2
```

For the 4032×3024 portrait HEIC:
- After EXIF transform → 3024×4032 (portrait)
- After thumbnail cap at 1920 long-edge → **1440×1920** (or similar, both rounded to even)
- Baker produces a **1440×1920 .mov**

So we now have a baked StitchClip whose `sourceURL` resolves to a **1440×1920** asset, but whose `naturalSize` field still claims **(4032, 3024)** and whose `preferredTransform` is `.identity`.

### Step E: AVMutableComposition inserts the baked .mov

`VideoCompressor/ios/Services/StitchExporter.swift:183-201`

```swift
let asset = AVURLAsset(url: clip.sourceURL)            // baked .mov
let videoTracks = try await asset.loadTracks(withMediaType: .video)
...
let trackNaturalSize = try await assetVideoTrack.load(.naturalSize)  // (1440, 1920)
...
if trackNaturalSize.width * trackNaturalSize.height
    > maxNaturalSize.width * maxNaturalSize.height {
    maxNaturalSize = trackNaturalSize
}
```

**Notice the discrepancy**: `trackNaturalSize` comes from the baked asset (1440×1920) and feeds `maxNaturalSize` and the passthrough size check, but the `clip.naturalSize` field still says (4032, 3024) and is what `displaySize` and `computeRenderSize` see for the `.still` clip.

### Step F: Compute render canvas

`VideoCompressor/ios/Services/StitchExporter.swift:854-881`

`computeRenderSize` votes via `clip.displayOrientation`. For our portrait HEIC:
- `displaySize = (4032, 3024)` → `displayOrientation = .landscape` (because `4032 > 3024 * 1.05`)
- If this is the only clip, auto canvas = **1920×1080 (landscape)**
- Even if the user picks `.portrait` mode (1080×1920), the next step still breaks — see below.

### Step G: makeAspectFitLayer applies the WRONG scale

`VideoCompressor/ios/Services/StitchExporter.swift:700-748`

```swift
private func makeAspectFitLayer(
    clip: StitchClip,
    track: AVMutableCompositionTrack,
    timeRange: CMTimeRange,
    renderSize: CGSize
) -> AVMutableVideoCompositionLayerInstruction {
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    var t = clip.preferredTransform                      // .identity
    ...
    let display = clip.displaySize                       // (4032, 3024)  ← WRONG
    if display.width > 0, display.height > 0,
       renderSize.width > 0, renderSize.height > 0 {
        let scale = min(
            renderSize.width  / display.width,           // 1920 / 4032 = 0.476
            renderSize.height / display.height           // 1080 / 3024 = 0.357
        )                                                // → 0.357
        let scaledW = display.width  * scale             // 1440
        let scaledH = display.height * scale             // 1080
        let dx = (renderSize.width  - scaledW) / 2       // 240
        let dy = (renderSize.height - scaledH) / 2       // 0
        t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))   // 0.357×
        t = t.concatenating(CGAffineTransform(translationX: dx, y: dy))
    }
    layer.setTransform(t, at: timeRange.start)
    ...
}
```

`setTransform` applies a **0.357× scale** to the actual 1440×1920 source, producing a **514×686** rendered rectangle on a 1920×1080 canvas. That's a tiny portrait-shaped patch sitting at offset (240, 0) — exactly the "small inset" the user described.

### Step H: Why the user's 800×600 PNG case in the spec would actually work

If the source had been a small no-EXIF PNG (800×600):
- Pre-bake `naturalSize = (800, 600)`
- Baker produces 800×600 .mov (unchanged — under maxEdge, no orientation rotation)
- `displaySize = (800, 600)`
- canvas auto = 1920×1080 (landscape vote)
- scale = `min(1920/800, 1080/600) = min(2.4, 1.8) = 1.8`
- Rendered: 1440×1080, centred — **correct, with thin pillarbox**

So the bug is **not** that small images aren't upscaled. The bug is that the `naturalSize` carried into the post-bake `StitchClip` is **stale relative to the baked .mov whenever EXIF rotation OR thumbnail downscale was applied** — which is virtually every iPhone photo (HEIC with orientation, JPEG > 1920px on long edge, etc.).

---

## 3. Root-cause hypotheses

### H1 (HIGH confidence) — Post-bake StitchClip carries pre-bake naturalSize

**Where:** `VideoCompressor/ios/Services/StitchExporter.swift:106-117` (the `StitchClip(... naturalSize: clip.naturalSize, preferredTransform: .identity ...)` swap).

**Why it affects stills but not videos:** Videos go through Step E with `clip.naturalSize` already matching the AVURLAsset (set from the same `track.load(.naturalSize)` call at import — `StitchTabView.swift:307-313`). Stills are different — `naturalSize` is set from `CGImageSource` pixel properties (pre-orientation, full-resolution), but the bake produces an asset whose dimensions are EXIF-oriented and capped at maxEdge=1920. The two diverge.

**Evidence chain:**
- `StitchTabView.swift:326-335` reads pixel-space dims (no orientation applied).
- `StillVideoBaker.swift:52-62` applies orientation AND caps at 1920 long-edge.
- `StitchExporter.swift:115` writes `naturalSize: clip.naturalSize` into the post-bake clip — never sees the actual baked dims.
- `StitchExporter.swift:720-733` (`makeAspectFitLayer`) computes scale against the wrong `displaySize`.
- Already flagged in red-team `RED-TEAM-HOTFIX-2.md` line 36 as M1: "naturalSize: clip.naturalSize (the still's image size, often a different aspect than displaySize of the baked .mov)…" — but deferred with "ship as-is and note as a known issue."

**Fix:** make `StillVideoBaker.bake` return `(URL, CGSize)` where the CGSize is the actual baked-output dimensions (the post-rounding `width`/`height` from `StillVideoBaker.swift:66-67`). Use that size in the post-bake `StitchClip`.

**Confidence:** ~95%. The math is mechanical and the user's symptom (small inset, off-centre on the long-axis side, wrong canvas orientation auto-pick) is exactly what the formulas predict.

### H2 (LOW confidence) — Aspect-fit math has a "no upscale" guard

`makeAspectFitLayer` uses `min(scaleX, scaleY)` with no `min(scale, 1.0)` cap. **Verified:** there is NO upscale cap; small sources DO get scaled up. So this is NOT the bug. Fully ruled out.

---

## 4. Recommended fix

**File:** `VideoCompressor/ios/Services/StillVideoBaker.swift`
**File:** `VideoCompressor/ios/Services/StitchExporter.swift`

### Diff (recommended shape)

`StillVideoBaker.swift:39` — change return type:

```swift
// Before:
func bake(still sourceURL: URL, duration: Double) async throws -> URL

// After:
func bake(still sourceURL: URL, duration: Double) async throws -> (url: URL, size: CGSize)
```

`StillVideoBaker.swift:224` — return the size we already computed:

```swift
// Before:
return outURL

// After:
return (url: outURL, size: CGSize(width: width, height: height))
```

`StitchExporter.swift:98-117` — capture the size and use it:

```swift
// Before:
let bakedURL = try await baker.bake(still: clip.sourceURL, duration: clamped)
bakedStillURLs.append(bakedURL)
var bakedEdits = clip.edits
bakedEdits.trimStartSeconds = 0
bakedEdits.trimEndSeconds = clamped
let baked = StitchClip(
    id: clip.id,
    sourceURL: bakedURL,
    displayName: clip.displayName,
    naturalDuration: CMTime(seconds: clamped, preferredTimescale: 600),
    naturalSize: clip.naturalSize,
    kind: .video,
    preferredTransform: .identity,
    ...
)

// After:
let bakeResult = try await baker.bake(still: clip.sourceURL, duration: clamped)
bakedStillURLs.append(bakeResult.url)
var bakedEdits = clip.edits
bakedEdits.trimStartSeconds = 0
bakedEdits.trimEndSeconds = clamped
let baked = StitchClip(
    id: clip.id,
    sourceURL: bakeResult.url,
    displayName: clip.displayName,
    naturalDuration: CMTime(seconds: clamped, preferredTimescale: 600),
    naturalSize: bakeResult.size,            // ← use ACTUAL baked dimensions
    kind: .video,
    preferredTransform: .identity,           // baker bakes oriented + identity matches
    ...
)
```

### Alternative (if preserving the bake API matters)

After the bake, load the baked asset's track natural size:

```swift
let bakedURL = try await baker.bake(still: clip.sourceURL, duration: clamped)
let bakedAsset = AVURLAsset(url: bakedURL)
let bakedSize = try await bakedAsset.loadTracks(withMediaType: .video).first
    .flatMap { try? await $0.load(.naturalSize) } ?? clip.naturalSize
```

This is one extra await per still (cheap — the asset is local). Slightly less clean than threading the size through the return, but doesn't change `StillVideoBaker`'s public API.

### Crop-edit survival (HOTFIX-2 M1 follow-up)

Crops authored on a still's pre-bake displayed (oriented) preview need to map onto the baked oriented dimensions. If the inline editor renders against the oriented preview (likely — `ClipEditorInlinePanel` uses AVPlayer for video and image preview for stills, both showing the user-facing orientation), then `cropNormalized` is in oriented coords and matches the baked dims **after** this fix. If the editor rendered against pre-orientation pixels (unlikely, but worth a one-line check), the crop would still mis-map. Verify with a manual rotate-then-crop-then-export test on a HEIC; not a blocker.

---

## 5. Aspect-fit vs aspect-fill — UX recommendation

The user said "stretch to fit," but stretch literally distorts aspect (squashed/squished), which they would NOT want. They mean one of:

| Mode | Behavior | Trade-off |
|---|---|---|
| **Aspect-fit (current intent)** | Scale UP/DOWN to fit canvas, preserve aspect, fill residual with black bars. | No pixel data lost. Bars on mismatched axis. **What we have today (broken by H1).** |
| **Aspect-fill** | Scale to FILL canvas, preserve aspect, crop the overflowing axis. | No bars. Loses pixel data on the mismatched axis (e.g. a portrait photo on landscape canvas loses top/bottom). |
| **Stretch** | Scale x/y independently to canvas. | No bars, no crop, but distorts aspect. Almost never what users want for photos. |

**Recommend:** Keep aspect-fit as the default behavior — that's what the math is trying to do, and once H1 is fixed, the user's reported case ("HEIC photo on landscape canvas") will render as a 1440×1080 photo with thin 240px pillarbox bars on each side. This is the standard slideshow behaviour every consumer expects (Photos.app, Keynote, iMovie all default to aspect-fit). Most users get a satisfying "fits the frame" feel because their canvas usually matches the photo's orientation (auto-mode picks orientation from the photo's actual displaySize once H1 is fixed).

**Future enhancement (not blocking):** Per-clip "Fill / Fit / Stretch" toggle in `ClipEditorInlinePanel`. Default Fit. Surface as a small icon row in the inline editor next to the rotate/crop affordances. Track in backlog as a Phase 2/3 polish item — NOT for the hotfix.

---

## 6. Recommended cluster injection

**Recommendation:** new **Cluster 0 — hotfix** that lands BEFORE Cluster 1.

**Rationale:**
- This bug produces user-visible broken output for the most common photo type (HEIC). It's a ship-blocker for the still-in-stitch feature.
- Cluster 1 (`docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md`) is the natural home — it already touches `StillVideoBaker.bake` (changing it to O(1) via `scaleTimeRange`) and `StitchExporter.buildPlan`. But Cluster 1 is a multi-task refactor that may take 1-2 days; this fix is ~10 lines + tests and should ship same-day.
- If Cluster 1 hasn't started: fold this into Cluster 1 as Task 0 (preamble step) — both touch the same swap site, and the constant-time `scaleTimeRange` change in Cluster 1 will rebase cleanly on top of the size-return refactor.
- If Cluster 1 has started or shipped: ship as standalone Cluster 0 hotfix branch.

**Cluster 0 scope (one PR):**
1. Change `StillVideoBaker.bake` return to `(URL, CGSize)`.
2. Update the single call site in `StitchExporter.swift:98` to capture and use the new size.
3. Add a unit test in `VideoCompressorTests/StitchAspectRatioTests.swift` that constructs a baked `StitchClip` with `naturalSize` matching the baked dims and asserts `displaySize == bakedSize` (regression guard).
4. Add a sanity assertion in `StitchExporter.buildPlan` (debug builds only) that `clip.naturalSize == trackNaturalSize` for `.still`-derived clips, so this drift never re-emerges silently.

**Acceptance:**
- Manual test (Section 7 below) passes.
- All existing 138/143 tests still pass.
- One new regression test passes.

---

## 7. Manual iPhone test plan

**Setup:** clean install, fresh project, no existing stitches.

### Test A — Portrait HEIC on auto canvas (the user's failing case)

1. Take a portrait photo on the iPhone (or pick any portrait HEIC from Photos).
2. Stitch tab → import that single photo.
3. Tap Export with default `.auto` aspect mode.
4. **Expected (post-fix):** the photo renders FULL-SIZE in portrait orientation. Output canvas is 1080×1920 (auto picks portrait because the photo's `displayOrientation` is now portrait). No bars, no inset.
5. **Bug repro (current):** photo renders as small landscape inset on a 1920×1080 canvas, surrounded by huge black bars.

### Test B — Portrait HEIC on landscape canvas (worst aspect mismatch)

1. Same photo as Test A.
2. Switch aspect mode to `.landscape` (16:9).
3. Export.
4. **Expected (post-fix):** photo renders as a 608×1080 portrait rectangle centred on a 1920×1080 canvas, with 656px black pillarbox bars on each side. The photo fills the full vertical extent.
5. **Bug repro (current):** photo renders as a tiny ~514×686 patch off-centre on the 1920×1080 canvas.

### Test C — Small no-EXIF PNG (regression check — should already work)

1. Export an 800×600 PNG (e.g. a screenshot, then resize) into a stable location.
2. Drag-import into Stitch (or save to Photos and pick).
3. Default `.auto` mode → canvas should auto-pick landscape (1920×1080).
4. **Expected (both pre and post fix):** photo renders as 1440×1080 centred, with 240px pillarbox bars. (Already correct today; verify the fix doesn't regress this.)

### Test D — 4K landscape JPEG

1. Pick a 4032×3024 landscape JPEG (no EXIF rotation).
2. Default `.auto` mode.
3. **Expected (post-fix):** baked to 1920×1440, displayed as 1440×1080 landscape with 0px top/bottom (canvas 1920×1080) — wait, 1920/1440=1.333, 1080/1440=0.75 → scale 0.75 → 1440×1080. Hmm — actually 1920×1080 canvas, source baked at 1920×1440: scale = min(1920/1920, 1080/1440) = min(1, 0.75) = 0.75 → 1440×1080 centred with 240px pillarbox. Looks "almost full."
4. Verify: photo fills near-edge-to-edge horizontally, small horizontal bars only.

### Test E — Mixed (1 photo + 1 portrait video)

1. Add a portrait HEIC + a portrait iPhone video.
2. `.auto` should pick portrait canvas (1080×1920).
3. Export.
4. **Expected (post-fix):** both clips fill the canvas vertically; photo has thin pillarbox if its aspect doesn't exactly match 9:16, video fills exactly.
5. **Bug repro (current):** photo renders as tiny inset, video renders correctly — the visual mismatch is the giveaway.

### Pass criteria

All five tests render the photo at "near-canvas" scale with at most thin letterbox/pillarbox bars on the mismatched axis. No huge black margins. No cropping of photo content.

---

## Cross-references

- `RED-TEAM-HOTFIX-2.md` finding M1 (lines 36-37) — **identified this exact issue and shipped anyway**. This diagnosis upgrades it from "known issue" to "user-reported correctness bug" with a concrete fix.
- `AUDIT-06-codecs.md` C2 (lines 69-105) — wipe transition has a related but distinct bug (crop ramp interacts with aspect-fit). Not in scope here.
- `AUDIT-07-edge-cases.md` M3 — orientation tie-breaking (landscape wins ties). Adjacent but unrelated; once H1 is fixed, the auto canvas will pick the right orientation for HEIC stills because `displayOrientation` will read the post-bake (oriented) dimensions.
- `docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md` — natural absorption point if Cluster 1 hasn't shipped.
- `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` — the constant-time bake refactor referenced by Cluster 1; orthogonal to this fix and rebases cleanly on top.
