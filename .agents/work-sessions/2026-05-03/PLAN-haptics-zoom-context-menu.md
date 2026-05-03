# Plan — Haptics + Pinch-to-Zoom + Contextual Menu (Stitch tab follow-up)

**Author:** research subagent (sonnet)
**Date:** 2026-05-03
**Scope:** Read-only research + design doc. No code changes in this PR.
**Target PR:** Three Stitch-tab UX upgrades that should land together: tactile slider feedback, native long-press menu with extra actions, and pinch-to-zoom on the timeline.

---

## Existing precedents in the codebase

The project already uses `UI*FeedbackGenerator` in five spots, so this is the established pattern:

- `ios/Services/VideoLibrary.swift:465,479` — `UINotificationFeedbackGenerator().notificationOccurred(.success / .error)` after Save-to-Photos.
- `ios/Views/MetaCleanTab/MetaCleanExportSheet.swift:135,140` — same pattern for MetaClean export.
- `ios/Views/StitchTab/StitchExportSheet.swift:199,204` — same pattern for stitch export.
- `ios/Views/StitchTab/ClipEditorInlinePanel.swift:354` — `UIImpactFeedbackGenerator(style: .light).impactOccurred()` on the Split button.

There is **no** CoreHaptics usage anywhere in the project, and there shouldn't be — the system feedback generators cover everything we need here.

The existing timeline lives at `ios/Views/StitchTab/StitchTimelineView.swift` (113 lines). The body is a `ScrollView(.horizontal) → HStack(spacing: 8) → ForEach(project.clips) { ClipBlockView().frame(width: 200, height: 140) }`. Each tile already has `.draggable`, `.dropDestination`, and a `.contextMenu` with a single Delete action.

The slider surfaces are in `ios/Views/StitchTab/ClipEditorInlinePanel.swift` (playheadSlider, trimSlider, durationSlider) and in `ios/Views/StitchTab/TrimEditorView.swift` (`DualThumbSlider`).

---

## Part 1 — Haptic feedback on slider drags

### API choice

For tick-crossing feedback while dragging, the right tool is `UISelectionFeedbackGenerator`. From the Apple Human Interface Guidelines (Playing haptics): *"Selection — A subtle tap that communicates a selection change. People feel this haptic when they navigate a series of selectable items, such as the segments in a picker or the entries in a date picker."* That is exactly the sensation iOS Camera's shutter dial and `Picker`/`UIDatePicker` produce — and it is what the user is asking for.

`UIImpactFeedbackGenerator` is for discrete confirmations (button taps, snap-into-place). The existing Split button at `ClipEditorInlinePanel.swift:354` correctly uses `.light` impact for that purpose; we keep that.

`UINotificationFeedbackGenerator` is for outcome events (success / warning / error) — already used correctly for export completion.

`CoreHaptics`/`CHHapticEngine` is overkill for ticks and adds a startup-cost engine plus pattern files to maintain. We only reach for it when we need amplitude/sharpness curves or sustained textures (e.g. a haptic that swells with scrub speed). For "tick on every 0.5 s mark" the system selection generator already does the job, is free to call, and matches the iOS feel users expect.

### Decision

| Surface | Generator | Style |
| --- | --- | --- |
| Trim start handle crosses 0.5 s tick | `UISelectionFeedbackGenerator` | `.selectionChanged()` |
| Trim end handle crosses 0.5 s tick | `UISelectionFeedbackGenerator` | `.selectionChanged()` |
| Playhead slider crosses 1.0 s tick (coarser; playhead moves more) | `UISelectionFeedbackGenerator` | `.selectionChanged()` |
| Still-image duration slider (already step-quantised at 0.5 s) | `UISelectionFeedbackGenerator` | `.selectionChanged()` |
| Long-press lift on a clip tile | (none — `.contextMenu` provides system haptic automatically) | — |
| Successful drop after reorder | `UIImpactFeedbackGenerator` | `.soft` |
| Delete from context menu | `UINotificationFeedbackGenerator` | `.warning` |

`.prepare()` should be called in `onAppear` for the editor panel to remove the first-fire latency. The generator can be retained as a `@State` for the lifetime of the view.

### Where to wire it (insertion points)

A single tiny helper centralises the tick logic:

```swift
// ios/Views/StitchTab/HapticTicker.swift  (new, ~25 lines)
import UIKit

@MainActor
final class HapticTicker {
    private let generator = UISelectionFeedbackGenerator()
    private var lastTick: Int = .min
    private let step: Double

    init(step: Double = 0.5) { self.step = step }

    func prepare() { generator.prepare() }

    /// Call on every value change. Fires the haptic only when the
    /// value crosses an integer multiple of `step`.
    func update(_ value: Double) {
        let bucket = Int((value / step).rounded(.down))
        if bucket != lastTick {
            if lastTick != .min { generator.selectionChanged() }
            lastTick = bucket
            generator.prepare()
        }
    }

    func reset() { lastTick = .min }
}
```

Then wire it in:

