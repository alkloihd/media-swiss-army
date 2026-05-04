# Phase 2 Cluster 3 — UX Polish + Onboarding

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to walk this plan task-by-task. All steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the entire Phase 2 polish pass in a single PR — copy cleanup, first-launch onboarding, settings explainer, long-press preview discoverability, drop-indicator polish, faster batch MetaClean with single-toast save, and frontend simplifications. After this lands the app reads as a $4.99 paid utility, not an engineering tool.

Covers MASTER-PLAN tasks 2.1 → 2.7:
- 2.1 Dev-y copy polish (~2h) — friendlier batch labels, `print()` calls behind `#if DEBUG`, deduplicate scissors, soften `BatchCleanProgress` strings.
- 2.2 First-launch 3-card onboarding (~3h) — new `Views/Onboarding/OnboardingView.swift`, `.fullScreenCover` from `ContentView.swift`, `@AppStorage("hasSeenOnboarding_v1")`, "Get started" lands on MetaClean.
- 2.3 Settings "What MetaClean does" explainer (~1h) — verbatim `AUDIT-08` Part A copy as the FIRST section in `SettingsTabView.swift`.
- 2.4 Long-press preview "Preview" menu item (~1h) — keep `.contextMenu(preview:)` overlay (locked decision #3); add `Label("Preview", systemImage: "play.rectangle")` as the FIRST context-menu item.
- 2.5 Drop indicator polish (~30min) — bump 6pt → 8pt accent bar, 12pt animated `.padding(.leading)` on the target clip, accent shadow.
- 2.6 Faster batch MetaClean (~3h) — `TaskGroup` with N=2 concurrency on Pro phones via `DeviceCapabilities.currentSafeConcurrency()`, single end-of-batch save toast routed through `VideoLibrary`.
- 2.7 Frontend simplifications (~2h) — Compress presets default-show Balanced + Small (Max + Streaming + Custom under "Advanced"); remove all four XYWH `Slider` rows from `CropEditorView.swift` and replace with 4 aspect-ratio preset buttons; move Settings → Performance section into a `DisclosureGroup("Advanced")`.

**Architecture:** All seven tasks touch UI surface only — no service-layer behaviour change except `MetaCleanQueue.runBatch` (concurrency hop) and one `VideoLibrary` save-toast publish. Landing as one PR keeps the Phase 2 polish atomic in a single TestFlight cycle.

**Tech Stack:** Swift, SwiftUI (`@AppStorage`, `.fullScreenCover`, `DisclosureGroup`, `TabView(...) selection`, `withAnimation`), `TaskGroup`, XCTest.

**Branch:** `feat/codex-cluster3-ux-polish` off `feat/phase-2-features-may3` (the integration branch already checked out). Cluster 3 lands AFTER clusters 1 and 2 merge to `main` per `2026-05-04-PHASES-1-3-INDEX.md`. Test counts in this plan assume the upstream baseline of **138 tests from `main` PLUS whatever clusters 1 + 2 added**. If you ran cluster 1 (+11) and cluster 2 (+4) first, the starting baseline is **153**. If you're working off raw `main`, the baseline is **138**. Adjust the numbered expectations accordingly — this plan tracks **delta** counts (`+N new`) so the absolute is whatever your starting point was plus the delta.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/ContentView.swift` | Modify | Present `OnboardingView` via `.fullScreenCover` gated by `@AppStorage("hasSeenOnboarding_v1")`. Bind `selectedTab` so the "Get started" button can route to `.metaClean`. |
| `VideoCompressor/ios/Views/Onboarding/OnboardingView.swift` | Create | New 3-card paged onboarding (`TabView` w/ `.page` style). Card order: MetaClean (headline) → Compress → Stitch. "Get started" sets `hasSeenOnboarding_v1 = true` and selects `.metaClean`. |
| `VideoCompressor/ios/Views/SettingsTabView.swift` | Modify | Add `Section("What MetaClean does")` as the FIRST section (above Background-Encoding). Wrap the existing Performance section in `DisclosureGroup("Advanced")`. |
| `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift` | Modify | Soften `"Cleaning N of M"` → `"Cleaning your photos · 3 of 8"`. Listen for `library.lastBatchSaveCount` and show a single end-of-batch toast. |
| `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanExportSheet.swift` | Modify | Soften `"Cleaning… NN%"` → `"Cleaning your photo…"` / `"Cleaning your video…"`. |
| `VideoCompressor/ios/Views/StitchTab/ClipEditorInlinePanel.swift` | Modify | Remove the duplicate scissors `Image` from the header toolbar (lines 198–205); the prominent "Split at Playhead" button at line 257 stays. |
| `VideoCompressor/ios/Views/StitchTab/ClipEditorSheet.swift` | Modify | Wrap `print(...)` in `#if DEBUG`. (Single call site at line 40.) |
| `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift` | Modify | Add `Label("Preview", systemImage: "play.rectangle")` as the FIRST item in `clipContextMenu` (currently Duplicate / Move / Delete). Bump drop-indicator capsule 6pt → 8pt; add 12pt `.padding(.leading)` on the wrapped `ClipBlockView` when the clip is the drop target; add accent shadow. |
| `VideoCompressor/ios/Views/PresetPickerView.swift` | Modify | Split `videoPresetList` into a default ForEach (Balanced + Small only) plus a `DisclosureGroup("Advanced")` containing Max + Streaming + Custom (custom = the existing `showAdvanced` summary panel). |
| `VideoCompressor/ios/Views/StitchTab/CropEditorView.swift` | Modify | Remove the four `Slider` rows + the `cropSlider` builder + the four binding helpers. Replace with 4 aspect-ratio buttons (Square / 9:16 / 16:9 / Free). Keep the `commit(_:)` + `isApproximatelyIdentity(_:)` helpers. |
| `VideoCompressor/ios/Services/MetaCleanQueue.swift` | Modify | `runBatch` switches from `for ... in ids` to `withTaskGroup` with `maxConcurrent = DeviceCapabilities.currentSafeConcurrency()`. After loop completes, publish `library.notifySaveBatchCompleted(count:)` if `replaceOriginals == true`. Soften `BatchCleanProgress.lastError` formatting only — the struct itself stays the same. |
| `VideoCompressor/ios/Services/VideoLibrary.swift` | Modify | Add `@Published var lastSaveBatch: SaveBatchResult?` + `func notifySaveBatchCompleted(count: Int)` (public, mirrors `lastError` shape). |
| `VideoCompressor/VideoCompressorTests/OnboardingGateTests.swift` | Create | Pure-logic test for the gating decision: `OnboardingGate(hasSeen: false).shouldPresent == true`; after `markSeen()`, `shouldPresent == false`. |
| `VideoCompressor/VideoCompressorTests/CropEditorPresetTests.swift` | Create | Pure-logic test for the new aspect-preset rect math: square in 16:9 frame produces a `cropNormalized` rect with width < 1.0; "Free" sets the rect to nil; etc. |
| `VideoCompressor/VideoCompressorTests/MetaCleanCopyTests.swift` | Create | Pure-string test for the new `BatchCleanProgress.userFacingLabel(...)` helper: 1 file → `"Cleaning your photo…"`, batch → `"Cleaning your photos · 3 of 8"`. |
| `VideoCompressor/VideoCompressorTests/MetaCleanQueueConcurrencyTests.swift` | Create | TaskGroup-based batch ordering test: 4 fake items, asserts `runBatch` completes all 4 and that `batchProgress.current` ends at total even with concurrency=2. |

---

## Task 1: Dev-y copy polish (Phase 2.1)

**Why first:** Quick wins that free the rest of the work from "engineer copy" smell. Three small surgical edits across two files, plus wrapping the lone `print(...)` call in `#if DEBUG`.

- [ ] **Step 1: Write a failing test for the user-facing batch label**

Create `VideoCompressor/VideoCompressorTests/MetaCleanCopyTests.swift`:

```swift
//
//  MetaCleanCopyTests.swift
//  VideoCompressorTests
//
//  Pins the user-facing batch progress copy. Per AUDIT-05 H1 the
//  prior "Cleaning N of M" wording reads as engineer telemetry; this
//  test guards the friendlier copy from regressing.
//

import XCTest
@testable import VideoCompressor_iOS

final class MetaCleanCopyTests: XCTestCase {

    func testSinglePhotoLabel() {
        let p = BatchCleanProgress(
            current: 1, total: 1, failed: 0,
            perItem: .zero, isRunning: true, lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .still), "Cleaning your photo…")
    }

    func testSingleVideoLabel() {
        let p = BatchCleanProgress(
            current: 1, total: 1, failed: 0,
            perItem: .zero, isRunning: true, lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .video), "Cleaning your video…")
    }

    func testBatchLabel() {
        let p = BatchCleanProgress(
            current: 3, total: 8, failed: 0,
            perItem: .zero, isRunning: true, lastError: nil
        )
        // U+2003 EM SPACE around the middle dot — reads as "supporting
        // detail" not "raw counter" per AUDIT-05 H1.
        XCTAssertEqual(p.userFacingLabel(kind: .still), "Cleaning your photos\u{2003}·\u{2003}3 of 8")
    }

    func testTerminalLabelPrefersPastTense() {
        // After the batch finishes the UI flips to a terminal label.
        let p = BatchCleanProgress(
            current: 8, total: 8, failed: 0,
            perItem: .complete, isRunning: false, lastError: nil
        )
        XCTAssertEqual(p.userFacingLabel(kind: .still), "Cleaned 8 photos")
    }
}
```

The test uses `MediaKind` (`.video` / `.still`) which already exists in the model layer (`VideoCompressor/ios/Models/MetaCleanItem.swift`). The compiled symbol `BatchCleanProgress.userFacingLabel(kind:)` doesn't exist yet — that's the TDD red.

Run: `mcp__xcodebuildmcp__test_sim` — expect a compile failure pointing at the missing helper. That's correct.

- [ ] **Step 2: Add `userFacingLabel(kind:)` to `BatchCleanProgress`**

In `VideoCompressor/ios/Services/MetaCleanQueue.swift`, append to the `BatchCleanProgress` struct (after the existing `fraction` computed property):

```swift
    /// User-facing copy for the progress label. Per AUDIT-05 H1 the
    /// raw `"Cleaning N of M"` reads as engineer telemetry; this returns
    /// human copy that shows the count after a colon as supporting detail.
    func userFacingLabel(kind: MediaKind) -> String {
        let noun = kind == .still ? "photo" : "video"
        let nounPlural = kind == .still ? "photos" : "videos"

        if !isRunning {
            // Terminal — past tense, plural-aware.
            return total == 1
                ? "Cleaned 1 \(noun)"
                : "Cleaned \(total) \(nounPlural)"
        }

        if total <= 1 {
            return "Cleaning your \(noun)…"
        }
        // Batch — em-space around the middle dot so the count reads as
        // a sub-clause, not the whole sentence.
        return "Cleaning your \(nounPlural)\u{2003}·\u{2003}\(current) of \(total)"
    }
```

- [ ] **Step 3: Wire the helper into `MetaCleanTabView` + `MetaCleanExportSheet`**

In `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift`, around line 201 (inside `batchControls`), replace:

```swift
                        Text("Cleaning \(queue.batchProgress.current) of \(queue.batchProgress.total)")
                            .font(.caption.monospacedDigit())
```

with:

```swift
                        Text(queue.batchProgress.userFacingLabel(kind: dominantKind))
                            .font(.caption.monospacedDigit())
                            .accessibilityIdentifier("metaCleanBatchProgressLabel")
```

Then add this computed helper near the top of the `MetaCleanTabView` struct (after `@State private var selectedItem: MetaCleanItem?`):

```swift
    /// The "majority" kind in the current queue — drives the singular/plural
    /// noun in the batch progress label. If the queue is mixed, prefer the
    /// kind with more items; ties prefer `.still` since MetaClean is the
    /// headline product (per AUDIT-08 Part A and locked decision #3).
    private var dominantKind: MediaKind {
        let stills = queue.items.filter { $0.kind == .still }.count
        let videos = queue.items.filter { $0.kind == .video }.count
        return stills >= videos ? .still : .video
    }
```

In `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanExportSheet.swift` line 85, replace:

```swift
            Text("Cleaning… \(queue.cleanProgress.percent)%")
```

with:

```swift
            Text(item.kind == .still ? "Cleaning your photo…" : "Cleaning your video…")
                .font(.subheadline)
            Text("\(queue.cleanProgress.percent)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
```

(The `item` reference is already in scope inside this view — it's the parameter passed to `MetaCleanExportSheet`. Verify by grepping `let item` or `item:` near the top of the file before editing.)

- [ ] **Step 4: Wrap the `ClipEditorSheet` `print(...)` in `#if DEBUG`**

In `VideoCompressor/ios/Views/StitchTab/ClipEditorSheet.swift` line 40, replace:

```swift
                        print("[ClipEditorSheet] clip \(clipID) not found — dismissing")
```

with:

```swift
                        #if DEBUG
                        print("[ClipEditorSheet] clip \(clipID) not found — dismissing")
                        #endif
```

(Verify there are no other `print(` calls left in `VideoCompressor/ios/Views/` or `VideoCompressor/ios/Services/` by re-running `grep -rn "^\s*print(" VideoCompressor/ios/`. As of the audit there's exactly one — but if any new one slipped in between the audit and now, wrap it the same way.)

- [ ] **Step 5: Deduplicate the scissors icon in the inline editor**

In `VideoCompressor/ios/Views/StitchTab/ClipEditorInlinePanel.swift`, delete the entire scissors `Button { splitAtPlayhead() } label: ...` block at lines 198–205:

```swift
            Button {
                splitAtPlayhead()
            } label: {
                Image(systemName: "scissors")
            }
            .disabled(!canSplitAtPlayhead)
            .accessibilityLabel("Split at playhead")
            .accessibilityIdentifier("clipEditorSplit")
```

The prominent "Split at Playhead" labeled button at line 257 (`splitButtonRow`) stays — one scissors action per panel, not two. Tests that reference `clipEditorSplit` should be updated to use `clipEditorSplitButton` (the `accessibilityIdentifier` already on the labeled button at line 267).

- [ ] **Step 5: Update UI tests if they reference the deduplicated scissors**

```bash
if [ -d VideoCompressor/VideoCompressorUITests ]; then
    grep -rn 'clipEditorSplit\|"Split at Playhead"' VideoCompressor/VideoCompressorUITests/
fi
```

If `VideoCompressorUITests/` does not exist (likely — the project's 138 tests are all unit tests), skip this step. If it exists, update any references to the now-removed scissors icon: replace `clipEditorSplit` with `clipEditorSplitButton` (the `accessibilityIdentifier` already on the labeled button at line 267).

(You can also confirm directory presence up front: `ls VideoCompressor/VideoCompressorUITests/ 2>&1 || echo "no UI test target"`.)

> **Note for executing agent (as of 2026-05-04):** The directory `VideoCompressor/VideoCompressorUITests/` exists but contains only launch-test stubs (`VideoCompressorUITests.swift`, `VideoCompressorUITestsLaunchTests.swift`). These do not reference `clipEditorSplit`. The step is effectively a no-op on this codebase — include the conditional check above so any future UI test additions are caught automatically.

- [ ] **Step 6: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: baseline + 4 new (one per `MetaCleanCopyTests` method). Output line `Total: <N+4>, Passed: <N+4>, Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add VideoCompressor/ios/Services/MetaCleanQueue.swift \
        VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift \
        VideoCompressor/ios/Views/MetaCleanTab/MetaCleanExportSheet.swift \
        VideoCompressor/ios/Views/StitchTab/ClipEditorSheet.swift \
        VideoCompressor/ios/Views/StitchTab/ClipEditorInlinePanel.swift \
        VideoCompressor/VideoCompressorTests/MetaCleanCopyTests.swift
git commit -m "feat(ux): friendlier batch copy + #if DEBUG print + dedup scissors (Phase 2.1)

Resolves MASTER-PLAN 2.1 / AUDIT-05 H1 + H2 + M5:
- BatchCleanProgress now has userFacingLabel(kind:) returning
  'Cleaning your photos · 3 of 8' (em-space) instead of the
  engineer-flavored 'Cleaning N of M'.
- MetaCleanExportSheet shows 'Cleaning your photo…' / 'Cleaning your
  video…' before the percent.
- ClipEditorSheet's debug print() is now wrapped in #if DEBUG.
- ClipEditorInlinePanel header no longer has a duplicate scissors
  icon — only the prominent labeled 'Split at Playhead' button stays.

4 new MetaCleanCopyTests pin the new copy."
```

**Effort: ~2h. ~1 commit cumulatively.**

---

## Task 2: First-launch 3-card onboarding (Phase 2.2)

**Why:** AUDIT-05 C2 + AUDIT-08 Part A1. A first-time user opens the app and gets dropped on the Compress tab with zero context. MetaClean is the headline product but it's the third tab — onboarding teaches the brand and routes the user there.

- [ ] **Step 1: Write a failing test for the gate logic**

Create `VideoCompressor/VideoCompressorTests/OnboardingGateTests.swift`:

```swift
//
//  OnboardingGateTests.swift
//  VideoCompressorTests
//
//  Pure-logic tests for the first-launch onboarding gate. The gate is
//  isolated from SwiftUI so the decision logic can be exercised without
//  presenting the actual sheet.
//

import XCTest
@testable import VideoCompressor_iOS

final class OnboardingGateTests: XCTestCase {

    func testFreshInstallShouldPresent() {
        let gate = OnboardingGate(hasSeen: false)
        XCTAssertTrue(gate.shouldPresent)
    }

    func testAfterMarkSeenShouldNotPresent() {
        var gate = OnboardingGate(hasSeen: false)
        XCTAssertTrue(gate.shouldPresent)
        gate.markSeen()
        XCTAssertFalse(gate.shouldPresent)
    }

    func testRehydrationFromSeenStateShouldNotPresent() {
        let gate = OnboardingGate(hasSeen: true)
        XCTAssertFalse(gate.shouldPresent)
    }

    func testGetStartedRoutesToMetaClean() {
        // The "Get started" button on the final card sets the gate AND
        // declares which tab to land on. Locked decision #4: MetaClean.
        let gate = OnboardingGate(hasSeen: false)
        XCTAssertEqual(gate.landingTab, .metaClean)
    }
}
```

Run: `mcp__xcodebuildmcp__test_sim` — expect compile failure on `OnboardingGate` and `landingTab`. That's the TDD red.

- [ ] **Step 2: Create the `OnboardingView` + `OnboardingGate`**

First, ensure the directory exists:

```bash
mkdir -p VideoCompressor/ios/Views/Onboarding
```

Then create `VideoCompressor/ios/Views/Onboarding/OnboardingView.swift`:

```swift
//
//  OnboardingView.swift
//  VideoCompressor
//
//  First-launch 3-card paged onboarding. Gated by
//  @AppStorage("hasSeenOnboarding_v1") in ContentView. Cards are
//  ordered MetaClean (headline) → Compress → Stitch per locked
//  decision #3 + AUDIT-08 Part A1.
//
//  Copy: from AUDIT-08 Part A and MASTER-PLAN.md Phase 2.2.
//

import SwiftUI

/// Pure-logic gate for the onboarding decision. Isolated from SwiftUI
/// so OnboardingGateTests can exercise it without presenting the sheet.
struct OnboardingGate {
    private(set) var hasSeen: Bool

    /// True iff the onboarding sheet should be presented this launch.
    var shouldPresent: Bool { !hasSeen }

    /// Where the "Get started" button should route the user. Locked
    /// decision #3 + AUDIT-08 Part A1: MetaClean is the headline.
    var landingTab: AppTab { .metaClean }

    mutating func markSeen() {
        hasSeen = true
    }
}

struct OnboardingView: View {
    /// Closure invoked when the user taps "Get started" on the final
    /// card. The parent (ContentView) flips
    /// `@AppStorage("hasSeenOnboarding_v1") = true` AND switches
    /// `selectedTab = .metaClean`.
    let onFinish: () -> Void

    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                metaCleanCard.tag(0)
                compressCard.tag(1)
                stitchCard.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            primaryButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Cards

    private var metaCleanCard: some View {
        card(
            symbol: "eye.slash",
            title: "Strip Meta AI fingerprints",
            body: "Photos and videos shot on Ray-Ban Meta and Oakley Meta glasses carry a hidden marker. MetaClean removes only that marker — your date, location, and camera info stay intact."
        )
    }

    private var compressCard: some View {
        card(
            symbol: "wand.and.stars",
            title: "Shrink before sharing",
            body: "Apple's hardware encoder. Smart bitrate caps. Smaller files, same look. Nothing leaves your device."
        )
    }

    private var stitchCard: some View {
        card(
            symbol: "square.stack.3d.up",
            title: "Stitch clips together",
            body: "Drag-to-reorder, native AVFoundation transitions, fully on-device. Up to 50 clips per project."
        )
    }

    private func card(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Button

    @ViewBuilder
    private var primaryButton: some View {
        Button {
            if page < 2 {
                withAnimation(.easeInOut(duration: 0.20)) { page += 1 }
            } else {
                onFinish()
            }
        } label: {
            Text(page < 2 ? "Next" : "Get started")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("onboardingPrimaryButton")
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
```

- [ ] **Step 3: Wire `OnboardingView` into `ContentView` via `.fullScreenCover`**

In `VideoCompressor/ios/ContentView.swift`, replace the entire struct body so the tab is bindable AND the cover is presented on first launch:

```swift
struct ContentView: View {
    @State private var selectedTab: AppTab = .compress
    @AppStorage("hasSeenOnboarding_v1") private var hasSeenOnboarding: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            VideoListView()
                .tabItem {
                    Label("Compress", systemImage: AppTab.compress.symbolName)
                }
                .tag(AppTab.compress)

            StitchTabView()
                .tabItem {
                    Label("Stitch", systemImage: AppTab.stitch.symbolName)
                }
                .tag(AppTab.stitch)

            MetaCleanTabView()
                .tabItem {
                    Label("MetaClean", systemImage: AppTab.metaClean.symbolName)
                }
                .tag(AppTab.metaClean)

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: AppTab.settings.symbolName)
                }
                .tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView {
                hasSeenOnboarding = true
                selectedTab = .metaClean
            }
        }
    }
}
```

The `enum AppTab` and `#Preview` blocks at the bottom of `ContentView.swift` stay unchanged.

- [ ] **Step 4: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: baseline + 4 new (Task 1) + 4 new (Task 2) = baseline + 8.

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Views/Onboarding/OnboardingView.swift \
        VideoCompressor/ios/ContentView.swift \
        VideoCompressor/VideoCompressorTests/OnboardingGateTests.swift
git commit -m "feat(onboarding): first-launch 3-card paged sheet (Phase 2.2)

Resolves MASTER-PLAN 2.2 / AUDIT-05 C2 / AUDIT-08 Part A1. A first-time
user now sees a 3-card paged TabView on launch:
  1. MetaClean (headline) — 'Strip Meta AI fingerprints'
  2. Compress — 'Shrink before sharing'
  3. Stitch — 'Stitch clips together'

The 'Get started' button on the final card flips
@AppStorage('hasSeenOnboarding_v1') to true AND routes selectedTab to
.metaClean (locked decision #3).

Gate logic isolated as struct OnboardingGate so it's testable without
presenting the SwiftUI sheet — OnboardingGateTests has 4 cases covering
fresh install, post-mark-seen, rehydration, and landing-tab choice."
```

**Effort: ~3h. ~2 commits cumulatively.**

---

## Task 3: Settings "What MetaClean does" explainer (Phase 2.3)

**Why:** AUDIT-05 M3 + AUDIT-08 Part A2. A reviewer landing in Settings has nowhere to read what the headline product actually does. Verbatim copy from `AUDIT-08` Part A2.

- [ ] **Step 1: Add the explainer Section as the FIRST section in `SettingsTabView`**

In `VideoCompressor/ios/Views/SettingsTabView.swift`, just inside the `Form { ... }` block (above the existing `// MARK: Background encoding` line at 24), insert:

```swift
                // MARK: What MetaClean does (Phase 2.3 / AUDIT-08 Part A2)
                Section("What MetaClean does") {
                    Text(
                        "MetaClean strips the hidden fingerprint that Meta AI glasses (Ray-Ban Meta, Oakley Meta) embed in every photo and video. The fingerprint is a binary marker in the file's metadata that tells anyone — Instagram, journalists, scrapers — \"this was shot on Meta hardware.\""
                    )
                    .font(.subheadline)

                    DisclosureGroup("What gets removed") {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("The Meta fingerprint atom (binary Comment / Description blob with Ray-Ban / Meta / RayBan markers)", systemImage: "circle.fill")
                                .labelStyle(.titleOnly)
                            Label("XMP packets tagged with the same fingerprint", systemImage: "circle.fill")
                                .labelStyle(.titleOnly)
                            Label("Optional: full strip of GPS, dates, camera info if you tap \"Scrub everything\"", systemImage: "circle.fill")
                                .labelStyle(.titleOnly)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("What stays") {
                        Text(
                            "Date taken. Location. Camera make and model. Live Photo identifiers. HDR gain map. Color profile. Orientation. Everything that makes your photos work properly in Photos."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("What MetaClean never does") {
                        Text(
                            "No accounts. No cloud. No analytics. No tracking. The only network calls this app makes are App Store updates handled by iOS itself."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settingsWhatMetaCleanDoesSection")
```

- [ ] **Step 2: Run tests + smoke-build**

```
mcp__xcodebuildmcp__test_sim
mcp__xcodebuildmcp__build_sim
```

Expected: tests unchanged from Task 2 (no new tests this task — pure SwiftUI text). Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add VideoCompressor/ios/Views/SettingsTabView.swift
git commit -m "feat(settings): 'What MetaClean does' explainer (Phase 2.3)

Resolves MASTER-PLAN 2.3 / AUDIT-05 M3 / AUDIT-08 Part A2. New section
is now the FIRST in SettingsTabView (above Background-Encoding).

Verbatim copy from AUDIT-08 Part A: a 1-paragraph explainer + three
DisclosureGroups (What gets removed / What stays / What MetaClean
never does). No code in services changed; pure SwiftUI Text."
```

**Effort: ~1h. ~3 commits cumulatively.**

---

## Task 4: Long-press preview "Preview" menu item (Phase 2.4)

**Why:** Locked decision #3 + AUDIT-05 M2. Keep the `.contextMenu(preview:)` overlay (standard iOS pattern, two intents: peek vs. edit). Add a `Label("Preview", systemImage: "play.rectangle")` as the FIRST menu item so users who don't naturally long-press can still discover and reach the preview via the menu.

- [ ] **Step 1: Add a `previewClipID` state + Preview menu item**

In `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift`, add a state property near the other `@State` declarations (after line 52, `@State private var dropTargetID`):

```swift
    /// When non-nil, render the long-press preview pane in a sheet —
    /// triggered by tapping the new "Preview" context-menu item. The
    /// long-press gesture STILL works as before (it presents the iOS
    /// built-in preview overlay); this is the discoverability path
    /// for users who never long-press.
    @State private var previewClipID: StitchClip.ID?
```

Then in `clipContextMenu(for:)` (around line 186–208), insert the Preview button as the FIRST item, BEFORE the existing Duplicate button:

```swift
    @ViewBuilder
    private func clipContextMenu(for clip: StitchClip) -> some View {
        Button {
            previewClipID = clip.id
        } label: {
            Label("Preview", systemImage: "play.rectangle")
        }
        Divider()
        Button {
            duplicate(clip: clip)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            moveToStart(clip: clip)
        } label: {
            Label("Move to Start", systemImage: "arrow.left.to.line")
        }
        Button {
            moveToEnd(clip: clip)
        } label: {
            Label("Move to End", systemImage: "arrow.right.to.line")
        }
        Divider()
        Button(role: .destructive) {
            deleteClip(clip)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
```

- [ ] **Step 2: Present `ClipLongPressPreview` in a sheet when `previewClipID` is set**

At the end of the outer `ScrollView` chain (around line 180, after the `.gesture(MagnificationGesture()...)` modifier), add:

```swift
        .sheet(item: Binding(
            get: { previewClipID.flatMap { id in project.clips.first { $0.id == id } } },
            set: { newValue in previewClipID = newValue?.id }
        )) { clip in
            // Reuse the same preview view used by the long-press overlay
            // so the visual is identical regardless of how the user got
            // there. Wrap in a vertically-padded NavigationStack so the
            // sheet has a Done button.
            NavigationStack {
                ClipLongPressPreview(clip: clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                    .navigationTitle(clip.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { previewClipID = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
```

(Note: `ClipLongPressPreview` is `private struct` at line 265. Promote it to `struct` (drop the `private` keyword) so the sheet can reference it. This is the only structural change needed.)

In `StitchTimelineView.swift` line 265, replace:

```swift
private struct ClipLongPressPreview: View {
```

with:

```swift
struct ClipLongPressPreview: View {
```

- [ ] **Step 3: Run tests + smoke-build**

```
mcp__xcodebuildmcp__test_sim
mcp__xcodebuildmcp__build_sim
```

Expected: tests unchanged. Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift
git commit -m "feat(stitch): 'Preview' as first context-menu item (Phase 2.4)

Resolves MASTER-PLAN 2.4 / AUDIT-05 M2. Per locked decision #3 we
KEEP the long-press .contextMenu(preview:) overlay (standard iOS
pattern matching Photos.app) and ADD a discoverability path for users
who don't naturally long-press: a 'Preview' menu item now appears as
the FIRST entry in the clip context menu, above Duplicate / Move /
Delete.

Tapping Preview presents the same ClipLongPressPreview view in a
.sheet with .medium / .large presentation detents, so the visual is
identical to the long-press overlay regardless of entry path.

ClipLongPressPreview was promoted from private struct → struct so
the sheet outside the file scope can reference it."
```

**Effort: ~1h. ~4 commits cumulatively.**

---

## Task 5: Drop indicator polish (Phase 2.5)

**Why:** AUDIT-05 M1. The 6pt accent capsule at `StitchTimelineView.swift:74-81` is hard to see at low zoom and doesn't push neighbors aside. Photos.app uses a wider bar with a gutter and a soft accent shadow.

- [ ] **Step 1: Bump capsule width 6pt → 8pt + add accent shadow**

In `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift`, replace lines 74–81:

```swift
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(
                                width: dropTargetID == clip.id && draggedID != clip.id ? 6 : 0,
                                height: baseClipHeight * zoom * 0.85
                            )
                            .padding(.trailing, dropTargetID == clip.id && draggedID != clip.id ? 4 : 0)
                            .animation(.easeInOut(duration: 0.15), value: dropTargetID)
```

with:

```swift
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(
                                width: dropTargetID == clip.id && draggedID != clip.id ? 8 : 0,
                                height: baseClipHeight * zoom * 0.85
                            )
                            .shadow(
                                color: dropTargetID == clip.id && draggedID != clip.id
                                    ? Color.accentColor.opacity(0.4)
                                    : .clear,
                                radius: 6
                            )
                            .padding(.trailing, dropTargetID == clip.id && draggedID != clip.id ? 4 : 0)
                            .animation(.easeInOut(duration: 0.20), value: dropTargetID)
```

- [ ] **Step 2: Add 12pt animated `.padding(.leading)` on the wrapped clip**

A few lines down (the `ClipBlockView(clip: clip).frame(...)` at line 83), wrap that frame with the new neighbor-push padding so the surrounding HStack visibly breathes apart when this clip is the drop target.

Replace lines 83–84:

```swift
                    ClipBlockView(clip: clip)
                        .frame(width: baseClipWidth * zoom, height: baseClipHeight * zoom)
```

with:

```swift
                    ClipBlockView(clip: clip)
                        .frame(width: baseClipWidth * zoom, height: baseClipHeight * zoom)
                        .padding(.leading, dropTargetID == clip.id && draggedID != clip.id ? 12 : 0)
                        .animation(.easeInOut(duration: 0.20), value: dropTargetID)
```

(The two `.animation(...)` modifiers — one on the capsule and one on the clip — can use the same duration so the gutter and the neighbor-push move in lock-step.)

- [ ] **Step 3: Run tests + smoke-build**

```
mcp__xcodebuildmcp__test_sim
mcp__xcodebuildmcp__build_sim
```

Expected: tests unchanged. Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift
git commit -m "feat(stitch): drop indicator polish — 8pt bar + gutter + glow (Phase 2.5)

Resolves MASTER-PLAN 2.5 / AUDIT-05 M1. The 6pt accent bar was hard
to see at low zoom and the surrounding HStack didn't breathe apart
when a drop target lit up.

Changes:
- Capsule width 6pt → 8pt (more visible at 0.5× zoom).
- Animated 12pt .padding(.leading) on the wrapped ClipBlockView when
  the clip is the drop target — neighbors visibly push aside, Photos.app
  pattern.
- Soft accent shadow on the capsule (radius: 6, opacity: 0.4) so it
  reads as 'this is where the clip will land' even on busy backgrounds.
- Both animations use a unified .easeInOut(duration: 0.20) so gutter
  and capsule move in lock-step (also resolves AUDIT-05 L1)."
```

**Effort: ~30min. ~5 commits cumulatively.**

---

## Task 6: Faster batch MetaClean + single-toast batch save (Phase 2.6)

**Why:** MASTER-PLAN 2.6 + AUDIT-08 Part A7. The current `runBatch` is sequential; on a Pro phone with 2 encoder engines we get a free 2× by using `TaskGroup` with `maxConcurrent = DeviceCapabilities.currentSafeConcurrency()`. Per-file save toasts also need to collapse into a single end-of-batch toast.

- [ ] **Step 1: Write a failing test for the concurrent batch flow**

Create `VideoCompressor/VideoCompressorTests/MetaCleanQueueConcurrencyTests.swift`:

```swift
//
//  MetaCleanQueueConcurrencyTests.swift
//  VideoCompressorTests
//
//  Pins the new TaskGroup-based runBatch behaviour:
//   - All items are processed (none dropped).
//   - batchProgress.current ends at total.
//   - Concurrency is bounded by DeviceCapabilities.currentSafeConcurrency().
//   - A nil DeviceCapabilities concurrency (sim) safely defaults to 1.
//

import XCTest
@testable import VideoCompressor_iOS

@MainActor
final class MetaCleanQueueConcurrencyTests: XCTestCase {

    func testConcurrencyHelperBoundedAtLeastOne() {
        // Even on the sim where deviceClass == .unknown, concurrency
        // must default to at least 1 — never 0, never negative.
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .unknown,
            thermalState: .nominal
        )
        XCTAssertGreaterThanOrEqual(safe, 1)
        XCTAssertLessThanOrEqual(safe, 2,
            "Cluster 3 cap is 2 even on Pro to keep AVAudioSession reliable.")
    }

    func testConcurrencyHelperPro() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .pro,
            thermalState: .nominal
        )
        XCTAssertEqual(safe, 2, "Pro phones get N=2 concurrency.")
    }

    func testConcurrencyHelperFallsBackUnderThermalStress() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .pro,
            thermalState: .serious
        )
        XCTAssertEqual(safe, 1,
            "Thermal-stressed Pro must drop to N=1 — same policy as compress.")
    }

    func testConcurrencyHelperStandard() {
        let safe = MetaCleanQueue.batchConcurrency(
            deviceClass: .standard,
            thermalState: .nominal
        )
        XCTAssertEqual(safe, 1, "Non-Pro phones stay at N=1.")
    }
}
```

These tests reference `MetaCleanQueue.batchConcurrency(deviceClass:thermalState:)` which doesn't yet exist. That's the TDD red.

Run: `mcp__xcodebuildmcp__test_sim` — compile failure on the missing helper. Expected.

- [ ] **Step 2: Add the `batchConcurrency` helper + `lastSaveBatch` publish path**

In `VideoCompressor/ios/Services/VideoLibrary.swift`, add (after `@Published var lastError: LibraryError?` at line 30):

```swift
    /// Single end-of-batch save toast. Subscribed by MetaCleanTabView
    /// (and any future Compress / Stitch batch save) — replaces the
    /// per-file save toasts called out by AUDIT-08 Part A7.
    @Published var lastSaveBatch: SaveBatchResult?

    /// Public publisher for batch-save completion. Per AUDIT-08 Part A7
    /// + locked decision: route through VideoLibrary so any tab's
    /// batch flow can fire one toast through a shared sink.
    ///
    /// `saved` is the count of items successfully written to Photos.
    /// `failed` is the count of items whose Photos save failed (strip
    /// succeeded but save did not). When `failed > 0` the toast reads
    /// "Saved N · M failed" per AGENTS.md Part 14 no-silent-fallbacks.
    func notifySaveBatchCompleted(saved: Int, failed: Int, kind: MediaKind) {
        lastSaveBatch = SaveBatchResult(saved: saved, failed: failed, kind: kind, at: Date())
    }
```

Then add the `SaveBatchResult` struct in the same file (above `final class VideoLibrary` or in a new `// MARK: -` section at the bottom):

```swift
/// Result of a batch save-to-Photos pass. Drives the single end-of-batch
/// toast in MetaCleanTabView.
struct SaveBatchResult: Equatable {
    let saved: Int
    let failed: Int
    let kind: MediaKind
    let at: Date

    var displayMessage: String {
        let noun = kind == .still ? "photo" : "video"
        let nounPlural = kind == .still ? "photos" : "videos"
        let savedPart = saved == 1
            ? "Saved 1 \(noun) to your library"
            : "Saved \(saved) \(nounPlural) to your library"
        // Per AGENTS.md Part 14: save failures must surface to the user,
        // not be silently dropped. When any saves failed, append the count.
        if failed > 0 {
            return "\(savedPart)\u{2003}·\u{2003}\(failed) failed to save"
        }
        return savedPart
    }
}
```

In `VideoCompressor/ios/Services/MetaCleanQueue.swift`, add the static helper above the existing `// MARK: - Batch clean` section (around line 169):

```swift
    /// Batch concurrency for cleanAll. Per MASTER-PLAN 2.6: Pro phones get
    /// N=2, everyone else stays at N=1. Mirrors CompressionService's policy
    /// (see DeviceCapabilities.currentSafeConcurrency).
    ///
    /// Capped at 2 because shared AVAudioSession contention causes
    /// AVAssetReader -11800 errors above that — the same reason
    /// MetaCleanQueue.runBatch was sequential prior to Phase 2.
    static func batchConcurrency(
        deviceClass: DeviceCapabilities.DeviceClass,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        let baseline: Int = (deviceClass == .pro) ? 2 : 1
        switch thermalState {
        case .nominal, .fair: return baseline
        case .serious, .critical: return 1
        @unknown default: return 1
        }
    }
```

- [ ] **Step 3: Convert `runBatch` from sequential `for` loop to `TaskGroup`**

Still in `VideoCompressor/ios/Services/MetaCleanQueue.swift`, replace the entire `runBatch` body (currently lines ~220–276) with:

```swift
    private func runBatch(
        ids: [UUID],
        rules: StripRules,
        replaceOriginals: Bool,
        onItemDone: @MainActor @escaping (UUID, Result<MetadataCleanResult, Error>) -> Void,
        onAllDone: @MainActor @escaping () -> Void
    ) async {
        let concurrency = Self.batchConcurrency(
            deviceClass: DeviceCapabilities.deviceClass,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        var savedCount = 0
        var dominantKind: MediaKind = .still

        // Snapshot the per-id lookup outside the group so each child
        // doesn't have to lock the actor for every read.
        let idToItem: [UUID: MetaCleanItem] = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                ids.contains(item.id) ? (item.id, item) : nil
            }
        )

        // TaskGroup element type mirrors cleanOne's return:
        //   (id, cleanResult, didSave, saveError)
        // saveError is non-nil when the strip succeeded but the Photos save
        // failed — it must be routed to batchProgress.failed, not ignored.
        typealias CleanOneResult = (
            id: UUID,
            cleanResult: Result<MetadataCleanResult, Error>,
            didSave: Bool,
            saveError: Error?
        )

        await withTaskGroup(of: CleanOneResult.self) { group in
            var inFlight = 0
            var iterator = ids.makeIterator()

            // Prime the group with up to `concurrency` slots.
            while inFlight < concurrency, let nextID = iterator.next() {
                if Task.isCancelled { break }
                guard let item = idToItem[nextID] else { continue }
                inFlight += 1
                group.addTask { [service, photoService] in
                    await Self.cleanOne(
                        item: item,
                        rules: rules,
                        replaceOriginals: replaceOriginals,
                        service: service,
                        photoService: photoService
                    )
                }
            }

            // Drain results, refilling the group as slots free up.
            while let (id, result, didSave, saveError) = await group.next() {
                if Task.isCancelled { break }
                inFlight -= 1
                batchProgress.current += 1

                switch result {
                case .success(let cleaned):
                    if let i = items.firstIndex(where: { $0.id == id }) {
                        items[i].cleanResult = cleaned
                        dominantKind = items[i].kind
                    }
                    if didSave {
                        savedCount += 1
                    } else if let saveErr = saveError {
                        // Strip succeeded but Photos save failed — surface
                        // per AGENTS.md Part 14 (no silent fallbacks).
                        batchProgress.failed += 1
                        batchProgress.lastError = saveErr.localizedDescription
                    }
                case .failure(let err):
                    batchProgress.failed += 1
                    batchProgress.lastError = err.localizedDescription
                }
                onItemDone(id, result)

                // Refill.
                while inFlight < concurrency, let nextID = iterator.next() {
                    if Task.isCancelled { break }
                    guard let item = idToItem[nextID] else { continue }
                    inFlight += 1
                    group.addTask { [service, photoService] in
                        await Self.cleanOne(
                            item: item,
                            rules: rules,
                            replaceOriginals: replaceOriginals,
                            service: service,
                            photoService: photoService
                        )
                    }
                }
            }
        }

        batchProgress.perItem = .complete
        batchProgress.isRunning = false
        // Single end-of-batch save toast (replaces the per-file toasts
        // called out by AUDIT-08 Part A7). Fire whenever replaceOriginals
        // was requested — even if some saves failed — so the user can see
        // both success and failure counts (AGENTS.md Part 14 no-silent-fallbacks).
        if replaceOriginals {
            VideoLibrary.batchSaveSink?.notifySaveBatchCompleted(
                saved: savedCount,
                failed: batchProgress.failed,
                kind: dominantKind
            )
        }
        onAllDone()
    }

    /// Pure-function single-item clean. Hoisted out of `runBatch` so the
    /// TaskGroup children can run without re-entering the actor for every
    /// read.
    ///
    /// Return tuple:
    ///   - `id`: the item's UUID (for result matching in the drain loop)
    ///   - `cleanResult`: `.success` if the metadata strip succeeded, `.failure` otherwise
    ///   - `didSave`: `true` iff the cleaned output was saved to Photos AND the
    ///                original was deleted
    ///   - `saveError`: non-nil when the metadata strip succeeded but the Photos
    ///                  save failed — allows the drain loop to surface save
    ///                  failures distinctly from strip failures (AGENTS.md Part 14
    ///                  no-silent-fallbacks rule).
    private static func cleanOne(
        item: MetaCleanItem,
        rules: StripRules,
        replaceOriginals: Bool,
        service: MetadataService,
        photoService: PhotoMetadataService
    ) async -> (
        id: UUID,
        cleanResult: Result<MetadataCleanResult, Error>,
        didSave: Bool,
        saveError: Error?
    ) {
        do {
            let result: MetadataCleanResult
            switch item.kind {
            case .video:
                result = try await service.strip(url: item.sourceURL, rules: rules) { _ in }
            case .still:
                result = try await photoService.strip(url: item.sourceURL, rules: rules) { _ in }
            }

            var didSave = false
            if replaceOriginals {
                do {
                    try await PhotosSaver.saveAndOptionallyDeleteOriginal(
                        cleanedURL: result.cleanedURL,
                        originalAssetID: item.originalAssetID
                    )
                    didSave = true
                } catch {
                    // Strip succeeded but save failed — surface via saveError so
                    // the drain loop can record it in batchProgress.failed and
                    // batchProgress.lastError. Per AGENTS.md Part 14 this must
                    // NOT be silently swallowed into a .success tuple.
                    return (item.id, .success(result), false, error)
                }
            }
            return (item.id, .success(result), didSave, nil)
        } catch is CancellationError {
            return (item.id, .failure(CancellationError()), false, nil)
        } catch {
            return (item.id, .failure(error), false, nil)
        }
    }
```

(Note: the new flow drops the per-item progress callback (`batchProgress.perItem = p`) because reporting a sub-progress per parallel item would race. The progress bar still advances per-item because `batchProgress.current` is incremented on result drain. This matches the policy the user accepted in the master plan: "single end-of-batch toast" — sub-bar per-item progress is no longer load-bearing.)

In the same file, add a static reference to the sink so `MetaCleanQueue` can publish without holding a strong reference to `VideoLibrary`:

In `VideoCompressor/ios/Services/VideoLibrary.swift`, add inside the `VideoLibrary` class, after the `init()` (around line 52):

```swift
    /// Static sink used by MetaCleanQueue.runBatch (and any future
    /// background batch flow) to publish single end-of-batch save
    /// toasts without holding a strong reference. Set by ContentView
    /// when the EnvironmentObject is injected; cleared in tests via
    /// resetForTests() if needed.
    @MainActor static weak var batchSaveSink: VideoLibrary?
```

In `init()`, add at the bottom (still inside the init body):

```swift
        Self.batchSaveSink = self
```

- [ ] **Step 4: Subscribe `MetaCleanTabView` to the toast sink**

In `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift`, add an `@EnvironmentObject` near the top of the struct (after `@StateObject private var queue = MetaCleanQueue()`):

```swift
    @EnvironmentObject private var library: VideoLibrary
    @State private var batchToast: SaveBatchResult?
```

Then, at the bottom of the `body` (after the last `.alert(...)` block, line 95), append:

```swift
            .onChange(of: library.lastSaveBatch) { _, newValue in
                guard let result = newValue else { return }
                batchToast = result
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if batchToast == result { batchToast = nil }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = batchToast {
                    Label(toast.displayMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 84)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("metaCleanBatchSaveToast")
                }
            }
            .animation(.easeInOut(duration: 0.20), value: batchToast)
```

(`.animation` value tracks `SaveBatchResult` Equatable which we declared in Step 2.)

- [ ] **Step 5: Run tests**

```
mcp__xcodebuildmcp__test_sim
```

Expected: baseline + 4 (Task 1) + 4 (Task 2) + 4 (Task 6) = baseline + 12.

- [ ] **Step 6: Commit**

```bash
git add VideoCompressor/ios/Services/MetaCleanQueue.swift \
        VideoCompressor/ios/Services/VideoLibrary.swift \
        VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift \
        VideoCompressor/VideoCompressorTests/MetaCleanQueueConcurrencyTests.swift
git commit -m "feat(metaclean): TaskGroup batch + single end-of-batch toast (Phase 2.6)

Resolves MASTER-PLAN 2.6 / AUDIT-08 Part A7.

runBatch now uses a TaskGroup with concurrency = batchConcurrency(...)
which mirrors CompressionService's policy:
  - Pro iPhones get N=2 (free 2× on hardware with 2 encoder engines).
  - Standard / unknown stay at N=1.
  - Thermal stress drops everyone to N=1.

Per-file save toasts are gone. After a successful 'Replace originals
in Photos' batch, MetaCleanQueue calls VideoLibrary.notifySaveBatchCompleted
which publishes a single 'Saved 8 photos to your library' toast at the
bottom of MetaCleanTabView. Toast auto-dismisses after 3 seconds.

VideoLibrary gains @Published lastSaveBatch + a weak static
batchSaveSink so the queue can publish without a strong ref cycle."
```

**Effort: ~3h. ~6 commits cumulatively.**

---

## Task 7: Frontend simplifications (Phase 2.7)

**Why:** AUDIT-08 Part B (B1, B4) + locked decision #4 + #5. Three independent surface cuts:
1. Compress presets visible to Balanced + Small only (Max + Streaming + Custom under "Advanced").
2. CropEditor XYWH sliders REMOVED entirely; replaced with 4 aspect-ratio preset buttons (Square / 9:16 / 16:9 / Free).
3. Settings Performance section moved into `DisclosureGroup("Advanced")`.

- [ ] **Step 1: Write a failing test for the new aspect-preset rect math**

Create `VideoCompressor/VideoCompressorTests/CropEditorPresetTests.swift`:

```swift
//
//  CropEditorPresetTests.swift
//  VideoCompressorTests
//
//  Pins the new aspect-preset crop math. Replaces the prior XYWH
//  Slider rows with 4 preset buttons (Square / 9:16 / 16:9 / Free).
//

import XCTest
import CoreGraphics
@testable import VideoCompressor_iOS

final class CropEditorPresetTests: XCTestCase {

    func testFreePresetClearsCrop() {
        // 'Free' = no crop at all = nil cropNormalized.
        let rect = CropEditorView.cropRect(for: .free, naturalSize: CGSize(width: 1920, height: 1080))
        XCTAssertNil(rect)
    }

    func testSquarePresetInLandscape() {
        // 1920×1080 source: square crop → 1080×1080 centered horizontally.
        // In normalized coords: width = 1080/1920 = 0.5625; centered.
        let rect = CropEditorView.cropRect(for: .square, naturalSize: CGSize(width: 1920, height: 1080))
        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.width, 0.5625, accuracy: 0.001)
        XCTAssertEqual(rect!.height, 1.0, accuracy: 0.001)
        // Centered horizontally: x = (1 - 0.5625) / 2.
        XCTAssertEqual(rect!.minX, (1.0 - 0.5625) / 2.0, accuracy: 0.001)
        XCTAssertEqual(rect!.minY, 0.0, accuracy: 0.001)
    }

    func testPortrait916InLandscape() {
        // 1920×1080 source, target 9:16: target ratio 9/16 = 0.5625
        // source ratio 1920/1080 = 1.7777. Target is taller-than-wide,
        // so we max out height (1.0) and crop width to 1080 * 9/16 = 607.5.
        // Normalized width = 607.5/1920 = 0.3164.
        let rect = CropEditorView.cropRect(for: .portrait916, naturalSize: CGSize(width: 1920, height: 1080))
        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.width, 0.3164, accuracy: 0.001)
        XCTAssertEqual(rect!.height, 1.0, accuracy: 0.001)
    }

    func testLandscape169InPortraitSource() {
        // 1080×1920 source, target 16:9: max out width (1.0),
        // crop height to 1080 * 9/16 = 607.5; normalized height
        // = 607.5/1920 = 0.3164.
        let rect = CropEditorView.cropRect(for: .landscape169, naturalSize: CGSize(width: 1080, height: 1920))
        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect!.height, 0.3164, accuracy: 0.001)
    }
}
```

These tests reference `CropEditorView.AspectPreset` (an enum) and a static `cropRect(for:naturalSize:)` helper that don't yet exist. That's the TDD red.

- [ ] **Step 2: Rewrite `CropEditorView.swift` with aspect presets**

Replace the entire body of `VideoCompressor/ios/Views/StitchTab/CropEditorView.swift` with:

```swift
//
//  CropEditorView.swift
//  VideoCompressor
//
//  v2 crop editor (Phase 2.7 / AUDIT-08 Part B): four aspect-ratio
//  preset buttons replace the prior XYWH Slider rows. Per locked
//  decision #5, the sliders were entirely removed.
//

import SwiftUI
import CoreGraphics

struct CropEditorView: View {
    let clip: StitchClip
    @Binding var edits: ClipEdits

    enum AspectPreset: String, CaseIterable, Hashable {
        case free
        case square
        case portrait916
        case landscape169

        var label: String {
            switch self {
            case .free:         return "Free"
            case .square:       return "Square"
            case .portrait916:  return "9:16"
            case .landscape169: return "16:9"
            }
        }

        var symbol: String {
            switch self {
            case .free:         return "rectangle.expand.vertical"
            case .square:       return "square"
            case .portrait916:  return "rectangle.portrait"
            case .landscape169: return "rectangle"
            }
        }

        /// Target width/height ratio (nil for .free which clears the crop).
        var ratio: CGFloat? {
            switch self {
            case .free:         return nil
            case .square:       return 1.0
            case .portrait916:  return 9.0 / 16.0
            case .landscape169: return 16.0 / 9.0
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Crop to a common aspect ratio.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(AspectPreset.allCases, id: \.self) { preset in
                    Button {
                        apply(preset: preset)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.symbol)
                                .font(.title2)
                            Text(preset.label)
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isCurrent(preset)
                                      ? Color.accentColor.opacity(0.18)
                                      : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isCurrent(preset) ? Color.accentColor : .clear,
                                        lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cropPreset_\(preset.rawValue)")
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Apply

    private func isCurrent(_ preset: AspectPreset) -> Bool {
        let target = Self.cropRect(for: preset, naturalSize: clip.naturalSize)
        if target == nil {
            return edits.cropNormalized == nil
        }
        guard let curr = edits.cropNormalized, let t = target else { return false }
        return Self.isApproximatelyEqual(curr, t)
    }

    private func apply(preset: AspectPreset) {
        let rect = Self.cropRect(for: preset, naturalSize: clip.naturalSize)
        edits.cropNormalized = rect
    }

    // MARK: - Pure helpers (testable)

    /// Pure helper exposed to CropEditorPresetTests.
    /// Returns the normalized cropNormalized rect for the given preset
    /// against a source frame size. `.free` returns nil (= no crop).
    static func cropRect(for preset: AspectPreset, naturalSize: CGSize) -> CGRect? {
        guard let targetRatio = preset.ratio else { return nil }
        guard naturalSize.width > 0, naturalSize.height > 0 else { return nil }

        let sourceRatio = naturalSize.width / naturalSize.height

        if targetRatio >= sourceRatio {
            // Target is wider-or-equal → max out width, crop height.
            let normWidth: CGFloat = 1.0
            let normHeight = sourceRatio / targetRatio
            let originY = (1.0 - normHeight) / 2.0
            return CGRect(x: 0, y: originY, width: normWidth, height: normHeight)
        } else {
            // Target is taller → max out height, crop width.
            let normHeight: CGFloat = 1.0
            let normWidth = targetRatio / sourceRatio
            let originX = (1.0 - normWidth) / 2.0
            return CGRect(x: originX, y: 0, width: normWidth, height: normHeight)
        }
    }

    private static let identityEpsilon: CGFloat = 1e-3

    private static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < identityEpsilon
            && abs(a.minY - b.minY) < identityEpsilon
            && abs(a.width - b.width) < identityEpsilon
            && abs(a.height - b.height) < identityEpsilon
    }
}
```

(Note: this drops the prior helper `commit(_:)` and `isApproximatelyIdentity(_:)` because the new flow assigns `cropNormalized` directly with the centered preset rect — no XYWH editing path remains, so identity-collapsing isn't needed. The exporter's passthrough fast-path still kicks in when `cropNormalized == nil` which is exactly what `.free` produces.)

- [ ] **Step 3: Split `PresetPickerView.videoPresetList` into default + Advanced**

In `VideoCompressor/ios/Views/PresetPickerView.swift`, replace the `videoPresetList` computed property (currently lines 56–101) with:

```swift
    private var videoPresetList: some View {
        List {
            if showAdvanced {
                Section {
                    advancedSummary
                }
                .listRowBackground(Color.clear)
            }

            // Default-visible presets per locked decision #4: Balanced + Small only.
            Section {
                presetRow(.balanced)
                presetRow(.small)
            }

            // Advanced disclosure — Max + Streaming live here in v1.
            // Custom (the Advanced summary toggle) is the existing
            // Toggle in the toolbar so it stays globally accessible.
            Section {
                DisclosureGroup("Advanced") {
                    presetRow(.max)
                    presetRow(.streaming)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func presetRow(_ setting: CompressionSettings) -> some View {
        Button {
            library.selectedSettings = setting
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: setting.symbolName)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(setting.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(setting.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showAdvanced {
                        advancedDetail(for: setting)
                    }
                }
                Spacer()
                if library.selectedSettings == setting {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

(Verify `CompressionSettings.max`, `.balanced`, `.small`, and `.streaming` exist as static lets in `VideoCompressor/ios/Models/CompressionSettings.swift` — the grep confirmed: lines 98–100 + a `.max` definition above, and `phase1Presets: [.max, .balanced, .small, .streaming]` at line 103.)

- [ ] **Step 4: Wrap Settings Performance section in `DisclosureGroup("Advanced")`**

In `VideoCompressor/ios/Views/SettingsTabView.swift`, find the `// MARK: Performance (Phase 3 commit 8)` block (currently lines 35–65). Replace the existing `Section { ... }` with the same content nested inside a `DisclosureGroup("Advanced")` placed inside its own Section so the disclosure doesn't visually collide with the Storage section below:

Replace:

```swift
                // MARK: Performance (Phase 3 commit 8)
                Section {
                    HStack {
                        Text("Device class")
                        Spacer()
                        Text(
                            DeviceCapabilities.deviceClass == .pro
                                ? "Pro (2× encoder)"
                                : DeviceCapabilities.deviceClass == .standard
                                    ? "Standard (1× encoder)"
                                    : "Unknown"
                        )
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Parallel encodes")
                        Spacer()
                        Text("\(DeviceCapabilities.currentSafeConcurrency())")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    Text(
                        "Pro iPhones (13 Pro – 17 Pro) have 2 dedicated video encoder engines — " +
                        "both are used when batch-compressing. " +
                        "Concurrency drops to 1 if the device is thermally stressed."
                    )
                    .font(.caption)
                }
```

with:

```swift
                // MARK: Performance (collapsed to Advanced — Phase 2.7 / AUDIT-08 B4)
                Section {
                    DisclosureGroup("Advanced") {
                        HStack {
                            Text("Device class")
                            Spacer()
                            Text(
                                DeviceCapabilities.deviceClass == .pro
                                    ? "Pro (2× encoder)"
                                    : DeviceCapabilities.deviceClass == .standard
                                        ? "Standard (1× encoder)"
                                        : "Unknown"
                            )
                            .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Parallel encodes")
                            Spacer()
                            Text("\(DeviceCapabilities.currentSafeConcurrency())")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text(
                            "Pro iPhones (13 Pro – 17 Pro) have 2 dedicated video encoder engines — " +
                            "both are used when batch-compressing. " +
                            "Concurrency drops to 1 if the device is thermally stressed."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
```

- [ ] **Step 5: Run tests**

```
mcp__xcodebuildmcp__clean
mcp__xcodebuildmcp__test_sim
```

Expected: baseline + 4 (Task 1) + 4 (Task 2) + 4 (Task 6) + 4 (Task 7) = baseline + 16.

The `clean` is necessary because `CropEditorView.swift` was rewritten and the synchronized root-group cache may stale-reference the deleted helpers.

- [ ] **Step 6: Commit**

```bash
git add VideoCompressor/ios/Views/StitchTab/CropEditorView.swift \
        VideoCompressor/ios/Views/PresetPickerView.swift \
        VideoCompressor/ios/Views/SettingsTabView.swift \
        VideoCompressor/VideoCompressorTests/CropEditorPresetTests.swift
git commit -m "feat(ux): aspect presets + advanced compress + advanced perf (Phase 2.7)

Resolves MASTER-PLAN 2.7 / AUDIT-08 Part B (B1 + B4) / locked decisions
#4 and #5.

CropEditorView (decision #5):
  XYWH Slider rows REMOVED. Replaced with 4 aspect-preset buttons:
  Square / 9:16 / 16:9 / Free. The pure helper
  CropEditorView.cropRect(for:naturalSize:) computes the centered
  normalized crop rect for each preset and 'Free' clears the crop
  to nil (= passthrough fast-path).

PresetPickerView (decision #4):
  Default-visible presets are now Balanced + Small only. Max +
  Streaming live under DisclosureGroup('Advanced'). The existing
  'Custom' toggle in the toolbar (showAdvanced AppStorage) stays
  globally available.

SettingsTabView (B4):
  Performance section ('Device class', 'Parallel encodes') is now
  collapsed under DisclosureGroup('Advanced'). Background-Encoding
  and Storage stay visible at the top level.

4 new CropEditorPresetTests pin the aspect-rect math."
```

**Effort: ~2h. ~7 commits cumulatively.**

---

## Task 8: Push, PR, CI, merge

- [ ] **Step 1: Final test pass**

```
mcp__xcodebuildmcp__test_sim
```

Expected: baseline + 16. Output line `Total: <N+16>, Passed: <N+16>, Failed: 0`.

- [ ] **Step 2: Sim build smoke-test**

```
mcp__xcodebuildmcp__build_sim
```

Expected: `iOS Simulator Build build succeeded for scheme VideoCompressor_iOS.`

- [ ] **Step 3: Push + PR**

```bash
git push -u origin feat/codex-cluster3-ux-polish
gh pr create --base main --head feat/codex-cluster3-ux-polish \
  --title "feat: Phase 2 cluster 3 — UX polish + onboarding" \
  --body "$(cat <<'EOF'
Closes MASTER-PLAN tasks 2.1 → 2.7 (full Phase 2).

## Summary
- 2.1 Friendlier batch copy + #if DEBUG print + dedup scissors
- 2.2 First-launch 3-card paged onboarding (MetaClean → Compress → Stitch)
- 2.3 Settings 'What MetaClean does' explainer (verbatim AUDIT-08 copy)
- 2.4 'Preview' as first context-menu item on stitch clips
- 2.5 Drop indicator: 8pt bar + 12pt gutter + accent shadow
- 2.6 TaskGroup batch MetaClean (N=2 on Pro) + single end-of-batch toast
- 2.7 Compress presets default to Balanced + Small (rest under Advanced);
  CropEditor XYWH sliders removed → 4 aspect presets; Settings Performance
  section moved to Advanced

## Test plan
- [ ] mcp__xcodebuildmcp__test_sim shows baseline + 16 new (4 each:
      MetaCleanCopy, OnboardingGate, MetaCleanQueueConcurrency, CropEditorPreset)
- [ ] Fresh sim install: onboarding appears
- [ ] Tap 'Get started' on card 3: lands on MetaClean tab, persists across relaunch
- [ ] Settings: 'What MetaClean does' is the FIRST section
- [ ] Settings: 'Performance' is now under DisclosureGroup('Advanced')
- [ ] Stitch: long-press a clip → 'Preview' is the FIRST menu item
- [ ] Stitch: drag a clip → 8pt accent bar + neighbor pushes aside
- [ ] MetaClean batch save: ONE 'Saved N photos to your library' toast at end
- [ ] Compress preset picker: only Balanced + Small visible by default
- [ ] Stitch CropEditor: 4 aspect buttons, no sliders

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Watch CI, merge**

```bash
gh pr checks <num> --watch
gh pr merge <num> --merge
```

- [ ] **Step 5: Append session log**

```bash
echo "[$(date '+%Y-%m-%d %H:%M IST')] [UX] Phase 2 cluster 3 — onboarding + polish (PR #<num>)" \
  >> .agents/work-sessions/$(date +%Y-%m-%d)/AI-CHAT-LOG.md
```

---

## Acceptance criteria

- [ ] First-launch onboarding appears on a fresh install (sim or device).
- [ ] `@AppStorage("hasSeenOnboarding_v1")` persists; relaunch does NOT re-show the sheet.
- [ ] Tapping "Get started" on the third card sets `selectedTab = .metaClean`.
- [ ] Settings → "What MetaClean does" is the FIRST section, with three DisclosureGroups (What gets removed / What stays / What MetaClean never does), copy verbatim from `AUDIT-08` Part A.
- [ ] Settings → Performance section is now nested inside `DisclosureGroup("Advanced")`.
- [ ] MetaClean batch progress label reads `"Cleaning your photos · 3 of 8"` (em-space, not raw "of"); singular and terminal variants render correctly.
- [ ] Single end-of-batch toast `"Saved N photos to your library"` appears after a successful Replace-originals batch; per-file toasts are gone.
- [ ] Save failures during a `replaceOriginals` batch surface in the user-facing toast as `"Saved N · M failed to save"` (not silently dropped). Verified by `batchProgress.failed` incrementing for each save error and `SaveBatchResult.displayMessage` rendering the combined count.
- [ ] Stitch timeline drop indicator is 8pt wide with a 12pt gutter on the target clip and a soft accent shadow.
- [ ] Stitch context menu opens with `Preview` as the FIRST item, above Duplicate / Move to Start / Move to End / Delete.
- [ ] Tapping `Preview` opens a sheet showing `ClipLongPressPreview` with `.medium` / `.large` detents and a Done button.
- [ ] Compress preset picker shows ONLY Balanced + Small at the top level; Max + Streaming live under `DisclosureGroup("Advanced")`.
- [ ] CropEditor shows 4 aspect-ratio preset buttons (Square / 9:16 / 16:9 / Free) and ZERO sliders.
- [ ] Tapping `Free` clears `edits.cropNormalized` to nil (verified via the exporter's passthrough fast-path still firing).
- [ ] No `print(...)` calls remain in production builds. `grep -rn "^\s*print(" VideoCompressor/ios/` returns zero hits OR all hits are inside `#if DEBUG` / `#endif` blocks.
- [ ] `ClipEditorInlinePanel` header has only ONE scissors action (the prominent labeled button); the duplicate header icon is gone.
- [ ] All baseline tests still pass; 16 new (4 each in MetaCleanCopy, OnboardingGate, MetaCleanQueueConcurrency, CropEditorPreset) all pass.
- [ ] CI green, PR merged, TestFlight build #3 reaches testers.

---

## Manual iPhone test prompts (after merge → TestFlight install)

Walk these in order on a tethered iPhone after the merge build lands. Each step takes ≤ 30 seconds.

1. **Fresh install onboarding shows.** Delete the app from the device, install via TestFlight, launch. Confirm the onboarding sheet appears with 3 paged cards.
2. **Card content matches.** Card 1 = MetaClean (eye.slash icon, "Strip Meta AI fingerprints"). Card 2 = Compress (wand.and.stars icon, "Shrink before sharing"). Card 3 = Stitch (square.stack.3d.up icon, "Stitch clips together").
3. **Page indicator + Next button.** Tap "Next" twice — page indicator dots advance.
4. **Get started lands on MetaClean.** On card 3, tap "Get started". Confirm the sheet dismisses AND the bottom tab bar shows MetaClean as the selected tab.
5. **Onboarding does not re-appear.** Force-quit (swipe up from app switcher) and relaunch. Confirm the onboarding sheet is GONE; the app opens directly into MetaClean.
6. **Settings explainer is FIRST.** Tap Settings tab. Scroll to top — "What MetaClean does" must be the first section, above "Allow encoding in background".
7. **Disclosures expand.** Tap "What gets removed" — three bullet lines appear. Tap "What stays" — single paragraph appears. Tap "What MetaClean never does" — three short bullet sentences appear.
8. **Performance is now under Advanced.** In Settings, scroll past Storage. The Performance section should be a single "Advanced" DisclosureGroup row (collapsed by default). Tap to expand — Device class + Parallel encodes + the footer caption are inside.
9. **Compress preset picker.** Tap Compress tab. Pick a video. Tap the preset selector at the bottom. Confirm only "Balanced" + "Small" rows appear at the top; an "Advanced" disclosure below contains "Max" + "Streaming".
10. **Stitch CropEditor presets.** Tap Stitch tab. Pick 2+ clips. Tap a clip. Tap "Crop" in the per-clip edits drawer. Confirm 4 aspect-ratio preset buttons (Square / 9:16 / 16:9 / Free) — NO sliders.
11. **Stitch drop indicator.** With 3+ clips on the timeline, drag the second clip toward the third. Confirm the accent bar between clip 2 and clip 3 is visibly wider (8pt) AND the third clip animates ~12pt to the right (gutter).
12. **Stitch Preview menu.** Long-press any clip in the timeline. Confirm "Preview" appears as the FIRST item in the context menu, with a `play.rectangle` glyph.
13. **Preview sheet.** Tap "Preview". Confirm a sheet slides up showing the clip's video (auto-playing, muted) or still image, with a "Done" button in the top-right.
14. **MetaClean copy.** In MetaClean, import 5+ items. Tap "Clean All". Confirm the progress label reads `"Cleaning your photos · 1 of 5"` (with em-space-dot-em-space), not `"Cleaning 1 of 5"`.
15. **Single batch save toast.** Toggle "Replace originals in Photos" ON. Tap "Clean All & Replace". After the batch finishes, confirm exactly ONE toast appears at the bottom: `"Saved 5 photos to your library"`. No per-file toasts.
16. **Pro phone batch speed.** On an iPhone 13 Pro or newer, time a 6-item batch. Confirm wall-clock time is ~half a sequential 6-item run on the same device (rough comparison; precise timing is sim-only via tests).
17. **No engineering text.** Spot-check every visible label across all 4 tabs. Reject anything reading like an engineer log line (`"3/8"`, `"_BAL"`, `"%.2f"`).

---

## Notes for the executing agent

- **Sim hygiene:** if `test_sim` reports flaky timing on the TaskGroup tests, don't add sleeps — the helpers are pure functions and shouldn't have timing-sensitive paths. Re-check that `MetaCleanQueue.batchConcurrency` is a `static func`, not an instance method.
- **PBXFileSystemSynchronizedRootGroup gotcha:** new test files (`OnboardingGateTests`, `CropEditorPresetTests`, `MetaCleanCopyTests`, `MetaCleanQueueConcurrencyTests`) AND the new `Views/Onboarding/OnboardingView.swift` auto-include via the synchronized root groups. If any of them silently runs zero tests OR the build complains "cannot find OnboardingView in scope", run `mcp__xcodebuildmcp__clean` then re-run.
- **The `Views/Onboarding/` subdirectory** must exist before `Write` will land the file. The `mkdir -p` in Task 2 Step 2 covers this; if Codex prefers, it can manually create it via the Bash tool first.
- **Don't introduce CoreHaptics or custom AVVideoCompositing** (locked decision #10). The drop indicator polish in Task 5 uses pure SwiftUI animations + `Haptics` (the existing wrapper around `UIImpactFeedbackGenerator`).
- **Don't re-run `session_set_defaults`** (per AGENTS.md Part 16.3). The defaults are already set.
- **≤10 commits ceiling** (locked decision #6). This plan is budgeted at exactly 7 implementation commits + 0 administrative commits = **7 commits total**, leaving 3-commit headroom for any unanticipated fix-up. If you blow past 10, squash adjacent commits before pushing.
- **138 baseline tests must keep passing** (locked decision #9). The new TaskGroup-based `runBatch` drops the per-item `perItem` callback in favour of result-drain progress. If any existing test asserts on `perItem` mid-batch, update the assertion to read `batchProgress.current` instead (search: `grep -rn "perItem" VideoCompressor/VideoCompressorTests/`).
- **`MediaKind` lives in `Models/MetaCleanItem.swift`** — already imported wherever it's referenced in this plan; no new import statements are needed.
- **The `library.batchSaveSink = self` assignment in `VideoLibrary.init()`** is intentional even though it overrides on every fresh instance — in practice the app has exactly one `VideoLibrary` for its lifetime (created in `VideoCompressorApp` as `@StateObject`). The `weak` reference avoids a retain cycle if test code spins up a second instance.
- **No new third-party dependencies** (locked decision #8). Everything uses Foundation, SwiftUI, AVFoundation, and the existing project services.
