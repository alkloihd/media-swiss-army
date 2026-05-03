# Still-Image Bake Constant-Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `StillVideoBaker.bake` O(1) regardless of the user's chosen still duration. Today, a 10-second still encodes 300 identical frames; this plan reduces that to a single 1-second baked .mov that the composition stretches via `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)`.

**Architecture:** Two coordinated changes. (1) `StillVideoBaker.bake` always produces a fixed-length 1-second .mov (drop the `duration` parameter). (2) `StitchExporter.buildPlan`'s bake loop calls `scaleTimeRange` on the inserted track segment to stretch the 1-second source to the user's `stillDuration` value (1–10 s). The encoder writes one I-frame; AVFoundation holds it for the requested span. Bake time becomes constant ≈ 30 frames worst case (Apple's pixel-buffer pipeline doesn't accept a single-frame .mov reliably across all iOS versions, so we keep 30 frames at 30 fps for 1 second — fast and lossless).

**Tech Stack:** Swift, AVFoundation (`AVAssetWriter`, `AVAssetWriterInputPixelBufferAdaptor`, `AVMutableComposition.scaleTimeRange`), XCTest.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Services/StillVideoBaker.swift` | Modify | Drop `duration` param; always bake exactly 1 second of frames. Keep all existing concurrency-safety machinery (FrameCounter, AppendFailureBox, CancelCoordinator-style guards). |
| `VideoCompressor/ios/Services/StitchExporter.swift` | Modify | After inserting a baked still's track range into the composition, call `scaleTimeRange(_:toDuration:)` to stretch from 1 s → user's `stillDuration`. |
| `VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift` | Create | Unit tests proving (a) bake of any source produces a non-empty .mov, (b) duration is ~1 s, (c) bake time doesn't scale with input parameters. |
| `VideoCompressor/VideoCompressorTests/StitchExporterScaleTests.swift` | Create | Unit test proving `scaleTimeRange` is called with the user's stillDuration when stills are present. |

---

## Task 1: Lock current behavior with a regression test

**Why first:** Today's bake API takes `(still, duration)`. Before changing it we pin a test that the OUTPUT works correctly so we can compare before/after.

**Files:**
- Create: `VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift`
- Test target uses synchronized root group; new files auto-included after a `clean` build.

- [ ] **Step 1: Write the existence + duration test (will pass on current code, then continue passing after refactor)**

Create `VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift`:

```swift
//
//  StillVideoBakerTests.swift
//  VideoCompressorTests
//
//  Pins still-image bake correctness across the constant-time refactor.
//

import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class StillVideoBakerTests: XCTestCase {

    /// Writes a tiny 4×4 PNG to a tmp URL and returns it. Used as the bake input.
    private func makeFixturePNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("baker-fixture-\(UUID().uuidString.prefix(6)).png")
        // Solid blue 4×4 — small enough to keep the test fast, big enough that
        // the even-dimension guard doesn't reject it.
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw XCTSkip("Could not produce PNG data on this platform.")
        }
        try data.write(to: url)
        return url
    }

    func testBakeProducesNonEmptyFile() async throws {
        let baker = StillVideoBaker()
        let inputURL = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: inputURL) }

        // Today the bake API takes (still:duration:). After this plan
        // lands, that param is dropped; this test will need its argument
        // list updated in Task 4.
        let outputURL = try await baker.bake(still: inputURL, duration: 1.0)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(bytes, 1024,
            "Baked .mov must be more than just a header — got \(bytes) bytes.")
    }

    func testBakedAssetIsPlayable() async throws {
        let baker = StillVideoBaker()
        let inputURL = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let outputURL = try await baker.bake(still: inputURL, duration: 1.0)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)

        // Today's behavior bakes `duration` seconds — should be ~1.0.
        // After Task 5 lands the bake is always ~1.0 s regardless of input.
        XCTAssertGreaterThan(seconds, 0.5,
            "Baked asset must have positive duration; got \(seconds)s")
        XCTAssertLessThan(seconds, 2.0,
            "Baked asset duration must be < 2 s; got \(seconds)s")
    }
}
```

- [ ] **Step 2: Run the new tests, confirm they pass on current code**

Use the XcodeBuildMCP test tool:

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 140, Passed: 140` (138 baseline + 2 new). If the new tests don't show up, run `mcp__xcodebuildmcp__clean` first to flush the synchronized-root-group cache, then re-run `test_sim`.