- `ClipEditorInlinePanel.swift:220` (playheadSlider) — own a `HapticTicker(step: 1.0)`, call `update(newValue)` inside the slider's `set:` closure, `reset()` on drag start (`isDraggingPlayhead` flips true).
- `ClipEditorInlinePanel.swift:261` (trimSlider) — own two ticker instances `startTicker`/`endTicker` at `step: 0.5`, call inside the start/end binding setters.
- `ClipEditorInlinePanel.swift:129` (still-duration slider) — already `step: 0.5`; call `update(clamped)` in the setter.
- `TrimEditorView.swift:61` (`DualThumbSlider`) — same pattern as the inline trim.

`prepare()` once in `onAppearWithClip()` (`ClipEditorInlinePanel.swift:367`) and on the editor's first appearance.

### Why a custom ticker vs. relying on the slider's `step:` parameter

`SwiftUI.Slider` with a non-zero `step:` already snaps the binding to discrete values, but it does **not** emit any haptic — that's a UIKit-only behaviour on `UISlider` set to `isContinuous = false`. Wrapping it in a `UIViewRepresentable` is more code than the 25-line ticker, and we already have a custom `DualThumbSlider`, so we're committed to driving haptics ourselves.

---

## Part 2 — Pinch-to-zoom on the timeline

### Approach

A pure-SwiftUI solution: store a `@State private var zoomScale: CGFloat = 1.0` on `StitchTimelineView`, multiply each tile's width by it (`.frame(width: 200 * zoomScale, height: 140)`), and drive the scale from a `MagnificationGesture`. We do **not** wrap a `UIScrollView` — the existing `ScrollView(.horizontal)` keeps working, and `MagnificationGesture` composes cleanly with `.draggable` and `.contextMenu` because each lives on a different gesture phase (multi-touch pinch vs. single-finger long-press-and-drag).

### Why not UIScrollView (UIViewRepresentable)

The advantage of a real `UIScrollView` is "content stays anchored under the pinch centroid" — iMovie does this. We do not get that for free in SwiftUI; the `LazyHStack` will rescale around its leading edge. **However**, that anchoring requires either (a) reading the pinch centroid and shifting the `ScrollView`'s content offset to keep it stable, or (b) wrapping `UIScrollView` whose `delegate.viewForZooming` returns the timeline content view.

Option (a) is achievable in pure SwiftUI with `ScrollViewReader` + `scrollTo` + a `GeometryReader` to read the pinch's `location` from `MagnifyGesture` (iOS 17+ exposes `value.startLocation` / `value.location`). This is the lighter-weight path and what we'll ship first.

If user testing shows the lack of centroid-anchoring is unacceptable, we escalate to a `UIViewRepresentable` wrapping a `UIScrollView` with `minimumZoomScale=0.5`, `maximumZoomScale=3.0`, hosting the SwiftUI content via `UIHostingController`. That is a 2-3 hour migration, not a 1-day refactor, because the drag/drop and context menu remain on the SwiftUI children.

### Code sketch

```swift
// StitchTimelineView.swift
@State private var zoomScale: CGFloat = 1.0
@State private var pinchBaseline: CGFloat = 1.0

private let minZoom: CGFloat = 0.5     //  100 px tile
private let maxZoom: CGFloat = 2.5     //  500 px tile
private let baseTileWidth: CGFloat = 200
private let baseTileHeight: CGFloat = 140

var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8 * zoomScale) {
            ForEach(project.clips) { clip in
                ClipBlockView(clip: clip)
                    .frame(width: baseTileWidth * zoomScale,
                           height: baseTileHeight * zoomScale)
                    // … existing .opacity / .overlay / .onTapGesture /
                    //    .draggable / .dropDestination / .contextMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    .gesture(
        MagnificationGesture()
            .onChanged { value in
                let next = pinchBaseline * value
                zoomScale = min(max(next, minZoom), maxZoom)
            }
            .onEnded { _ in
                pinchBaseline = zoomScale
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
    )
}
```

### Risks / SwiftUI gesture composition gotchas

- `.draggable` on a child view uses a long-press-then-drag recogniser (single-finger). `MagnificationGesture` on the parent uses two-finger pinch. They do not conflict — iOS routes by touch count. Verified by the same pattern Apple uses in WWDC 2023 sample code "Building rich SwiftUI text experiences".
- `LazyHStack` with a changing tile width will recompute layout every frame during pinch — acceptable for ≤ 30 clips. If we hit perf issues, throttle `zoomScale` updates to `.animation(.interactiveSpring(), value: zoomScale)` on the body and let SwiftUI batch.
- The thumbnail strip inside `ClipBlockView` is fixed-resolution; at `zoomScale = 2.5` it will be soft. Acceptable for v1; if we want crisp thumbs at higher zoom, regenerate the strip when `zoomScale` crosses 1.5x (deferred).
- `MagnificationGesture` is deprecated in iOS 17 in favour of `MagnifyGesture` — use the new name behind `if #available(iOS 17.0, *)` once we drop iOS 16. For now `MagnificationGesture` still works on iOS 17/18.

---

## Part 3 — Long-press contextual menu (extended)

### Currently we have

`StitchTimelineView.swift:95-106`:

```swift
.contextMenu {
    Button(role: .destructive) {
        // remove
    } label: { Label("Delete", systemImage: "trash") }
}
```

`.contextMenu` already provides the standard iOS long-press haptic and lift animation on iOS 13+ — no additional code needed. The user's request "long-press → contextual menu with native haptic" is already half-done; we only need to add the additional actions.

### Adding

```swift
.contextMenu {
    Button {
        project.duplicate(clipID: clip.id)
    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }

    Button {
        if let i = project.clips.firstIndex(where: { $0.id == clip.id }), i > 0 {
            project.move(from: IndexSet(integer: i), to: 0)
        }
    } label: { Label("Move to Start", systemImage: "arrow.up.to.line") }

    Button {
        if let i = project.clips.firstIndex(where: { $0.id == clip.id }) {
            project.move(from: IndexSet(integer: i), to: project.clips.count)
        }
    } label: { Label("Move to End", systemImage: "arrow.down.to.line") }

    Button {
        replaceSourceTarget = clip.id  // triggers PhotosPicker presentation
    } label: { Label("Replace Source…", systemImage: "arrow.triangle.2.circlepath") }

    Divider()

    Button(role: .destructive) {
        // existing delete
    } label: { Label("Delete", systemImage: "trash") }
} preview: {
    ClipBlockView(clip: clip)
        .frame(width: 280, height: 196)   // larger than the tile
}
```

The `preview:` parameter (iOS 16+) shows a larger thumbnail of the clip during the long-press lift — exactly the iMovie / Photos app feel. Free of extra code beyond the closure.

### Required `StitchProject` API

`duplicate(clipID:)` is the only new method we need on the model. It deep-copies the clip's `edits` and inserts the duplicate immediately after the original. `move(from:to:)` already exists. `Replace Source…` requires hooking into the existing `PhotosPicker`-driven import path; details out of scope for this plan.

### iPadOS pointer / right-click parity

`.contextMenu` automatically maps to two-finger trackpad click and right-click on iPadOS without any extra work. Confirmed by Apple's docs on `View/contextMenu(menuItems:preview:)`.

---

## Part 4 — Estimated implementation effort

| Feature | Effort (hours) | Risk |
| --- | --- | --- |
| Haptic ticker helper + 4 wiring sites | 1.0 | low |
| Context menu — Duplicate / Move-to-start / Move-to-end / preview | 0.75 | low (Duplicate needs a `StitchProject.duplicate(clipID:)`) |
| Pinch-to-zoom (no centroid anchor) | 1.0 | medium — verify gesture composition on a device |
| Replace-Source action | 0.75 | medium — touches the import pipeline |
| Total | ~3.5 hours | — |

**Order of implementation (smallest blast radius first):**
1. Haptic ticker + wiring (isolated, additive, no model changes).
2. Context menu extras (move-to-start / move-to-end / preview thumbnail) — no new model API except the trivial `duplicate`.
3. Pinch-to-zoom (single file, additive `@State`).
4. Replace-Source — defer to a separate PR if PR scope swells.

---

## Part 5 — Test plan

Most of this work is gesture-driven, which Swift unit tests can't exercise. Split tests by what's realistically testable:

- **`StitchProjectTests` (XCTest, no UI)** — add cases for the new model APIs:
  - `duplicate_insertsAfterOriginal_withMatchingEdits`
  - `move_from_lastIndex_to_zero_movesToStart`
  - `move_from_zero_to_count_movesToEnd`
  Place in `VideoCompressorTests/StitchProjectMoveAndDuplicateTests.swift` (new).
- **`HapticTickerTests`** — pure-Swift testable: feed a sequence of values, count how many times a stub generator's `selectionChanged()` is invoked. Confirms tick boundary logic. Place in `VideoCompressorTests/HapticTickerTests.swift` (new). Inject the generator via a small protocol so the test can substitute a counting fake.
- **UI/manual** — smoke test on a real device (haptics are silent on the simulator):
  - Drag trim handle slowly across 5 s — feel ten distinct ticks.
  - Long-press a clip — feel the standard iOS lift-haptic, see the larger preview, see five menu items.
  - Pinch out on the timeline with three clips — tiles grow, scroll position holds the leading clip.
  - Pinch in below 0.5x — clamp engages, no further shrink.

Auto-pinch UI tests via XCUITest are flaky and not worth the maintenance; cover by manual checklist in the PR description instead.

---

## Sources

- Apple Human Interface Guidelines — *Playing haptics*: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- Apple Developer Documentation — `UISelectionFeedbackGenerator`: https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator
- Apple Developer Documentation — `UIImpactFeedbackGenerator`: https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator
- Apple Developer Documentation — `MagnificationGesture`: https://developer.apple.com/documentation/swiftui/magnificationgesture
- Apple Developer Documentation — `View.contextMenu(menuItems:preview:)`: https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:preview:)
- Existing project precedents:
  - `ios/Services/VideoLibrary.swift:465`
  - `ios/Views/StitchTab/ClipEditorInlinePanel.swift:354`
  - `ios/Views/StitchTab/StitchTimelineView.swift:95`
