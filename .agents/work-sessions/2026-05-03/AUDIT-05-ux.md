# UX / Accessibility / Frontend Simplicity Audit

**Date:** 2026-05-03
**Scope:** `VideoCompressor/ios/Views/` + `Models/StitchProject.swift` published surface
**Reviewer:** subagent/opus, READ-ONLY pass
**Goal:** identify "dev-y" friction before App Store launch — bias toward simple polish over big refactors.

---

## Executive summary

The app is structurally sound and per-screen UX is good (live trim with auto-play, undo/redo, good empty states, proper error alerts). The app feels "dev-y" mostly in three places:

1. **The headline product name on the home screen** — `Alkloihd Video Swiss-AK` ships in production-facing text.
2. **Engineer-flavored counters and numeric output** — "Cleaning 3 of 8", "Trim 0:08.42 / Playhead 7.45 s", `1.00` crop-rect floats.
3. **Discoverability gaps that read as "missing onboarding"** — no first-launch screen, the Settings tab does not explain MetaClean, and the inline editor's controls are not obvious on first contact.

15 findings below. CRITICAL is anything you would not want a reviewer or first-time customer to see. HIGH is "blocker for a v1.0 polished feel". MEDIUM/LOW are polish.

| Severity | Count |
|---|---|
| CRITICAL | 2 |
| HIGH | 5 |
| MEDIUM | 5 |
| LOW | 3 |
| **TOTAL** | **15** |

---

## CRITICAL

### C1 — Navigation title is a placeholder string visible to users
**File:** `VideoCompressor/ios/Views/VideoListView.swift:31`
**Issue:** `navigationTitle("Alkloihd Video Swiss-AK")` — this is the first thing the user reads when they open the app and it looks like a leftover engineering codename. The other tabs use clean titles (`"Stitch"`, `"MetaClean"`, `"Settings"`). Compress should match.
**Fix:** Replace with `navigationTitle("Compress")`. If you want a unique product name, do it once in `App.swift` / Launch Screen, not on this tab.

---

### C2 — No first-launch onboarding (PUBLISHING P5 backlog item, called out by user)
**File:** `VideoCompressor/ios/ContentView.swift` (entire root view)
**Issue:** A first-time user is dropped directly onto the Compress tab with zero context. The tab order itself does not signal that **MetaClean is the headline feature** (PUBLISHING.md Part 7). MetaClean is the third tab.
**Fix:** Add a `OnboardingSheetView` shown on first launch (gated by `@AppStorage("hasSeenOnboarding")`). Three pages, one sentence each:

> 1. **Strip Meta AI fingerprints** from photos and videos shot on Ray-Ban / Oakley Meta glasses — runs entirely on your phone.
> 2. **Compress and stitch** large videos without uploading them to the cloud.
> 3. **Save to Photos with one tap.** Originals stay untouched unless you ask.

Pair page 1 with the `eye.slash` symbol so users associate that icon with the headline benefit. **Effort: 2-3h, single new file.**

---

## HIGH

### H1 — "Cleaning N of M" reads as engineer telemetry, not user copy
**File:** `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift:201`
**Code:** `Text("Cleaning \(queue.batchProgress.current) of \(queue.batchProgress.total)")`
**Issue:** Per PUBLISHING.md Part 7 P10, this is exactly the line called out as too "dev-y". The progress bar already shows the fraction; the text should be human.
**Fix:** Reword:
- 1 file: `"Cleaning 1 photo…"` (singular) / `"Cleaning your video…"`
- batch: `"Cleaning your photos · 3 of 8"` (em-space separator) — the count after a colon reads as supporting detail, not the whole message.
- For terminal states, prefer `"Cleaned 8 photos"` over `"Done · 8/8"`.

Same pattern at `MetaCleanExportSheet.swift:85` (`"Cleaning… \(percent)%"`).

---