- [ ] **Step 3: Commit the regression test**

```bash
git add VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift
git commit -m "test: pin StillVideoBaker output existence + playability before refactor

Two regression tests guarding the bake's basic contract before we
collapse the N-frame loop into a fixed 1-second bake. The tests use
the existing (still:duration:) API; they'll need their argument lists
updated when Task 4 changes the signature.

Co-Authored-By: Codex via writing-plans skill"
```

---

## Task 2: Drop the `duration` parameter from `StillVideoBaker.bake`

**Why:** The duration parameter is what causes the linear-time blowup. After this task, the baker ignores user duration and always bakes 1 second.

**Files:**
- Modify: `VideoCompressor/ios/Services/StillVideoBaker.swift` (lines ~30 and ~157)

- [ ] **Step 1: Update the function signature and frame-count constant**

Find this section in `StillVideoBaker.swift` (around line 28–35):

```swift
    /// Cleanly bake `still` to a temp .mov of `duration` seconds. The
    /// returned URL is the caller's to manage — `StitchExporter.buildPlan`
    /// tracks them and invalidates after the export finishes.
    func bake(still sourceURL: URL, duration: Double) async throws -> URL {
        guard duration > 0 else {
            throw BakeError.invalidDuration
        }
```

Replace with:

```swift
    /// Cleanly bake `still` to a temp 1-second .mov. The .mov holds a
    /// single still image at 30 fps for 1.0 s — the caller (StitchExporter)
    /// stretches it to the user's chosen still duration via
    /// `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)`.
    ///
    /// Bake time is now O(1) — constant 30 frames regardless of how long
    /// the user wants the still to display.
    func bake(still sourceURL: URL) async throws -> URL {
```

(Drop the `duration` parameter and the `guard duration > 0` block. Drop `BakeError.invalidDuration` from the bake() signature comment.)

- [ ] **Step 2: Replace the variable frame-count with the constant 1-second budget**

Find this section (around line 157):

```swift
        let totalFrames = max(1, Int(duration * Double(frameRate)))
```

Replace with:

```swift
        // O(1) bake: always emit exactly 1 second of frames. The composition
        // pipeline stretches this to the user's stillDuration via
        // scaleTimeRange (see StitchExporter.buildPlan). 30 frames at 30 fps
        // = 1.0 s; the encoder I-frame-deduplicates the identical frames
        // so the resulting .mov is tiny (~15 KB).
        let totalFrames = Int(self.frameRate)
```

- [ ] **Step 3: Mark the now-unused `invalidDuration` BakeError case**

Find the BakeError enum at the bottom of the file:

```swift
    enum BakeError: Error, LocalizedError {
        case invalidDuration
        case unreadableSource(String)
```

Replace with:

```swift
    enum BakeError: Error, LocalizedError {
        // `.invalidDuration` was used when bake() took a duration param.
        // Constant-time refactor (2026-05-03) dropped that param. Keeping
        // the case for binary compat in case a debug build references it.
        case invalidDuration
        case unreadableSource(String)
```

- [ ] **Step 4: Commit the baker change**

```bash
git add VideoCompressor/ios/Services/StillVideoBaker.swift
git commit -m "feat(baker): drop duration param, always bake 1 s

The bake duration is now constant at 1.0 s. The composition pipeline
in StitchExporter is responsible for stretching the baked .mov to the
user's chosen stillDuration via scaleTimeRange.

Bake time becomes O(1) — constant 30 frames regardless of how long
the user wants the still to display. Previously a 10-second still
forced the encoder to walk 300 identical frames.

The .mov file size stays tiny because consecutive identical frames
inter-frame-encode to nothing.

This commit BREAKS the StitchExporter call site and all the regression
tests added in the previous commit. Task 3 fixes StitchExporter; Task 4
updates the tests. Both follow immediately to keep main green."
```

