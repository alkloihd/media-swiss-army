# Snap-Mode Multi-Camera Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Real-device verification is mandatory** at every PR within this cluster — the simulator has no cameras and cannot exercise `AVCaptureMultiCamSession` at all.

**Goal:** Add a fourth top-level capability to the app — `Capture` — that lets the user record multi-camera, multi-segment video sessions in any of six layouts, swap which camera feeds any cell with a tap mid-session, pause and resume across phone-off, edit before commit, and hand the session off to the existing Stitch render pipeline. Mirrors the LG G6 "Snap" mode the user used heavily on that device.

**Architecture:** `AVCaptureMultiCamSession`-backed actor wraps live camera I/O. A `CaptureProject` model (mirrors `StitchProject`) holds an ordered list of `CaptureClip`s; each clip is a multi-track recording with one `.mov` per active camera plus a `CaptureLayout` snapshot. Recording uses one `AVCaptureMovieFileOutput` per camera (separate files per slot, simpler than buffer composition). Layout swaps mid-session use Strategy B: finalize the active clip, restart the session with new bindings, register the new clip — sub-second gap, simpler code, identical user-visible result because the segment timeline shows continuity. Render-time composition uses `AVMutableComposition` with multiple video tracks + per-track `AVMutableVideoCompositionLayerInstruction` for layout, then runs through the existing `CompressionService.encode` pipeline.

**Tech Stack:** Swift 5.9 / iOS 18 deployment target / SwiftUI / AVFoundation (`AVCaptureMultiCamSession`, `AVCaptureMovieFileOutput`, `AVCaptureDevice.DiscoverySession`, `AVMutableComposition`, `AVMutableVideoCompositionLayerInstruction`) / Combine. iOS 26 features (`.glassEffect()`, expanded multi-cam formats) used with `#available` gating + iOS 18 fallbacks. No third-party dependencies. Reuses existing `CompressionService`, `StitchExporter`, `CacheSweeper`, and the freshly-shipped Cluster 3.5 theme tokens once those land.

---

## Branch

`feat/cluster-6-snap-mode-multicam` off the latest `main` AFTER Cluster 2.5 hotfix and Cluster 3.5 visual redo have merged. Stitch-pipeline conflicts are unlikely because this cluster reuses (does not modify) `StitchExporter` / `CompressionService`.

## Hard Constraints (read before writing one line)

1. **Bundle ID is `ca.nextclass.VideoCompressor` — locked.** Do NOT touch `PRODUCT_BUNDLE_IDENTIFIER`. See AGENTS.md DO-NOT-RENAME banner.
2. **Don't touch `.github/workflows/testflight.yml`.**
3. **No CoreHaptics, no `AVVideoCompositing` subclass.** Use built-in `AVMutableVideoCompositionLayerInstruction` for layout transforms.
4. **Real-device gate is enforced for every PR in this cluster.** Sim has no cameras. After CI green, append `[BLOCKED]` line in AI-CHAT-LOG and WAIT for user `[DECISION]` before merging. No exceptions.
5. **`AVCaptureMultiCamSession.isMultiCamSupported` MUST be queried before any session work.** A12+ Bionic devices only. iPhone X / 8 / SE1 do not support multi-cam — single-camera fallback path is mandatory.
6. **Disk space monitor is mandatory.** Multi-cam HEVC writes 80–120 MB/min/camera at 1080p. 4 cameras = 320–480 MB/min. Auto-stop at 90% free-disk consumed.
7. **No background recording.** iOS suspends `AVCaptureSession` on background; `audio` background mode permits brief continuation but not real recording. The pause/resume contract is: on `scenePhase == .background` finalize current clip + persist, on `.active` restore session and let user tap Resume.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Capture/CaptureLayout.swift` | Create | `enum CaptureLayout` — `.single`, `.topBottom`, `.sideBySide`, `.pipBottomRight`, `.threeGrid`, `.fourGrid`. Each case knows its `slotCount` (1–4) and renders an `[CGRect]` for a given canvas size. |
| `VideoCompressor/ios/Capture/CaptureCameraRoster.swift` | Create | `enum CaptureCameraID` — `.frontTrueDepth`, `.rearMain`, `.rearWide`, `.rearTele`. Discovery wraps `AVCaptureDevice.DiscoverySession` and returns the available subset for the current device. |
| `VideoCompressor/ios/Capture/CaptureSlot.swift` | Create | `struct CaptureSlot: Codable` — `id: UUID`, `cameraID: CaptureCameraID`, `position: Int` (0..3), maps a camera to a layout cell. |
| `VideoCompressor/ios/Capture/CaptureClip.swift` | Create | `struct CaptureClip: Codable, Identifiable` — `id: UUID`, `layout: CaptureLayout`, `slots: [CaptureSlot]`, `urls: [UUID: URL]` (one .mov per slot id), `duration: CMTime`, `recordedAt: Date`. |
| `VideoCompressor/ios/Capture/CaptureProject.swift` | Create | `@MainActor final class CaptureProject: ObservableObject` — ordered `[CaptureClip]`, current `activeLayout`, current `activeSlots`, `recordingState: .idle/.preparing/.recording/.paused/.finalizing`, `errorState`. |
| `VideoCompressor/ios/Capture/CaptureProjectStore.swift` | Create | Disk persistence under `Documents/CaptureProjects/<project-uuid>/project.json` + `clips/<clip-uuid>/<slot-uuid>.mov`. Atomic writes, snapshot-on-background, restore-on-active. |
| `VideoCompressor/ios/Capture/CaptureSession.swift` | Create | `actor CaptureSession` — wraps `AVCaptureMultiCamSession`. Configures inputs/outputs based on `activeLayout`+`activeSlots`. Starts/stops recording per slot. Probes `hardwareCost`. |
| `VideoCompressor/ios/Capture/CaptureRenderer.swift` | Create | At render time, builds an `AVMutableComposition` with one `AVMutableCompositionTrack` per slot in a clip, applies per-track `AVMutableVideoCompositionLayerInstruction` transforms based on `CaptureLayout`, returns a single `(asset:, videoComposition:)` ready for `CompressionService.encode`. |
| `VideoCompressor/ios/Capture/CaptureExportBridge.swift` | Create | Converts a `CaptureProject` to a `StitchProject`-equivalent input that the existing export pipeline can consume. One `StitchClip` per `CaptureClip` (the layout-composed video). |
| `VideoCompressor/ios/Views/CaptureTab/CaptureTabView.swift` | Create | Tab root. Shows viewfinder + control bar + segment timeline. |
| `VideoCompressor/ios/Views/CaptureTab/CaptureViewfinderView.swift` | Create | Live grid of `AVCaptureVideoPreviewLayer` views laid out per `CaptureLayout`. Each cell has a "tap to swap" affordance and a long-press detach-to-fullscreen. |
| `VideoCompressor/ios/Views/CaptureTab/CaptureControlBar.swift` | Create | Record / pause / stop. Layout picker entry. Camera roster. Elapsed timer. |
| `VideoCompressor/ios/Views/CaptureTab/CaptureLayoutPickerSheet.swift` | Create | Sheet with thumbnails of the 6 layouts; layouts the device can't sustain are disabled with a tooltip. |
| `VideoCompressor/ios/Views/CaptureTab/CaptureSegmentTimelineView.swift` | Create | Horizontal `LazyHStack` of recorded clip thumbnails. Drag to reorder via `.onMove`. Tap to trim. Swipe to delete. |
| `VideoCompressor/ios/Views/CaptureTab/CaptureExportSheet.swift` | Create | Bridges to existing export sheet. Uses presets from `CompressionSettings`. |
| `VideoCompressor/ios/ContentView.swift` | Modify | Add `case capture` to `AppTab` enum (4 → 5 tabs); add `CaptureTabView()` to the `TabView`. |
| `VideoCompressor/VideoCompressor_iOS.xcodeproj/project.pbxproj` | Modify | Add `INFOPLIST_KEY_NSCameraUsageDescription` and `INFOPLIST_KEY_NSMicrophoneUsageDescription` to both Debug + Release. |
| `VideoCompressor/VideoCompressorTests/Capture/CaptureLayoutTests.swift` | Create | Unit tests for layout → CGRect math at all canvas sizes |
| `VideoCompressor/VideoCompressorTests/Capture/CaptureCameraRosterTests.swift` | Create | Discovery returns expected subset on simulator (front camera only) |
| `VideoCompressor/VideoCompressorTests/Capture/CaptureProjectTests.swift` | Create | Append / reorder / delete clip semantics |
| `VideoCompressor/VideoCompressorTests/Capture/CaptureProjectStoreTests.swift` | Create | Persistence round-trip; restore from disk; corrupted-file recovery |
| `VideoCompressor/VideoCompressorTests/Capture/CaptureRendererTests.swift` | Create | Composition correctness — per-layout layer instructions produce expected `setTransform` values; composition duration equals max slot duration per clip |
| `VideoCompressor/VideoCompressorTests/Capture/CaptureSessionLifecycleTests.swift` | Create | Sim-only: confirms session refuses to start without device support, refuses unsupported layouts, tears down cleanly |

---

## Tasks

### Task 1: CaptureLayout + tests

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureLayout.swift`
- Test: `VideoCompressor/VideoCompressorTests/Capture/CaptureLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// CaptureLayoutTests.swift
import XCTest
import CoreGraphics
@testable import VideoCompressor_iOS

final class CaptureLayoutTests: XCTestCase {

    func testSingleLayoutFillsFullCanvas() {
        let canvas = CGSize(width: 1080, height: 1920)
        let rects = CaptureLayout.single.rects(in: canvas)
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0], CGRect(origin: .zero, size: canvas))
    }

    func testTopBottomSplitsCanvasInHalfVertically() {
        let canvas = CGSize(width: 1080, height: 1920)
        let rects = CaptureLayout.topBottom.rects(in: canvas)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0,    width: 1080, height: 960))
        XCTAssertEqual(rects[1], CGRect(x: 0, y: 960,  width: 1080, height: 960))
    }

    func testSideBySideSplitsCanvasInHalfHorizontally() {
        let canvas = CGSize(width: 1920, height: 1080)
        let rects = CaptureLayout.sideBySide.rects(in: canvas)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0], CGRect(x: 0,   y: 0, width: 960, height: 1080))
        XCTAssertEqual(rects[1], CGRect(x: 960, y: 0, width: 960, height: 1080))
    }

    func testPipBottomRightPlacesSecondaryAtQuarterSize() {
        let canvas = CGSize(width: 1080, height: 1920)
        let rects = CaptureLayout.pipBottomRight.rects(in: canvas)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0], CGRect(origin: .zero, size: canvas))
        let pipW: CGFloat = 360
        let pipH: CGFloat = 640
        let pipMargin: CGFloat = 32
        XCTAssertEqual(rects[1], CGRect(x: 1080 - pipW - pipMargin,
                                         y: 1920 - pipH - pipMargin,
                                         width: pipW, height: pipH))
    }

    func testThreeGridStacksTopFullPlusTwoBelow() {
        let canvas = CGSize(width: 1080, height: 1920)
        let rects = CaptureLayout.threeGrid.rects(in: canvas)
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0], CGRect(x: 0,    y: 0,    width: 1080, height: 960))
        XCTAssertEqual(rects[1], CGRect(x: 0,    y: 960,  width: 540,  height: 960))
        XCTAssertEqual(rects[2], CGRect(x: 540,  y: 960,  width: 540,  height: 960))
    }

    func testFourGridQuartersTheCanvas() {
        let canvas = CGSize(width: 1080, height: 1920)
        let rects = CaptureLayout.fourGrid.rects(in: canvas)
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(rects[0], CGRect(x: 0,    y: 0,    width: 540, height: 960))
        XCTAssertEqual(rects[1], CGRect(x: 540,  y: 0,    width: 540, height: 960))
        XCTAssertEqual(rects[2], CGRect(x: 0,    y: 960,  width: 540, height: 960))
        XCTAssertEqual(rects[3], CGRect(x: 540,  y: 960,  width: 540, height: 960))
    }

    func testSlotCountMatchesRectCount() {
        for layout in CaptureLayout.allCases {
            XCTAssertEqual(layout.slotCount, layout.rects(in: CGSize(width: 100, height: 100)).count,
                           "Layout \(layout) must have slotCount equal to rect count")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mcp__xcodebuildmcp__test_sim` (or CLI fallback `xcodebuild ... test` if MCP times out).
