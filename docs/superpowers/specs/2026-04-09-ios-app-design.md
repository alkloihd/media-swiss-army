# Video Compressor — Native iOS/macOS App Design Spec

**Date:** 2026-04-09
**Status:** Draft
**Platform:** iOS + macOS (Universal App)
**Language:** Swift 6.1 + SwiftUI
**Xcode:** 16.4
**Target:** iOS 17+, macOS 14+

---

## 1. Overview

A native iOS/macOS app for on-device video compression, stitching, and metadata cleaning. All processing happens locally using Apple's VideoToolbox hardware encoders. No cloud, no servers, no data leaves the device.

### Core Principles

- **Local-first** — all compute on-device, zero cloud dependency
- **Privacy** — no network calls, no analytics, no telemetry, files never leave the device
- **On-device power** — leverage VideoToolbox hardware encoders (A-series / M-series chips)
- **Minimal UI** — clean, focused, no unnecessary options or clutter
- **Auto theme** — follows system dark/light mode automatically, no manual toggle

### Origin

This app evolves from a Node.js + FFmpeg web app prototype. The UX design (2D compression matrix, visual controls, tab structure) transfers as concepts. The code is entirely new — native Swift replacing JavaScript, AVFoundation replacing FFmpeg, PhotoKit replacing multer.

---

## 2. App Structure

### Three Tabs

| Tab | Purpose |
|-----|---------|
| **Compress** | Select videos, choose compression settings via the 2D matrix, compress on-device |
| **Stitch** | Visual timeline to reorder, trim, and concatenate multiple clips |
| **MetaClean** | Inspect and surgically strip metadata (Meta glasses fingerprints, etc.) |

### Navigation

- `TabView` with 3 tabs at the bottom (iOS) or sidebar (macOS)
- Each tab is self-contained with its own file selection and processing

---

## 3. Compress Tab

### 3.1 File Selection

- **iOS:** `PHPickerViewController` for camera roll selection (multi-select enabled)
- **macOS:** `NSOpenPanel` for file picker + drag-and-drop onto the window
- Shows selected videos as cards with: thumbnail, filename, duration, file size, resolution
- Batch selection — compress multiple files with the same settings

### 3.2 The Compression Matrix (Hero Control)

A 2D interactive grid rendered with SwiftUI `Canvas` and Core Animation:

**X-axis:** Resolution (6 stops)
- 4K (3840px)
- 2K (2560px)
- 1440p
- 1080p
- 720p
- 480p

**Y-axis:** Compression level (6 stops)
- Lossless (~95% of original)
- Maximum (~75%)
- High (~55%)
- Balanced (~35%)
- Compact (~18%)
- Tiny (~8%)

**Behavior:**
- Tap or drag to select a cell — selected cell glows, nearby cells brighten
- Crosshair lines track the selection
- Pulse animation on selection
- Color gradient: green (large/pristine) → yellow → orange → pink → purple (tiny/lossy)
- Each cell shows estimated percentage of original size
- Percentages update dynamically based on:
  - Selected codec
  - Selected encoder mode (HW vs SW)
  - Actual source file stats when a file is loaded (resolution, bitrate, duration)
- Ambient breathing animation when idle

**Resolution behavior:**
- If source is 1080p, the 4K/2K/1440p columns are disabled (no upscaling)
- The matrix adapts to show only valid options

### 3.3 Codec Selector

Pill-style buttons below the matrix:

| Codec | Badge | Description | iOS Encoder |
|-------|-------|-------------|-------------|
| H.264 | — | Universal compatibility | `AVVideoCodecType.h264` via VideoToolbox |
| H.265 | HW | Best balance (default) | `AVVideoCodecType.hevc` via VideoToolbox |

