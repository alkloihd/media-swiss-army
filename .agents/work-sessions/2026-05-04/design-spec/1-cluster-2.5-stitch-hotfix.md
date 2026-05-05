# Cluster 2.5 — Stitch hotfix (P0, user-blocking)

> **For the executing agent:** Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. TDD red-then-green discipline. **Real-device verification BEFORE merging is non-negotiable** — the bug class only reproduces on iPhone hardware, not the simulator.

## Goal

Close the three real-device gaps the user reported on TestFlight today after Cluster 2 merged, ranked by user-pain.

## Branch

`fix/cluster-2.5-stitch-hotfix` off `main@6d7941e` (or whatever `main` is when work starts).

## Tech stack

Swift 5.9 / iOS 18 deployment target / SwiftUI / AVFoundation. No new dependencies. No `.github/workflows/testflight.yml` edits. No bundle id touches.

## File structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Models/StitchProject.swift` | Modify | Add `func clearAll() async` that empties `clips`, deletes their `sourceURL` files under `Documents/StitchInputs/`, resets `exportState` to `.idle`, and resets any export-related transient state. Idempotent. |
| `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` | Modify | Add an overflow toolbar item `"Start over"` (system image `arrow.counterclockwise.circle`) that calls `clearAll()` after a `.confirmationDialog`. Disable when `project.clips.isEmpty`. |
| `VideoCompressor/ios/Views/StitchTab/StitchExportSheet.swift` | Modify | After `saveStatus == .saved`, the sheet's primary CTA changes from "Save to Photos" to **"Done — start a new project"**. Tap → call `project.clearAll()` and dismiss the sheet. The existing "Export Again" button stays available for users who want to re-render before clearing. |
| `VideoCompressor/ios/Services/StitchExporter.swift` | Modify | Extend `stitchDownshift` table to cover Streaming + Custom: `Streaming → Streaming-no-transitions → small`. When the entire fallback chain exhausts, throw `CompressionError.encoderEnvelopeRejected(message:)` — a NEW error case carrying the user-friendly message below — instead of bubbling the raw `AVFoundationErrorDomain -11841`. |
| `VideoCompressor/ios/Models/CompressionError.swift` | Modify | Add `case encoderEnvelopeRejected(message: String)` with `displayMessage` returning the user-friendly string (see Task 2 step 3 below) and `recoverySuggestion` returning a one-line "Try removing transitions, splitting into shorter clips, or selecting a smaller preset." |
| `VideoCompressor/ios/Views/StitchTab/StitchExportSheet.swift` | Modify | Render `CompressionError.encoderEnvelopeRejected` inline in the export sheet (red banner with the friendly message) instead of as an `.alert`. Less intrusive, more readable. |
| `VideoCompressor/VideoCompressorTests/StitchProjectClearAllTests.swift` | Create | TDD coverage for `clearAll()` — empty list afterwards, files removed from disk, idempotent on repeated calls, idempotent on empty project. |
| `VideoCompressor/VideoCompressorTests/StitchExporterFallbackChainTests.swift` | Create | Synthetic `-11841` injection covering: Max → Balanced → Small full chain, Streaming → Streaming-no-transitions → Small, exhausted chain throws `encoderEnvelopeRejected` with the right message, no raw -11841 surfaces. |

## Tasks

### Task 1 — `StitchProject.clearAll()` + UI button

- [ ] **Step 1:** Write `StitchProjectClearAllTests` first. Cover (a) appends 3 clips, calls `clearAll()`, asserts `clips.isEmpty` AND each clip's `sourceURL` file no longer exists on disk; (b) calls `clearAll()` on an empty project — must not throw; (c) calls `clearAll()` twice in a row — second call must be a no-op.
- [ ] **Step 2:** `mcp__xcodebuildmcp__test_sim` — confirm the new test class fails to compile (no `clearAll()` method exists yet). That's the TDD red.
- [ ] **Step 3:** Implement `clearAll() async` in `StitchProject.swift`. For each clip, attempt `try? FileManager.default.removeItem(at: clip.sourceURL)` — best-effort, don't throw on missing files. Reset `clips = []`, `exportState = .idle`, `lastExportURL = nil`. Use `MainActor.run` if needed for the array mutation.
- [ ] **Step 4:** `test_sim` again — green.
- [ ] **Step 5:** Add the toolbar overflow item in `StitchTabView`. Use `.toolbar` `Menu` with `arrow.counterclockwise.circle.fill` symbol and label "Start over". Wrap the call site in `.confirmationDialog("Clear all \(project.clips.count) clips?", ...)` so the user can't tap-fat-finger their way to a wipe. Tapping the destructive option calls `Task { await project.clearAll() }`.
- [ ] **Step 6:** `build_sim` — confirm the toolbar renders.
- [ ] **Commit:** `feat(stitch): add Start Over with confirmation`

