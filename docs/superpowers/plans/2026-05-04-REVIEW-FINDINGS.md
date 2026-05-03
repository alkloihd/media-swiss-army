# Plan Suite Review — 2026-05-04

**Reviewer:** Opus 4.7 red-team agent (read-only)
**Scope:** 6 cluster plans + INDEX + MANIFEST + 3 DIAGs + canonical TDD plan
**Verdict:** **NEEDS FIXES BEFORE COMMIT** — 4 CRITICAL, 7 HIGH, 6 MEDIUM, plus several LOW/nits. Fix the 4 CRITICAL findings before Codex starts; the HIGH set should be pre-resolved or surfaced in the deviation log. Cluster 0 + Cluster 5 are otherwise execution-ready; Cluster 2 needs the most rework.

`HEAD` of `main` at the moment of review = `4dd7525` (`chore: kickstarter answers + Xcode pbxproj key reorder`). The INDEX claims `2608a1c`; minor staleness (one commit later — `4dd7525` is on top of `c299340`, not `2608a1c`).

---

## CRITICAL findings (must fix before Codex starts)

### C1. Cluster 2 Task 1 mutates an immutable `let videoOutputSettings` — won't compile
**File:** `docs/superpowers/plans/2026-05-04-phase1-cluster2-stitch-correctness.md`, Task 1 Step 3
**Issue:** Plan says, after the existing settings dict is built, "append":
```swift
videoOutputSettings[AVVideoColorPropertiesKey] = [...]
videoOutputSettings[AVVideoCompressionPropertiesKey] = compProps
```
But `CompressionService.swift:192` declares it as `let`:
```swift
let videoOutputSettings: [String: Any] = [
    AVVideoCodecKey: settings.videoCodec.rawValue,
    AVVideoWidthKey: NSNumber(value: targetWidth),
    AVVideoHeightKey: NSNumber(value: targetHeight),
    AVVideoCompressionPropertiesKey: compressionProps,
]
```
Mutating a `let` dictionary is a Swift compile error.
**Fix:** Plan must change the declaration to `var videoOutputSettings: [String: Any] = ...` BEFORE attempting the mutation step. The plan footnote says "Verify the local variable name — it might be `videoSettings` rather than `videoOutputSettings`. Match the existing site exactly." That's not enough — it must also be promoted to `var`.
**Owner:** Plan author (update plan); or Codex must include the `let → var` swap as part of Step 3.

### C2. Cluster 2 Task 2 misdescribes the existing audio architecture — proposed "addMutableTrack per segment" conflicts with the A/B-track design
**File:** `docs/superpowers/plans/2026-05-04-phase1-cluster2-stitch-correctness.md`, Task 2 Steps 2–4
**Issue:** Plan claims `Segment` lives "around line 50–55" and the fix should "addMutableTrack per segment" inside the loop. The ACTUAL code has:
- `Segment` is a function-local struct at line 163 (inside `buildPlan`), not a top-level type around line 50.
- Audio tracks are PRE-allocated at line 134/148–149 as `audioTrackA` / `audioTrackB` (an A/B alternating model), NOT created per-segment.
- Insertion logic at line 227–250: `useTrackB = needsAB && (segments.count % 2 == 1)` then `audioT = useTrackB ? audioTrackB : audioTrackA`. The clip's audio is inserted into one of those two pre-allocated tracks, not a brand-new track.
- The `i % 2` parity bug being fixed by Cluster 2 is the SAME bug as the A/B selection logic at insert-time being mirrored in `buildAudioMix(...)` at line 359 (`let trackIdx = audioTracks.count == 1 ? 0 : (i % 2)`). The fix needs to propagate from the same source — `useTrackB` decisions made at insertion — not by adding new tracks.

The bug DOES exist (skipped audio-less clips break parity in `buildAudioMix`), but the proposed fix re-architects the audio path in a way that the surrounding `audioTrackA / audioTrackB / needsAB` machinery does not support. Codex will get stuck or land a half-correct rewrite.
**Fix:** Re-author Task 2 with the actual A/B architecture. The minimal-diff fix is: extend the segment record to carry `audioTrack: AVMutableCompositionTrack?` recording the SAME `audioT` chosen at insertion (lines 229 + 247–249). Do NOT call `composition.addMutableTrack(...)` per segment in the loop. `buildAudioMix` then iterates audible segments using each segment's recorded `audioTrack` instead of the parity formula. The pre-allocated audioTrackA/audioTrackB still feed the AudioMix as the actual underlying tracks.
**Owner:** Plan author. Codex should not execute the current Task 2 — at minimum add a deviation log entry before re-architecting.