**Notes:**
- Both H.264 and H.265 are hardware-accelerated on all modern iPhones/Macs
- No AV1 encoding on iOS (Apple hasn't added VideoToolbox AV1 encode support)
- No software-only encoders — iOS only exposes hardware encoding, which is fine (it's fast and efficient)
- No HW/SW toggle needed (unlike the web app) — iOS is always hardware

### 3.4 Audio Controls

Collapsible section below codec selector:

- **Bitrate slider:** 128k → 320k (default: 192k, floor: 128k)
  - Snap stops at 128k, 160k, 192k, 256k, 320k
- **Audio codec:** AAC (default) / Passthrough (copy audio stream unchanged)
  - AAC via `AVAudioSettings` with `kAudioFormatMPEG4AAC`
  - Passthrough = no audio re-encoding, preserves original quality + channels
- **Channel preservation:** Auto-detect and preserve stereo / 5.1 / spatial audio
  - Display indicator: "Stereo", "5.1 Surround", "Spatial Audio"
  - When passthrough is selected, channels are always preserved
  - When AAC is selected, maintain original channel layout

### 3.5 Target Size Mode

Alternative to the matrix — toggle between "Visual Matrix" and "Target Size" modes:

- User enters target file size in MB (quick presets: 50 / 100 / 250 / 500 MB)
- System calculates the best resolution + quality + codec to hit target
- Shows 2 ranked solutions:
  - **Fast** — H.265 hardware, higher bitrate, less quality loss
  - **Best Quality** — H.265 hardware, lower resolution, better quality-per-pixel
- User picks one and compresses

### 3.6 Summary Panel

Sticky panel (bottom sheet on iOS, sidebar on macOS) showing:

- Estimated output size (MB + percentage of original)
- Visual quality meter (bar graph)
- Encode time estimate
- Current settings at a glance: resolution, codec, audio, format
- Color-coded to match the matrix selection

### 3.7 Advanced Options

Collapsible section:

- **Container format:** MP4 (default) / MOV / MKV
  - MP4 for universal compatibility
  - MOV for Apple ecosystem
  - MKV for maximum codec flexibility
- **Frame rate:** Original (default) / 60 / 30 / 24 fps
  - Dropping from 30 to 24 saves ~20% and looks cinematic
- **Preserve metadata:** Toggle (default: ON)
  - GPS, dates, camera info, creation time
  - Uses `AVAssetExportSession.metadata` pass-through
- **Fast start (MP4):** Toggle (default: ON)
  - Moves moov atom to front for streaming compatibility

### 3.8 Save Options

After compression completes, present:

- **Keep both** — save compressed to same album as original
- **Replace original** — save compressed + delete original (iOS shows permission dialog)
- **Share** — share sheet (AirDrop, Files, Messages, etc.)
- Default behavior configurable in Settings (defaults to "Keep both")

### 3.9 Progress

- Per-file progress bar with percentage
- Current encoding speed (e.g., "3.2x realtime")
- ETA countdown
- Batch progress (e.g., "2 of 4 files")
- Background processing supported — user can leave the app
- Notification when complete

---

## 4. Stitch Tab

### 4.1 Clip Selection

Same file picker as Compress tab. Multi-select required (minimum 2 clips).

### 4.2 Visual Timeline

A horizontal scrollable timeline:

- **Clip blocks** — rectangular blocks whose width is proportional to duration
- **Thumbnail strips** — frame thumbnails extracted via `AVAssetImageGenerator` as background
- **Drag to reorder** — press and hold to pick up, drag to rearrange
- **Trim handles** — left/right edge handles on each clip, drag to set trim in/out
- **Stitch point indicators** — colored dividers between clips
- **Time ruler** — tick marks above the timeline showing total duration
- **Duration badge** — each clip shows its duration, total duration shown above

**Implementation:**
- `AVAssetImageGenerator` for thumbnail extraction at evenly spaced intervals
- Drag-and-drop via SwiftUI `.draggable()` / `.dropDestination()` or `UICollectionView` with drag
- Trim via custom gesture recognizers on edge handles
- State: array of `{ asset, trimStart, trimEnd, order }`

### 4.3 Stitch Output Options

- Same compression controls as Compress tab (matrix, codec, audio)
- **Lossless concat** option — if all clips share the same codec/resolution/fps, offer lossless concatenation via `AVMutableComposition` (no re-encode, instant)
- **Re-encode** — if clips differ or user wants compression, re-encode the composed timeline

### 4.4 Output

- Stitched video saved to Photos or exported via share sheet
- Uses `_STITCH` suffix in filename

---

## 5. MetaClean Tab

### 5.1 File Selection

Same picker. Can select photos (HEIC/JPEG) and videos (MOV/MP4).

### 5.2 Metadata Display

- Read metadata via `AVAsset.metadata` (videos) and `CGImageSource` (photos)
- Display as tag cards grouped by category:
  - **Device** — camera model, lens, software
  - **Location** — GPS coordinates, altitude
  - **Time** — creation date, modification date
  - **Technical** — resolution, codec, bitrate, color space
  - **Custom** — Meta glasses fingerprints, AI tags, etc.
- Color-coded: red (will be removed), green (will be preserved)

### 5.3 Cleaning Modes

- **Auto (Meta glasses)** — detect and strip Meta-specific metadata tags (Description, Comment containing device fingerprint, CreationDate patterns)
- **Manual** — user selects which tag categories to strip
- **Strip all** — remove everything except essential technical metadata

### 5.4 Output

- Cleaned file saved with `_CLEAN` suffix
- Before/after metadata count shown
- Animated strip effect on the tag cards when cleaning runs

---

## 6. Settings

Minimal — accessible via gear icon in navigation:

- **Default save behavior:** Keep both / Replace original / Ask every time (default: Keep both)
- **Default compression preset:** Which matrix cell to start with (default: 1080p Balanced)
- **Default audio bitrate:** 128k / 192k / 256k / 320k (default: 192k)
- **Preserve metadata by default:** Toggle (default: ON)
- **About:** Version, credits, privacy policy link

No theme toggle — follows system automatically.

---

## 7. iOS Frameworks & APIs

| Need | Framework / API | Notes |
|------|----------------|-------|
| Video encoding | `AVAssetWriter` + `AVAssetWriterInput` | Full control over VideoToolbox encoding params |
| Quick export | `AVAssetExportSession` | Simpler API for standard presets |
| Video composition | `AVMutableComposition` | Stitch, trim, time ranges |
| Hardware encoding | `VideoToolbox` (via AVFoundation) | H.264 + H.265 on all modern devices |
| Photo library | `PhotoKit` (`PHPickerViewController`, `PHAsset`) | Pick, save, delete |
| File access (macOS) | `NSOpenPanel` + Security-Scoped Bookmarks | Sandboxed file access |
| Photo metadata | `CGImageSource`, `CGImageProperties` | EXIF, GPS, TIFF, IPTC |
| Video metadata | `AVAsset.metadata`, `AVMetadataItem` | Read/write/strip |
| Thumbnails | `AVAssetImageGenerator` | Frame extraction for timeline |
| Audio settings | `AVAudioSettings`, `AudioToolbox` | AAC encoding, channel config |
| UI | `SwiftUI` | All views, multiplatform |
| Graphics | `Canvas`, `TimelineView`, Core Animation | Matrix grid, animations |
| Background processing | `BGProcessingTask` | Continue compression in background |
| Notifications | `UNUserNotificationCenter` | Alert when compression completes |

---

## 8. Data Model

```swift
// Core types
struct CompressionSettings {
    var resolution: Resolution      // .fourK, .twoK, .p1440, .p1080, .p720, .p480
    var quality: QualityLevel       // .lossless, .maximum, .high, .balanced, .compact, .tiny
    var codec: VideoCodec           // .h264, .h265
    var audioBitrate: Int           // 128_000...320_000
    var audioMode: AudioMode        // .aac, .passthrough
    var format: ContainerFormat     // .mp4, .mov, .mkv
    var fps: FPSOption              // .original, .fps60, .fps30, .fps24
    var preserveMetadata: Bool
    var fastStart: Bool
}

struct VideoItem: Identifiable {
    let id: UUID
    let asset: PHAsset              // or URL for macOS file
    var thumbnail: Image?
    var duration: TimeInterval
    var fileSize: Int64
    var resolution: CGSize
    var codec: String
    var bitrate: Int64
    var status: ProcessingStatus    // .idle, .queued, .processing(progress), .done, .error
    var outputURL: URL?
}

struct StitchClip: Identifiable {
    let id: UUID
    var videoItem: VideoItem
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var order: Int
    var thumbnailStrip: [Image]
}

enum SaveBehavior {
    case keepBoth
    case replaceOriginal
    case askEveryTime
}
```

---

## 9. Encoding Pipeline

### Compress Flow

```
PHPicker → PHAsset → AVURLAsset → AVAssetReader
                                        ↓
                                  AVAssetWriter ← CompressionSettings
                                  (VideoToolbox HW encoder)
                                        ↓
                                  Output URL (app sandbox temp)
                                        ↓
                              PHPhotoLibrary.save() → Camera Roll
                              (or share sheet export)
```

### Bitrate Calculation

Map the 6×6 matrix to actual encoding parameters:

```swift
func encodingParams(for settings: CompressionSettings, source: VideoItem) -> [String: Any] {
    let targetHeight: Int = settings.resolution.pixels  // e.g., 1080
    let resFactor = pow(Double(targetHeight) / Double(source.resolution.height), 2)
    let qualityFactor = settings.quality.factor          // 0.95 down to 0.08
    let targetBitrate = Int(Double(source.bitrate) * resFactor * qualityFactor)

    return [
        AVVideoCodecKey: settings.codec.avCodecType,
        AVVideoWidthKey: scaledWidth(source: source, targetHeight: targetHeight),
        AVVideoHeightKey: targetHeight,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: settings.codec.profileLevel,
            AVVideoAllowFrameReorderingKey: true,
        ]
    ]
}
```

### Smart Capping

Same logic as the web app — prevent output exceeding input:
- Balanced: cap at 70% of source bitrate
- Compact: cap at 40%
- Tiny: cap at 20%
- Lossless/Maximum: no cap

### Stitch Flow

```
[Clip1, Clip2, Clip3] → AVMutableComposition
                              ↓
                    Compatible codecs/res? ──yes──→ Lossless export
                              │                     (no re-encode)
                              no
                              ↓
                    AVAssetExportSession or AVAssetWriter
                    (re-encode with compression settings)
                              ↓
                    Output URL → Camera Roll
```

---

## 10. Visual Design

### Color System

Same gradient palette as the matrix mockup:

| Token | Dark Mode | Light Mode | Usage |
|-------|-----------|------------|-------|
| `background` | #0a0a1a | #f8f9fa | App background |
| `card` | #0f0f23 | #ffffff | Card/panel surfaces |
| `cardBorder` | #1a1a35 | #e2e8f0 | Card borders |
| `textPrimary` | #e0e0e0 | #1a1a2e | Main text |
| `textSecondary` | #666666 | #888888 | Muted text |
| `accentGreen` | #22c55e | #16a34a | Positive/primary actions |
| `accentYellow` | #facc15 | #eab308 | Warnings, time estimates |
| `accentOrange` | #f97316 | #ea580c | Medium compression |
| `accentPink` | #ec4899 | #db2777 | High compression |
| `accentPurple` | #a855f7 | #9333ea | Maximum compression |

### Theme

- Auto dark/light following system `colorScheme` — no manual toggle
- Glow effects and particles in dark mode
- Subtle shadows and clean borders in light mode
- All colors via SwiftUI `Color` extension tied to asset catalog or computed from scheme

### Animations

- Matrix cell selection: glow pulse, crosshair fade-in, particle burst
- Progress bars: animated gradient fill with glow
- Stitch timeline: smooth drag reorder with haptic feedback
- MetaClean: tag cards dissolve/shred animation on strip
- Tab transitions: matched geometry effect

### Typography

- SF Pro (system default) — no custom fonts needed
- Title: `.title2.bold()`
- Section headers: `.caption.textCase(.uppercase).tracking(1.5)`
- Body: `.subheadline`
- Values/numbers: `.system(.title, design: .rounded, weight: .bold)`

---

## 11. Project Structure

```
VideoCompressor/
  VideoCompressor.xcodeproj
  VideoCompressorApp.swift          // @main, TabView, app lifecycle
  Models/
    CompressionSettings.swift       // Settings data model
    VideoItem.swift                 // Video file model
    StitchClip.swift                // Stitch clip model
    Enums.swift                     // Resolution, QualityLevel, VideoCodec, etc.
  Views/
    CompressTab/
      CompressView.swift            // Main compress screen
      MatrixGridView.swift          // 2D compression matrix (Canvas)
      CodecSelectorView.swift       // Codec pill buttons
      AudioControlsView.swift       // Audio bitrate + codec
      TargetSizeModeView.swift      // Target size alternative
      SummaryPanelView.swift        // Output estimate panel
      AdvancedOptionsView.swift     // Format, FPS, metadata toggles
    StitchTab/
      StitchView.swift              // Main stitch screen
      TimelineView.swift            // Horizontal clip timeline
      ClipBlockView.swift           // Individual clip with trim handles
      TrimHandleView.swift          // Draggable trim edges
    MetaCleanTab/
      MetaCleanView.swift           // Main metaclean screen
      MetadataTagView.swift         // Individual tag card
      MetadataListView.swift        // Tag list with categories
    Shared/
      VideoPickerView.swift         // PHPicker wrapper
      FileCardView.swift            // Video file card (thumbnail, info)
      ProgressBarView.swift         // Animated progress bar
      SettingsView.swift            // App settings
  Services/
    CompressionService.swift        // AVAssetWriter encoding pipeline
    StitchService.swift             // AVMutableComposition pipeline
    MetadataService.swift           // Metadata read/write/strip
    ThumbnailService.swift          // AVAssetImageGenerator
    PhotoLibraryService.swift       // PHPhotoLibrary save/delete
    EstimationService.swift         // Size/time estimation math
  Extensions/
    Color+Theme.swift               // Color system
    View+Modifiers.swift            // Shared view modifiers
  Resources/
    Assets.xcassets                 // App icon, colors
```

---

## 12. What's NOT in Scope (v1.0)

- Cloud processing of any kind
- User accounts or authentication
- AV1 encoding (not available on iOS VideoToolbox)
- Audio-only compression
- Waveform visualization in timeline (future enhancement)
- Crop/rotation tools (future enhancement)
- Video filters/effects
- iPad split-screen optimization (works but not optimized)
- Watch app
- Widgets

---

## 13. Development Phases

### Phase 1 — Foundation
- Xcode project setup (multiplatform iOS + macOS)
- Data models and enums
- Color system and theme
- Tab navigation shell
- PHPicker integration
- Video probing (read metadata, duration, resolution, bitrate)

### Phase 2 — Compress
- Matrix grid view (Canvas rendering, touch/drag interaction, animations)
- Codec selector
- Audio controls
- Summary panel with live estimates
- AVAssetWriter encoding pipeline
- Progress reporting
- Save to Photos / share sheet

### Phase 3 — Stitch
- Timeline view with clip blocks
- Thumbnail strip generation
- Drag to reorder
- Trim handles
- AVMutableComposition pipeline
- Lossless concat detection
- Re-encode option with compression settings

### Phase 4 — MetaClean
- Metadata reading (CGImageSource, AVAsset.metadata)
- Tag display with categories
- Meta glasses fingerprint detection
- Surgical strip + clean copy
- Animated tag removal UI

### Phase 5 — Polish
- Advanced options (format, FPS, metadata toggle, fast start)
- Target Size mode
- Settings screen
- Background processing
- Notifications
- macOS-specific adaptations (sidebar nav, NSOpenPanel, window sizing)
- App icon and App Store assets
