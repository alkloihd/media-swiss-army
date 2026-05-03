# Stitch + MetaClean Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-05-03
**Branch:** `feature/metaclean-stitch` (current worktree: `claude/jolly-pare-f79c78`)
**Status:** Draft
**Spec:** `docs/superpowers/specs/2026-04-09-ios-app-design.md` sections 4 (Stitch) & 5 (MetaClean)
**Phased plan reference:** `docs/superpowers/plans/2026-04-10-ios-app-phase1-2.md`
**Phase 1 baseline commit:** `5db2187` (Compress flow with AVAssetExportSession + 4-reviewer audit fixes)
**Latest log entries informing this plan:** `{E-0503-0935}`, `{E-0503-0936}`, `{E-0503-0938}` in `.agents/work-sessions/2026-05-03/AI-CHAT-LOG.md`

**Goal:** Ship two independent feature tabs — a visual Stitch timeline with per-clip trim/crop/reorder where editing is lazy and only renders at export, and a MetaClean tab that strips metadata via remux (no re-encode) with a clear "save new" vs "delete original" UX that respects iOS Photos library constraints.

**Architecture:** Both features sit beside the existing Compress tab in a `TabView` shell. Stitch composes existing primitives — it stores per-clip operations as plain Swift values, builds an `AVMutableComposition` only at export time, and reuses the AVAssetWriter pipeline planned for Compress phase 2 (or `AVAssetExportPresetPassthrough` when clips are codec-compatible and untrimmed). MetaClean uses a separate `MetadataService` that reads via `AVAsset.metadata` / `CGImageSource`, then writes a clean copy via `AVAssetWriter` with `metadata = []` and pass-through tracks (no re-encode) — never overwriting the source.

**Tech Stack:** SwiftUI (iOS 17+), AVFoundation (`AVMutableComposition`, `AVAssetWriter`, `AVAssetReader`, `AVAssetImageGenerator`), PhotosUI (`PhotosPicker`), PhotoKit (`PHPhotoLibrary`, `PHAssetChangeRequest`), CoreGraphics (`CGImageSource` / `CGImageDestination` for stills in v2).

---

## Q&A — Direct Answers to User Questions

**Q1. "Will that work with individual videos where they all show up in the «stitch» timeline but can be clicked on and cropped or shortened or edited before stitching?"**

Yes. Each imported clip becomes a `StitchClip` value containing `sourceURL`, `naturalDuration`, and a `var edits: ClipEdits` field. Tapping a clip presents a `ClipEditorSheet` with three tabs: Trim, Crop, Rotate. Edits are applied to the in-memory `edits` value only — no file is touched. The timeline re-renders the affected `ClipBlockView` to reflect new duration / crop preview.

**Q2. "How easily can I add videos to be stitched?"**

`PhotosPicker(selection: ..., maxSelectionCount: 20, matching: .videos, preferredItemEncoding: .current)` gives multi-select natively. The picker returns `[PhotosPickerItem]`; we `loadTransferable(type: VideoFile.self)` for each in parallel via a `TaskGroup`, copy to `Documents/StitchInputs/`, append to the timeline. There is also an "Add more" button at the right edge of the timeline that re-opens the picker — selections are appended, never replaced.

**Q3. "Do we have press and hold to reorder them also?"**

Yes. Two reorder mechanisms are recommended:

- **Primary (smoother on iOS 17):** SwiftUI `List` with `.onMove(perform:)` inside an `EditButton`-controlled environment. Press-and-hold gesture is built in; reorder feels native; works with VoiceOver. We use a horizontally-laid-out `List` via `.listStyle(.plain)` + custom row insets to mimic a timeline track.
- **Alternate (more "timeline-ish"):** SwiftUI `.draggable(StitchClipID)` + `.dropDestination(for: StitchClipID.self)` on each block. Lets users drag freely to any position with live insertion indicators. Slightly more work to make accessible.

We ship `.onMove` first (one commit), then layer `.draggable/.dropDestination` over it as a follow-up if the timeline UX feels constrained. Code skeleton is in Task S5.

**Q4. "I'd like to be able to easily reorder visually and cut or trim or crop videos if possible where all the processing happens at the end."**

Confirmed lazy-processing model. The pipeline:

```
Import → StitchClip { url, naturalDuration, edits=.identity }
Tap → ClipEditorSheet mutates clip.edits in place (trim, crop, rotation)
Reorder → reorders the [StitchClip] array
Stitch & Export → StitchExporter builds AVMutableComposition from the array,
                  applies edits as composition instructions, then runs the
                  writer pipeline once.
```

Memory cost while editing N clips: O(N) `StitchClip` values + O(N) cached thumbnail strips. No transcoded bytes until the user taps Export.

**Q5. "How will things be saved natively to the gallery for individual meta data stripping — can this work by overwriting the file? Or will it compress and save a new version?"**

