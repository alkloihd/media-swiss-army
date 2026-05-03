# Cluster 0 — Hotfixes (compression -11841 + photo scale-fit)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. All steps use checkbox (`- [ ]`) syntax for tracking.
>
> **THIS CLUSTER LANDS FIRST** — before Cluster 1, before Cluster 2, before any other Phase 1+ work. Compression is broken on real iPhones for **3 of 4 presets** (`Max`, `Balanced`, `Streaming` all error with `AVFoundationErrorDomain -11841`); only `Small` succeeds. The photo bug renders stitched photos as tiny black-bordered insets. Both are launch-blockers and both share a small enough fix surface to ship as one PR.

---

## Goal

Restore compression on the three failing presets and make stitched photos render at full canvas scale, with the same single PR. The user's verbatim real-device report:

> "compression failed: the operation couldn't be completed (AVFoundationErrorDomain error -11841)"
> "it seems to only work with small compression but max quality and balanced and web seem to not work from what i see"
> "one image did not stretch to fit and was way too small which was annoying — i thought photos would auto fit into the frame or something regardless of size or aspect ratio"

The diagnoses behind the fix scope live at:

- `docs/superpowers/plans/2026-05-04-DIAG-compression-presets.md` — `-11841` root-cause analysis (encoder envelope rejection on Max preset's uncapped source-bitrate pass-through).
- `docs/superpowers/plans/2026-05-04-DIAG-photo-scale-fit.md` — post-bake `StitchClip` carries pre-orientation `naturalSize` while the baked `.mov` lives at EXIF-oriented + thumbnail-capped dimensions, so `makeAspectFitLayer` computes scale against the wrong rect.

This cluster ships ~80 LOC of code + 5–6 regression tests + 6 commits. Defense-in-depth retry-with-downshift catches edge cases the diagnostic hypotheses might have missed.

---

## Branch

**`feat/codex-cluster0-hotfixes`** off `feat/phase-2-features-may3` (already checked out at session start). Codex creates the branch, lands the work, opens a PR back to the same parent. Once merged, Cluster 1 rebases off the post-merge head.

---

## Tech Stack

- Swift 5.9 / iOS 17+
- AVFoundation: `AVAssetWriter`, `AVAssetWriterInput`, `AVVideoColorPropertiesKey`, `AVVideoExpectedSourceFrameRateKey`, `AVVideoMaxKeyFrameIntervalKey`
- VideoToolbox: profile/level keys (`kVTProfileLevel_HEVC_Main_AutoLevel`)
- XCTest + `mcp__xcodebuildmcp__test_sim`
- No new dependencies. No `AVVideoCompositing`. No CoreHaptics.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Services/StillVideoBaker.swift` | Modify | Change `bake(still:duration:)` return from `URL` to `(url: URL, size: CGSize)`. The CGSize is the post-orientation, post-cap dimensions already computed at lines 66–67. |
| `VideoCompressor/ios/Services/StitchExporter.swift` | Modify | Capture the new `(url, size)` tuple from `baker.bake(...)` and write `bakeResult.size` into the post-bake `StitchClip.naturalSize` instead of the stale `clip.naturalSize`. |
| `VideoCompressor/ios/Models/CompressionSettings.swift` | Modify | Cap `Max` preset bitrate at `min(safeSource × 0.9, 50 Mbps)` and the probe-failure fallback at 30 Mbps (down from 20 Mbps + uncapped pass-through). |
| `VideoCompressor/ios/Services/CompressionService.swift` | Modify | (a) Inject SDR `AVVideoColorPropertiesKey` (BT.709 / 709-transfer / 709-matrix). (b) Clamp `AVVideoExpectedSourceFrameRateKey` to ≤120 and `AVVideoMaxKeyFrameIntervalKey` to ≤60. (c) Wrap `compress(input:settings:onProgress:)` in a one-shot retry-with-downshift on `-11841`. |
| `VideoCompressor/VideoCompressorTests/StitchAspectRatioTests.swift` | Modify | Add regression test: a baked-still `StitchClip` whose `naturalSize` matches the actually-baked `.mov`'s `naturalSize` produces a near-full-canvas render rect (no tiny inset). |
| `VideoCompressor/VideoCompressorTests/CompressionSettingsTests.swift` | Modify | Add regression test: `Max.bitrate(forSourceBitrate:)` never exceeds source bitrate (was `Int64.max → safeSource`; now must enforce 90% cap and 50 Mbps absolute ceiling). |
| `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift` | Modify | Add tests for: (a) the SDR color-properties helper output shape, (b) `clamp(frameRate:)` and `clamp(gop:)` helpers, (c) the downshift table that maps `Max → Balanced → Small`. |

---

## Tasks

### Task 1 — Change `StillVideoBaker.bake` return to `(URL, CGSize)`

**Why first:** Every later step in the photo-scale fix depends on this signature change. Tests are written first; the implementation flips the return type; the call site (Task 2) consumes the new shape. Coordination note for **Cluster 1 (cache + still-bake-O(1))** — its plan currently expects `bake(still:)` to return `URL`. After this hotfix lands, Cluster 1's refactor must preserve the `(URL, CGSize)` return signature instead. Document in the Cluster 1 PR notes.

**Files:**
- Modify: `VideoCompressor/ios/Services/StillVideoBaker.swift` (lines 39 and 224)
- Modify: `VideoCompressor/VideoCompressorTests/StitchAspectRatioTests.swift` (append regression test)

- [ ] **Step 1: Write the regression test that pins post-bake `naturalSize` correctness**

In `VideoCompressor/VideoCompressorTests/StitchAspectRatioTests.swift`, append a new test method. The test bakes a 4-pixel green PNG fixture, then asserts that the baker's returned size matches the baked asset's `naturalSize` loaded via `AVURLAsset`.

```swift

    /// Cluster 0 hotfix: StillVideoBaker.bake must return the actual baked
    /// dimensions so StitchExporter.buildPlan can write the correct
    /// naturalSize into the post-bake StitchClip. Without this, the photo
    /// renders as a tiny inset on the canvas (DIAG-photo-scale-fit.md H1).
    func testBakeReturnsActualBakedSize() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hotfix-baker-fixture-\(UUID().uuidString.prefix(6)).png")
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw XCTSkip("PNG encoding unavailable on this platform.")
        }
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let baker = StillVideoBaker()
        let result = try await baker.bake(still: tmpURL, duration: 1.0)
        defer { try? FileManager.default.removeItem(at: result.url) }

        XCTAssertGreaterThan(result.size.width,  0, "Returned size width must be positive.")
        XCTAssertGreaterThan(result.size.height, 0, "Returned size height must be positive.")

        // Cross-check against the actual baked .mov.
        let asset = AVURLAsset(url: result.url)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let actual = try await track?.load(.naturalSize) ?? .zero
        XCTAssertEqual(result.size.width,  actual.width,  accuracy: 0.5,
            "Returned width must match baked asset's naturalSize.width.")
        XCTAssertEqual(result.size.height, actual.height, accuracy: 0.5,
            "Returned height must match baked asset's naturalSize.height.")
    }