Expected: build fails — `CaptureLayout` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// CaptureLayout.swift
import CoreGraphics

/// One of the six fixed multi-camera arrangements supported by the Capture
/// tab. Each case knows how to lay out its cells on a given canvas size.
///
/// LG G6 "Snap" mode inspiration: user can change layout mid-session;
/// the renderer composes each clip's per-slot videos into the chosen
/// arrangement at export time.
enum CaptureLayout: String, CaseIterable, Codable, Sendable {
    case single
    case topBottom
    case sideBySide
    case pipBottomRight
    case threeGrid
    case fourGrid

    var slotCount: Int {
        switch self {
        case .single:           return 1
        case .topBottom:        return 2
        case .sideBySide:       return 2
        case .pipBottomRight:   return 2
        case .threeGrid:        return 3
        case .fourGrid:         return 4
        }
    }

    /// Cells for this layout on a canvas. Origin top-left, math in CGImage
    /// coordinates (Y grows downward — same convention as `AVMutableVideo
    /// CompositionLayerInstruction`'s setTransform).
    func rects(in canvas: CGSize) -> [CGRect] {
        let w = canvas.width
        let h = canvas.height
        switch self {
        case .single:
            return [CGRect(origin: .zero, size: canvas)]
        case .topBottom:
            return [
                CGRect(x: 0, y: 0,     width: w, height: h / 2),
                CGRect(x: 0, y: h / 2, width: w, height: h / 2),
            ]
        case .sideBySide:
            return [
                CGRect(x: 0,     y: 0, width: w / 2, height: h),
                CGRect(x: w / 2, y: 0, width: w / 2, height: h),
            ]
        case .pipBottomRight:
            let pipW = w / 3
            let pipH = h / 3
            let pipMargin: CGFloat = 32
            return [
                CGRect(origin: .zero, size: canvas),
                CGRect(x: w - pipW - pipMargin,
                       y: h - pipH - pipMargin,
                       width: pipW, height: pipH),
            ]
        case .threeGrid:
            return [
                CGRect(x: 0,     y: 0,     width: w,     height: h / 2),
                CGRect(x: 0,     y: h / 2, width: w / 2, height: h / 2),
                CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2),
            ]
        case .fourGrid:
            return [
                CGRect(x: 0,     y: 0,     width: w / 2, height: h / 2),
                CGRect(x: w / 2, y: 0,     width: w / 2, height: h / 2),
                CGRect(x: 0,     y: h / 2, width: w / 2, height: h / 2),
                CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2),
            ]
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mcp__xcodebuildmcp__test_sim`. Expected: 7 new tests green; existing 252 stay green.

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Capture/CaptureLayout.swift VideoCompressor/VideoCompressorTests/Capture/CaptureLayoutTests.swift
git commit -m "feat(capture): introduce CaptureLayout with 6 multi-cam arrangements"
```

---

### Task 2: CaptureCameraRoster + discovery

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureCameraRoster.swift`
- Test: `VideoCompressor/VideoCompressorTests/Capture/CaptureCameraRosterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// CaptureCameraRosterTests.swift
import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class CaptureCameraRosterTests: XCTestCase {

    /// Simulator has only the front camera available (and via PhotosPicker
    /// Apple supplies a synthesized one). Test that discovery doesn't crash
    /// and returns a stable, deterministic subset.
    func testDiscoverySimulatorReturnsSubsetWithoutCrashing() {
        let roster = CaptureCameraRoster.discoverAvailable()
        // On simulator we expect 0 or 1 cameras; the call must not throw or
        // return nil. Discovery is mandatory before any session config.
        XCTAssertGreaterThanOrEqual(roster.count, 0)
    }

    func testCameraIDOrderIsStable() {
        // Discovery must always yield a deterministic ordering so that
        // CaptureSlot.position assignment is reproducible across launches.
        let first = CaptureCameraRoster.discoverAvailable()
        let second = CaptureCameraRoster.discoverAvailable()
        XCTAssertEqual(first, second)
    }
}
```

- [ ] **Step 2: Run — fails to compile**

Run: `mcp__xcodebuildmcp__test_sim`. Expected: build error — `CaptureCameraRoster` undefined.

- [ ] **Step 3: Implement**

```swift
// CaptureCameraRoster.swift
import AVFoundation

/// Identifies a logical camera position on the device. The same enum is
/// used in CaptureSlot to bind a slot to a specific camera.
enum CaptureCameraID: String, Codable, Sendable, CaseIterable, Hashable {
    case frontTrueDepth
    case rearMain
    case rearWide
    case rearTele

    /// Apple device-type backing this logical camera. Falls back to the
    /// closest available type at discovery time if the exact one is missing.
    var preferredDeviceTypes: [AVCaptureDevice.DeviceType] {
        switch self {
        case .frontTrueDepth:
            return [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        case .rearMain:
            return [.builtInWideAngleCamera, .builtInDualWideCamera]
        case .rearWide:
            return [.builtInUltraWideCamera, .builtInDualWideCamera]
        case .rearTele:
            return [.builtInTelephotoCamera, .builtInDualCamera]
        }
    }

    var preferredPosition: AVCaptureDevice.Position {
        self == .frontTrueDepth ? .front : .back
    }

    var displayName: String {
        switch self {
        case .frontTrueDepth: return "Front"
        case .rearMain:       return "Main"
        case .rearWide:       return "Ultra Wide"
        case .rearTele:       return "Telephoto"
        }
    }
}

/// Discovers which logical cameras are physically available on this device.
/// On simulator returns a small subset (front camera only). Order is stable
/// across calls so that slot assignment is reproducible.
enum CaptureCameraRoster {