iOS does not let third-party apps overwrite Photos-library assets in place. Apple's `PHAssetChangeRequest` API exposes only `creationRequestForAsset(...)`, `deleteAssets(...)`, and edit-via-content-editing-output (which requires per-asset adjustment data and is gated on user re-confirmation each time). So the cleanest UX:

- **Default:** "Save Cleaned Copy" — writes a new asset to Photos with `_CLEAN` suffix. Original is untouched.
- **Optional toggle:** "Delete Original After Save" — when enabled, after the new asset is saved successfully, run `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(...) }`. iOS shows a system confirmation dialog ("Delete photo?") — we can't suppress that. The user taps Delete; the original moves to Recently Deleted (recoverable for 30 days).

This is the closest thing to "overwriting" iOS will allow. We surface this constraint inline in the UI as a one-line note next to the toggle: "iOS doesn't allow apps to edit Photos in place — we save a clean copy and (optionally) delete the original."

The stripping itself is **remux, not re-encode** — `AVAssetWriter` with `outputSettings: nil` on each input passes the original encoded samples through unchanged. Pixel quality is bit-identical; only the metadata atom is rewritten.

---

## Goals

- Add a **Stitch tab** that imports multiple videos, displays them on a horizontal timeline with thumbnails, allows per-clip trim / crop / rotate edits in a sheet, supports press-and-hold reorder, and only encodes at export.
- Add a **MetaClean tab** that imports videos, shows their metadata grouped by category, strips selected categories via remux, and saves a clean copy to Photos with an optional "delete original" follow-up.
- Both tabs honor the existing `_STITCH` / `_CLEAN` filename convention from `MEMORY.md`.
- Reuse the type-design refactors from `{E-0503-0936}` (BoundedProgress, CompressedOutput, CompressionSettings) — extend them rather than fork new shapes.
- Ship in 4–6 reviewable commits; each commit must build green and leave the app launchable.

## Non-Goals

- **Color grading, filters, audio mixing, multi-track editing, transitions** — out of scope. Stitch is concat-with-cuts-and-crops only.
- **Photo (HEIC / JPEG) metadata stripping** — defer to Phase 3 per `{E-0503-0938}`. MetaClean v1 ships videos only.
- **In-place Photos overwrite** — Apple's API surface does not permit this; explained in Q5.
- **Lossless concat across mixed codecs** — not attempted in v1; if codecs/dimensions/fps differ, we always re-encode. Lossless detection added later as a perf optimization.
- **Background `BGProcessingTask`** — keep encode foreground for now; user must keep the app open. Spec section 7 lists this as a future concern.
- **Multi-clip cropping with different aspect ratios** — v1 applies the same crop per clip individually; the export composition uses `renderSize` from each clip's edited rect, so the final video may have varying frame sizes via letterbox. v2 can offer a "unify aspect ratio" toggle.

---

## Architecture Diagram

```
                   ┌─────────────────────────────────────────────┐
                   │ VideoCompressorApp (TabView shell)           │
                   ├──────────────┬──────────────┬───────────────┤
                   │ Compress     │ Stitch       │ MetaClean     │
                   │ (Phase 1)    │ (this plan)  │ (this plan)   │
                   └──────┬───────┴──────┬───────┴──────┬────────┘
                          │              │              │
                          ▼              ▼              ▼
              VideoLibrary       StitchProject    MetaCleanQueue
              @MainActor SO      @MainActor SO    @MainActor SO
                          │              │              │
                          └──────────┬───┴──────────────┘
                                     ▼
                          ┌─────────────────────┐
                          │ Shared Models       │
                          │ - VideoMetadata     │
                          │ - BoundedProgress   │
                          │ - CompressedOutput  │
                          │ - CompressionSettings│
                          └─────────────────────┘
                                     │
                  ┌──────────────────┼─────────────────┐
                  ▼                  ▼                 ▼
          CompressionService  StitchExporter   MetadataService
          (actor, AV writer)  (actor)          (actor)
                  │                  │                 │
                  │                  ▼                 │
                  │     AVMutableComposition           │
                  │     (built lazily at export)       │
                  ▼                  ▼                 ▼
               AVAssetWriter pipeline (shared)    AVAssetWriter remux
               • per-track read/write             • outputSettings: nil
               • bitrate caps                     • metadata: filtered
               • progress @ 10 Hz                 • progress @ 10 Hz
                                                  │
                                                  ▼
                                       PhotosSaver (existing)
                                       + optional delete-original
```

`StitchExporter` does **not** duplicate `CompressionService`'s encoding logic. It builds the `AVMutableComposition`, computes a single `CompressionSettings` for the output (or detects passthrough is safe), then hands the composition off to a small extension on `CompressionService` that accepts an `AVAsset` instead of a URL. This keeps the encode pipeline DRY across Compress and Stitch.

---

## File Structure

New files under `VideoCompressor/ios/`:

```
Models/
  StitchClip.swift                   # StitchClip, ClipEdits, CropRect, Rotation
  StitchProject.swift                # @MainActor ObservableObject; clip array + reorder
  MetadataTag.swift                  # MetadataTag, MetadataCategory, StripRules

Services/
  StitchExporter.swift               # actor; build AVMutableComposition + delegate to writer
  MetadataService.swift              # actor; read AVAsset.metadata, write clean remux
  ThumbnailStripGenerator.swift      # actor; AVAssetImageGenerator wrapper

Views/StitchTab/
  StitchTabView.swift                # tab root; project state + import button
  StitchTimelineView.swift           # horizontal List with .onMove
  ClipBlockView.swift                # one clip's row: thumbnails + duration badge
  ClipEditorSheet.swift              # tap-to-edit sheet (Trim / Crop / Rotate tabs)
  TrimEditorView.swift               # dual-handle trim slider over scrubber
  CropEditorView.swift               # rect overlay over preview frame
  StitchExportSheet.swift            # final compression settings + Export button

Views/MetaCleanTab/
  MetaCleanTabView.swift             # tab root; queue state + import + scan
  MetadataInspectorView.swift        # tag-card list grouped by category
  MetadataTagCardView.swift          # one tag card with red/green strip indicator
  MetaCleanExportSheet.swift         # save options (new copy / delete original toggle)
```

Modified existing files:

- `VideoCompressorApp.swift` — wrap root in `TabView` with three tabs (Stitch shell already arrives in Phase 2 commit 1 per `{E-0503-0938}`; this plan assumes that has landed).
- `Models/VideoFile.swift` — adopt `BoundedProgress` and `CompressedOutput` types from `{E-0503-0936}` if not already done.
- `Services/CompressionService.swift` — add overload `encode(asset:settings:onProgress:)` that takes an `AVAsset` (so `StitchExporter` can hand it the composition). The URL-based `compress(...)` becomes a thin wrapper that constructs an `AVURLAsset`.
- `Services/PhotosSaver.swift` — add `saveAndOptionallyDeleteOriginal(newURL:originalAssetID:)` for MetaClean.

Xcode 16 file-system synchronized groups mean adding files to these folders requires zero `.pbxproj` edits.

---

## Tasks

Each task lists files, a code skeleton where load-bearing, and a tight checkbox sequence. TDD where the seam supports it (model + service tests). UI tasks lean on simulator launch + screenshot verification because SwiftUI tests are flaky for gesture-heavy views.

---

### Task S1: `StitchClip` and `ClipEdits` model — S

**Files:**
- Create: `VideoCompressor/ios/Models/StitchClip.swift`
- Test: `VideoCompressor_iOSTests/StitchClipTests.swift` (file may need to be added to test target)

**Skeleton:**

```swift
import Foundation
import AVFoundation
import CoreGraphics

struct StitchClip: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    let naturalDuration: CMTime
    let naturalSize: CGSize
    var edits: ClipEdits

    /// Effective duration after trim, in seconds.
    var trimmedDurationSeconds: Double {
        let total = CMTimeGetSeconds(naturalDuration)
        let start = edits.trimStartSeconds ?? 0
        let end = edits.trimEndSeconds ?? total
        return max(0, end - start)
    }
}

struct ClipEdits: Hashable, Sendable {
    /// nil = use clip start (0). In source clip seconds.
    var trimStartSeconds: Double?
    /// nil = use clip end (naturalDuration). In source clip seconds.
    var trimEndSeconds: Double?
    /// Crop rect in normalized 0...1 coordinates over the clip's natural size.
    /// nil = no crop.
    var cropNormalized: CGRect?
    /// 0 / 90 / 180 / 270 — clockwise rotation applied at render time.
    var rotationDegrees: Int

    static let identity = ClipEdits(
        trimStartSeconds: nil,
        trimEndSeconds: nil,
        cropNormalized: nil,
        rotationDegrees: 0
    )
}
```

- [ ] **Step 1:** Write failing test `StitchClipTests.testTrimmedDurationFollowsEdits` — assert default `trimmedDurationSeconds` equals natural, and after setting `trimStart=2, trimEnd=5` on a 10s clip equals 3.
- [ ] **Step 2:** Run test, verify it fails (no `StitchClip` type yet).
- [ ] **Step 3:** Write the file above.
- [ ] **Step 4:** Run test, verify pass.
- [ ] **Step 5:** Add boundary tests: trim values clamped negative, trim end before trim start, full crop rect normalization. Implement clamping in computed property.
- [ ] **Step 6:** Commit `feat(ios): add StitchClip and ClipEdits value types`.

---

### Task S2: `StitchProject` ObservableObject — S

**Files:**
- Create: `VideoCompressor/ios/Models/StitchProject.swift`
- Test: `VideoCompressor_iOSTests/StitchProjectTests.swift`

**Skeleton:**