### H2 — Inline editor density: too many controls competing for attention
**File:** `VideoCompressor/ios/Views/StitchTab/ClipEditorInlinePanel.swift:172-226` (header) + 230-348 (sliders/buttons)
**Issue:** The editor surface stacks: clip-name title row + 5 toolbar icons (undo/redo/scissors/reset/close) + video player + duration label + playhead slider + **Split-at-Playhead button (full-width prominent)** + trim slider + split hint. The scissors action is duplicated (icon at line 198 AND button at line 257), and the contextual hint at lines 336-347 explains the split flow with markdown bold + a follow-up sentence about long-pressing. That is too much chrome for what should be a tap-and-drag editor.
**Fix (small):**
- Drop the scissors icon from the header toolbar (line 198-205) — keep only the bordered Split button. One scissors per panel.
- Collapse the multi-line `splitHint` into a single short caption: `"Drag the playhead, then tap Split."` Use the disabled state of the Split button itself to communicate "can't split here" instead of switching the hint copy.
- Move undo/redo into a single `Menu` ("⋯ → Undo / Redo / Reset") if visual density is still an issue. iOS users expect undo behind a long-press / shake / overflow menu, not as primary chrome.

---

### H3 — Duration readout exposes raw float ("Trim 0:08.42 / Playhead 7.45 s")
**File:** `VideoCompressor/ios/Views/StitchTab/ClipEditorInlinePanel.swift:362-364`
**Code:** `String(format: "Trim %d:%02d.%02d / Playhead %.2f s", m, s, cs, playheadSeconds)`
**Issue:** Two different time formats in one line, mixing minutes-seconds-centiseconds with raw seconds. Reads as a debug HUD.
**Fix:** Show only the trimmed clip duration in the header readout: `"0:08.4"`. Move the playhead label, if needed, under the playhead slider as a tiny `.caption2.tertiary` `"7.5s"` aligned with the thumb. Most editors do not show this at all.

---

### H4 — Crop editor surfaces normalized float coordinates (X/Y/W/H sliders, "0.05–1.00")
**File:** `VideoCompressor/ios/Views/StitchTab/CropEditorView.swift:18-44`
**Issue:** Four sliders labeled X/Y/Width/Height with values `"%.2f"` (0.00–1.00). The view itself acknowledges this with a footer: `"v2 will offer an interactive crop rectangle over a preview frame."` — meaning the team already knows. This is an expert-only UI shipped to a consumer app.
**Fix (must-do for v1):**
- Either ship aspect-ratio presets only ("Square", "9:16", "16:9", "Free") and hide the four sliders behind a "Custom" disclosure, OR
- Pull this entire Crop tab out of `ClipEditorSheet.swift:52-53` for v1.0 and ship it in v1.1 with the interactive overlay. The Stitch tab also has aspect-mode at the project level (StitchTabView.swift:154-159), which already covers the 80% use case. **Per-clip free-form crop is not v1.0 critical.**
- If kept, change "X/Y/Width/Height" to "Left / Top / Width / Height" with percentage formatting (`50%` not `0.50`).

---

### H5 — Aspect-mode and Transition pickers eat ~140pt of vertical space above the timeline
**File:** `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift:51-57` and 144-211
**Issue:** Both pickers ship as full-width segmented controls with icon + label + caption text underneath, stacked. On a 6.1" iPhone in portrait, the timeline strip is pushed toward the bottom. Captions duplicate information already conveyed by the icons (e.g., `"9:16 canvas. Landscape clips will pillarbox…"` is a long sentence for a button labeled `"Portrait"` with a portrait icon).
**Fix:** Collapse both into a single "Output" toolbar pill: `[ Auto · Hard cut ]` that opens a sheet on tap. The captions belong in the sheet. The current state-name is enough at the top level. Saves ~100pt for the timeline. Same pattern as PresetPickerView.

---

## MEDIUM