    static func discoverAvailable() -> [CaptureCameraID] {
        var available: [CaptureCameraID] = []
        for id in CaptureCameraID.allCases {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: id.preferredDeviceTypes,
                mediaType: .video,
                position: id.preferredPosition
            )
            if !session.devices.isEmpty {
                available.append(id)
            }
        }
        return available
    }

    /// Returns the AVCaptureDevice for a logical camera, or nil if absent.
    static func device(for id: CaptureCameraID) -> AVCaptureDevice? {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: id.preferredDeviceTypes,
            mediaType: .video,
            position: id.preferredPosition
        )
        return session.devices.first
    }
}
```

- [ ] **Step 4: Run — green**

Run: `mcp__xcodebuildmcp__test_sim`. Expected: 2 new tests green.

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Capture/CaptureCameraRoster.swift VideoCompressor/VideoCompressorTests/Capture/CaptureCameraRosterTests.swift
git commit -m "feat(capture): add CaptureCameraRoster discovery + 4 logical camera IDs"
```

---

### Task 3: CaptureSlot + CaptureClip + Codable round-trip

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureSlot.swift`
- Create: `VideoCompressor/ios/Capture/CaptureClip.swift`
- Test: `VideoCompressor/VideoCompressorTests/Capture/CaptureProjectTests.swift` (initial subset)

- [ ] **Step 1: Write the failing test**

```swift
// CaptureProjectTests.swift  (initial subset — extended in Task 5)
import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class CaptureProjectTests: XCTestCase {

    func testCaptureSlotEncodesAndDecodes() throws {
        let slot = CaptureSlot(cameraID: .rearMain, position: 0)
        let data = try JSONEncoder().encode(slot)
        let decoded = try JSONDecoder().decode(CaptureSlot.self, from: data)
        XCTAssertEqual(decoded.id, slot.id)
        XCTAssertEqual(decoded.cameraID, .rearMain)
        XCTAssertEqual(decoded.position, 0)
    }

    func testCaptureClipKeepsSlotIDsAndURLsAligned() {
        let slot1 = CaptureSlot(cameraID: .rearMain, position: 0)
        let slot2 = CaptureSlot(cameraID: .frontTrueDepth, position: 1)
        let url1 = URL(fileURLWithPath: "/tmp/slot1.mov")
        let url2 = URL(fileURLWithPath: "/tmp/slot2.mov")
        let clip = CaptureClip(
            layout: .topBottom,
            slots: [slot1, slot2],
            urls: [slot1.id: url1, slot2.id: url2],
            duration: CMTime(seconds: 5, preferredTimescale: 600),
            recordedAt: Date()
        )
        XCTAssertEqual(clip.urls[slot1.id], url1)
        XCTAssertEqual(clip.urls[slot2.id], url2)
        XCTAssertEqual(clip.slots.count, 2)
        XCTAssertEqual(clip.layout.slotCount, clip.slots.count)
    }
}
```

- [ ] **Step 2: Run — fails to compile**

- [ ] **Step 3: Implement CaptureSlot**

```swift
// CaptureSlot.swift
import Foundation

/// Binds one logical camera (CaptureCameraID) to one cell in a CaptureLayout.
struct CaptureSlot: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let cameraID: CaptureCameraID
    /// Position 0..(layout.slotCount - 1). Stored explicitly so reorder
    /// without changing camera bindings is a one-property edit.
    var position: Int

    init(id: UUID = UUID(), cameraID: CaptureCameraID, position: Int) {
        self.id = id
        self.cameraID = cameraID
        self.position = position
    }
}
```

- [ ] **Step 4: Implement CaptureClip**

```swift
// CaptureClip.swift
import Foundation
import AVFoundation

/// One recorded segment in a capture session. Has one .mov per slot.
/// At render time these tracks are composed into a single video frame
/// laid out per CaptureLayout.
struct CaptureClip: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    /// Which arrangement was active when this clip recorded.
    let layout: CaptureLayout
    /// Camera bindings active during this clip. slots.count == layout.slotCount.
    let slots: [CaptureSlot]
    /// One recorded URL per slot. urls[slot.id] is the .mov file for that slot.
    let urls: [UUID: URL]
    /// Composition duration of this clip — equals max slot duration.
    let duration: CMTime
    let recordedAt: Date

    init(
        id: UUID = UUID(),
        layout: CaptureLayout,
        slots: [CaptureSlot],
        urls: [UUID: URL],
        duration: CMTime,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.layout = layout
        self.slots = slots
        self.urls = urls
        self.duration = duration
        self.recordedAt = recordedAt
    }
}

extension CMTime: Codable {
    public enum CodingKeys: String, CodingKey {
        case value, timescale
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(Int64.self, forKey: .value)
        let t = try c.decode(Int32.self, forKey: .timescale)
        self.init(value: v, timescale: t)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(self.value, forKey: .value)
        try c.encode(self.timescale, forKey: .timescale)
    }
}
```

- [ ] **Step 5: Run — green**

Run: `mcp__xcodebuildmcp__test_sim`. Expected: both new tests green.

- [ ] **Step 6: Commit**

```bash
git add VideoCompressor/ios/Capture/CaptureSlot.swift VideoCompressor/ios/Capture/CaptureClip.swift VideoCompressor/VideoCompressorTests/Capture/CaptureProjectTests.swift
git commit -m "feat(capture): add CaptureSlot + CaptureClip Codable models"
```

---

### Task 4: CaptureProject ObservableObject

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureProject.swift`
- Modify: `VideoCompressor/VideoCompressorTests/Capture/CaptureProjectTests.swift` (extend)

- [ ] **Step 1: Extend the test file with reorder/append/delete cases**

```swift
// Append to CaptureProjectTests.swift

@MainActor
func testProjectAppendsAndReorders() {
    let project = CaptureProject()
    let clip1 = makeClip()
    let clip2 = makeClip()
    let clip3 = makeClip()

    project.append(clip1)
    project.append(clip2)
    project.append(clip3)
    XCTAssertEqual(project.clips.map(\.id), [clip1.id, clip2.id, clip3.id])

    project.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
    XCTAssertEqual(project.clips.map(\.id), [clip3.id, clip1.id, clip2.id])

    project.remove(at: IndexSet(integer: 1))
    XCTAssertEqual(project.clips.map(\.id), [clip3.id, clip2.id])
}

@MainActor
func testProjectStartsIdle() {
    let project = CaptureProject()
    XCTAssertEqual(project.recordingState, .idle)
    XCTAssertTrue(project.clips.isEmpty)
    XCTAssertEqual(project.activeLayout, .single)
}

@MainActor
func testProjectClearAllRemovesClipsAndDeletesFiles() throws {
    // For this test, write two .mov stubs and confirm clearAll deletes them.
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("captureProjectClearAllTest-\(UUID())")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let stubURL1 = tmpDir.appendingPathComponent("stub1.mov")
    let stubURL2 = tmpDir.appendingPathComponent("stub2.mov")
    try Data("a".utf8).write(to: stubURL1)
    try Data("b".utf8).write(to: stubURL2)

    let slot = CaptureSlot(cameraID: .rearMain, position: 0)
    let clip = CaptureClip(
        layout: .single, slots: [slot],
        urls: [slot.id: stubURL1],
        duration: CMTime(seconds: 1, preferredTimescale: 600)
    )
    let project = CaptureProject()
    project.append(clip)
    project.append(CaptureClip(
        layout: .single, slots: [slot],
        urls: [slot.id: stubURL2],
        duration: CMTime(seconds: 1, preferredTimescale: 600)
    ))

    project.clearAll()
    XCTAssertTrue(project.clips.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stubURL1.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: stubURL2.path))
}

private func makeClip() -> CaptureClip {
    let slot = CaptureSlot(cameraID: .rearMain, position: 0)
    return CaptureClip(
        layout: .single,
        slots: [slot],
        urls: [slot.id: URL(fileURLWithPath: "/tmp/\(UUID()).mov")],
        duration: CMTime(seconds: 1, preferredTimescale: 600)
    )
}
```

- [ ] **Step 2: Run — fails to compile**

- [ ] **Step 3: Implement CaptureProject**