```swift
@MainActor
final class StitchProject: ObservableObject {
    @Published private(set) var clips: [StitchClip] = []
    @Published var exportProgress: BoundedProgress = .zero
    @Published var exportState: StitchExportState = .idle
    @Published var lastError: StitchError?

    private let inputsDir: URL
    private let exporter: StitchExporter

    init(exporter: StitchExporter = StitchExporter()) {
        self.exporter = exporter
        self.inputsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StitchInputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: inputsDir, withIntermediateDirectories: true)
    }

    func append(_ clip: StitchClip) { clips.append(clip) }
    func remove(at offsets: IndexSet) { clips.remove(atOffsets: offsets) }
    func move(from src: IndexSet, to dst: Int) { clips.move(fromOffsets: src, toOffset: dst) }
    func updateEdits(for id: StitchClip.ID, _ apply: (inout ClipEdits) -> Void) { /* mutate by id */ }
}

enum StitchExportState: Hashable, Sendable {
    case idle, building, encoding, finished(CompressedOutput), cancelled
}
```

- [ ] **Step 1:** Write failing tests for `append`, `remove`, `move`, `updateEdits`.
- [ ] **Step 2:** Run, fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run, pass.
- [ ] **Step 5:** Commit `feat(ios): StitchProject ObservableObject with reorderable clips`.

---

### Task S3: `ThumbnailStripGenerator` actor — S

**Files:**
- Create: `VideoCompressor/ios/Services/ThumbnailStripGenerator.swift`

```swift
actor ThumbnailStripGenerator {
    /// Returns evenly-spaced thumbnails across the clip's natural duration.
    func generate(for asset: AVURLAsset, count: Int, maxDimension: CGFloat) async throws -> [CGImage] {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .positiveInfinity

        let duration = try await asset.load(.duration)
        let total = CMTimeGetSeconds(duration)
        let times: [CMTime] = (0..<count).map { i in
            CMTime(seconds: total * Double(i) / Double(max(count, 1)), preferredTimescale: 600)
        }
        // Use `images(for: times)` async sequence (iOS 16+).
        var out: [CGImage] = []
        for try await result in gen.images(for: times) {
            if case .success(_, let cg, _) = result { out.append(cg) }
        }
        return out
    }
}
```

- [ ] **Step 1:** Write a smoke test using a bundled fixture mp4 — assert exactly N frames returned.
- [ ] **Step 2:** Implement and pass.
- [ ] **Step 3:** Commit `feat(ios): thumbnail strip generator for stitch timeline`.

---

### Task S4: `StitchTabView` shell + PhotosPicker import — S

**Files:**
- Create: `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift`
- Modify: `VideoCompressor/ios/VideoCompressorApp.swift` (replace existing Stitch placeholder)

```swift
struct StitchTabView: View {
    @StateObject private var project = StitchProject()
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if project.clips.isEmpty {
                    EmptyStateView(
                        title: "No clips yet",
                        message: "Pick videos to stitch together.",
                        systemImage: "film.stack"
                    )
                } else {
                    StitchTimelineView(project: project)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 20,
                        matching: .videos,
                        preferredItemEncoding: .current
                    ) { Label("Add", systemImage: "plus") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Stitch & Export") { /* present StitchExportSheet */ }
                        .disabled(project.clips.count < 2)
                }
            }
            .onChange(of: pickerItems) { _, items in importClips(items) }
        }
    }
}
```

- [ ] **Step 1:** Add file with the body above plus a stub `importClips` that just appends placeholder clips.
- [ ] **Step 2:** Wire `VideoCompressorApp` `TabView` to mount `StitchTabView` for the Stitch tab.
- [ ] **Step 3:** Build via XcodeBuildMCP `build_run_sim`. Verify 3 tabs appear, Stitch tab shows empty state.
- [ ] **Step 4:** Implement `importClips` end-to-end: per item, `loadTransferable(type: VideoFile.self)` (reuse the existing `VideoTransferable` shape), copy into `Documents/StitchInputs/`, build `StitchClip` (via `AVURLAsset.load(.duration, .tracks)`), append to project.
- [ ] **Step 5:** Inject test fixture via `xcrun simctl addmedia`, manually verify import flow.
- [ ] **Step 6:** Commit `feat(ios): StitchTabView with PhotosPicker multi-import`.

---

### Task S5: `StitchTimelineView` with `.onMove` reorder — M

**Files:**
- Create: `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift`
- Create: `VideoCompressor/ios/Views/StitchTab/ClipBlockView.swift`

```swift
struct StitchTimelineView: View {
    @ObservedObject var project: StitchProject
    @State private var editingClipID: StitchClip.ID?

    var body: some View {
        List {
            ForEach(project.clips) { clip in
                ClipBlockView(clip: clip)
                    .contentShape(Rectangle())
                    .onTapGesture { editingClipID = clip.id }
            }
            .onMove(perform: project.move(from:to:))
            .onDelete(perform: project.remove(at:))
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active)) // always-on reorder + delete
        .sheet(item: Binding(
            get: { project.clips.first(where: { $0.id == editingClipID }) },
            set: { newValue in editingClipID = newValue?.id }
        )) { clip in
            ClipEditorSheet(project: project, clipID: clip.id)
        }
    }
}
```