### M1 — Drop indicator is a 6pt bar to the LEFT only — does not push neighbors aside
**File:** `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift:74-81`
**Issue:** The capsule has a fixed-width `frame(width: 6 ...)` and `padding(.trailing, 4)` when active, but the surrounding `HStack(spacing: 8)` does not animate to give it more room — meaning the indicator overlaps tightly between two clips at default zoom and is easy to miss at low zoom (0.5×). Per the user's question: yes, it should be more visible, AND neighboring clips should breathe apart slightly.
**Fix:** When `dropTargetID == clip.id`, apply `.padding(.leading, 12)` to the wrapped clip via animated `withAnimation(.easeOut(duration: 0.18))`. The 6pt bar then sits in a 12pt gutter that's easy to read. Also bump the bar to 8pt wide and use `Color.accentColor` with `.shadow(color: .accentColor.opacity(0.4), radius: 6)` for a soft glow — Photos.app uses this.

---

### M2 — Long-press preview overlay vs. inline-editor playback (user's Q10)
**File:** `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift:152-157` (current contextMenu preview)
**Recommendation: KEEP the long-press contextMenu overlay.** Here's the comparison:

| Pattern | Pros | Cons |
|---|---|---|
| **Current: contextMenu lift overlay** | iOS-native gesture (Photos.app, Messages); auto-haptic; 360×220 preview is large and centered; doesn't disrupt timeline scroll position; works without selection. | One extra gesture for users to discover. |
| **Alt: play in inline editor** | One less gesture pattern; user already knows the inline editor exists. | Forces a tap → a long animated transition (selection ring + panel slide-up) just to preview; user loses scroll position; preview area smaller (16:9 in 220pt panel ≈ 391×220 — about the same); 16:9 letterboxing for portrait phone clips makes the preview shrink further. Worst: tapping any clip BOTH selects it for editing AND plays it — those are two different intents.

**Verdict:** the contextMenu pattern matches user mental model from Photos. The inline editor is for *editing*; the long-press is for *peeking*. They serve different needs. Document the long-press in onboarding (one screen showing the gesture).

**Small enhancement:** add `Label("Preview", systemImage: "play.rectangle")` as the FIRST item in the context menu (`StitchTimelineView.swift:186-208`) so users who don't naturally long-press can still discover and reach the preview via a tap-then-menu path. Currently the menu has Duplicate / Move-to-Start/End / Delete — Preview is implicit only.

---

### M3 — Settings tab is missing the "What MetaClean does" explainer (PUBLISHING P6)
**File:** `VideoCompressor/ios/Views/SettingsTabView.swift:23-120`
**Issue:** Currently shows: Background-encoding toggle, Performance read-out (device class, parallel encodes), Storage. **Nothing explains the headline product (MetaClean) or which fingerprints get stripped.** Reviewers will land here looking for it.
**Fix:** Add a fourth section above "Storage":

```swift
Section("About MetaClean") {
    NavigationLink {
        MetaCleanExplainerView()
    } label: {
        Label("What MetaClean strips", systemImage: "eye.slash")
    }
    NavigationLink {
        PrivacyPolicyView()  // wraps SFSafariViewController to your GitHub Pages
    } label: {
        Label("Privacy Policy", systemImage: "hand.raised")
    }
    Link(destination: URL(string: "mailto:rishaal@nextclass.ca")!) {
        Label("Contact Support", systemImage: "envelope")
    }
}
```

The explainer should match the 4-mode breakdown from the strip-mode picker (`MetadataInspectorView.swift:91-99`): Auto / Strip All / Keep All — with a sentence per mode. **Effort: 1h, two new files.**