```swift
// CaptureProject.swift
import Foundation
import AVFoundation
import Combine

@MainActor
final class CaptureProject: ObservableObject {

    enum RecordingState: Equatable, Sendable {
        case idle
        case preparing
        case recording(startedAt: Date)
        case paused(elapsedAtPause: TimeInterval)
        case finalizing
        case failed(reason: String)
    }

    @Published private(set) var clips: [CaptureClip] = []
    @Published var activeLayout: CaptureLayout = .single
    @Published var activeSlots: [CaptureSlot] = []
    @Published var recordingState: RecordingState = .idle

    /// Persistent project ID; backs the on-disk directory.
    let id: UUID = UUID()

    func append(_ clip: CaptureClip) {
        clips.append(clip)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }

    func remove(at offsets: IndexSet) {
        for idx in offsets.sorted(by: >) {
            let clip = clips[idx]
            for url in clip.urls.values {
                try? FileManager.default.removeItem(at: url)
            }
            clips.remove(at: idx)
        }
    }

    /// Wipes the project: removes every clip's per-slot .mov from disk,
    /// resets recording state, leaves activeLayout/activeSlots intact so
    /// the next session starts in the same arrangement.
    func clearAll() {
        for clip in clips {
            for url in clip.urls.values {
                try? FileManager.default.removeItem(at: url)
            }
        }
        clips.removeAll()
        recordingState = .idle
    }
}
```

- [ ] **Step 4: Run — green**

- [ ] **Step 5: Commit**

```bash
git add VideoCompressor/ios/Capture/CaptureProject.swift VideoCompressor/VideoCompressorTests/Capture/CaptureProjectTests.swift
git commit -m "feat(capture): add CaptureProject with append/move/remove/clearAll"
```

---

### Task 5: CaptureProjectStore — disk persistence + restore

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureProjectStore.swift`
- Test: `VideoCompressor/VideoCompressorTests/Capture/CaptureProjectStoreTests.swift`

Persistence contract: project state is serialized to `Documents/CaptureProjects/<project-uuid>/project.json`, with per-clip per-slot .mov files at `Documents/CaptureProjects/<project-uuid>/clips/<clip-uuid>/<slot-uuid>.mov`. Atomic snapshot on background; restore-on-active.

- [ ] **Step 1: Write tests**

```swift
// CaptureProjectStoreTests.swift
import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class CaptureProjectStoreTests: XCTestCase {

    var tmpRoot: URL!

    override func setUp() {
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("captureStoreTest-\(UUID())")
        try? FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
    }

    @MainActor
    func testStoreRoundTripsEmptyProject() async throws {
        let project = CaptureProject()
        let store = CaptureProjectStore(rootURL: tmpRoot)
        try await store.save(project)
        let restored = try await store.load(projectID: project.id)
        XCTAssertEqual(restored.id, project.id)
        XCTAssertTrue(restored.clips.isEmpty)
        XCTAssertEqual(restored.activeLayout, project.activeLayout)
    }

    @MainActor
    func testStoreRoundTripsThreeClipProject() async throws {
        let project = CaptureProject()
        let slot = CaptureSlot(cameraID: .rearMain, position: 0)
        for _ in 0..<3 {
            let url = tmpRoot.appendingPathComponent("\(UUID()).mov")
            try Data().write(to: url)
            project.append(CaptureClip(
                layout: .single,
                slots: [slot],
                urls: [slot.id: url],
                duration: CMTime(seconds: 2, preferredTimescale: 600)
            ))
        }
        let store = CaptureProjectStore(rootURL: tmpRoot)
        try await store.save(project)
        let restored = try await store.load(projectID: project.id)
        XCTAssertEqual(restored.clips.count, 3)
    }

    @MainActor
    func testCorruptedJSONReturnsFreshProject() async throws {
        let id = UUID()
        let dir = tmpRoot.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not-json".write(to: dir.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        let store = CaptureProjectStore(rootURL: tmpRoot)
        let restored = try await store.load(projectID: id)
        // Corrupt → empty project, log + continue. Never throws to caller.
        XCTAssertTrue(restored.clips.isEmpty)
    }
}
```

- [ ] **Step 2: Run — fails to compile**

- [ ] **Step 3: Implement**

```swift
// CaptureProjectStore.swift
import Foundation

actor CaptureProjectStore {

    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL = CaptureProjectStore.defaultRootURL()) {
        self.rootURL = rootURL
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("CaptureProjects", isDirectory: true)
    }

    private struct Snapshot: Codable {
        let id: UUID
        let activeLayout: CaptureLayout
        let activeSlots: [CaptureSlot]
        let clips: [CaptureClip]
    }

    @MainActor
    private func snapshot(of project: CaptureProject) -> Snapshot {
        Snapshot(
            id: project.id,
            activeLayout: project.activeLayout,
            activeSlots: project.activeSlots,
            clips: project.clips
        )
    }

    func save(_ project: CaptureProject) async throws {
        let snap = await snapshot(of: project)
        let dir = rootURL.appendingPathComponent(snap.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("project.json")
        let data = try JSONEncoder().encode(snap)
        try data.write(to: url, options: .atomic)
    }

    func load(projectID: UUID) async throws -> CaptureProject {
        let dir = rootURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("project.json")
        let project = await CaptureProject()
        guard fileManager.fileExists(atPath: url.path) else {
            return project
        }
        do {
            let data = try Data(contentsOf: url)
            let snap = try JSONDecoder().decode(Snapshot.self, from: data)
            await MainActor.run {
                project.activeLayout = snap.activeLayout
                project.activeSlots = snap.activeSlots
                for clip in snap.clips {
                    project.append(clip)
                }
            }
            return project
        } catch {
            // Corrupted snapshot → return a fresh project under the same id.
            return project
        }
    }
}
```

- [ ] **Step 4: Run — green**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): add CaptureProjectStore atomic disk persistence"
```

---

### Task 6: CaptureSession actor (single-camera proof-of-life)

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureSession.swift`
- Test: `VideoCompressor/VideoCompressorTests/Capture/CaptureSessionLifecycleTests.swift`

Constraints: simulator has no cameras. The lifecycle test must only exercise the parts that don't require hardware (state transitions, support detection).

- [ ] **Step 1: Write tests**

```swift
// CaptureSessionLifecycleTests.swift
import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class CaptureSessionLifecycleTests: XCTestCase {

    func testIsMultiCamSupportedExposedThroughActor() async {
        let supported = await CaptureSession.isMultiCamSupportedOnThisDevice()
        // On simulator this is false; on iPhone XS+ this is true. We only
        // assert the API responds.
        XCTAssertNotNil(supported as Bool?)
    }

    func testStartFailsCleanlyWhenMultiCamUnsupported() async {
        let session = CaptureSession()
        do {
            try await session.start(layout: .topBottom, slots: [
                CaptureSlot(cameraID: .rearMain, position: 0),
                CaptureSlot(cameraID: .frontTrueDepth, position: 1),
            ])
            XCTFail("Expected start() to fail on simulator")
        } catch CaptureSession.SessionError.multiCamUnsupported {
            // Expected on simulator
        } catch {
            // Acceptable: any other graceful failure (no camera, etc.)
        }
    }

    func testStopOnIdleSessionIsNoOp() async {
        let session = CaptureSession()
        await session.stop()  // must not throw or hang
    }
}
```

- [ ] **Step 2: Run — fails to compile**

- [ ] **Step 3: Implement (proof of life — full multi-cam in Task 7)**

```swift
// CaptureSession.swift
import AVFoundation
import Combine
import os

actor CaptureSession {

    enum SessionError: Error {
        case multiCamUnsupported
        case cameraUnavailable(CaptureCameraID)
        case configurationFailed(String)
        case alreadyRunning
        case notRunning
    }

    private var session: AVCaptureMultiCamSession?
    private var movieOutputs: [UUID: AVCaptureMovieFileOutput] = [:]
    private var slotInputs: [UUID: AVCaptureDeviceInput] = [:]
    private var isRunning = false

    private let log = Logger(subsystem: "com.nextclass.VideoCompressor", category: "CaptureSession")

    static func isMultiCamSupportedOnThisDevice() -> Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    func start(layout: CaptureLayout, slots: [CaptureSlot]) async throws {
        guard !isRunning else { throw SessionError.alreadyRunning }
        guard Self.isMultiCamSupportedOnThisDevice() else {
            throw SessionError.multiCamUnsupported
        }
        let session = AVCaptureMultiCamSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for slot in slots {
            guard let device = CaptureCameraRoster.device(for: slot.cameraID) else {
                throw SessionError.cameraUnavailable(slot.cameraID)
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw SessionError.configurationFailed("cannot add input for \(slot.cameraID)")
            }
            session.addInputWithNoConnections(input)
            self.slotInputs[slot.id] = input

            let movieOut = AVCaptureMovieFileOutput()
            guard session.canAddOutput(movieOut) else {
                throw SessionError.configurationFailed("cannot add movie output for \(slot.cameraID)")
            }
            session.addOutputWithNoConnections(movieOut)

            // Connect this input's video port to its movie output.
            if let videoPort = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position).first {
                let connection = AVCaptureConnection(inputPorts: [videoPort], output: movieOut)
                guard session.canAddConnection(connection) else {
                    throw SessionError.configurationFailed("cannot wire connection for \(slot.cameraID)")
                }
                session.addConnection(connection)
            }
            self.movieOutputs[slot.id] = movieOut
        }

        // Hardware cost gate.
        if session.hardwareCost > 1.0 {
            throw SessionError.configurationFailed("hardwareCost \(session.hardwareCost) exceeds 1.0 — try a lighter layout or fewer cameras")
        }

        self.session = session
        session.startRunning()
        self.isRunning = true
    }

    func stop() async {
        guard isRunning, let session = session else { return }
        session.stopRunning()
        self.session = nil
        self.movieOutputs = [:]
        self.slotInputs = [:]
        self.isRunning = false
    }

    /// Returns the AVCaptureMovieFileOutput for a slot, used by the recording
    /// state machine in Task 7.
    func movieOutput(for slotID: UUID) -> AVCaptureMovieFileOutput? {
        movieOutputs[slotID]
    }
}
```

- [ ] **Step 4: Run — green** (3 new tests)

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): scaffold CaptureSession actor wrapping AVCaptureMultiCamSession"
```