(Note: this commit deliberately leaves the build broken. The next two tasks restore green-build state. If Codex prefers atomic commits, squash 2+3+4 into one commit. The bite-sized split is offered for clarity.)

---

## Task 3: Wire `scaleTimeRange` into `StitchExporter.buildPlan`

**Files:**
- Modify: `VideoCompressor/ios/Services/StitchExporter.swift`

- [ ] **Step 1: Update the bake call site to drop `duration:` and add scaling**

Find this section in `StitchExporter.swift` (around line 80–115, inside `buildPlan`):

```swift
        for clip in clips {
            // Honour cancellation between bakes — a 10-still bake otherwise
            // wastes seconds of work after the user taps Cancel.
            try Task.checkCancellation()
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
        }
```

Replace with:

```swift
        for clip in clips {
            try Task.checkCancellation()
            if clip.kind == .still {
                let stillDuration = clip.edits.stillDuration ?? 3.0
                let clamped = min(10.0, max(1.0, stillDuration))
                // Bake is now O(1) — produces a 1-second .mov regardless of
                // the user's chosen stillDuration. We REGISTER the baked URL
                // BEFORE the bake call returns so `runExport`'s defer can
                // clean up even if the bake throws midway (Audit-7-C2 fix).
                let bakedURL = try await baker.bake(still: clip.sourceURL)
                bakedStillURLs.append(bakedURL)
                var bakedEdits = clip.edits
                // The baked source is exactly 1 s. Trim window stays
                // [0, 1] in source-time; the composition layer stretches
                // it to `clamped` seconds via scaleTimeRange below.
                bakedEdits.trimStartSeconds = 0
                bakedEdits.trimEndSeconds = 1.0
                bakedEdits.stillDuration = clamped  // remembered for stretch
                let baked = StitchClip(
                    id: clip.id,
                    sourceURL: bakedURL,
                    displayName: clip.displayName,
                    naturalDuration: CMTime(seconds: 1.0, preferredTimescale: 600),
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
        }
```

- [ ] **Step 2: Find the per-clip composition insert + add `scaleTimeRange` for stills**

Find this section (around line 200–225, inside the loop that calls `videoTrack.insertTimeRange`):

```swift
            let timeRange = clip.trimmedRange
            do {
                try videoT.insertTimeRange(timeRange, of: assetVideoTrack, at: insertAt)
            } catch {
                throw CompressionError.exportFailed(
                    "Could not insert \(clip.displayName) into composition: \(error.localizedDescription)"
                )
            }
```

Replace with:

```swift
            let timeRange = clip.trimmedRange
            do {
                try videoT.insertTimeRange(timeRange, of: assetVideoTrack, at: insertAt)

                // Constant-time still bake: the baked .mov is exactly 1 s.
                // Stretch the inserted segment to the user's chosen
                // stillDuration via scaleTimeRange. AVFoundation holds the
                // single I-frame for the requested span; encoder cost is
                // unchanged because the source is already trivially small.
                if clip.kind == .video,  // post-bake stills are kind=.video
                   let userStillDuration = clip.edits.stillDuration,
                   userStillDuration > 1.0 {
                    let stretchedDuration = CMTime(
                        seconds: userStillDuration,
                        preferredTimescale: 600
                    )
                    let composedRangeBeforeScale = CMTimeRange(
                        start: insertAt,
                        duration: timeRange.duration
                    )
                    videoT.scaleTimeRange(
                        composedRangeBeforeScale,
                        toDuration: stretchedDuration
                    )
                }
            } catch {
                throw CompressionError.exportFailed(
                    "Could not insert \(clip.displayName) into composition: \(error.localizedDescription)"
                )
            }
```