Why `List + .onMove` over `.draggable / .dropDestination` for v1: native press-and-hold gesture, accessible by default, less custom hit-testing, ships in fewer LoC. Switch to draggable/drop only if the user feedback says timeline-feel matters more than accessibility.

- [ ] **Step 1:** Stub `ClipBlockView` with name + duration label only.
- [ ] **Step 2:** Add `StitchTimelineView` with the body above.
- [ ] **Step 3:** Build & run; manually verify reorder (long-press, drag) and swipe-to-delete on simulator.
- [ ] **Step 4:** Wire `ThumbnailStripGenerator` into `ClipBlockView` (async-load 4 thumbnails as `HStack` background, `.task` lifecycle).
- [ ] **Step 5:** Commit `feat(ios): stitch timeline with reorder + thumbnails`.

---

### Task S6: `ClipEditorSheet` with Trim, Crop, Rotate tabs — M

**Files:**
- Create: `VideoCompressor/ios/Views/StitchTab/ClipEditorSheet.swift`
- Create: `VideoCompressor/ios/Views/StitchTab/TrimEditorView.swift`
- Create: `VideoCompressor/ios/Views/StitchTab/CropEditorView.swift`

```swift
struct ClipEditorSheet: View {
    @ObservedObject var project: StitchProject
    let clipID: StitchClip.ID
    @Environment(\.dismiss) private var dismiss
    @State private var draftEdits: ClipEdits = .identity

    var body: some View {
        NavigationStack {
            TabView {
                TrimEditorView(clip: clip, edits: $draftEdits)
                    .tabItem { Label("Trim", systemImage: "scissors") }
                CropEditorView(clip: clip, edits: $draftEdits)
                    .tabItem { Label("Crop", systemImage: "crop") }
                RotateEditorView(edits: $draftEdits)
                    .tabItem { Label("Rotate", systemImage: "rotate.right") }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        project.updateEdits(for: clipID) { $0 = draftEdits }
                        dismiss()
                    }
                }
            }
            .onAppear { draftEdits = clip.edits }
        }
    }

    private var clip: StitchClip {
        project.clips.first(where: { $0.id == clipID })!
    }
}
```

- [ ] **Step 1:** Stub the three editor views with placeholder controls returning `draftEdits` unchanged.
- [ ] **Step 2:** Implement `TrimEditorView` — dual-handle slider over a static thumbnail strip; bind to `draftEdits.trimStartSeconds` / `trimEndSeconds`. Use `Slider` for v1 (single thumb pair via two `Slider`s side-by-side); custom dual-thumb in v2.
- [ ] **Step 3:** Implement `CropEditorView` — overlay a `Rectangle` with `DragGesture` corners over a `VideoPlayer` snapshot or first thumbnail; bind to `draftEdits.cropNormalized`. v1 supports free crop only; aspect-locked presets in v2.
- [ ] **Step 4:** Implement `RotateEditorView` — four buttons (0/90/180/270) toggling `draftEdits.rotationDegrees`; show a preview rotated via `.rotationEffect`.
- [ ] **Step 5:** Manual sim test: tap clip, edit trim, hit Done, verify timeline reflects new duration; reopen and edit again — values persisted.
- [ ] **Step 6:** Commit `feat(ios): per-clip editor sheet with trim/crop/rotate`.

---

### Task S7: `StitchExporter` builds `AVMutableComposition` lazily — L

**Files:**
- Create: `VideoCompressor/ios/Services/StitchExporter.swift`
- Modify: `VideoCompressor/ios/Services/CompressionService.swift` (add `encode(asset:settings:onProgress:)` overload)