```

- [ ] **Step 2: Run the test to confirm it fails (red)**

```
mcp__xcodebuildmcp__test_sim
```

Expected: **the build will fail (compile error in the new test)** — the test references `result.url` and `result.size`, but `bake(still:duration:)` currently returns `URL` not a tuple, so the compiler emits "value of type 'URL' has no member 'url'". **That's the TDD red for this task** — instead of a runtime test failure, the failing signal is a compile break in the freshly-added test. The implementation in Step 3 makes the test compile and pass simultaneously. (This phrasing differs from other plans that say "expect 1 test failure" because here the failing artefact is the build, not a test that ran-and-asserted-false.)

If Codex prefers a green-then-red approach, comment-out the new test temporarily, run `test_sim` to confirm baseline `Total: 138, Passed: 138, Failed: 0`, then re-enable it before Step 3.

- [ ] **Step 3: Change the `bake` signature and the single `return` statement**

In `VideoCompressor/ios/Services/StillVideoBaker.swift`, replace line 39:

```swift
    func bake(still sourceURL: URL, duration: Double) async throws -> URL {
```

With:

```swift
    /// Cleanly bake `still` to a temp .mov of `duration` seconds. Returns
    /// the .mov URL **and** the actual baked dimensions (post-EXIF-orientation,
    /// post-thumbnail-cap). Callers MUST use the returned size when writing
    /// the post-bake `StitchClip.naturalSize` — the source's pre-orientation
    /// `CGImageSourceCreateWithURL` size diverges from the baked .mov for
    /// any iPhone HEIC (orientation rotated) or any image > 1920 long edge
    /// (thumbnail capped). See `docs/superpowers/plans/2026-05-04-DIAG-photo-scale-fit.md`.
    func bake(still sourceURL: URL, duration: Double) async throws -> (url: URL, size: CGSize) {
```

Then locate line 224:

```swift
        return outURL
```

Replace with:

```swift
        // Width / height are the post-EXIF-orientation, post-thumbnail-cap
        // dimensions computed at the top of bake (lines 66–67). They are the
        // exact dimensions of the .mov on disk — exactly what
        // AVURLAsset(url: outURL).loadTracks(.video).first.naturalSize
        // returns. Returning them here lets StitchExporter set the
        // StitchClip.naturalSize correctly without an extra asset load.
        return (url: outURL, size: CGSize(width: width, height: height))
```

- [ ] **Step 4: Re-run the test, confirm it passes (green)**

```
mcp__xcodebuildmcp__test_sim
```

Expected:

```
Test Counts:
  Total: 139
  Passed: 139
  Failed: 0
```

(138 baseline + 1 new). At this point the **call site in `StitchExporter.swift:98–101` still passes `clamped` and assigns the result to a `URL` variable, so the build is broken on that file.** That is intentional — Task 2 fixes it immediately. If atomic commits are preferred, squash Tasks 1–2 into one commit; the bite-sized split is offered for clarity.

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Services/StillVideoBaker.swift \
        VideoCompressor/VideoCompressorTests/StitchAspectRatioTests.swift
git commit -m "feat(baker): return (URL, CGSize) so callers can use baked dimensions

The pre-bake StitchClip.naturalSize comes from CGImageSourceCreateWithURL
which is pre-EXIF-orientation and uncapped, while the baked .mov lives
at EXIF-oriented + thumbnail-capped dimensions. Without the size
returned, StitchExporter.buildPlan wrote the stale natural size into
the post-bake StitchClip and makeAspectFitLayer scaled against the
wrong rect — yielding the tiny-inset render the user reported.

This commit BREAKS StitchExporter.swift line 98 (it still treats the
return as a bare URL). Task 2 (next commit) fixes the call site.

Reference: docs/superpowers/plans/2026-05-04-DIAG-photo-scale-fit.md H1
Coordination: Cluster 1's still-bake-O(1) refactor must preserve this
(URL, CGSize) return signature. Update Cluster 1 plan accordingly."
```

**Effort: ~20 min. 1 commit.**

---

### Task 2 — Update `StitchExporter.buildPlan` to use the new size

**Why:** Task 1 left `StitchExporter.swift:98–117` broken because the bake now returns a tuple. This task fixes the call site and writes the **actual** baked size into the post-bake clip.

**Files:**
- Modify: `VideoCompressor/ios/Services/StitchExporter.swift` (lines 98–117)

- [ ] **Step 1: Update the bake call site to consume the tuple**

Find the bake region in `VideoCompressor/ios/Services/StitchExporter.swift` (lines 95–120 inside `buildPlan`):

```swift
            if clip.kind == .still {
                let stillDuration = clip.edits.stillDuration ?? 3.0
                let clamped = min(10.0, max(1.0, stillDuration))
                let bakedURL = try await baker.bake(
                    still: clip.sourceURL,
                    duration: clamped
                )
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
                    originalAssetID: clip.originalAssetID,
                    creationDate: clip.creationDate,
                    edits: bakedEdits
                )
                bakedClips.append(baked)
                stillsBaked += 1
                await onPrepareProgress(stillsBaked, totalStills)
            } else {
                bakedClips.append(clip)
            }
```

Replace with:

```swift
            if clip.kind == .still {
                let stillDuration = clip.edits.stillDuration ?? 3.0
                let clamped = min(10.0, max(1.0, stillDuration))
                // Cluster 0 hotfix (DIAG-photo-scale-fit.md H1): bake now
                // returns the actual baked .mov's dimensions. We MUST write
                // bakeResult.size — not clip.naturalSize — into the post-bake
                // StitchClip, because the pre-bake naturalSize is the
                // pre-orientation CGImage pixel size and diverges from the
                // baked .mov for any iPhone HEIC (rotated) or image > 1920
                // long edge (thumbnail-capped).
                let bakeResult = try await baker.bake(
                    still: clip.sourceURL,
                    duration: clamped
                )
                bakedStillURLs.append(bakeResult.url)
                var bakedEdits = clip.edits
                bakedEdits.trimStartSeconds = 0
                bakedEdits.trimEndSeconds = clamped
                let baked = StitchClip(
                    id: clip.id,
                    sourceURL: bakeResult.url,
                    displayName: clip.displayName,
                    naturalDuration: CMTime(seconds: clamped, preferredTimescale: 600),
                    naturalSize: bakeResult.size,    // ← USE BAKED DIMENSIONS
                    kind: .video,
                    preferredTransform: .identity,   // baker already oriented
                    originalAssetID: clip.originalAssetID,
                    creationDate: clip.creationDate,
                    edits: bakedEdits
                )
                bakedClips.append(baked)
                stillsBaked += 1
                await onPrepareProgress(stillsBaked, totalStills)
            } else {
                bakedClips.append(clip)
            }
```

- [ ] **Step 2: Run tests; expect `Total: 139, Passed: 139`**

```
mcp__xcodebuildmcp__test_sim
```

Expected:

```
Test Counts:
  Total: 139
  Passed: 139
  Failed: 0
```

If a previously-green test in `StitchAspectRatioTests` flips red because it relied on the OLD stale-naturalSize behaviour, **that's a real bug the old tests were silently encoding** — read the failing assertion, confirm the new behaviour is the correct intent, and update the test to match. Note the change in your commit message.

- [ ] **Step 3: Commit**

```bash
git add VideoCompressor/ios/Services/StitchExporter.swift
git commit -m "fix(stitch): use baked-mov dimensions for post-bake StitchClip naturalSize

Resolves DIAG-photo-scale-fit.md H1 — the stale naturalSize swap was
flagged by RED-TEAM-HOTFIX-2 M1 and deferred 'as a known issue'. User
confirmed this is the bug behind the tiny-inset photo render.

Now the post-bake clip's naturalSize matches the baked .mov, so
makeAspectFitLayer (StitchExporter.swift:720-733) computes the correct
scale (no more 0.357× shrink against a stale 4032×3024) and the photo
renders pillarboxed at full canvas height.

139/139 tests passing."
```

**Effort: ~10 min. 1 commit.**

---

### Task 3 — Cap `Max` preset bitrate to ≤ source bitrate (and a hard 50 Mbps ceiling)

**Why:** Per `DIAG-compression-presets.md` §4 + Hypothesis #1, `Max` preset (`(.source, .lossless)`) currently returns the source bitrate verbatim and falls back to 20 Mbps when the probe fails. For 4K HDR HEVC iPhone capture (typically 50–100 Mbps; Apple ProRes class 200+ Mbps), this exceeds the on-device VideoToolbox HEVC encoder's level envelope on non-Pro phones and `writer.finishWriting()` rejects with `-11841`. AUDIT-06 H4 already filed this as a quality bug; the field report grades it as a functional regression.

**Files:**
- Modify: `VideoCompressor/ios/Models/CompressionSettings.swift` (lines 128–131 and 152)
- Modify: `VideoCompressor/VideoCompressorTests/CompressionSettingsTests.swift` (add cap test)

- [ ] **Step 1: Write the bitrate-cap regression test (red)**

In `VideoCompressor/VideoCompressorTests/CompressionSettingsTests.swift`, append:

```swift

    /// Cluster 0 hotfix (DIAG-compression-presets.md Hypothesis #1).
    /// Max preset must NEVER exceed source × 0.9 OR 50 Mbps, whichever
    /// is smaller. Pre-fix it returned the source bitrate verbatim,
    /// which exceeded VideoToolbox HW encoder envelope on 4K HDR HEVC
    /// iPhone captures (50–100 Mbps source) and surfaced -11841 from
    /// writer.finishWriting().
    func testMaxPresetBitrateRespectsSourceCap() {
        // 100 Mbps source → cap at 50 Mbps absolute ceiling.
        let high = CompressionSettings.max.bitrate(forSourceBitrate: 100_000_000)
        XCTAssertLessThanOrEqual(high, 50_000_000,
            "Max preset must cap at 50 Mbps for high-bitrate sources; got \(high) bps.")

        // 30 Mbps source → cap at source × 0.9 = 27 Mbps (below 50 Mbps absolute).
        let mid = CompressionSettings.max.bitrate(forSourceBitrate: 30_000_000)
        XCTAssertLessThanOrEqual(mid, 27_000_000 + 100,
            "Max preset must cap at source×0.9 when below absolute ceiling; got \(mid) bps.")
        XCTAssertLessThanOrEqual(mid, 30_000_000,
            "Max preset must NEVER exceed source bitrate; got \(mid) bps.")

        // Probe failure (sourceBitrate == 0) → fallback ≤ 30 Mbps (was 20 Mbps).
        let unknown = CompressionSettings.max.bitrate(forSourceBitrate: 0)
        XCTAssertLessThanOrEqual(unknown, 30_000_000,
            "Max preset probe-failure fallback must be ≤ 30 Mbps; got \(unknown) bps.")
    }

    func testMaxPresetBitrateNeverExceedsSource() {
        // Property test across realistic source bitrates.
        for src: Int64 in [1_000_000, 5_000_000, 10_000_000,
                            25_000_000, 60_000_000, 200_000_000] {
            let result = CompressionSettings.max.bitrate(forSourceBitrate: src)
            XCTAssertLessThanOrEqual(result, src,
                "Max bitrate (\(result)) must never exceed source (\(src)).")
            XCTAssertLessThanOrEqual(result, 50_000_000,
                "Max bitrate (\(result)) must not exceed absolute 50 Mbps ceiling.")
        }
    }
```

Run:

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 141, Passed: 139, Failed: 2` (139 baseline + 2 new failing). The two new tests fail because today's `Max` returns `safeSource` (uncapped) and 20_000_000 fallback. That's the TDD red.

- [ ] **Step 2: Apply the cap in `CompressionSettings.bitrate(forSourceBitrate:)`**

Find the `case (.source, .lossless):` block in `VideoCompressor/ios/Models/CompressionSettings.swift` (lines 128–131):

```swift
        case (.source, .lossless):  // Max
            targetBitrate = Int64.max
            sourceCapRatio = 1.0
            floor = 0
```

Replace with:

```swift
        case (.source, .lossless):  // Max
            // Cluster 0 hotfix (DIAG-compression-presets.md Hypothesis #1 +
            // AUDIT-06 H4): cap at 50 Mbps absolute ceiling AND at source ×
            // 0.9 — passing the source bitrate through verbatim exceeded
            // VideoToolbox HW encoder envelope on 4K HDR HEVC iPhone
            // captures (50–100 Mbps source) and surfaced AVError -11841
            // from writer.finishWriting(). Picking the smaller of the two
            // gives a hardware-safe ceiling that still preserves visual
            // quality (90% of source on a high-bitrate H.265 source is
            // visually indistinguishable from passthrough).
            targetBitrate = 50_000_000
            sourceCapRatio = 0.9
            floor = 0
```

Then replace the smart-cap return at `CompressionSettings.swift` lines 161–162 with an explicit Max-fallback guard. This is the simplest defensible structure: keep the existing `cappedSource` / `smart` math, but add an explicit branch that picks a sensible probe-failure floor for Max instead of relying on the now-unreachable `Int64.max` dead block.

Find the smart-cap return at lines 161–162:

```swift
        let smart = min(targetBitrate, cappedSource)
        return Swift.max(floor, smart)
```

Replace with:

```swift
        let smart = min(targetBitrate, cappedSource)
        let result = Swift.max(floor, smart)

        // Cluster 0 hotfix: probe failure on Max (no source bitrate) used
        // to fall back to 20 Mbps via an Int64.max branch above (now removed
        // because targetBitrate is 50 Mbps, never Int64.max). Keep that
        // floor at 30 Mbps for Max specifically — high enough for 4K HEVC
        // quality, low enough to stay inside HW envelope.
        if resolution == .source && quality == .lossless && safeSource == Int64.max {
            return 30_000_000
        }
        return result
```

The pre-existing probe-failure block at lines 150–153 (`if targetBitrate == Int64.max { return safeSource == Int64.max ? 20_000_000 : safeSource }`) is now unreachable because `targetBitrate` for Max is `50_000_000`, not `Int64.max`. Leave it untouched — Swift's dead-code analysis ignores it and removing it would broaden the diff. The explicit Max guard above is the single canonical fallback path.

- [ ] **Step 3: Re-run tests, confirm green**

```
mcp__xcodebuildmcp__test_sim
```

Expected:

```
Test Counts:
  Total: 141
  Passed: 141
  Failed: 0
```

(139 baseline-after-Task-2 + 2 new). The Max bitrate-cap tests now pass.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Models/CompressionSettings.swift \
        VideoCompressor/VideoCompressorTests/CompressionSettingsTests.swift
git commit -m "fix(compress): cap Max preset bitrate at min(source × 0.9, 50 Mbps)

Resolves DIAG-compression-presets.md Hypothesis #1 + AUDIT-06 H4.
Max preset previously returned source bitrate verbatim, which exceeded
VideoToolbox HW encoder envelope on 4K HDR HEVC iPhone captures
(50–100 Mbps source bitrate). writer.finishWriting() rejected with
AVError -11841 ('invalid video composition' — empirically VT's catch-all
for envelope rejection).

Cap is min(source × 0.9, 50 Mbps absolute ceiling). Probe failure
falls back to 30 Mbps (was 20 Mbps; 30 Mbps fits 4K HEVC at acceptable
visual quality without trip-wiring the encoder).

141/141 tests passing."
```

**Effort: ~30 min. 1 commit.**

---

### Task 4 — Add SDR `AVVideoColorPropertiesKey` defensive defaults

**Why:** Per `DIAG-compression-presets.md` Hypothesis #2 + AUDIT-06 H1, the encoder receives 8-bit 4:2:0 frames from the reader (`CompressionService.swift:254–256`) but the writer never sets `AVVideoColorPropertiesKey`. On HDR sources, the source's tagged BT.2020 / PQ / HLG colorimetry disagrees with the reader's actual 8-bit Rec.709 output and the writer's encoder validator may reject the configuration with `-11841`. Full HDR passthrough is **out of scope** for this hotfix (it's owned by Cluster 2 / TASK-39); this task ships the SDR-only safety net that suppresses the colour-mismatch validation rejection on the common case.

**Files:**
- Modify: `VideoCompressor/ios/Services/CompressionService.swift` (extend `compressionProps` at lines 178–184)
- Modify: `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift` (helper test)

- [ ] **Step 1: Write the helper test (red)**

In `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift`, append:

```swift

    /// Cluster 0 hotfix (DIAG-compression-presets.md Hypothesis #2 +
    /// AUDIT-06 H1): the writer must declare its output colorimetry
    /// (BT.709 / 709 transfer / 709 matrix for SDR) so the encoder
    /// validator doesn't reject the configuration on HDR sources where
    /// reader 8-bit output disagrees with source colorimetry tags.
    /// Full HDR passthrough is Cluster 2 scope; this is the SDR safety net.
    func testSDRColorPropertiesShape() {
        let props = CompressionService.sdrColorProperties()
        XCTAssertEqual(props[AVVideoColorPrimariesKey] as? String,
                       AVVideoColorPrimaries_ITU_R_709_2)
        XCTAssertEqual(props[AVVideoTransferFunctionKey] as? String,
                       AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(props[AVVideoYCbCrMatrixKey] as? String,
                       AVVideoYCbCrMatrix_ITU_R_709_2)
    }
```

Run:

```
mcp__xcodebuildmcp__test_sim
```

Expected: **the build will fail (compile error in the new test)** because `CompressionService.sdrColorProperties()` doesn't exist yet. That's the TDD red — Step 2's implementation adds the helper and the test compiles + passes simultaneously.

- [ ] **Step 2: Add the helper to `CompressionService` and inject it into `videoOutputSettings`**

In `VideoCompressor/ios/Services/CompressionService.swift`, add a static helper above the `enum CompressionError` declaration (around line 537, just before `enum CompressionError`):

```swift
    /// Cluster 0 hotfix: SDR (BT.709) color properties dict applied to the
    /// writer's videoOutputSettings. Without `AVVideoColorPropertiesKey`,
    /// the encoder's color-mismatch validator can reject HDR sources whose
    /// tagged BT.2020 / HLG colorimetry disagrees with the reader's 8-bit
    /// Rec.709 output — surfaced empirically as AVError -11841 from
    /// writer.finishWriting(). Full HDR passthrough is Cluster 2 scope.
    /// Exposed as `static` for testability.
    static func sdrColorProperties() -> [String: Any] {
        return [
            AVVideoColorPrimariesKey:    AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey:  AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey:       AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
    }
```

Then inject it at the videoOutputSettings construction (line 192, where the dict is built):

Find:

```swift
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec.rawValue,
            AVVideoWidthKey: NSNumber(value: targetWidth),
            AVVideoHeightKey: NSNumber(value: targetHeight),
            AVVideoCompressionPropertiesKey: compressionProps,
        ]
```

Replace with:

```swift
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec.rawValue,
            AVVideoWidthKey: NSNumber(value: targetWidth),
            AVVideoHeightKey: NSNumber(value: targetHeight),
            AVVideoCompressionPropertiesKey: compressionProps,
            // Cluster 0 hotfix (DIAG Hypothesis #2 / AUDIT-06 H1):
            // declare SDR BT.709 output colorimetry so the encoder
            // validator never trips on HDR-source vs 8-bit-reader
            // colorimetry disagreement. Full HDR passthrough is
            // Cluster 2 scope; this is the SDR safety net.
            AVVideoColorPropertiesKey: Self.sdrColorProperties(),
        ]
```

- [ ] **Step 3: Run tests, confirm green**

```
mcp__xcodebuildmcp__test_sim
```

Expected:

```
Test Counts:
  Total: 142
  Passed: 142
  Failed: 0
```

(141 baseline-after-Task-3 + 1 new).

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Services/CompressionService.swift \
        VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift
git commit -m "fix(compress): declare SDR BT.709 color properties on writer (defensive)

Resolves DIAG-compression-presets.md Hypothesis #2 (overlap with
AUDIT-06 H1). Without AVVideoColorPropertiesKey, the encoder's
color-mismatch validator can reject HDR sources whose tagged BT.2020 /
HLG colorimetry disagrees with the reader's 8-bit Rec.709 output —
surfaced as AVError -11841 from writer.finishWriting().

This commit ships the SDR-only safety net (BT.709 / 709 transfer /
709 matrix). Full HDR detection + Main10 profile + 10-bit pixel
format is Cluster 2's TASK-39 scope.

142/142 tests passing."
```

**Effort: ~25 min. 1 commit.**

---

### Task 5 — Clamp `AVVideoExpectedSourceFrameRateKey` (≤120) and `AVVideoMaxKeyFrameIntervalKey` (≤60)

**Why:** Per `DIAG-compression-presets.md` Hypothesis #3, slow-mo iPhone captures (120/240 fps) propagate `nominalFrameRate = 240` into both `AVVideoExpectedSourceFrameRateKey` and the GOP key (`gop = frameRate × 2 = 480`). Combined with the Streaming preset's H.264 High AutoLevel, the encoder's macroblock-rate budget at Level 5.2 is exceeded and the encoder rejects the configuration. Even on Max/Balanced where this hypothesis is less likely the primary cause, the clamps cost nothing and remove a known footgun.

**Files:**
- Modify: `VideoCompressor/ios/Services/CompressionService.swift` (lines 168–169 and the `compressionProps` dict at 180–181)
- Modify: `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift` (add clamp tests)

- [ ] **Step 1: Write helper-shape tests (red)**

In `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift`, append:

```swift

    /// Cluster 0 hotfix (DIAG-compression-presets.md Hypothesis #3): clamp
    /// the source-frame-rate hint to ≤ 120 fps and the GOP to ≤ 60 frames
    /// so slow-mo iPhone captures (240 fps nominal) don't push the encoder
    /// past its level-budget envelope.
    func testFrameRateClampedToMax120() {
        XCTAssertEqual(CompressionService.clamp(frameRate: 30),  30)
        XCTAssertEqual(CompressionService.clamp(frameRate: 60),  60)
        XCTAssertEqual(CompressionService.clamp(frameRate: 120), 120)
        XCTAssertEqual(CompressionService.clamp(frameRate: 240), 120,
            "240 fps slow-mo must clamp to 120.")
        XCTAssertEqual(CompressionService.clamp(frameRate: 0), 30,
            "Zero/missing nominalFrameRate must default to 30.")
    }

    func testGopClampedToMax60() {
        XCTAssertEqual(CompressionService.clamp(gop: 60),  60)
        XCTAssertEqual(CompressionService.clamp(gop: 240), 60,
            "Slow-mo GOP (240) must clamp to 60.")
        XCTAssertEqual(CompressionService.clamp(gop: 1), 2,
            "GOP must be at least 2.")
    }
```

Run: `mcp__xcodebuildmcp__test_sim` — **the build will fail (compile error in the new tests)** because `CompressionService.clamp(frameRate:)` and `CompressionService.clamp(gop:)` don't exist yet. That's the TDD red; Step 2's helpers make the tests compile + pass.

- [ ] **Step 2: Add the helpers and use them in `encode`**

In `VideoCompressor/ios/Services/CompressionService.swift`, append helpers above the `enum CompressionError` declaration (just below the `sdrColorProperties()` helper from Task 4):

```swift
    /// Cluster 0 hotfix: clamp source frame rate hint to a value the
    /// encoder's level envelope can actually accommodate. Slow-mo iPhone
    /// captures (120/240 fps `nominalFrameRate`) cause the encoder to
    /// budget for a macroblock rate beyond H.264 High Level 5.2 / HEVC
    /// Main Level 5.1. Encoded clips still PLAY at the slow-mo rate
    /// downstream — this only affects the encoder's expectations.
    static func clamp(frameRate: Float) -> Float {
        guard frameRate > 0 else { return 30 }
        return min(frameRate, 120)
    }

    /// GOP clamp: at most one keyframe every 60 frames (~2 s at 30 fps,
    /// ~1 s at 60 fps, ~0.5 s at 120 fps). Pre-fix `gop = frameRate × 2 =
    /// 480` for 240 fps slow-mo exceeded level macroblock budgets.
    static func clamp(gop: Int) -> Int {
        return Swift.max(2, Swift.min(gop, 60))
    }
```

Then update the encode site at lines 168–169:

```swift
        // Video output settings dict.
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30
        let gop = Int(frameRate.rounded()) * 2  // 2-second GOP
```

Replace with:

```swift
        // Video output settings dict.
        // Cluster 0 hotfix (DIAG Hypothesis #3): clamp slow-mo source frame
        // rates and GOP. Slow-mo iPhone clips report nominalFrameRate=240
        // and propagating that into the encoder's level budget exceeded
        // H.264 High Level 5.2 / HEVC Main Level 5.1 macroblock rates.
        let frameRate = Self.clamp(frameRate: nominalFrameRate)
        let gop = Self.clamp(gop: Int(frameRate.rounded()) * 2)
```

The `compressionProps` dict at lines 178–184 already reads `frameRate` and `gop`, so no change is needed there — they pick up the clamped values automatically.

- [ ] **Step 3: Run tests; confirm green**

```
mcp__xcodebuildmcp__test_sim
```

Expected:

```
Test Counts:
  Total: 144
  Passed: 144
  Failed: 0
```

(142 baseline-after-Task-4 + 2 new).

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Services/CompressionService.swift \
        VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift
git commit -m "fix(compress): clamp frame rate (≤120) + GOP (≤60) for slow-mo sources

Resolves DIAG-compression-presets.md Hypothesis #3. Slow-mo iPhone
captures (120/240 fps nominalFrameRate) propagated through to the
encoder's AVVideoExpectedSourceFrameRateKey and gop = frameRate * 2
budget (480 frames for 240 fps), exceeding H.264 High Level 5.2 and
HEVC Main Level 5.1 macroblock-rate envelopes. Surfaced as -11841.

Slow-mo clips still PLAY at the source frame rate downstream; this
only changes the encoder's level-budget hints.

144/144 tests passing."
```

**Effort: ~25 min. 1 commit.**

---

### Task 6 — Add `-11841` retry-with-downshift to `CompressionService.compress`

**Why:** Tasks 3–5 cover the three diagnostic hypotheses. This task is **defense-in-depth**: even if all three hypotheses miss an edge case (e.g. an unanticipated source-format combination on a non-Pro phone), the encoder's `-11841` rejection no longer surfaces as a raw `[AVFoundationErrorDomain -11841]` dialog. Instead, we automatically retry once with the next-lower preset and surface a friendly toast.

**Downshift table** (mirrors `CompressionSettings.phase1Presets` ordering):

| Source preset | Retry preset | Friendly message |
|---|---|---|
| `Max` (`.source` × `.lossless`) | `Balanced` (`.fhd1080` × `.high`) | "Max Quality was rejected by the encoder for this source. Falling back to Balanced." |
| `Balanced` (`.fhd1080` × `.high`) | `Small` (`.hd720` × `.balanced`) | "Balanced was rejected by the encoder for this source. Falling back to Small." |
| `Streaming` (`.sd540` × `.balanced`) | `Small` (`.hd720` × `.balanced`) | "Streaming was rejected by the encoder for this source. Falling back to Small." |
| `Small` (`.hd720` × `.balanced`) | (no retry — already the safest) | The original `-11841` error surfaces unchanged (no retry attempted). |

**Files:**
- Modify: `VideoCompressor/ios/Services/CompressionService.swift` (wrap `compress(input:settings:onProgress:)` and add the downshift table helper)
- Modify: `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift` (downshift table test)

- [ ] **Step 1: Write the downshift-table test (red)**

In `VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift`, append:

```swift

    /// Cluster 0 hotfix: defensive retry-with-downshift when -11841 fires.
    /// Pre-fix the user got [AVFoundationErrorDomain -11841] verbatim;
    /// post-fix we automatically downshift one preset and surface a
    /// friendly toast.
    func testDownshiftTableMaxToBalanced() {
        let next = CompressionService.downshift(from: .max)
        XCTAssertEqual(next?.id, CompressionSettings.balanced.id,
            "Max must downshift to Balanced.")
    }

    func testDownshiftTableBalancedToSmall() {
        let next = CompressionService.downshift(from: .balanced)
        XCTAssertEqual(next?.id, CompressionSettings.small.id,
            "Balanced must downshift to Small.")
    }

    func testDownshiftTableStreamingToSmall() {
        let next = CompressionService.downshift(from: .streaming)
        XCTAssertEqual(next?.id, CompressionSettings.small.id,
            "Streaming must downshift to Small.")
    }

    func testDownshiftTableSmallReturnsNil() {
        XCTAssertNil(CompressionService.downshift(from: .small),
            "Small is the safest preset and has no further fallback.")
    }
```

Run: `mcp__xcodebuildmcp__test_sim` — **the build will fail (compile error in the new tests)** because `CompressionService.downshift(from:)` doesn't exist yet. That's the TDD red; Step 2's helper makes the tests compile + pass.

- [ ] **Step 2: Add the downshift helper + a friendly-message helper**

In `VideoCompressor/ios/Services/CompressionService.swift`, append above the `enum CompressionError` declaration:

```swift
    /// Cluster 0 hotfix: defensive retry table for `-11841`. Returns the
    /// next-safer preset, or nil if the input is already the safest. We
    /// only downshift ONCE; if the retry also fails, the user sees the
    /// original error.
    static func downshift(from settings: CompressionSettings) -> CompressionSettings? {
        switch (settings.resolution, settings.quality) {
        case (.source,  .lossless):  return .balanced   // Max → Balanced
        case (.fhd1080, .high):      return .small       // Balanced → Small
        case (.sd540,   .balanced):  return .small       // Streaming → Small
        case (.hd720,   .balanced):  return nil          // Small: no further downshift
        default:                     return nil
        }
    }

    /// Cluster 0 hotfix: friendly fallback message shown once the retry
    /// completes successfully. Surfaced via the standard onProgress /
    /// VideoLibrary error pipeline as a toast (consumer responsibility —
    /// this just produces the string).
    static func downshiftMessage(from: CompressionSettings,
                                  to: CompressionSettings) -> String {
        return "\(from.title) was rejected by the encoder for this source. " +
               "Falling back to \(to.title)."
    }
```

- [ ] **Step 3: Wrap `compress(input:settings:onProgress:)` with retry-on-`-11841`**

In `VideoCompressor/ios/Services/CompressionService.swift`, the `compress(input:settings:onProgress:)` method currently delegates straight to `encode(...)`. Wrap the delegation with a `do/catch` on `CompressionError.exportFailed` whose message contains `-11841`:

Find lines 59–83:

```swift
    func compress(
        input inputURL: URL,
        settings: CompressionSettings,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {

        let asset = AVURLAsset(url: inputURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])

        // Sanity check: must have a video track.
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw CompressionError.noVideoTrack
        }

        let outputURL = Self.outputURL(forInput: inputURL, settings: settings)
        return try await encode(
            asset: asset,
            videoComposition: nil,
            settings: settings,
            outputURL: outputURL,
            onProgress: onProgress
        )
    }
```

Replace with:

```swift
    func compress(
        input inputURL: URL,
        settings: CompressionSettings,
        onProgress: @MainActor @Sendable @escaping (BoundedProgress) -> Void
    ) async throws -> URL {

        let asset = AVURLAsset(url: inputURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])

        // Sanity check: must have a video track.
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw CompressionError.noVideoTrack
        }

        let outputURL = Self.outputURL(forInput: inputURL, settings: settings)
        do {
            return try await encode(
                asset: asset,
                videoComposition: nil,
                settings: settings,
                outputURL: outputURL,
                onProgress: onProgress
            )
        } catch let CompressionError.exportFailed(msg)
            where msg.contains("-11841"),
                let fallback = Self.downshift(from: settings)
        {
            // Cluster 0 hotfix: defensive retry-with-downshift. The encoder
            // surfaced AVError -11841 ('invalid video composition' — VT's
            // catch-all envelope rejection). Try once at the next-safer
            // preset and surface a friendly explanation.
            #if DEBUG
            print("[Cluster0] -11841 on \(settings.title); retrying at \(fallback.title)")
            #endif
            let fallbackOutputURL = Self.outputURL(forInput: inputURL, settings: fallback)
            // Build a fresh asset for the retry — the previous one may have
            // entered a `.failed` state in the reader's view of the world.
            let retryAsset = AVURLAsset(url: inputURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
            ])
            let url = try await encode(
                asset: retryAsset,
                videoComposition: nil,
                settings: fallback,
                outputURL: fallbackOutputURL,
                onProgress: onProgress
            )
            // Surface the friendly note via a final progress beat — the
            // VideoLibrary consumer reads `.complete` separately. Concrete
            // toast wiring is the consumer's responsibility; for now log
            // it so QA can see we hit the fallback.
            #if DEBUG
            print("[Cluster0] Downshifted: \(Self.downshiftMessage(from: settings, to: fallback))")
            #endif
            return url
        }
    }
```

(Keep the wider stitch path — `encode(asset:videoComposition:audioMix:settings:outputURL:onProgress:)` — untouched. The stitch flow has its own retry pattern owned by Cluster 2.)

**Double-failure attribution:** the retry's `encode(...)` call is NOT itself wrapped in another do/catch. On double-failure (the retry also throws `-11841`, or `Self.downshift(from:)` returns `nil` because the input was already `Small`), the retry's error (or the original if no downshift was attempted) surfaces unchanged. The user-facing copy (and any logs) will reflect the LAST preset attempted, not the originally-requested one — e.g. a Max-then-Balanced double failure surfaces as a Balanced-preset error, not a Max-preset error. This is acceptable for v1 because the retry is best-effort; if Codex wants tighter attribution later, wrap the retry in another do/catch and synthesize a composite "tried Max, tried Balanced, both failed" error.

- [ ] **Step 4: Run tests; confirm green**

```
mcp__xcodebuildmcp__test_sim
```

Expected:

```
Test Counts:
  Total: 148
  Passed: 148
  Failed: 0
```

(144 baseline-after-Task-5 + 4 new downshift table tests).

- [ ] **Step 5: Build the app for sim once to confirm no compile-time regressions**

```
mcp__xcodebuildmcp__build_sim
```

Expected:

```
✅ iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.
```

- [ ] **Step 6: Commit**

```bash
git add VideoCompressor/ios/Services/CompressionService.swift \
        VideoCompressor/VideoCompressorTests/CompressionServiceTests.swift
git commit -m "fix(compress): retry-with-downshift on AVError -11841 (defense-in-depth)

Even with Tasks 3-5 in place, an unanticipated source-format edge case
could still trip -11841. This wrap on compress(input:settings:onProgress:)
catches CompressionError.exportFailed messages that contain '-11841',
downshifts one preset (Max → Balanced → Small; Streaming → Small), and
retries once. The user sees the smaller-preset output instead of a raw
[AVFoundationErrorDomain -11841] dialog.

On double-failure (retry also fails, or downshift returns nil because
input was already Small), the LAST preset's error surfaces unchanged
— attribution reflects the retried preset, not the original. Composite
'tried Max, tried Balanced' wrapping is deferred to a future polish pass.

148/148 tests passing."
```

**Effort: ~45 min. 1 commit.**

---

### Task 7 — Push, PR, CI, merge → TestFlight cycle #0

- [ ] **Step 1: Final test pass**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 148, Passed: 148, Failed: 0`.

- [ ] **Step 2: Build sim**

```
mcp__xcodebuildmcp__build_sim
```

Expected: `✅ iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.`

- [ ] **Step 3: Push + PR**

```bash
git push -u origin feat/codex-cluster0-hotfixes
gh pr create --base feat/phase-2-features-may3 --head feat/codex-cluster0-hotfixes \
  --title "fix(hotfix): -11841 on 3 of 4 compress presets + photo scale-fit" \
  --body "$(cat <<'EOF'
## Summary

Cluster 0 hotfix — lands BEFORE clusters 1-5 because compression is
broken on real iPhones for 3 of 4 presets (Max, Balanced, Streaming
all fail with AVError -11841; only Small succeeds). Photos in stitch
also render as a tiny inset on canvas.

## Bugs fixed

1. **Compression -11841**
   - Cap Max preset bitrate at min(source × 0.9, 50 Mbps) — was uncapped.
   - Declare SDR BT.709 color properties on writer — defensive.
   - Clamp source frame rate (≤120 fps) and GOP (≤60 frames) — slow-mo safety.
   - Defense-in-depth: retry-with-downshift on -11841 (Max → Balanced
     → Small; Streaming → Small) with friendly DEBUG log message.

2. **Stitched photo renders as tiny inset**
   - StillVideoBaker.bake now returns (URL, CGSize); StitchExporter uses
     the actual baked-mov size for post-bake StitchClip.naturalSize
     (was the stale pre-orientation CGImage source size).

## Test plan

- [ ] All 4 compression presets succeed on a 4K HDR HEVC iPhone source.
- [ ] Stitching a portrait HEIC with a landscape iPhone video renders
      pillarboxed (NOT a tiny inset).
- [ ] -11841 retry surfaces a friendly fallback (DEBUG log; toast wiring
      is downstream).
- [ ] All 138 baseline tests still pass; 10 new regression tests pass.
- [ ] None of the 7 PR #9 audit-CRITICAL fixes regress.

## Coordination note for Cluster 1

Cluster 1 (cache + still-bake-O(1)) currently expects `bake(still:)`
to return `URL`. After this hotfix lands, Cluster 1's refactor must
preserve the `(URL, CGSize)` return signature instead. Update Cluster
1's plan accordingly before execution.

References:
- docs/superpowers/plans/2026-05-04-DIAG-compression-presets.md
- docs/superpowers/plans/2026-05-04-DIAG-photo-scale-fit.md

148/148 tests passing.

🤖 Generated with [Codex](https://openai.com/codex)
EOF
)"
```

- [ ] **Step 4: Watch CI, merge**

```bash
gh pr checks <num> --watch
gh pr merge <num> --merge
```

Expected: 4/4 CI checks pass (ESLint / Prettier / Security Audit / Syntax Check). Merge into `feat/phase-2-features-may3`.

- [ ] **Step 5: Append session log**

```bash
echo "[$(TZ='Asia/Kolkata' date '+%Y-%m-%d %H:%M IST')] [solo/codex] [FIX] Cluster 0 hotfix — -11841 + photo scale (PR #<num>)" \
  >> .agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md
```

**Effort: ~20 min. 0 new commits (PR + merge only).**

---

## Acceptance criteria

- [ ] All 4 compression presets (`Max`, `Balanced`, `Small`, `Streaming`) succeed on a 4K HDR HEVC iPhone source on a real iPhone.
- [ ] A 400×400 PNG (or any small image) stitched with a 1920×1080 video renders pillarboxed at full canvas height (NOT a small black-bordered inset).
- [ ] A portrait HEIC (e.g. 4032×3024 with EXIF orientation tag 6) stitched alone renders at the auto canvas as a near-full-frame portrait, not a tiny landscape inset.
- [ ] When `-11841` fires, the retry-with-downshift produces a smaller-preset output instead of surfacing the raw error string. (DEBUG log is acceptable; user-facing toast wiring is downstream.)
- [ ] On double-failure (retry also returns `-11841`, or input was already `Small` so no downshift exists), the LAST preset's error surfaces unchanged. Verify by forcing a contrived double failure on a debug build — error message should reference the retried preset (or the original if no retry was attempted), not a synthesized composite.
- [ ] All 138 baseline tests still pass; 10 new regression tests (1 baker, 2 cap, 1 color, 2 clamp, 4 downshift) pass for a total of 148.
- [ ] None of the 7 PR #9 audit-CRITICAL fixes regress: re-run cancellation-race tests (`CompressionServiceTests`), baker tests (`StillVideoBakerTests` if any pre-existed — current tree only has `StitchAspectRatioTests`), and stitch transitions tests.
- [ ] CI green on the PR (4/4 checks: ESLint / Prettier / Security Audit / Syntax Check).

---

## Manual iPhone test prompts (tethered, post-merge)

The lead's standing protocol (HANDOFF-TO-CLAUDE-TERMINAL.md) is "visually walk the app before declaring anything done." Run these against a tethered iPhone via `mcp__xcodebuildmcp__build_run_device`:

1. **Compress a 4K iPhone HEVC video at Max preset** → must succeed (was failing with `-11841`). Verify output size is a sensible fraction of source.
2. **Same source at Balanced** → must succeed.
3. **Same source at Streaming** → must succeed.
4. **Same source at Small** → still succeeds (regression check — Small was the only working preset before).
5. **Stitch test:** import a small portrait PNG (e.g. a screenshot, ~750×1334) + a 1920×1080 landscape iPhone video. Default `.auto` aspect mode. Export. The PNG must appear pillarboxed at full canvas height — NOT as a small inset surrounded by huge black margins. Cross-check against the visual described in `DIAG-photo-scale-fit.md` Test A and Test B.
6. **Stitch test (HEIC):** import a portrait iPhone HEIC photo. Default `.auto` aspect mode. Export. The photo must render at the auto-picked portrait canvas (1080×1920) at near-full-frame, NOT as a small landscape inset on a 1920×1080 canvas.
7. **(If reproducible)** force a deliberately broken preset combination (e.g. set the `Max` ceiling to 200 Mbps temporarily on a debug build) → verify the retry-with-downshift fires and the user sees a smaller-preset output instead of a raw `-11841` dialog. The DEBUG `print()` confirms the path; full toast wiring is downstream.

**Pass criteria:** all 7 produce a usable output file. None surface `[AVFoundationErrorDomain -11841]` to the user. The PNG/HEIC stitched outputs match the rendered geometry described in `DIAG-photo-scale-fit.md` §7 Test A–E.

---

## Notes for the executing agent

- **Coordination with Cluster 1 (cache + still-bake-O(1)):** Cluster 1's plan currently expects `StillVideoBaker.bake(still:)` to return `URL`. **After this hotfix lands, the bake signature is `(URL, CGSize)` going forward.** Cluster 1's refactor MUST preserve this return signature when it (a) drops the `duration` parameter and (b) collapses the N-frame loop into a constant 1-second bake. The reviewer of Cluster 1 should catch this and update Cluster 1's plan accordingly before execution. The signature-preserving change for Cluster 1 is mechanical: keep the `return (url: outURL, size: CGSize(width: width, height: height))` line untouched while the surrounding `totalFrames` math changes.

- **Sim hygiene:** if `test_sim` flakes on encoder-related tests, run `xcrun simctl shutdown all && killall Simulator` first. The lead's session may still have zombie simulators from yesterday's 9-agent audit dispatch.

- **Don't call `mcp__xcodebuildmcp__session_set_defaults`** — per AGENTS.md Part 16.3, multiple agents touching session defaults swap each other's project paths and break their builds. The current defaults are correct.

- **Defense-in-depth retry is part of the contract.** Even if Hypothesis #1 is the sole root cause and Tasks 3–5 cover it, ship Task 6 anyway. The cost is ~30 LOC and 4 tests; the value is a graceful fallback the next time an iPhone model / iOS version / source format combination surprises us.

- **PBXFileSystemSynchronizedRootGroup gotcha:** new test methods on existing test files don't trigger the rebuild dance; appending to `StitchAspectRatioTests.swift`, `CompressionSettingsTests.swift`, and `CompressionServiceTests.swift` is safe without `mcp__xcodebuildmcp__clean`.

- **Don't introduce CoreHaptics or a custom `AVVideoCompositing` class.** Per AGENTS.md Part 16.7 and PR #9's audit findings, the existing `Haptics.swift` + built-in opacity/crop ramps cover today's needs. This hotfix has no UX-layer changes.

- **Don't touch `.github/workflows/testflight.yml`** (per AGENTS.md Part 16.9). The merge into `feat/phase-2-features-may3` does NOT auto-trigger TestFlight; only a merge into `main` does. If the user wants to send this hotfix to TestFlight directly (skipping the staging branch), ask first — that's a `feat/phase-2-features-may3 → main` PR, not a Cluster 0 deliverable.

- **≤10 commits per PR.** Currently sketched: 6 implementation commits (Tasks 1–6) + 0 PR-glue commits = 6. Comfortable headroom if Codex needs to add a fixup commit in CI feedback.

- **138 baseline tests must keep passing.** If any pre-existing test breaks, do NOT update it to "match new behaviour" without explicit reasoning — the test may have been encoding a real invariant. Read the assertion, confirm the new behaviour is correct, and document the change in the commit message.

- **Locked decisions (do NOT deviate):**
  - Privacy-first: zero network, zero analytics, zero third-party SDKs.
  - iOS 17+. Bundle: `com.alkloihd.videocompressor`. Team: `9577LMA4J5`.
  - Output sandbox: `Documents/Outputs/`, `tmp/StillBakes/`. No new working dirs.