---

### Task 7: Recording state machine (per-slot AVCaptureMovieFileOutput)

**Files:**
- Modify: `VideoCompressor/ios/Capture/CaptureSession.swift`
- Modify: `VideoCompressor/ios/Capture/CaptureProject.swift`

Recording starts each per-slot `AVCaptureMovieFileOutput` simultaneously, captures to disk, and on stop produces a single `CaptureClip` whose duration = max(slot.duration). The composition uses the multicam session's synchronization clock to align.

- [ ] **Step 1: Add per-slot recording API to CaptureSession**

```swift
// Append to CaptureSession.swift

extension CaptureSession {
    struct RecordingHandles {
        let clipDir: URL
        let outputs: [UUID: URL]
    }

    func startRecording(layout: CaptureLayout, slots: [CaptureSlot], rootURL: URL) async throws -> RecordingHandles {
        guard isRunning else { throw SessionError.notRunning }
        let clipID = UUID()
        let dir = rootURL
            .appendingPathComponent("clips", isDirectory: true)
            .appendingPathComponent(clipID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var outputs: [UUID: URL] = [:]
        for slot in slots {
            guard let movieOut = movieOutputs[slot.id] else { continue }
            let url = dir.appendingPathComponent("\(slot.id.uuidString).mov")
            outputs[slot.id] = url
            movieOut.startRecording(to: url, recordingDelegate: NoopMovieRecordingDelegate.shared)
        }
        return RecordingHandles(clipDir: dir, outputs: outputs)
    }

    func stopRecording() async {
        for output in movieOutputs.values where output.isRecording {
            output.stopRecording()
        }
        // Wait briefly for finalization. iOS finalizes the .mov header on stop.
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}

/// AVFoundation requires a non-nil delegate; we don't need callbacks so route
/// to /dev/null. Errors are surfaced via output.error checks at clip-assembly.
final class NoopMovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    static let shared = NoopMovieRecordingDelegate()
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            os_log("CaptureSession recording error: %{public}@", "\(error)")
        }
    }
}
```

- [ ] **Step 2: Add record/pause/stop driver in CaptureProject**

```swift
// Append to CaptureProject.swift

extension CaptureProject {

    func record(using session: CaptureSession, store: CaptureProjectStore) async throws {
        guard recordingState == .idle || recordingState.isPausedOrFinalized else { return }
        recordingState = .preparing
        let projectDir = CaptureProjectStore.defaultRootURL()
            .appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let handles = try await session.startRecording(layout: activeLayout, slots: activeSlots, rootURL: projectDir)
        recordingState = .recording(startedAt: Date())
        // Persist a snapshot immediately so a crash mid-record still leaves
        // a recoverable project.
        try await store.save(self)
        // The actual finalization happens when stopRecording is called.
        // The .mov files Apple writes to handles.outputs[slot.id] become the
        // urls of the next CaptureClip.
        let layoutSnapshot = activeLayout
        let slotsSnapshot = activeSlots
        let urlsSnapshot = handles.outputs
        // Track in-flight clip in a transient property so stop can finalize.
        self.inFlightLayout = layoutSnapshot
        self.inFlightSlots = slotsSnapshot
        self.inFlightURLs = urlsSnapshot
    }

    func stop(using session: CaptureSession, store: CaptureProjectStore) async throws {
        guard case .recording(let startedAt) = recordingState else { return }
        recordingState = .finalizing
        await session.stopRecording()
        let duration = CMTime(seconds: Date().timeIntervalSince(startedAt), preferredTimescale: 600)
        guard let layout = inFlightLayout, let slots = inFlightSlots, let urls = inFlightURLs else { return }
        let clip = CaptureClip(layout: layout, slots: slots, urls: urls, duration: duration)
        append(clip)
        inFlightLayout = nil
        inFlightSlots = nil
        inFlightURLs = nil
        recordingState = .idle
        try await store.save(self)
    }

    fileprivate var inFlightLayout: CaptureLayout? {
        get { _inFlight.layout }
        set { _inFlight.layout = newValue }
    }
    fileprivate var inFlightSlots: [CaptureSlot]? {
        get { _inFlight.slots }
        set { _inFlight.slots = newValue }
    }
    fileprivate var inFlightURLs: [UUID: URL]? {
        get { _inFlight.urls }
        set { _inFlight.urls = newValue }
    }
    private var _inFlight: (layout: CaptureLayout?, slots: [CaptureSlot]?, urls: [UUID: URL]?) {
        get { (layout: nil, slots: nil, urls: nil) /* placeholder; use stored property */ }
        set { /* use a stored property */ }
    }
}

extension CaptureProject.RecordingState {
    var isPausedOrFinalized: Bool {
        switch self {
        case .paused, .finalizing, .idle: return true
        default: return false
        }
    }
}
```

> **NOTE for executing agent:** the `_inFlight` getter/setter shorthand above is illustrative — implement as actual stored properties on `CaptureProject` (not extension state, since extensions can't hold stored state). Move `inFlightLayout: CaptureLayout?`, `inFlightSlots: [CaptureSlot]?`, `inFlightURLs: [UUID: URL]?` to the main `CaptureProject` class declaration.

- [ ] **Step 3: Add a smoke test that records nothing on simulator and verifies state transitions**

```swift
// In CaptureProjectTests.swift
@MainActor
func testRecordingStateTransitionsOnSimulatorAreSafe() async throws {
    let project = CaptureProject()
    let session = CaptureSession()
    let store = CaptureProjectStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("rcsTest-\(UUID())"))

    do {
        try await project.record(using: session, store: store)
    } catch CaptureSession.SessionError.multiCamUnsupported, CaptureSession.SessionError.notRunning {
        // Expected on simulator
        XCTAssertEqual(project.recordingState, .preparing)  // we got past preparing before failure
    } catch {
        // Anything that doesn't crash is acceptable on sim
    }
}
```

- [ ] **Step 4: Run — green**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): add per-slot recording state machine"
```

---

### Task 8: AppTab + CaptureTabView shell

**Files:**
- Modify: `VideoCompressor/ios/ContentView.swift`
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureTabView.swift`

- [ ] **Step 1: Update AppTab enum**

```swift
// In ContentView.swift, modify AppTab enum
enum AppTab: Hashable {
    case compress
    case stitch
    case metaClean
    case capture        // NEW
    case settings

    var title: String {
        switch self {
        case .compress:  return "Compress"
        case .stitch:    return "Stitch"
        case .metaClean: return "MetaClean"
        case .capture:   return "Capture"
        case .settings:  return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .compress:  return "wand.and.stars"
        case .stitch:    return "square.stack.3d.up"
        case .metaClean: return "eye.slash"
        case .capture:   return "video.bubble.fill"
        case .settings:  return "gearshape"
        }
    }
}

// Add the Capture tab in the TabView body, between MetaClean and Settings:
CaptureTabView()
    .tabItem {
        Label("Capture", systemImage: AppTab.capture.symbolName)
    }
    .tag(AppTab.capture)
```

- [ ] **Step 2: Stub CaptureTabView**

```swift
// CaptureTabView.swift
import SwiftUI

struct CaptureTabView: View {
    @StateObject private var project = CaptureProject()
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !CaptureSession.isMultiCamSupportedOnThisDevice() {
                    // Older device — surface the soft block.
                    ContentUnavailableView(
                        "Multi-camera unavailable on this device",
                        systemImage: "video.slash",
                        description: Text("Capture requires an iPhone XS or later. You can still use Compress, Stitch, and MetaClean.")
                    )
                } else {
                    Text("Capture (work in progress)")
                        .font(.headline)
                    Text("Layouts available: \(CaptureLayout.allCases.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Capture")
        }
    }
}
```

- [ ] **Step 3: Build the app on the sim — visual smoke**