### Task 2 — Extended encoder fallback table + friendly error

- [ ] **Step 1:** Add `case encoderEnvelopeRejected(message: String)` to `CompressionError.swift`. `displayMessage` returns the supplied `message`; `recoverySuggestion` returns "Try removing transitions, splitting into shorter clips, or selecting a smaller preset."
- [ ] **Step 2:** Write `StitchExporterFallbackChainTests`. Inject a deterministic `-11841` once, then twice, then on every attempt. Assert: single rejection produces a `CompressionResult` with a fallback note; double rejection on Max produces note "We dropped transitions and used Balanced instead."; exhausted chain throws `encoderEnvelopeRejected` with message "Your iPhone's encoder couldn't handle this combination." — never surfaces raw `-11841`.
- [ ] **Step 3:** Implement `runReencodeWithTransitionFallback` extension in `StitchExporter.swift` that:
  - On first `-11841`: drop transitions, retry at same preset.
  - On second `-11841`: downshift one preset using a NEW table that handles ALL presets:
    - `Max → Balanced`
    - `Balanced → Small`
    - `Small → Small-no-transitions` (if transitions weren't already off)
    - `Streaming → Streaming-no-transitions → Small`
    - `Custom(...) → Small`
  - On third `-11841`: throw `CompressionError.encoderEnvelopeRejected(message: "Your iPhone's encoder couldn't handle this combination.")`
- [ ] **Step 4:** `test_sim` — green for both new tests + all existing 248 passing tests + 1 skip = expect 252+ green.
- [ ] **Step 5:** Render `encoderEnvelopeRejected` in `StitchExportSheet` as an inline red banner (`Label` + `RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.1))`) showing message + recovery suggestion. NOT an alert.
- [ ] **Commit:** `fix(stitch): exhaustive fallback table + friendly error message`

### Task 3 — Auto-prompt to start new project after Save

- [ ] **Step 1:** In `StitchExportSheet.swift`, when `saveStatus == .saved`, replace the existing primary-CTA-area with a vertically stacked pair of buttons:
  - Primary (`.borderedProminent`): "Done — start a new project" → `await project.clearAll(); dismiss()`
  - Secondary (`.bordered`): "Export Again" (existing behavior preserved)
- [ ] **Step 2:** `build_sim` and verify in MCP UI snapshot the post-save layout shows both buttons.
- [ ] **Commit:** `feat(stitch): post-save Done CTA returns to a clean session`

### Task 4 — Real-device verification + PR

- [ ] **Step 1:** `mcp__xcodebuildmcp__test_sim` final pass — expect 252+ green.
- [ ] **Step 2:** `mcp__xcodebuildmcp__build_sim` clean.
- [ ] **Step 3 (NEW REQUIREMENT):** Append a `[BLOCKED]` line to today's `AI-CHAT-LOG.md`:
  `[YYYY-MM-DD HH:MM SAST] [solo/codex/<model>] [BLOCKED] Cluster 2.5 ready for real-device verification — install latest TestFlight, test stitch + Random transition + Small preset, test re-render after save, test Start Over button. Will not merge until user confirms via [DECISION] line. Continuing on Cluster 3.5 spec meanwhile.`
- [ ] **Step 4:** Open PR with the title `fix(stitch): clear-all + exhaustive fallback + post-save start-new-project`.
- [ ] **Step 5:** Wait for the user's `[DECISION]` line (Claude relays it) confirming real-device pass before merging. If user reports failure, do NOT auto-merge — file new findings into AI-CHAT-LOG and pivot to fix.

## Acceptance criteria

- [ ] `StitchTabView` has a "Start over" overflow toolbar action with confirmation
- [ ] `StitchProject.clearAll()` exists, is tested, removes both list and disk files
- [ ] No raw `AVFoundationErrorDomain -11841` ever surfaces to the user — replaced by friendly message
- [ ] All 4 named presets + Custom have a fallback path through the encoder rejection chain
- [ ] After saving to Photos, the user sees a primary "Done — start a new project" CTA
- [ ] **User has installed the resulting TestFlight build and confirmed all three flows work on iPhone 18 hardware**

## Notes for the executing agent

- Sim tests are NECESSARY but not SUFFICIENT for this PR. The user's bug class (`-11841` envelope rejection) does not reproduce on the iPhone 16 Pro simulator — the simulator's HW encoder is far more permissive than real iPhone 18 silicon. Real-device gate is enforced via the `[BLOCKED]` protocol above.
- Reviewer subagents have a habit of timing out on this codebase. Use the existing 1-strike-then-static-diff fallback policy — do not retry a hung reviewer.
- Keep commits atomic per task. Three commits + the PR.