```swift
actor StitchExporter {
    struct Plan {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?  // nil if no crop/rotate needed
        let renderSize: CGSize
        let canPassthrough: Bool  // all clips share codec + dims + fps + no edits
    }

    func buildPlan(from clips: [StitchClip]) async throws -> Plan {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw StitchError.compositionInsertFailed }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor: CMTime = .zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var anyEdit = false

        for clip in clips {
            let asset = AVURLAsset(url: clip.sourceURL)
            let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first!
            let timeRange = clip.cmTrimRange()  // CMTimeRange from edits.trimStart/End

            try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: cursor)
            if let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: assetAudio, at: cursor)
            }
            // Emit a per-segment instruction if crop/rotate present.
            if clip.edits.cropNormalized != nil || clip.edits.rotationDegrees != 0 {
                anyEdit = true
                instructions.append(buildInstruction(clip: clip, track: videoTrack, at: cursor))
            }
            cursor = CMTimeAdd(cursor, timeRange.duration)
        }

        let videoComposition: AVMutableVideoComposition?
        if anyEdit {
            let vc = AVMutableVideoComposition()
            vc.instructions = instructions
            vc.frameDuration = CMTime(value: 1, timescale: 30)
            vc.renderSize = computeRenderSize(clips: clips)
            videoComposition = vc
        } else {
            videoComposition = nil
        }

        return Plan(
            composition: composition,
            videoComposition: videoComposition,
            renderSize: computeRenderSize(clips: clips),
            canPassthrough: !anyEdit && allClipsShareFormat(clips)
        )
    }

    func export(
        plan: Plan,
        settings: CompressionSettings,
        outputURL: URL,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        if plan.canPassthrough {
            // Use AVAssetExportSession with AVAssetExportPresetPassthrough — fastest path.
        } else {
            // Hand off to CompressionService.encode(asset: plan.composition, ...).
        }
        return outputURL
    }
}
```

- [ ] **Step 1:** Add `CompressionService.encode(asset:settings:onProgress:)` overload taking `AVAsset` (refactor existing `compress(input:...)` to call into this).
- [ ] **Step 2:** Implement `StitchExporter.buildPlan` with empty `instructions` (no crop/rotate yet).
- [ ] **Step 3:** Implement `StitchExporter.export` passthrough branch. Test: 2-clip stitch, no edits, all matching codec → check output file exists, plays in QuickTime.
- [ ] **Step 4:** Implement `buildInstruction` for crop (use `setCropRectangle(_:at:)` on `AVMutableVideoCompositionLayerInstruction`).
- [ ] **Step 5:** Implement rotation via `setTransform(_:at:)` on the same layer instruction.
- [ ] **Step 6:** Implement re-encode branch — wire to `CompressionService.encode(asset:settings:onProgress:)`.
- [ ] **Step 7:** End-to-end manual test on simulator: 2 clips, trim one, export, verify duration in result.
- [ ] **Step 8:** Commit `feat(ios): StitchExporter with passthrough + re-encode paths`.

---

### Task S8: `StitchExportSheet` + Save to Photos — S

**Files:**
- Create: `VideoCompressor/ios/Views/StitchTab/StitchExportSheet.swift`

- [ ] **Step 1:** Settings selector reuses `MatrixGridView` (or current `PresetPickerView` if matrix not yet landed) bound to a local `CompressionSettings`.
- [ ] **Step 2:** "Export" button calls `project.export(settings:)` which delegates to `StitchExporter` with progress streaming to `project.exportProgress`.
- [ ] **Step 3:** On finish, present standard `PhotosSaver.saveVideo(at:)` flow.
- [ ] **Step 4:** Commit `feat(ios): stitch export sheet wires settings + save-to-Photos`.

---

### Task M1: `MetadataTag` + category model — S

**Files:**
- Create: `VideoCompressor/ios/Models/MetadataTag.swift`

```swift
struct MetadataTag: Identifiable, Hashable, Sendable {
    let id: UUID
    let key: String              // e.g. "com.apple.quicktime.location.ISO6709"
    let displayName: String
    let value: String
    let category: MetadataCategory
    let isMetaFingerprint: Bool  // true for the binary-Comment-with-Meta-fingerprint case
}

enum MetadataCategory: String, CaseIterable, Hashable, Sendable {
    case device, location, time, technical, custom

    var displayName: String { /* localized name */ "" }
    var systemImage: String { /* SF Symbol */ "" }
}

struct StripRules: Hashable, Sendable {
    var stripCategories: Set<MetadataCategory>
    var stripMetaFingerprintAlways: Bool

    static let autoMetaGlasses = StripRules(
        stripCategories: [.custom],
        stripMetaFingerprintAlways: true
    )
    static let stripAll = StripRules(
        stripCategories: Set(MetadataCategory.allCases).subtracting([.technical]),
        stripMetaFingerprintAlways: true
    )
}
```

- [ ] **Step 1:** Tests for `StripRules.autoMetaGlasses` membership.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** Commit `feat(ios): MetadataTag + StripRules model`.

---

### Task M2: `MetadataService` — read + remux strip — L

**Files:**
- Create: `VideoCompressor/ios/Services/MetadataService.swift`

```swift
actor MetadataService {
    func read(url: URL) async throws -> [MetadataTag] {
        let asset = AVURLAsset(url: url)
        let common = try await asset.load(.metadata)
        let qt = try await asset.loadMetadata(for: .quickTimeMetadata)
        let user = try await asset.loadMetadata(for: .quickTimeUserData)
        return (common + qt + user).map { item in
            classify(item)  // → MetadataTag with category + isMetaFingerprint
        }
    }

    /// Remux the source URL with metadata filtered per `rules`. No re-encode.
    func strip(url sourceURL: URL, rules: StripRules) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let outputURL = Self.cleanedURL(for: sourceURL)
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Pass-through every track with outputSettings: nil — no re-encode.
        for track in try await asset.loadTracks(withMediaType: .video) {
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            // … reader pump using AVAssetReaderTrackOutput with outputSettings: nil
        }
        // Same for audio tracks.

        // Filter metadata per rules.
        let kept = try await asset.load(.metadata).filter { !shouldStrip($0, rules: rules) }
        writer.metadata = kept

        // … run reader/writer pump, finishWriting.
        return outputURL
    }

    static func cleanedURL(for source: URL) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Cleaned", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)_CLEAN.mp4")
    }
}
```