### C3. Cluster 5 Task 4 over-promotes private `read()` helpers without showing them — likely cascading async upgrades elsewhere
**File:** `docs/superpowers/plans/2026-05-04-phase3-cluster5-meta-marker-registry.md`, Task 4 Step 2
**Issue:** Plan says `read(from:)` is already async so adding `await` is "clean," and only mentions `makeTag` as needing async. Verified: `PhotoMetadataService.swift:268` `private func makeTag(...)` is sync; lines 82 and 107 invoke it. Both are inside `read(from:)` which is async — confirmed. **However**, the plan does NOT inspect every other call site of `isFingerprintTag` / `xmpContainsFingerprint`. `grep -rn "isFingerprintTag\(\|xmpContainsFingerprint\(" VideoCompressor/` returned 7 production sites + 11 test sites. Of those production sites, 5 are inside synchronous helpers (visible on inspection of lines 82, 107, 123, 272). The plan's hand-wave "Apply the same `await` upgrade if needed" is inadequate — Codex needs an exhaustive pre-walk so that when the new `async` requirement cascades, it doesn't silently miss a sync helper that now needs to bubble up to the nearest async parent.
**Fix:** Add a Step 2.5 to Task 4 of Cluster 5: "Run `grep -rn 'isFingerprintTag\|xmpContainsFingerprint' VideoCompressor/` and update EACH production hit. If a synchronous helper calls one of these, the helper must also become `async` and its call sites updated, recursively until the bubble-up reaches an already-`async` parent."
**Owner:** Plan author — at minimum add the exhaustive-walk step. Codex will discover the gap empirically but a half-applied async cascade is what causes the most painful "the build is red and I don't know why" loops.

### C4. Cluster 0 dead-code removal step contradicts itself across 3 successive replacements — "delete the dead block" then "actually keep it but guard it" — Codex can't deterministically execute
**File:** `docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md`, Task 3 Step 2
**Issue:** Three successive instructions on the same code region, each rewriting the previous:
1. "Delete the dead block" (lines 416–420) → replace with comment "(Removed: ...)"
2. "If the dead branch makes Codex nervous, leave a `precondition(...)` instead — either is fine."
3. "Actually a cleaner approach: keep the existing structure but pick a sensible probe-failure fallback explicitly. Replace the smart-cap return at lines 161–162 with an explicit Max guard:" — this contradicts step 1's "delete" instruction.

A subagent walking this in `superpowers:subagent-driven-development` will end up applying option 1 first, then option 3, producing a code path with both a deleted block AND an explicit guard further down the function — an inconsistent intermediate state. The plan does not state which option is canonical.
**Fix:** Pick ONE option and delete the other two from the plan. Recommended: option 3 (explicit Max-fallback guard at line 161-162) — it's simplest to reason about and avoids the `Int64.max` overflow concern raised in step 2. Remove options 1 and 2 entirely.
**Owner:** Plan author. Codex must not start Task 3 until this is resolved.

---

## HIGH findings (should fix before merge)

### H1. Cross-cluster API-conflict coordination is documented but not landed in Cluster 1's plan
**Files:** `docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md` Task 1 ↔ `docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md` Task 1 Step 2
**Issue:** Cluster 0 changes `bake(still:duration:)` return type to `(URL, CGSize)`. Cluster 1's plan still shows the OLD signature `bake(still:) async throws -> URL` (line 108) and `bake(still:intoPreallocated:) async throws -> URL` (line 95). The INDEX coordination note acknowledges this and says "Codex executor should rebase Cluster 1 against post-Cluster-0 main before starting." That's procedural — but Cluster 1's plan file ITSELF still encodes the wrong return type at the code-block level. Codex executing line-by-line with `superpowers:subagent-driven-development` will write a function that returns `URL` and break the call site in `StitchExporter.buildPlan` (which after Cluster 0 expects a tuple).
**Fix:** Update Cluster 1's plan code blocks to reflect the post-Cluster-0 signature: `bake(still:) async throws -> (url: URL, size: CGSize)` and the same for `bake(still:intoPreallocated:)`. Update the `bakeImpl` body inside the file similarly. Or add an explicit "PREREQ: rebase against post-Cluster-0 main, then update these snippets" callout at the very top of Cluster 1's Task 1.
**Owner:** Plan author or Codex (post-rebase, must update each code block in the plan before executing).