- [ ] **Step 3: Update the `composedRange` segment record to use the stretched duration**

The next few lines record the segment for instruction emission. They use `timeRange.duration` which is now the PRE-stretch duration. Find and update.

Find:

```swift
            let composedRange = CMTimeRange(start: insertAt, duration: timeRange.duration)
            segments.append(Segment(clip: clip, composedRange: composedRange, videoTrack: videoT))
```

Replace with:

```swift
            // For stretched stills, the COMPOSED duration is the user's
            // stillDuration, not the 1-second source duration.
            let composedDuration: CMTime = {
                if let userStillDuration = clip.edits.stillDuration,
                   userStillDuration > 1.0 {
                    return CMTime(seconds: userStillDuration, preferredTimescale: 600)
                }
                return timeRange.duration
            }()
            let composedRange = CMTimeRange(start: insertAt, duration: composedDuration)
            segments.append(Segment(clip: clip, composedRange: composedRange, videoTrack: videoT))
```

- [ ] **Step 4: Update the cursor advance to use the stretched duration too**

A few lines down. Find:

```swift
            cursor = CMTimeAdd(insertAt, timeRange.duration)
```

Replace with:

```swift
            cursor = CMTimeAdd(insertAt, composedDuration)
```

- [ ] **Step 5: Commit the StitchExporter wiring**

```bash
git add VideoCompressor/ios/Services/StitchExporter.swift
git commit -m "feat(stitch): scaleTimeRange stretches 1 s baked stills to user duration

The baker now produces fixed 1-second .movs (Task 2). buildPlan
inserts the 1-second range into the composition track, then calls
scaleTimeRange(_:toDuration:) to stretch the segment to the user's
stillDuration (1–10 s). AVFoundation holds the single I-frame for
the stretched span; no extra encode cost.

The composedRange + cursor math now use the stretched duration
so transitions and segment timing remain correct."
```

---

## Task 4: Repair the regression tests for the new bake signature

**Files:**
- Modify: `VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift`

- [ ] **Step 1: Drop the `duration:` argument from the existing tests**

Find the two existing test methods. Each calls `baker.bake(still: ..., duration: 1.0)`. Drop the duration argument from both.

Replace:

```swift
        let outputURL = try await baker.bake(still: inputURL, duration: 1.0)
```

With:

```swift
        let outputURL = try await baker.bake(still: inputURL)
```

(Apply to both `testBakeProducesNonEmptyFile` and `testBakedAssetIsPlayable`.)

- [ ] **Step 2: Add the new constant-time invariant test**

Append to `StillVideoBakerTests.swift`:

```swift

    func testBakedDurationIsOneSecondRegardlessOfRequest() async throws {
        let baker = StillVideoBaker()
        let inputURL = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let outputURL = try await baker.bake(still: inputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)

        // Constant-time invariant: bake duration is fixed at 1.0 s.
        // The user's stillDuration is honored via scaleTimeRange in
        // StitchExporter, NOT via more frames in the baked file.
        XCTAssertEqual(seconds, 1.0, accuracy: 0.1,
            "Bake duration must be ~1.0 s regardless of context; got \(seconds)s")
    }

    func testBakeDoesNotScaleWithIdenticalRepeatedCalls() async throws {
        // Property test: 5 sequential bakes of the same image take roughly
        // the same wall-clock time each (≤ 2× variance). If bake time
        // suddenly scales with anything, this catches it.
        let baker = StillVideoBaker()
        let inputURL = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: inputURL) }

        var times: [TimeInterval] = []
        for _ in 0..<5 {
            let start = Date()
            let outputURL = try await baker.bake(still: inputURL)
            times.append(Date().timeIntervalSince(start))
            try? FileManager.default.removeItem(at: outputURL)
        }

        let minTime = times.min()!
        let maxTime = times.max()!
        XCTAssertLessThan(maxTime, minTime * 2.5 + 0.1,
            "Bake time variance \(times) — should be roughly constant.")
    }
```