- [ ] **Step 1:** Unit test `read(url:)` against the bundled Meta-glasses fixture (commits `be6e360`, `a3ad413` reference the fingerprint atoms). Assert at least one `isMetaFingerprint == true` tag is returned.
- [ ] **Step 2:** Implement `read`, pass test.
- [ ] **Step 3:** Unit test `strip(url:rules:)` with `.autoMetaGlasses` — call `read` on the output and assert no `isMetaFingerprint == true` tag remains, and that video duration / track codec / dimensions are bit-identical to source.
- [ ] **Step 4:** Implement reader/writer pump (mirror the Phase 2 AVAssetWriter pipeline drafted in `{E-0503-0938}` Gap 3, but simpler — `outputSettings: nil` everywhere). Pass test.
- [ ] **Step 5:** Edge case: file with no metadata at all — `strip` should still succeed and produce a valid output.
- [ ] **Step 6:** Commit `feat(ios): MetadataService with read + remux-strip`.

---

### Task M3: `MetaCleanTabView` + `MetadataInspectorView` — M

**Files:**
- Create: `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift`
- Create: `VideoCompressor/ios/Views/MetaCleanTab/MetadataInspectorView.swift`
- Create: `VideoCompressor/ios/Views/MetaCleanTab/MetadataTagCardView.swift`

- [ ] **Step 1:** `MetaCleanTabView` mirrors `StitchTabView` shape — `PhotosPicker` import, list of imported videos, tapping one routes to `MetadataInspectorView`.
- [ ] **Step 2:** `MetadataInspectorView` calls `MetadataService.read(url:)` on appear, groups results by `category`, renders `MetadataTagCardView` per tag.
- [ ] **Step 3:** Each card uses red border + strikethrough when its category is in the active `StripRules`, green border otherwise. Tapping a category header in Manual mode toggles its membership.
- [ ] **Step 4:** Mode picker at top: Auto (Meta glasses) / Manual / Strip All — bound to `@State StripRules`.
- [ ] **Step 5:** "Clean" button in toolbar opens `MetaCleanExportSheet`.
- [ ] **Step 6:** Commit `feat(ios): metaclean tab with metadata inspector`.

---

### Task M4: `MetaCleanExportSheet` with save-options + delete-original toggle — M

**Files:**
- Create: `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanExportSheet.swift`
- Modify: `VideoCompressor/ios/Services/PhotosSaver.swift` — add `saveAndOptionallyDeleteOriginal(...)`

```swift
extension PhotosSaver {
    /// Saves `cleanedURL` as a new asset. If `originalAssetID` non-nil and
    /// `deleteOriginal` true, fires a separate change request to delete the
    /// original. iOS will surface a system confirmation dialog for the delete.
    func saveAndOptionallyDeleteOriginal(
        cleanedURL: URL,
        originalAssetID: String?,
        deleteOriginal: Bool
    ) async throws {
        try await saveVideo(at: cleanedURL)  // existing helper

        guard deleteOriginal, let id = originalAssetID else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard assets.count > 0 else { return }

        try await PHPhotoLibrary.shared().performChangesAndWait {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }
}
```

- [ ] **Step 1:** Sheet UI: filename preview (`<original>_CLEAN.mp4`), `Toggle("Delete original after save")` with helper text "iOS will ask you to confirm. Original moves to Recently Deleted (recoverable for 30 days)."
- [ ] **Step 2:** Track the original `PHAsset` localIdentifier through the import chain — extend `VideoTransferable` to carry it (currently we lose it after the picker hands us a URL). Use `PhotosPickerItem.itemIdentifier`.
- [ ] **Step 3:** "Clean & Save" button runs `MetadataService.strip(url:rules:)`, then `PhotosSaver.saveAndOptionallyDeleteOriginal`.
- [ ] **Step 4:** Manual sim test: import test fixture, scan, run Auto mode, verify clean file appears in Photos. Then re-test with delete-original toggle on, confirm system delete dialog.
- [ ] **Step 5:** Commit `feat(ios): metaclean export sheet with optional delete-original`.

---

## Recommended Commit Ordering

Six independently-shippable commits across both features:

| # | Commit | Tasks | Effort |
|---|--------|-------|--------|
| 1 | `feat(ios): stitch model + project state` | S1, S2 | S |
| 2 | `feat(ios): stitch tab shell + timeline reorder + thumbnails` | S3, S4, S5 | M |
| 3 | `feat(ios): per-clip editor sheet (trim/crop/rotate)` | S6 | M |
| 4 | `feat(ios): stitch exporter (composition + passthrough + re-encode)` | S7, S8 | L |
| 5 | `feat(ios): metaclean model + remux-strip service` | M1, M2 | L |
| 6 | `feat(ios): metaclean tab UI + delete-original` | M3, M4 | M |

Why this order: 1 lands the Stitch type system without UI changes; 2 ships a reorderable timeline that already feels like the feature; 3 stays inside Stitch but adds the per-clip editor (lazy edits visible in the timeline); 4 finally produces output. 5 and 6 are the MetaClean half — independent of Stitch — so a parallel teammate could take them while another agent works on Stitch (per `CLAUDE.md` multi-agent rules). Commits 5 and 6 can be reordered with the Stitch four if MetaClean becomes higher priority.

---

## Risk Register

| # | Risk | Likelihood | Mitigation |
|---|------|-----------|------------|
| R1 | `AVMutableComposition` chokes on mixed codecs (HEVC + H.264 in the same composition track) — older iOS versions silently produce black frames for one of them. | Med | Build per-clip `AVMutableCompositionTrack` only if codecs match; otherwise fall back to per-clip re-encode segments. Detect at `buildPlan` time and force `canPassthrough = false`. |
| R2 | `loadTransferable(type: VideoFile.self)` performance with 20+ videos — copying gigabyte-scale files into `Documents/StitchInputs/` is slow and disk-hungry. | High | Use `moveItem` instead of `copyItem` (per HIGH-1 fix in `{E-0503-0935}` already applied to Compress). Show a per-item progress chip during import. Cap multi-select at 20 (PhotosPicker limit). |
| R3 | `PHAssetChangeRequest.deleteAssets` requires authorization scope `.readWrite`, but Phase 1 only requested `.addOnly`. | High | Bump the entitlement to `.readWrite` only when the delete-original toggle is engaged; show a re-prompt explaining why. Update `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` accordingly. Without `.readWrite`, the delete request silently no-ops. |
| R4 | Large file remux for MetaClean exhausts memory if `expectsMediaDataInRealTime = true` — the writer queues full samples in RAM. | Med | Use `expectsMediaDataInRealTime = false` and serial sample-buffer pump (read sample → append → wait if not ready). Already the standard pattern; document in service header. |
| R5 | `AVAssetImageGenerator.images(for:)` on iOS 17 occasionally drops frames near keyframe boundaries, leading to a blank thumbnail in the strip. | Low | Tolerate failures per-image — the strip rendering ignores `nil` and shows a neutral placeholder. |
| R6 | The trim-handle `Slider`-pair UX feels janky vs. native iMovie. | Med | v1 ships dual-`Slider`. If user feedback says it's too coarse, write a custom dual-thumb gesture in v2 — already isolated behind `TrimEditorView`. |
| R7 | Crop math is wrong when source has rotation in `preferredTransform` — naive `cropNormalized: CGRect` over `naturalSize` ignores 90°-rotated portrait video. | Med | Apply `preferredTransform` first, then crop in display-space, then map back to encoder coordinates. Add a unit test fixture with portrait video. Pin to ≤ 1080p sources for v1 to keep encode time bounded. |

---

## Notes on Reusing `{E-0503-0936}` Type-Design Refactors

The type-design-analyzer recommended (lines 134–161 of `AI-CHAT-LOG.md`) a `BoundedProgress` newtype, a `CompressedOutput` payload, and a typed `LibraryError` sum. **All three apply to Stitch and MetaClean:**

- `BoundedProgress` lives on `StitchProject.exportProgress` and any per-tag scan progress in MetaClean.
- `CompressedOutput` is the value flowed out of `StitchExporter.export` and `MetadataService.strip` — the writer's success payload, not a loose `URL`.
- `StitchError` and `MetaCleanError` should be typed enums conforming to `Error, Hashable, Sendable` — never `String`-decayed. This is a hard invariant; add a `displayMessage: String` accessor for alert binding, but keep the typed value for branching.

Likewise, `CompressionSettings` (the planned struct replacing the `CompressionPreset` enum from `{E-0503-0938}` Gap 2) is the natural shape for `StitchExportSheet`'s output settings and any optional re-encode in MetaClean. **Do not introduce a parallel "stitch settings" type.**

If Phase 2 commit 2 (the `CompressionSettings` refactor) has not landed when this plan is executed, prepend an interim Task 0: "Adopt `CompressionSettings`" — it's a half-day refactor and unblocks both features cleanly.

---

## Status

Plan ready for execution. Ship behind a feature flag if desired; both tabs degrade safely to "Coming soon" placeholders if the corresponding `Service` actor fails to initialize.