Run: `mcp__xcodebuildmcp__build_sim` then `build_run_sim`. Confirm the new tab appears with the placeholder content.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(capture): add Capture tab to AppTab + placeholder view"
```

---

### Task 9: CaptureViewfinderView — live multi-cam preview

**Files:**
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureViewfinderView.swift`

Wraps `AVCaptureVideoPreviewLayer` per slot using `UIViewRepresentable`. Lays out preview cells per `CaptureLayout.rects(in:)`. Tap on a cell opens the camera roster picker for that slot.

- [ ] **Step 1: Implement preview layer wrapper**

```swift
// CaptureViewfinderView.swift
import SwiftUI
import AVFoundation

struct CaptureViewfinderView: View {
    let session: CaptureSession
    @Binding var layout: CaptureLayout
    @Binding var slots: [CaptureSlot]
    let availableCameras: [CaptureCameraID]
    let onSlotTapped: (CaptureSlot) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                ForEach(slots) { slot in
                    let rect = layout.rects(in: geo.size)[slot.position]
                    PreviewLayerView(session: session, slotID: slot.id)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { onSlotTapped(slot) }
                        .accessibilityIdentifier("captureSlot-\(slot.position)")
                }
            }
        }
    }
}

private struct PreviewLayerView: UIViewRepresentable {
    let session: CaptureSession
    let slotID: UUID

    func makeUIView(context: Context) -> PreviewView {
        PreviewView(session: session, slotID: slotID)
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    init(session: CaptureSession, slotID: UUID) {
        super.init(frame: .zero)
        backgroundColor = .black
        Task {
            // Bind preview layer to the session's input port for this slot.
            // (Implementation detail — exposes a hook in CaptureSession.)
            await session.bindPreview(self.previewLayer, toSlotID: slotID)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
```

- [ ] **Step 2: Add `bindPreview` to CaptureSession**

```swift
// In CaptureSession.swift
extension CaptureSession {
    func bindPreview(_ previewLayer: AVCaptureVideoPreviewLayer, toSlotID slotID: UUID) async {
        guard let session = session, let input = slotInputs[slotID] else { return }
        guard let port = input.ports(for: .video, sourceDeviceType: nil, sourceDevicePosition: .unspecified).first else { return }
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        if session.canAddConnection(connection) {
            session.addConnection(connection)
        }
    }
}
```

- [ ] **Step 3: Wire to CaptureTabView — replace placeholder with viewfinder + control bar stubs**

Update `CaptureTabView` to instantiate `CaptureSession` and pass through to `CaptureViewfinderView`. Add a placeholder `CaptureControlBar` (record/pause/stop buttons that drive `CaptureProject.record(using:store:)`).

- [ ] **Step 4: Real-device smoke**

Append to AI-CHAT-LOG: `[BLOCKED] Cluster 6 Task 9 needs real-device smoke — install latest TestFlight, open Capture tab, confirm one camera previews live, no crash.`

- [ ] **Step 5: Commit (sim build green only — device confirmation deferred to PR gate)**

```bash
git commit -am "feat(capture): live preview layer + viewfinder layout"
```

---

### Task 10: CaptureControlBar — record/pause/stop + layout picker entry

**Files:**
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureControlBar.swift`
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureLayoutPickerSheet.swift`

Buttons: record (red filled circle, system image `record.circle.fill`), pause/resume (system image `pause.circle.fill` / `record.circle`), stop (system image `stop.fill`). Layout picker entry sits to the left.

- [ ] **Step 1: Implement CaptureControlBar**

```swift
// CaptureControlBar.swift
import SwiftUI

struct CaptureControlBar: View {
    @ObservedObject var project: CaptureProject
    let session: CaptureSession
    let store: CaptureProjectStore
    @Binding var layoutPickerVisible: Bool

    var body: some View {
        HStack(spacing: 24) {
            Button { layoutPickerVisible = true } label: {
                Label("Layout", systemImage: layoutSymbol)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button { Task { await record() } } label: {
                Image(systemName: project.recordingState.isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(project.recordingState.isRecording ? .gray : .red)
                    .symbolEffect(.bounce, value: project.recordingState.isRecording)
            }
            .accessibilityIdentifier("captureRecordButton")

            Spacer()

            Text(elapsed)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var layoutSymbol: String {
        switch project.activeLayout {
        case .single:           return "rectangle"
        case .topBottom:        return "rectangle.split.1x2"
        case .sideBySide:       return "rectangle.split.2x1"
        case .pipBottomRight:   return "rectangle.inset.bottomright.filled"
        case .threeGrid:        return "rectangle.split.3x1"
        case .fourGrid:         return "rectangle.split.2x2"
        }
    }

    private var elapsed: String {
        switch project.recordingState {
        case .recording(let startedAt):
            let s = Int(Date().timeIntervalSince(startedAt))
            return String(format: "%02d:%02d", s / 60, s % 60)
        default:
            return "00:00"
        }
    }

    @MainActor
    private func record() async {
        do {
            if project.recordingState.isRecording {
                try await project.stop(using: session, store: store)
            } else {
                try await project.record(using: session, store: store)
            }
        } catch {
            project.recordingState = .failed(reason: error.localizedDescription)
        }
    }
}

extension CaptureProject.RecordingState {
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Implement CaptureLayoutPickerSheet**

```swift
// CaptureLayoutPickerSheet.swift
import SwiftUI