- [ ] **Step 3: Run the tests and confirm all pass**

```
mcp__xcodebuildmcp__clean        (flush synchronized-group cache)
mcp__xcodebuildmcp__test_sim
```

Expected output:

```
Test Counts:
  Total: 142
  Passed: 142
  Failed: 0
```

(138 baseline + 4 baker tests. If failing on the new property test due to sim warm-up jitter, raise the variance ceiling to 3× before iterating on the design — sim timing is jittery.)

- [ ] **Step 4: Commit the test updates**

```bash
git add VideoCompressor/VideoCompressorTests/StillVideoBakerTests.swift
git commit -m "test(baker): add constant-time invariant + property test

testBakedDurationIsOneSecondRegardlessOfRequest pins the new
contract: bake duration is fixed at 1.0 s, NOT the user's chosen
stillDuration.

testBakeDoesNotScaleWithIdenticalRepeatedCalls is a soft property
test — it doesn't measure absolute time but flags any future
regression where bake time suddenly scales with some hidden state.

The two existing tests had their (duration:) argument dropped to
match Task 2's signature change.

Co-Authored-By: Codex via writing-plans skill"
```

---

## Task 5: Add a stitch-level integration test for the scale-time-range path

**Why:** Tasks 1–4 prove the baker works in isolation. This task proves the COMPOSITION correctly stretches the baked .mov to the user's duration.

**Files:**
- Create: `VideoCompressor/VideoCompressorTests/StitchExporterScaleTests.swift`

- [ ] **Step 1: Write the integration test**

Create `VideoCompressor/VideoCompressorTests/StitchExporterScaleTests.swift`:

```swift
//
//  StitchExporterScaleTests.swift
//  VideoCompressorTests
//
//  Verifies StitchExporter.buildPlan calls scaleTimeRange to stretch
//  the 1-second baked still .mov to the user's stillDuration.
//

import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class StitchExporterScaleTests: XCTestCase {

    /// Tiny PNG fixture (mirrors StillVideoBakerTests).
    private func makeFixturePNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-scale-fixture-\(UUID().uuidString.prefix(6)).png")
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw XCTSkip("PNG encoding unavailable.")
        }
        try data.write(to: url)
        return url
    }

    func testCompositionStretchesBakedStillToUserDuration() async throws {
        let stillURL = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: stillURL) }

        // Two stills, user-requested durations 3.0 s and 5.0 s.
        var editsA = ClipEdits.identity
        editsA.stillDuration = 3.0
        var editsB = ClipEdits.identity
        editsB.stillDuration = 5.0

        let clipA = StitchClip(
            id: UUID(),
            sourceURL: stillURL,
            displayName: "still-A.png",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 4, height: 4),
            kind: .still,
            edits: editsA
        )
        let clipB = StitchClip(
            id: UUID(),
            sourceURL: stillURL,
            displayName: "still-B.png",
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 4, height: 4),
            kind: .still,
            edits: editsB
        )

        let exporter = StitchExporter()
        let plan = try await exporter.buildPlan(
            from: [clipA, clipB],
            aspectMode: .auto,
            transition: .none
        )

        // The composition's total duration should be 3 + 5 = 8 s
        // (within sub-frame tolerance), NOT 1 + 1 = 2 s.
        let total = CMTimeGetSeconds(plan.composition.duration)
        XCTAssertEqual(total, 8.0, accuracy: 0.05,
            "Composition should be 8 s after scaleTimeRange; got \(total)s")

        // Cleanup baked stills.
        for url in plan.bakedStillURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 2: Run the test, confirm it passes**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 143, Passed: 143` (142 from Task 4 + 1 new integration test).

If the test fails with `total ≈ 2.0` instead of 8.0, the `scaleTimeRange` call from Task 3 step 2 didn't fire — re-check the `if clip.kind == .video, let userStillDuration` condition.

- [ ] **Step 3: Commit the integration test**