### H2. Cluster 1 Task 1 Step 1 instructs Codex to "wrap the bake call in a try/throw structure that always appends the URL on partial creation" — but the proposed code doesn't actually use a `defer` or guarantee partial-creation cleanup
**File:** `docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md`, Task 1 Step 1
**Issue:** The step heading says "wrap the bake call in a try/throw structure that always appends the URL on partial creation" but the body just adds `bakedStillURLs.append(preAllocURL)` BEFORE the bake — there's no `defer`, no `do/catch`, no actual try/throw structure. The append-before-bake DOES achieve the cleanup goal (the URL is registered for the runExport defer to sweep), so the implementation is fine, but the heading misleads. Worse: if `baker.bake` throws after partial bytes are written to disk, the registered URL is `preAllocURL` — but the baker MIGHT have written to a DIFFERENT path (line 70 has the `if bakedURL != preAllocURL { ... bakedStillURLs[last] = bakedURL }` correction, but that line only runs on bake SUCCESS). On bake failure, the partial file at the baker's actual output URL leaks and never gets registered.
**Fix:** Either guarantee the baker writes to `preAllocURL` (the new `bake(still:intoPreallocated:)` overload added in Step 2 does this — make sure it's the only callable path), OR wrap in `do { … } catch { ... cleanup ... throw }`. Recommended: rely on the `bake(still:intoPreallocated:)` overload exclusively in `buildPlan` so the URL is always known up-front.
**Owner:** Plan author or Codex.

### H3. Cluster 3 Task 6 silent fallback on save failure — `catch` returns `.success(...)` with `didSave=false`
**File:** `docs/superpowers/plans/2026-05-04-phase2-cluster3-ux-polish-and-onboarding.md`, Task 6 Step 3 (the `cleanOne` static helper)
**Issue:**
```swift
if replaceOriginals {
    do { try await PhotosSaver.saveAndOptionallyDeleteOriginal(...); didSave = true }
    catch {
        return (item.id, .success(result), false)
        // Surface the save failure via the Success result; the
        // caller still records the strip as success ...
    }
}
```
This swallows save failures into `.success` with `didSave=false`. The user gets "Saved 5 photos" (the per-batch count) when in reality 7 of 12 failed to save and only 5 saved successfully. The user-facing toast says "Saved 5 of 12 photos" but the failed-save errors never bubble up — they're silently lost.
**Fix:** Either route save failures through `batchProgress.failed` + `batchProgress.lastError`, OR change the return tuple to `(UUID, Result<MetadataCleanResult, Error>, didSave: Bool, saveError: Error?)` so the drain loop can record save errors separately. Document the policy in the plan: "save failures during a `replaceOriginals` batch surface in the toast as 'Saved 5 — 7 failed to save'".
**Owner:** Plan author. The code as written violates AGENTS.md's "no silent fallbacks" rule.

### H4. Cluster 4's review-prompter integration uses `await MainActor.run { … }` from inside an already MainActor-isolated function
**File:** `docs/superpowers/plans/2026-05-04-phase3-cluster4-app-store-hardening.md`, Task 3 Step 3
**Issue:** Plan inserts:
```swift
await MainActor.run {
    ReviewPrompter.shared.recordSuccessAndMaybePrompt()
}
```
Inside `MetaCleanQueue.runClean`. Verified: `MetaCleanQueue` is declared `@MainActor` at the class level (`MetaCleanQueue.swift:18`), so `runClean` is already main-actor-isolated. `await MainActor.run { ... }` inside an already-MainActor context is legal but redundant. More importantly: `ReviewPrompter` is `@MainActor` and `shared` is a static — calling `ReviewPrompter.shared.recordSuccessAndMaybePrompt()` from a MainActor context is just a direct call. The `await` is also unnecessary because there's no actor hop.
**Fix:** Replace with the direct call `ReviewPrompter.shared.recordSuccessAndMaybePrompt()`. The plan does say "(Verify the surrounding context compiles — `runClean` is `async`, so `await MainActor.run` is fine. If the function is already main-actor-isolated, the wrapper is unnecessary; adapt accordingly.)" — but that adaptive caveat means Codex has to make a judgment call instead of executing the plan literally. Pre-resolve in the plan.
**Owner:** Plan author.

### H5. Cluster 5 false-positive guard test has a logic bug for the long-payload "meta" trigger
**File:** `docs/superpowers/plans/2026-05-04-phase3-cluster5-meta-marker-registry.md`, Task 3 Step 1 (`testBinaryAtomMetaMarkerInLargePayloadDoesTrigger`)
**Issue:** The test asserts:
```swift
let hit = await MetadataService.isMetaGlassesFingerprint(
    key: "com.apple.quicktime.comment",
    decodedText: String(repeating: "x", count: 796) + "meta",
    isBinarySource: true,
    atomByteCount: 800
)
XCTAssertTrue(hit, "Binary 800-byte atom containing 'meta' must trigger.")
```
But the bundled JSON `binaryAtomMarkers.comment` does NOT contain a bare `"meta"` substring — it has `"meta wearable"`, `"meta ai"`, `"captured with meta"` (multi-word). The default-bundled fallback DOES have bare `"meta"` (`MetaMarkerRegistry.defaultBundled()` line 343 = `["ray-ban", "rayban", "meta"]`), but in this test path the JSON IS loaded from the bundle (not the fallback). The detector will run substring matches against `["ray-ban", "rayban", "ray ban", "meta wearable", "meta ai", "captured with meta"]` — NONE of which is in the test's input string `"xxxx...meta"`. The test will FAIL (assertion expects `true`, actual `false`).
**Fix:** Either change the test input to `"xxxx...meta wearable"` (or another marker present in the bundled JSON), OR add bare `"meta"` to `binaryAtomMarkers.comment` in the JSON (which then weakens the false-positive guard's value because user-typed text containing `meta` is more common than `meta wearable`).
**Owner:** Plan author. This is a hard contradiction — the test as written cannot pass against the JSON as written.

### H6. Cluster 4 Task 4 references a stale repo URL but says NOT to "fix" reference docs to match — yet the plan-test asserts `Link(destination: URL(string: "https://alkloihd.github.io/media-swiss-army/privacy/")!)`. Project name `media-swiss-army` is unsuitable for a public privacy-policy URL listed in App Store Connect.
**File:** `docs/superpowers/plans/2026-05-04-phase3-cluster4-app-store-hardening.md`, Task 4 (URL choice)
**Issue:** The repo name `media-swiss-army` is the working name but is profane and will be visible in the App Store Connect privacy policy URL field. App Reviewers see this. Apple App Review can reject for inappropriate language in submitted URLs.
**Fix:** Either (a) rename the public Pages output path (set up a custom domain or rename the repo before enabling Pages), OR (b) host the privacy policy on a separate non-profane URL (e.g. `mediaswissarmy.app/privacy`), OR (c) explicitly tell the user this is a manual step they need to resolve before App Store submission. The plan's "Notes for the executing agent" mentions GitHub Pages enablement as a manual step but does NOT flag the repo-name profanity issue.
**Owner:** Plan author + user (need to decide URL strategy before this PR can land safely).

### H7. Cluster 0 Task 6 retry path swallows the "Small itself fails" case differently than expected
**File:** `docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md`, Task 6 Step 3
**Issue:** Retry catch clause:
```swift
} catch let CompressionError.exportFailed(msg)
    where msg.contains("-11841"),
        let fallback = Self.downshift(from: settings)
{ ... retry ... }
```
If `Self.downshift(from: settings) == nil` (i.e. settings is `Small` already), the `where`-clause-with-`let` fails to bind, the catch doesn't fire, and the original `-11841` error propagates. That's the intended behavior. **But** the catch's body itself does NOT have a do/catch — if the RETRY also throws `-11841` (with downshift failing), the retry's error propagates without further fallback. The plan says "If the retry also fails, or if Small itself fails, the original error surfaces unchanged." — but actually what surfaces is the RETRY's error, not the ORIGINAL error. Different message, different preset attribution. The acceptance criterion ("verify the retry-with-downshift fires and the user sees a smaller-preset output instead of a raw `-11841` dialog") doesn't cover the double-failure case.
**Fix:** Either (a) clarify in the plan that the retry's error replaces the original on double-failure (and update the user-facing copy/log accordingly), OR (b) wrap the retry in another do/catch and surface a "tried Max, tried Balanced, both failed" composite error. Recommend (a) for simplicity.
**Owner:** Plan author.

---

## MEDIUM findings (nice to fix)

### M1. INDEX file says `2608a1c` is the starting point; current `main` HEAD is `4dd7525`
**File:** `docs/superpowers/plans/2026-05-04-PHASES-1-3-INDEX.md` line 7
**Issue:** "Starting point: `main` at `2608a1c` (post-PR-9 merge)." Verified `git rev-parse HEAD` = `4dd7525d`. One commit drift (the `chore: kickstarter answers + Xcode pbxproj key reorder`). Not load-bearing for line refs (which all checked out), but the INDEX claim is stale.
**Fix:** Update to `4dd7525` or a "main as of <date>" wording.
**Owner:** Plan author or Codex (post-checkout, update before opening PR).

### M2. INDEX "Phase 6 candidates" section still says "Not part of the 5 cluster PRs" — should be 6
**File:** `docs/superpowers/plans/2026-05-04-PHASES-1-3-INDEX.md` line 63
**Issue:** Pre-existing flag from the INDEX agent. Confirmed verbatim:
```
These are ideas to revisit AFTER Phase 1-3 ships. Not part of the 5 cluster PRs.
```
**Fix:** Change "5 cluster PRs" → "6 cluster PRs."
**Owner:** Plan author.

### M3. Cluster 1 Task 3 wires sweepOnCancel into "PhotoMetadataService" + "PhotoCompressionService" without verifying those services exist or what their cancel branches look like
**File:** `docs/superpowers/plans/2026-05-04-phase1-cluster1-cache-and-still-bake.md`, Task 3 Step 3
**Issue:** Plan instructs Codex to "find each early-throw / cancel branch (typically `try? FileManager.default.removeItem(at: outputURL); throw ...`)" and replace. There's no grep verification step, so Codex will scan blind. Also `PhotoMetadataService` is real (verified), but `PhotoCompressionService` was not directly verified — could exist or be misnamed.
**Fix:** Add a pre-step: "Run `grep -rn 'cancel\|throw' VideoCompressor/ios/Services/PhotoMetadataService.swift VideoCompressor/ios/Services/PhotoCompressionService.swift` to enumerate ALL cancel branches, then visit each."
**Owner:** Plan author or Codex.

### M4. Cluster 3 Task 1 Step 5 says `XCUIApplication().buttons["clipEditorSplit"]` may exist in UI tests; instructs replace if found — but no UI tests are part of this codebase's 138 baseline
**File:** `docs/superpowers/plans/2026-05-04-phase2-cluster3-ux-polish-and-onboarding.md`, Task 1 Step 5
**Issue:** The grep `grep -rn "clipEditorSplit\b" VideoCompressor/` is fine, but the assumption that hits live in `VideoCompressorUITests/` is unverified. Probably no harm — grep returns nothing means no edit needed — but the plan should say so explicitly so Codex doesn't waste a step looking.
**Fix:** Pre-confirm UI test directory existence in the plan. Or change "Search for any `XCUIApplication()..." to "If `VideoCompressorUITests/` exists, search for ..." with conditional execution.
**Owner:** Plan author.

### M5. Cluster 2 Task 2 audio-mix test references undefined helpers `Self.makeShortVideoFixture(withAudio:)` and `Self.makePNGFixture()`
**File:** `docs/superpowers/plans/2026-05-04-phase1-cluster2-stitch-correctness.md`, Task 2 Step 1
**Issue:** Plan says "(Helpers `makeShortVideoFixture(withAudio:)` and `makePNGFixture()` may need adding to the test class. ... If not, add a private static `makeShortVideoFixture` that writes a 1-second 4×4 silent .mov via `AVAssetWriter` and add a 2-channel AAC track.)" — that's ~30 LOC of AVAssetWriter boilerplate left as an exercise. Codex will either hand-roll something subtly wrong or skip the test.
**Fix:** Either (a) include the fixture-helper code inline in the plan, OR (b) commit the helpers to a shared `TestFixtures.swift` first and reference from both Cluster 0 and Cluster 2 plans.
**Owner:** Plan author.

### M6. Cluster 0 Task 1 Step 2 expects the test to fail at compile time, but the test references `result.url` which doesn't exist on `URL` — this is a true compile failure, not a TDD-red runtime failure. The plan's "If Codex prefers a green-then-red approach, comment-out the new test temporarily" workaround is fine, but doesn't match the rest of the suite's pattern (other plans expect runtime test failures, not compile breaks).
**File:** `docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md`, Task 1 Step 2
**Issue:** Mostly cosmetic — Codex will hit a compile failure, see it as red, and proceed. But the inconsistency with how other plans phrase TDD-red ("expect 1 test failure") may confuse a strict subagent that's looking for "test ran, asserted, failed."
**Fix:** Standardize the language: explicitly say "build will fail" vs "test will run and fail."
**Owner:** Plan author.

---

## LOW / nits

### L1. Cluster 0 Task 7 Step 5 uses `TZ=Africa/Johannesburg` (SAST) for the session-log timestamp, but every other plan and the user's MEMORY.md say IST (Indian Standard Time)
`docs/superpowers/plans/2026-05-04-cluster0-hotfixes.md`, Task 7 Step 5: `TZ=Africa/Johannesburg date '+%Y-%m-%d %H:%M SAST'`. User's memory says IST. Switch to `TZ='Asia/Kolkata' date '+%Y-%m-%d %H:%M IST'`.

### L2. Cluster 2 Task 4 Step 1 test uses `await project.append(...)` and `await MainActor.run { ... }` interchangeably — `StitchProject` is `@MainActor`, so the `MainActor.run` is redundant.
Sub-issue of correctness, not behaviour. Tests still pass; just stylistic noise.

### L3. Cluster 3 Task 4's `ClipLongPressPreview` promotion from `private struct` to public `struct` is fine, but the plan doesn't mention that doing so might trigger SwiftUI's preview-cache to rebuild differently — minor, no fix needed, just an observation.

### L4. Effort estimates look optimistic — Cluster 3 alone has 7 tasks across 12h, and the inline guidance for any single task is ~2-3h. With test-debug loops the realistic minimum is ~16-18h.
Out of scope to "fix" but Codex/user should expect schedule slippage.

### L5. Cluster 2 plan's "Why" comment on Task 1 says HDR videos "wash to SDR" — verified. But the plan does NOT adjust the Task 4 ordering note: Task 4 (auto-sort) is added but the test count math at the end (`Total: 143`) omits the "+1" from auto-sort. (Actually re-read: it does account for it, "138 + 2 HDR + 1 audio-mix + 1 stage-collision + 1 auto-sort = 143." OK, no fix needed.)

### L6. Cluster 5 Task 4 Step 3 introduces `XCTAssertTrueAsync` / `XCTAssertFalseAsync` as private helpers in `PhotoMediaTests.swift` — fine, but the plan doesn't surface that this is a workaround for Swift's `XCTAssert*` macros not accepting async autoclosures. Future Codex sessions adding more async tests may duplicate. Recommend documenting in `AGENTS.md` Part 14 as a project convention.

---

## Cross-cluster file-edit conflict matrix

| File | Clusters touching it | Conflict risk | Recommended order |
|---|---|---|---|
| `CompressionService.swift` | 0 (retry, color, clamps), 1 (sweepOnCancel), 2 (HDR detection + Main10) | **MEDIUM-HIGH** — Cluster 0's clamp + color injection at lines 168-184; Cluster 2 layers HDR detection + Main10 profile around the same lines. | Cluster 0 → Cluster 2 → Cluster 1 (cache wiring is the smallest patch). Plan says Cluster 0 first, then Cluster 1, then Cluster 2 — disagree on the 2-vs-1 order; prefer 2 before 1 because Cluster 2's HDR detection rewrites the same `videoOutputSettings` and `compressionProps` blocks Cluster 0 just modified. |
| `StitchExporter.swift` | 0 (uses bake CGSize), 1 (still-bake refactor + audio-trail-defer), 2 (audio mix parity, scaleTimeRange, HDR), Cluster 5 (none) | **HIGH** — three clusters touch the bake region (lines 90-120) AND the segment loop (lines 220-260). | Cluster 0 → Cluster 1 → Cluster 2. Each rebases on top of the previous. Cluster 1's `predictedOutputURL` overload + Cluster 2's audio-track-per-segment fix don't overlap the same lines so a clean 3-way merge is feasible IF Cluster 0 lands first as planned. |
| `StitchTabView.swift` | 2 (auto-sort + stage collision), 3 (UX polish: copy + onboarding routing) | **LOW** — Cluster 2 touches `importClips` (line 242) + `stageToStitchInputs` (line 383). Cluster 3 changes `dominantKind` helper (different region). | Cluster 2 → Cluster 3. No line overlap. |
| `MetaCleanQueue.swift` | 1 (sweepAfterSave on success, optional), 3 (TaskGroup runBatch), 4 (ReviewPrompter wire-in), 5 (none) | **MEDIUM** — Cluster 3 rewrites `runBatch` wholesale (lines 220-276 → ~120 LOC of TaskGroup); Cluster 4 inserts a single-line call into `runClean` success at line 128. Cluster 1 may add `sweepAfterSave` calls. | Cluster 1 → Cluster 3 → Cluster 4. Cluster 1 lands a single-line addition in `runClean` success; Cluster 3 then wholesale-rewrites `runBatch` (a different function); Cluster 4 adds the ReviewPrompter call to `runClean`. All three target different lines. |
| `PhotoMetadataService.swift` | 1 (sweepOnCancel), 5 (registry wire-in + async cascade) | **MEDIUM** — Cluster 1 adds a single line to cancel branches; Cluster 5 makes `xmpContainsFingerprint`, `isFingerprintTag`, `makeTag` all `async`. The async cascade may touch the same `read(from:)` body Cluster 1 touches. | Cluster 1 → Cluster 5. Sequential. |
| `MetadataService.swift` | 1 (sweepOnCancel), 5 (registry wire-in + async cascade + new params on detector) | **MEDIUM** — Same pattern as PhotoMetadataService. Cluster 5's `await Self.isMetaGlassesFingerprint(...)` change at line 437 happens inside the same loop Cluster 1 may touch. | Cluster 1 → Cluster 5. |
| `SettingsTabView.swift` | 3 (Performance → Advanced disclosure + What-MetaClean explainer), 4 (Privacy Policy row) | **LOW** — Cluster 3 inserts at the top of the Form; Cluster 4 inserts at the bottom (after Storage). | Cluster 3 → Cluster 4. |
| `CompressionSettings.swift` | 0 (Max bitrate cap) | Single-cluster, no conflict. |
| `StillVideoBaker.swift` | 0 (return tuple), 1 (drop duration param + add intoPreallocated overload + wire to bakeImpl) | **HIGH** — Cluster 0 changes return type; Cluster 1 restructures the function body and adds 2 new entry points. | Cluster 0 → Cluster 1. Cluster 1 must update its plan's code blocks per H1. |
| `StitchTimelineView.swift` | 3 (Preview menu item, drop indicator polish, ClipLongPressPreview→public) | Single-cluster, no conflict. |
| `CropEditorView.swift` | 3 (whole-file rewrite) | Single-cluster, no conflict. |
| `PresetPickerView.swift` | 3 (Advanced disclosure split) | Single-cluster, no conflict. |
| `ContentView.swift` | 3 (onboarding fullScreenCover) | Single-cluster, no conflict. |

---

## What's GOOD (so we keep doing it)

- **Verbatim code blocks** in every plan — Codex doesn't have to interpret pseudocode. Massive reduction in execution variance.
- **TDD discipline is genuinely enforced** — every task has a "write failing test → run test (red) → write impl → run test (green) → commit" rhythm. The "expected `Total: N+X, Passed: N+X, Failed: 0`" callouts give Codex a hard verification target.
- **Cluster 0 + Cluster 5 plans are nearly execution-ready** — Cluster 0 needs only C4 fixed; Cluster 5 needs only C3 + H5 fixed. Both can ship after small edits.
- **Locked-decision capture in INDEX is excellent provenance** — 13 numbered decisions with the user's verbatim choice. Codex can reference these instead of re-asking.
- **Manual iPhone test prompts in every cluster** — addresses the user's stated requirement directly. They're real, walk-through-able tests, not synthetic.

---

## Bottom-line recommendation

Fix the 4 CRITICAL findings (especially **C2** — Cluster 2's audio architecture mismatch is the biggest landmine; Codex will get stuck there) and resolve **H1** (Cluster 1's plan code blocks need post-Cluster-0 signature updates) before letting Codex start. After those two fixes, Cluster 0 + Cluster 1 can ship today; Clusters 3-5 are mostly fine; Cluster 2 needs the most rework. **Don't ship Cluster 4 until the GitHub Pages URL choice (H6) is resolved by the user** — App Review profanity rejection is a real risk.

Single biggest risk: **C2** — Codex executing Cluster 2 Task 2 against the actual audio architecture will produce a half-correct rewrite that breaks existing transitions and audio mix. Stop and re-author Task 2 first.