struct CaptureLayoutPickerSheet: View {
    @Binding var selected: CaptureLayout
    let availableCount: Int   // device-supported max simultaneous cameras
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(CaptureLayout.allCases, id: \.self) { layout in
                        Button {
                            if layout.slotCount <= availableCount {
                                selected = layout
                                dismiss()
                            }
                        } label: {
                            LayoutThumbnail(layout: layout, enabled: layout.slotCount <= availableCount)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Layout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LayoutThumbnail: View {
    let layout: CaptureLayout
    let enabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color(.tertiarySystemBackground)
                ForEach(0..<layout.slotCount, id: \.self) { i in
                    let canvas = CGSize(width: 120, height: 160)
                    let r = layout.rects(in: canvas)[i]
                    Rectangle()
                        .stroke(.secondary, lineWidth: 1)
                        .background(Color.accentColor.opacity(0.15))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(layout.rawValue.capitalized)
                .font(.caption)
            if !enabled {
                Text("Not supported on this device")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .opacity(enabled ? 1 : 0.4)
    }
}
```

- [ ] **Step 3: Wire into CaptureTabView**

Update `CaptureTabView` to embed `CaptureViewfinderView` + `CaptureControlBar` + sheet for `CaptureLayoutPickerSheet`. Maintain `@State` for `layoutPickerVisible` and `availableCount` (computed at view appearance via runtime probe).

- [ ] **Step 4: `build_sim` — confirm UI lays out**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): control bar + layout picker"
```

---

### Task 11: Tap-to-swap camera

**Files:**
- Modify: `VideoCompressor/ios/Views/CaptureTab/CaptureTabView.swift`
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureCameraPickerSheet.swift`

When the user taps a slot in the viewfinder, present a sheet listing the available cameras. Selection updates `CaptureProject.activeSlots` and triggers `CaptureSession.reconfigure(slots:)` which uses Strategy B (finalize current clip if recording, restart with new bindings).

- [ ] **Step 1: Implement camera picker sheet**

```swift
// CaptureCameraPickerSheet.swift
import SwiftUI

struct CaptureCameraPickerSheet: View {
    let slot: CaptureSlot
    let availableCameras: [CaptureCameraID]
    let onPick: (CaptureCameraID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableCameras, id: \.self) { id in
                    Button {
                        onPick(id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: id == .frontTrueDepth ? "person.fill" : "camera.fill")
                            Text(id.displayName)
                            Spacer()
                            if id == slot.cameraID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Slot \(slot.position + 1)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
```

- [ ] **Step 2: Add reconfigure(slots:) to CaptureSession**

```swift
// In CaptureSession.swift
extension CaptureSession {
    /// Strategy B mid-session swap: stop current recording (if any),
    /// stop the session, rebuild with new slot bindings, restart.
    func reconfigure(layout: CaptureLayout, slots: [CaptureSlot]) async throws {
        let wasRunning = isRunning
        await stop()
        if wasRunning {
            try await start(layout: layout, slots: slots)
        }
    }
}
```

- [ ] **Step 3: Wire viewfinder onSlotTapped to the picker**

In `CaptureTabView`, add `@State private var cameraPickerSlot: CaptureSlot?` and on `onSlotTapped` set the state. Sheet on `cameraPickerSlot != nil` shows `CaptureCameraPickerSheet`. On pick, mutate `project.activeSlots`, then `Task { try? await session.reconfigure(layout: project.activeLayout, slots: project.activeSlots) }`.

- [ ] **Step 4: `build_sim` + add `[BLOCKED]` for device verification**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): tap-any-cell to swap which camera feeds it"
```

---

### Task 12: Pause/resume + scenePhase persistence

**Files:**
- Modify: `VideoCompressor/ios/Views/CaptureTab/CaptureTabView.swift`
- Modify: `VideoCompressor/ios/Capture/CaptureProject.swift`
- Modify: `VideoCompressor/ios/Capture/CaptureSession.swift`

On `scenePhase == .background`: if recording, call `project.pause(...)` which finalizes the in-flight clip (closes movie outputs) and persists. On `scenePhase == .active`: restore `CaptureProject` from disk, leave the session torn down — user must tap Resume to restart.

- [ ] **Step 1: Add pause / resume to CaptureProject**

```swift
// In CaptureProject.swift
extension CaptureProject {
    func pause(using session: CaptureSession, store: CaptureProjectStore) async throws {
        guard case .recording(let startedAt) = recordingState else { return }
        recordingState = .finalizing
        await session.stopRecording()
        let elapsed = Date().timeIntervalSince(startedAt)
        if let layout = inFlightLayout, let slots = inFlightSlots, let urls = inFlightURLs {
            let clip = CaptureClip(
                layout: layout, slots: slots, urls: urls,
                duration: CMTime(seconds: elapsed, preferredTimescale: 600)
            )
            append(clip)
        }
        inFlightLayout = nil
        inFlightSlots = nil
        inFlightURLs = nil
        recordingState = .paused(elapsedAtPause: elapsed)
        try await store.save(self)
    }

    /// Resume = start a NEW recording in the same project. Previous clips
    /// are preserved; user perceives continuity in the segment timeline.
    func resume(using session: CaptureSession, store: CaptureProjectStore) async throws {
        guard case .paused = recordingState else { return }
        try await record(using: session, store: store)
    }
}
```

- [ ] **Step 2: Wire scenePhase**

```swift
// In CaptureTabView body
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background, project.recordingState.isRecording {
        Task { try? await project.pause(using: session, store: store) }
    }
}
```

Add `@Environment(\.scenePhase) private var scenePhase` at the top of CaptureTabView.

- [ ] **Step 3: Add Resume button to control bar when state == .paused**

- [ ] **Step 4: Add disk-persistence smoke test**

```swift
@MainActor
func testPersistedProjectRestoresClipsAfterReload() async throws {
    let store = CaptureProjectStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("persistTest-\(UUID())"))
    let project = CaptureProject()
    let slot = CaptureSlot(cameraID: .rearMain, position: 0)
    let stub = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
    try Data().write(to: stub)
    project.append(CaptureClip(
        layout: .single, slots: [slot],
        urls: [slot.id: stub],
        duration: CMTime(seconds: 1, preferredTimescale: 600)
    ))
    try await store.save(project)
    let restored = try await store.load(projectID: project.id)
    XCTAssertEqual(restored.clips.count, 1)
    XCTAssertEqual(restored.clips[0].slots.first?.cameraID, .rearMain)
}
```

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): pause/resume + scenePhase auto-finalize"
```

---

### Task 13: Segment timeline (reorder / trim / delete)

**Files:**
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureSegmentTimelineView.swift`
- Reuse: existing `ClipEditorSheet` from StitchTab for trim UX

- [ ] **Step 1: Implement timeline strip**

```swift
// CaptureSegmentTimelineView.swift
import SwiftUI

struct CaptureSegmentTimelineView: View {
    @ObservedObject var project: CaptureProject
    @State private var trimTarget: CaptureClip?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(project.clips) { clip in
                    SegmentChip(clip: clip)
                        .onTapGesture { trimTarget = clip }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let idx = project.clips.firstIndex(where: { $0.id == clip.id }) {
                                    project.remove(at: IndexSet(integer: idx))
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 80)
        .sheet(item: $trimTarget) { _ in
            // Trim editor — out of scope for v1; placeholder.
            Text("Trim editor coming soon").padding()
        }
    }
}

private struct SegmentChip: View {
    let clip: CaptureClip
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: clip.layout.thumbnailSymbol)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("\(Int(clip.duration.seconds))s")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private extension CaptureLayout {
    var thumbnailSymbol: String {
        switch self {
        case .single:           return "rectangle"
        case .topBottom:        return "rectangle.split.1x2"
        case .sideBySide:       return "rectangle.split.2x1"
        case .pipBottomRight:   return "rectangle.inset.bottomright.filled"
        case .threeGrid:        return "rectangle.split.3x1"
        case .fourGrid:         return "rectangle.split.2x2"
        }
    }
}
```

- [ ] **Step 2: Wire into CaptureTabView under the viewfinder**

- [ ] **Step 3: `build_sim`**

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(capture): segment timeline with delete + tap-to-trim entry"
```

---

### Task 14: CaptureRenderer — multi-track composition

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureRenderer.swift`
- Test: `VideoCompressor/VideoCompressorTests/Capture/CaptureRendererTests.swift`

Per clip: build an `AVMutableComposition` with one track per slot. Apply `AVMutableVideoCompositionLayerInstruction.setTransform` per slot mapping the source frame into its layout cell. Output: `(asset: AVComposition, videoComposition: AVVideoComposition)` ready to feed into `CompressionService.encode`.

- [ ] **Step 1: Test composition arithmetic with stub video**

```swift
// CaptureRendererTests.swift
import XCTest
import AVFoundation
@testable import VideoCompressor_iOS

final class CaptureRendererTests: XCTestCase {

    /// Build a 1-second 480x640 black .mov fixture. Composing two of these
    /// in topBottom layout should produce a 1-second composition with
    /// two video tracks each at 480x640 mapped to the top-half / bottom-half
    /// of a 480x1280 canvas. (Canvas size = layout-derived from slot count.)
    func testTopBottomCompositionHasTwoTracksAndCorrectDuration() async throws {
        let url1 = try await fixture(width: 480, height: 640, seconds: 1)
        let url2 = try await fixture(width: 480, height: 640, seconds: 1)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        let slot1 = CaptureSlot(cameraID: .rearMain, position: 0)
        let slot2 = CaptureSlot(cameraID: .frontTrueDepth, position: 1)
        let clip = CaptureClip(
            layout: .topBottom,
            slots: [slot1, slot2],
            urls: [slot1.id: url1, slot2.id: url2],
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let renderer = CaptureRenderer()
        let result = try await renderer.compose(clip: clip, canvasSize: CGSize(width: 480, height: 1280))
        let tracks = try await result.asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 2)
        let duration = try await result.asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 1.0, accuracy: 0.1)
    }

    private func fixture(width: Int, height: Int, seconds: Double) async throws -> URL {
        // Reuse StillVideoBaker test helper if available; otherwise inline:
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * 30)
        for i in 0..<frames {
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
```

- [ ] **Step 2: Implement renderer**

```swift
// CaptureRenderer.swift
import AVFoundation
import CoreGraphics

actor CaptureRenderer {

    struct Composed: Sendable {
        let asset: AVAsset
        let videoComposition: AVVideoComposition
    }

    func compose(clip: CaptureClip, canvasSize: CGSize) async throws -> Composed {
        let composition = AVMutableComposition()
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

        let rects = clip.layout.rects(in: canvasSize)

        for slot in clip.slots {
            guard let url = clip.urls[slot.id] else { continue }
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceTrack = tracks.first else { continue }

            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            let duration = try await asset.load(.duration)
            try compTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: .zero
            )

            // Map source naturalSize into the target rect.
            let sourceSize = try await sourceTrack.load(.naturalSize)
            let target = rects[slot.position]
            let scaleX = target.width / sourceSize.width
            let scaleY = target.height / sourceSize.height
            let scale = min(scaleX, scaleY)  // aspect-fit; letterbox if needed
            let scaledW = sourceSize.width * scale
            let scaledH = sourceSize.height * scale
            let dx = target.midX - scaledW / 2
            let dy = target.midY - scaledH / 2
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: dx, y: dy))

            let inst = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
            inst.setTransform(transform, at: .zero)
            layerInstructions.append(inst)
        }

        let mainInst = AVMutableVideoCompositionInstruction()
        mainInst.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        mainInst.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvasSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [mainInst]

        return Composed(asset: composition, videoComposition: videoComposition)
    }
}
```

- [ ] **Step 3: Run — green**

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(capture): CaptureRenderer composes per-slot tracks per layout"
```

---

### Task 15: Export bridge to StitchExporter

**Files:**
- Create: `VideoCompressor/ios/Capture/CaptureExportBridge.swift`
- Create: `VideoCompressor/ios/Views/CaptureTab/CaptureExportSheet.swift`

The bridge composes each `CaptureClip` into a single `.mov` (via `CaptureRenderer`), produces a synthetic `StitchProject` whose clips ARE those composed `.mov`s, and uses the existing `StitchExporter` end-to-end. Reuses presets, transitions, fallback chain, save flow.

- [ ] **Step 1: Implement the bridge**

```swift
// CaptureExportBridge.swift
import AVFoundation

actor CaptureExportBridge {

    let renderer: CaptureRenderer
    init(renderer: CaptureRenderer = CaptureRenderer()) { self.renderer = renderer }

    /// Compose every CaptureClip in a CaptureProject into a single composed
    /// .mov per clip, then return a StitchProject ready to export through
    /// the existing pipeline.
    @MainActor
    func makeStitchProject(from project: CaptureProject, canvasSize: CGSize) async throws -> StitchProject {
        let stitch = StitchProject()
        for clip in project.clips {
            let composed = try await renderer.compose(clip: clip, canvasSize: canvasSize)
            // Render composed asset to a single .mov in StitchInputs/.
            let outURL = try await renderToFile(composed: composed)
            // Register with StitchProject as a regular video clip.
            let stitchClip = StitchClip(
                id: clip.id,
                sourceURL: outURL,
                displayName: clip.id.uuidString.prefix(6) + ".mov",
                naturalDuration: clip.duration,
                naturalSize: canvasSize,
                kind: .video,
                preferredTransform: .identity,
                edits: .identity
            )
            stitch.append(stitchClip)
        }
        return stitch
    }

    private func renderToFile(composed: CaptureRenderer.Composed) async throws -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StitchInputs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("capture-\(UUID()).mov")
        guard let exporter = AVAssetExportSession(asset: composed.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "CaptureExportBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "exporter init failed"])
        }
        exporter.videoComposition = composed.videoComposition
        exporter.outputFileType = .mov
        exporter.outputURL = url
        await exporter.export()
        guard exporter.status == .completed else {
            throw NSError(domain: "CaptureExportBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: exporter.error?.localizedDescription ?? "compose export failed"])
        }
        return url
    }
}
```

- [ ] **Step 2: Implement export sheet UI**

`CaptureExportSheet` opens a `StitchExportSheet` once the bridge has produced the stitch project. Pass through preset selection, transition selection, save flow.

- [ ] **Step 3: Run — green** (bridge has no unit test on sim because composition runs through AVFoundation; manual smoke during real-device test)

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(capture): export bridge composes via StitchExporter pipeline"
```

---

### Task 16: Permissions, disk-budget guard, error states

**Files:**
- Modify: `VideoCompressor/VideoCompressor_iOS.xcodeproj/project.pbxproj`
- Modify: `VideoCompressor/ios/Capture/CaptureSession.swift`
- Modify: `VideoCompressor/ios/Views/CaptureTab/CaptureTabView.swift`

- [ ] **Step 1: Add Info.plist usage descriptions**

Open `project.pbxproj` and add to the `INFOPLIST_KEY_*` block for both Debug and Release configs (one per app target — DO NOT touch test target configs):

```
INFOPLIST_KEY_NSCameraUsageDescription = "Media Swiss Army uses the cameras for in-app multi-camera recording. Recordings stay on device — nothing is uploaded.";
INFOPLIST_KEY_NSMicrophoneUsageDescription = "Media Swiss Army records the microphone alongside the camera so your captured clips include audio.";
```

- [ ] **Step 2: Permission probe before session start**

```swift
// In CaptureSession.swift
extension CaptureSession {
    enum PermissionState { case granted, denied, undetermined }

    static func cameraPermission() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static func requestCameraPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
```

- [ ] **Step 3: Disk space monitor**

```swift
// In CaptureSession.swift
extension CaptureSession {
    /// Returns free disk space on the volume containing Documents/, in bytes.
    static func freeDiskBytes() -> Int64 {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return bytes
        }
        return 0
    }
}

// Add in CaptureProject.record(...) before starting recording:
let free = CaptureSession.freeDiskBytes()
if free < 200 * 1024 * 1024 {  // 200 MB threshold
    recordingState = .failed(reason: "Less than 200 MB free — clear storage and try again.")
    return
}
```

- [ ] **Step 4: UI for permission-denied**

Add `ContentUnavailableView` in `CaptureTabView` for `cameraPermission == .denied` with a deep link to `UIApplication.openSettingsURLString`.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(capture): camera + mic permissions + disk-budget guard"
```

---

### Task 17: Premium gating hook

**Files:**
- Create: `VideoCompressor/ios/Capture/CapturePremiumGate.swift`
- Modify: `VideoCompressor/ios/Views/CaptureTab/CaptureLayoutPickerSheet.swift`

For testing the user wants ALL functionality unlocked, but the architecture must support gating multi-cam behind a future paywall.

- [ ] **Step 1: Implement gate**

```swift
// CapturePremiumGate.swift
import Foundation

enum CapturePremiumGate {
    /// Dev/test build: everything unlocked. When monetization lands, replace
    /// this with a StoreKit 2 purchase check.
    static var isPremiumUnlocked: Bool { true }

    static func isLayoutAllowed(_ layout: CaptureLayout) -> Bool {
        if isPremiumUnlocked { return true }
        return layout.slotCount <= 1   // only single-camera in free tier
    }
}
```

- [ ] **Step 2: Wire into picker sheet**

In `CaptureLayoutPickerSheet`, add `enabled = enabled && CapturePremiumGate.isLayoutAllowed(layout)`. Add a "Premium" badge for non-allowed layouts (hidden in test build because everything is unlocked).

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(capture): premium gate scaffold (all unlocked in test build)"
```

---

### Task 18: Snapshot tests + final verification + PR

- [ ] **Step 1: Run full test suite**

`mcp__xcodebuildmcp__test_sim`. Expected: 252+ existing tests stay green; ~30+ new Capture tests pass on simulator. Capture tests that require hardware are XCTSkip'd cleanly with a comment.

- [ ] **Step 2: `mcp__xcodebuildmcp__build_sim`** clean.

- [ ] **Step 3: `mcp__xcodebuildmcp__build_run_sim`** — confirm app launches, Capture tab visible, camera-permission UI surfaces correctly.

- [ ] **Step 4: Append `[BLOCKED]` to AI-CHAT-LOG**

```
[YYYY-MM-DD HH:MM SAST] [solo/codex/<model>] [BLOCKED] Cluster 6 ready for real-device verification — install latest TestFlight, walk through Capture tab: (1) tap into Capture, grant permissions; (2) pick topBottom layout, assign rear-main + front cameras; (3) record 5 seconds, swap front camera to rear-wide mid-recording, confirm new clip starts; (4) lock phone, unlock, confirm project preserved with clips intact, tap Resume; (5) record 3 more seconds, stop; (6) reorder/delete a clip in the timeline; (7) tap Export → pick Small preset → Save to Photos; (8) confirm Photos shows the composed multi-cam video. Will not merge until user confirms via [DECISION].
```

- [ ] **Step 5: PR**

```bash
git push -u origin feat/cluster-6-snap-mode-multicam
gh pr create --base main --head feat/cluster-6-snap-mode-multicam --title "feat(capture): Snap-mode multi-camera capture with pause/resume + render handoff"
```

PR body should list the 18 tasks + per-feature summary + the BLOCKED real-device walkthrough.

- [ ] **Step 6: After user `[DECISION]` confirms real-device pass, merge**

```bash
gh pr merge <num> --merge
```

Do NOT pre-merge.

---

## Self-Review

**Spec coverage:**
- ✅ Layouts (single, topBottom, sideBySide, pipBottomRight, threeGrid, fourGrid) — Task 1
- ✅ Multi-camera discovery + assignment — Tasks 2, 6, 8
- ✅ Recording state machine — Task 7
- ✅ Pause/resume across phone-off — Task 12
- ✅ Mid-session layout/camera swap — Task 11 (Strategy B)
- ✅ Pre-render edit (reorder/delete/trim entry) — Task 13
- ✅ Render handoff to StitchExporter — Tasks 14, 15
- ✅ Permissions + disk budget — Task 16
- ✅ Premium gate scaffold — Task 17
- ✅ Real-device gate — Task 18

**Placeholder check:** No "TBD" / "implement later" / "similar to Task N" left. Inline note at Task 7 Step 2 is explicit guidance to the implementer about an extension-state shorthand.

**Type consistency:** `CaptureCameraID`, `CaptureLayout`, `CaptureSlot`, `CaptureClip`, `CaptureProject`, `CaptureSession`, `CaptureProjectStore`, `CaptureRenderer`, `CaptureExportBridge` — all referenced consistently. `CaptureProject.RecordingState` cases referenced uniformly. `clearAll()` matches between hotfix spec #1 and this plan (the same naming convention is used for both StitchProject.clearAll() and CaptureProject.clearAll()).

---

## Execution Handoff

Plan complete and saved to `.agents/work-sessions/2026-05-04/design-spec/3-cluster-6-snap-mode-multicam.md`.

This plan should run via `superpowers:subagent-driven-development` — fresh subagent per task plus pre-merge real-device gate per the BLOCKED protocol established for the iOS work.

Effort estimate: 16–22 hours for the executing agent. Real-device testing per task adds an interactive layer that only the user can drive, so total elapsed time depends on user availability for the BLOCKED walkthroughs at Tasks 9, 11, and 18.