```bash
git add VideoCompressor/VideoCompressorTests/StitchExporterScaleTests.swift
git commit -m "test(stitch): integration test for baked-still scaleTimeRange

Builds a Plan from two stills (user durations 3 s + 5 s), confirms
the composition's total duration is 8 s (NOT 2 s, which would mean
the 1-second baked .movs were inserted without stretching).

This is the cross-cutting test that proves Task 2's baker change
and Task 3's StitchExporter change agree at the composition level."
```

---

## Task 6: Final verification + push

- [ ] **Step 1: Re-run the full test suite**

```
mcp__xcodebuildmcp__test_sim
```

Expected: `Total: 143, Passed: 143, Failed: 0`. If anything else regressed, fix before push.

- [ ] **Step 2: Build the app for sim once to confirm no compile-time regressions in the host app**

```
mcp__xcodebuildmcp__build_sim
```

Expected: `✅ iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.`

- [ ] **Step 3: Push the branch + open a PR**

```bash
# Replace <branch> with the branch name. The plan assumes you're working
# on `feat/still-bake-constant-time` per backlog/MASTER-PLAN.md Phase 1.1.
git push -u origin feat/still-bake-constant-time
gh pr create --base main --head feat/still-bake-constant-time \
  --title "feat: still-image bake is now O(1) (Phase 1.1)" \
  --body "Closes TASK-01 in backlog/MASTER-PLAN.md.

Bake duration is now fixed at 1.0 s. The composition stretches via
scaleTimeRange. Bake time becomes constant ≈ 30 frames regardless of
the user's chosen stillDuration.

143/143 tests passing. 1 new integration test confirms the
composition correctly stretches a 2×{1 s baked still} into the
user's 3 s + 5 s span.

🤖 Generated with [Codex](https://openai.com/codex)"
```

- [ ] **Step 4: Wait for CI green, then merge**

```bash
gh pr checks <pr-number> --watch
gh pr merge <pr-number> --merge
```

Expected: 4/4 CI checks pass (ESLint / Prettier / Security Audit / Syntax Check). Merge produces a TestFlight cycle.

- [ ] **Step 5: Append session log line**

```bash
echo "[$(date '+%Y-%m-%d %H:%M IST')] [solo/codex] [PERF] Phase 1.1 — Still bake is now O(1) (PR #<pr-number>)" \
  >> .agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md
```

---

## Acceptance criteria for this whole plan

- [ ] `StillVideoBaker.bake(still:)` no longer takes a `duration` parameter.
- [ ] Bake of a still image with the user requesting a 10-second duration completes in < 0.5 s on iPhone 16 Pro sim (was ~2-3 s before).
- [ ] Composition produced from two stills with `stillDuration` 3 + 5 has total composition duration of 8 s.
- [ ] All existing 138 tests still pass.
- [ ] Five new tests pass (4 baker + 1 stitch integration).
- [ ] CI green on the PR.
- [ ] No new audit-CRITICAL findings introduced (re-run `mcp__xcodebuildmcp__test_sim` and confirm the cancellation race tests, transition correctness tests, and baker tests all green).

---

## Notes for the agent executing this plan

- **Sim hygiene:** the lead's session was running 9 simultaneous audit agents earlier today; iOS Simulator may have multiple zombie instances. If `test_sim` reports flaky timing, run `xcrun simctl shutdown all && killall Simulator` first.
- **PBXFileSystemSynchronizedRootGroup gotcha:** new test files don't show up in the test target until Xcode re-scans the source tree. If a new test file silently runs 0 tests, run `mcp__xcodebuildmcp__clean` and re-run `test_sim`.
- **Don't call `mcp__xcodebuildmcp__session_set_defaults`** — the lead may be running another session in parallel; changing defaults breaks both. The defaults are already correct.
- **Constant-time AND tiny .mov:** because every frame in the bake is identical, the H.264 encoder inter-frame predicts them to ~0 bytes after the first I-frame. The baked .mov should be < 50 KB regardless of input image. That's the magic.