Also: "Performance — Pro (2× encoder)" is engineer-language for an end-user setting. Either remove it (it's read-only, has no setting), or rename to `"This iPhone"` with `"Encodes 2 videos at once"` for Pro and `"Encodes 1 video at a time"` for Standard.

---

### M4 — `accessibilityIdentifier` coverage is good, but `accessibilityLabel` is sparse outside ClipEditorInlinePanel
**Files:** `VideoCompressor/ios/Views/VideoRowView.swift`, `MetaCleanRowView.swift`, `ClipBlockView.swift`, `MetadataTagCardView.swift`
**Issue:** `accessibilityIdentifier` is set on most leaf controls (good for UI tests), but VoiceOver users get the synthesized label from each Image+Text combination, which on `MetaCleanRowView` reads as `"film, IMG_0823, 12 tags · 2 Meta fingerprints, chevron right"` — fine but verbose. Worse: `ClipBlockView` (the timeline tile) has no `.accessibilityLabel` so VoiceOver users navigating the Stitch timeline hear `"image, image, image, image, IMG_0823, 0:08, edited, scissors"` — the four thumbnail images get focus before the clip name.
**Fix:** Wrap `ClipBlockView.body` with `.accessibilityElement(children: .combine).accessibilityLabel("\(clip.displayName), \(durationLabel)\(clip.isEdited ? ", edited" : "")")`. Same pattern on `MetaCleanRowView` and `VideoRowView`.

Also: the `MetadataTagCardView` uses red strikethrough to mean "will strip" and green to mean "keep" — color-only signaling. Add an `.accessibilityLabel("\(tag.displayName), will be stripped")` on the willStrip branch.

---

### M5 — `ClipEditorSheet.swift` Crop tab + `print(...)` debug logging in production code
**File:** `VideoCompressor/ios/Views/StitchTab/ClipEditorSheet.swift:41`
**Code:** `print("[ClipEditorSheet] clip \(clipID) not found — dismissing")`
**Issue:** Raw `print` calls ship in release builds and clutter Console.app for any user who plugs into Xcode. PUBLISHING.md P10 specifically calls out hidden release-build logging as a polish item. Note: this whole sheet may be unused if the inline editor is the primary editor (ContentView.swift never references ClipEditorSheet directly), but it's still in the binary.
**Fix:** Replace all `print(...)` in Views with `os.Logger` calls compiled out in release: `Logger(subsystem: "com.nextclass.videocompressor", category: "editor").debug("...")`. Or, if `ClipEditorSheet` is dead code in v1.0 since the inline panel replaced it, delete the file entirely (saves 82 LOC).

---

## LOW

### L1 — Animation timing inconsistency across the same view
**File:** `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift:72` and `StitchTimelineView.swift:81, 124`
**Issue:** The inline editor opens with `.easeInOut(duration: 0.22)`, the drop indicator with `.easeInOut(duration: 0.15)`, and the move animation with `.easeInOut(duration: 0.25)`. None are wrong, but the inconsistency is noticeable when the user drops a clip while the editor is already open — three slightly-different timings overlap.
**Fix:** Standardize on `.easeInOut(duration: 0.20)` for all three, or extract a `static let kStandardAnim = Animation.easeInOut(duration: 0.20)` in a shared constants file. Apple's HIG points to 0.2-0.3s for state transitions.

---

### L2 — Tab bar icon for MetaClean (`eye.slash`) reads as "hidden" not "stripped"
**File:** `VideoCompressor/ios/ContentView.swift:65`
**Issue:** `eye.slash` is great for "hide content" but somewhat weak for "remove metadata fingerprints". `wand.and.stars` is on Compress (which is fine — magic compress) but it would also fit MetaClean ("magic clean"). Other candidates: `sparkles.rectangle.stack`, `square.and.line.vertical.and.square` (clear), `shield.checkered` (privacy-forward).
**Fix:** Test 2-3 alternates. My pick: `shield.checkered` — privacy framing matches the headline product. `wand.and.stars` should stay on Compress (the icon is also used on the Compress button in `VideoListView.swift:187`).

---

### L3 — Two ~485 / ~420 LOC view files that could split for maintainability
**Files:**
- `VideoCompressor/ios/Views/StitchTab/ClipEditorInlinePanel.swift` (485 LOC) — contains panel + still-preview subview + 4 ticker objects + drag handlers.
- `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` (420 LOC) — contains tab + aspect picker + transition picker + import logic + filename-staging extension.
**Severity:** LOW because both are functioning today and a refactor for refactor's sake risks regressions in the live-trim flow.
**Fix (deferred):** When you next touch either file: pull `StillPreview` (lines 449-485 of ClipEditorInlinePanel) into its own `Shared/StillPreview.swift` (it's already a candidate for reuse since `ClipLongPressPreview` in StitchTimelineView duplicates the same ImageIO logic at lines 314-330 — DRY win). Pull `importClips` (lines 242-374 of StitchTabView) into a `StitchImporter` service so the View shrinks to the SwiftUI body. Each refactor is ~30min.

---

## Areas already in good shape (no findings)

- **Empty states:** All three tabs (Compress, Stitch, MetaClean) use the shared `CenteredEmptyState` with a clear icon, title, message, and primary action button. Top-tier.
- **Loading states in inline editor:** `StillPreview.swift:454-462` shows a `ProgressView().tint(.white)` over black while ImageIO loads — exactly right.
- **Error alerts** with `recoverySuggestion` + "Open Settings" button (`VideoListView.swift:62-81`) — better than 90% of indie apps.
- **Save toast** with auto-dismiss + retry path (`VideoListView.swift:135-156`) — solid.
- **Haptic vocabulary:** `Haptics.tapLight / tapMedium / tapRigid / selectionTick / notifyWarning` is well-thought-out and used consistently across drag/drop, sort, split, delete.
- **Live-apply edits** in trim editor (no "Done" modal needed) — modern iOS pattern, reads as polished.
- **Drag preview** for timeline reorder (`StitchTimelineView.swift:104-113`) shows a semi-transparent floating thumbnail + medium haptic on lift — matches Photos.app feel.

---

## Quick-win punch list (in suggested order, ~12 hours total)

1. **C1** — One-line title fix. (5 min)
2. **H1, H3** — Copy polish on progress text + duration readout. (30 min)
3. **M5** — Strip `print()` calls; delete dead `ClipEditorSheet.swift` if unused. (15 min)
4. **L2** — Try `shield.checkered` for MetaClean tab. (5 min)
5. **H4** — Hide Crop tab behind aspect-ratio presets OR remove from v1.0. (1-2h)
6. **M3** — Add "About MetaClean" + Privacy + Support links to Settings. (1h)
7. **C2** — First-launch onboarding sheet (3 pages). (2-3h)
8. **H2** — Inline editor: drop the duplicate scissors icon, shorten hint. (30 min)
9. **H5** — Collapse aspect + transition pickers into a single Output pill. (1h)
10. **M1** — Animate drop indicator with neighbor-push. (45 min)
11. **M4** — Add `.accessibilityLabel` + `.accessibilityElement(.combine)` to row views. (1h)
12. **M2** — Add "Preview" item to clip context menu. (15 min)
13. **L1** — Standardize animation duration constant. (15 min)

---

## File-LOC snapshot (for refactor planning)

| File | LOC |
|---|---|
| ClipEditorInlinePanel.swift | 485 |
| StitchTabView.swift | 420 |
| StitchTimelineView.swift | 334 |
| TrimEditorView.swift | 257 |
| MetaCleanTabView.swift | 254 |
| StitchExportSheet.swift | 228 |
| VideoListView.swift | 208 |
| PresetPickerView.swift | 192 |
| VideoRowView.swift | 170 |
| MetaCleanExportSheet.swift | 149 |
| SettingsTabView.swift | 144 |
| CropEditorView.swift | 130 |
| ClipBlockView.swift | 116 |
| MetadataInspectorView.swift | 100 |
| ClipEditorSheet.swift | 82 |
| MetadataTagCardView.swift | 66 |
| PlaceholderTabView.swift | 59 |
| MetaCleanRowView.swift | 57 |
| CenteredEmptyState.swift | 54 |
| RotateEditorView.swift | 49 |
| EmptyStateView.swift | 39 |

Two files cross the 300-LOC line. Three more sit at 250-260 LOC. None of these are blockers; the architecture is healthy. Defer the splits until the next time you touch the file for a feature.
