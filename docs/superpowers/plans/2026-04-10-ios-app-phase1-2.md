# VideoCompressor iOS/macOS App — Phase 1 & 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working iOS/macOS universal app that compresses videos on-device using VideoToolbox hardware encoders, with the 2D compression matrix UI from the web prototype.

**Architecture:** SwiftUI multiplatform app with AVFoundation encoding pipeline. PhotoKit for file access on iOS, NSOpenPanel on macOS. Compression settings map to AVAssetWriter + VideoToolbox bitrate parameters. No cloud, no server, all local.

**Tech Stack:** Swift 6.1, SwiftUI, AVFoundation, VideoToolbox, PhotoKit, Xcode 16.4

**Spec:** `docs/superpowers/specs/2026-04-09-ios-app-design.md`

---

## File Structure

```
VideoCompressor/
  VideoCompressorApp.swift              # @main entry, TabView shell
  Models/
    CompressionSettings.swift           # Settings data model + enums
    VideoItem.swift                     # Video file model with metadata
  Views/
    CompressTab/
      CompressView.swift                # Main compress screen (picker + controls + action)
      MatrixGridView.swift              # 2D resolution x quality Canvas grid
      CodecSelectorView.swift           # H.264 / H.265 codec pills
      AudioControlsView.swift           # Audio bitrate slider + codec picker
      SummaryPanelView.swift            # Live output estimate panel
      ProgressOverlayView.swift         # Full-screen compress progress
      CompletionView.swift              # Done screen with stats
    Shared/
      VideoPickerButton.swift           # PHPicker wrapper (iOS) / NSOpenPanel (macOS)
      VideoThumbnailView.swift          # Async thumbnail from AVAssetImageGenerator
  Services/
    CompressionService.swift            # AVAssetWriter encoding pipeline
    ProbeService.swift                  # Read video metadata (duration, resolution, bitrate, codec)
    EstimationService.swift             # Size/time estimation math
    PhotoLibraryService.swift           # Save to Photos, delete original
  Extensions/
    Color+Theme.swift                   # Color system (accent colors, semantic tokens)
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: Xcode project via GUI (cannot be scripted)
- Create: `VideoCompressor/Extensions/Color+Theme.swift`
- Create: `VideoCompressor/VideoCompressorApp.swift`

- [ ] **Step 1: Create Xcode project**

Open Xcode → File → New → Project → Multiplatform → App
- Product Name: `VideoCompressor`
- Team: Your Apple Developer account
- Organization Identifier: `com.yourname` (e.g., `com.rishaal`)
- Interface: SwiftUI
- Language: Swift
- Storage: None
- Uncheck "Include Tests" for now

Set deployment targets:
- iOS: 17.0
- macOS: 14.0

- [ ] **Step 2: Create Color+Theme.swift**

```swift
// VideoCompressor/Extensions/Color+Theme.swift
import SwiftUI

extension Color {
    // Backgrounds
    static let bgPrimary = Color(light: .init(hex: "f8f9fa"), dark: .init(hex: "0a0a1a"))
    static let bgCard = Color(light: .init(hex: "ffffff"), dark: .init(hex: "0f0f23"))
    static let bgCardBorder = Color(light: .init(hex: "e2e8f0"), dark: .init(hex: "1a1a35"))

    // Text
    static let textPrimary = Color(light: .init(hex: "1a1a2e"), dark: .init(hex: "e0e0e0"))
    static let textSecondary = Color(light: .init(hex: "888888"), dark: .init(hex: "666666"))
    static let textMuted = Color(light: .init(hex: "aaaaaa"), dark: .init(hex: "444444"))

    // Accents
    static let accentGreen = Color(light: .init(hex: "16a34a"), dark: .init(hex: "22c55e"))
    static let accentYellow = Color(light: .init(hex: "eab308"), dark: .init(hex: "facc15"))
    static let accentOrange = Color(light: .init(hex: "ea580c"), dark: .init(hex: "f97316"))
    static let accentPink = Color(light: .init(hex: "db2777"), dark: .init(hex: "ec4899"))
    static let accentPurple = Color(light: .init(hex: "9333ea"), dark: .init(hex: "a855f7"))
    static let accentCyan = Color(light: .init(hex: "0891b2"), dark: .init(hex: "06b6d4"))

    // Helper: light/dark adaptive color
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 3: Replace default ContentView with tab shell**

Replace the default `ContentView.swift` (or `VideoCompressorApp.swift`):

```swift
// VideoCompressor/VideoCompressorApp.swift
import SwiftUI

@main
struct VideoCompressorApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                CompressPlaceholderView()
                    .tabItem {
                        Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                    }

                StitchPlaceholderView()
                    .tabItem {
                        Label("Stitch", systemImage: "link")
                    }

                MetaCleanPlaceholderView()
                    .tabItem {
                        Label("MetaClean", systemImage: "xmark.shield")
                    }
            }
            .tint(.accentGreen)
            .preferredColorScheme(.dark)
        }
    }
}

struct CompressPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Compress tab coming soon")
                .foregroundStyle(.textSecondary)
                .navigationTitle("Compress")
        }
    }
}

struct StitchPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Stitch tab coming soon")
                .foregroundStyle(.textSecondary)
                .navigationTitle("Stitch")
        }
    }
}

struct MetaCleanPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("MetaClean tab coming soon")
                .foregroundStyle(.textSecondary)
                .navigationTitle("MetaClean")
        }
    }
}
```

- [ ] **Step 4: Build and run on simulator**

Run: Cmd+R in Xcode with iPhone 15 Pro simulator selected.
Expected: App launches with 3 tabs, dark theme, green tint, placeholder text in each tab.

- [ ] **Step 5: Build and run on physical iPhone**

Plug in iPhone, select it as run target, hit Cmd+R.
Expected: Same 3-tab app on your phone. Xcode handles signing automatically.

- [ ] **Step 6: Commit**

```bash
cd VideoCompressor
git init
git add -A
git commit -m "feat: initial Xcode project with 3-tab shell and color system"
```

---

## Task 2: Data Models

**Files:**
- Create: `VideoCompressor/Models/CompressionSettings.swift`
- Create: `VideoCompressor/Models/VideoItem.swift`

- [ ] **Step 1: Create CompressionSettings.swift**

```swift
// VideoCompressor/Models/CompressionSettings.swift
import Foundation

enum Resolution: String, CaseIterable, Identifiable {
    case fourK = "4K"
    case twoK = "2K"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }

    var height: Int {
        switch self {
        case .fourK: 2160
        case .twoK: 1440
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }

    var columnIndex: Int {
        switch self {
        case .fourK: 0
        case .twoK: 1
        case .p1440: 2
        case .p1080: 3
        case .p720: 4
        case .p480: 5
        }
    }
}

enum QualityLevel: String, CaseIterable, Identifiable {
    case lossless = "Lossless"
    case maximum = "Maximum"
    case high = "High"
    case balanced = "Balanced"
    case compact = "Compact"
    case tiny = "Tiny"

    var id: String { rawValue }

    /// Approximate percentage of original file size
    var sizePercentage: Double {
        switch self {
        case .lossless: 0.95
        case .maximum: 0.75
        case .high: 0.55
        case .balanced: 0.35
        case .compact: 0.18
        case .tiny: 0.08
        }
    }

    var rowIndex: Int {
        switch self {
        case .lossless: 0
        case .maximum: 1
        case .high: 2
        case .balanced: 3
        case .compact: 4
        case .tiny: 5
        }
    }

    /// Quality rating out of 5 for the visual meter
    var qualityRating: Int {
        switch self {
        case .lossless, .maximum: 5
        case .high: 4
        case .balanced: 3
        case .compact: 2
        case .tiny: 1
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case h265 = "H.265"

    var id: String { rawValue }

    var isHardwareAccelerated: Bool { true } // Both are HW-accelerated on Apple Silicon
}

enum AudioMode: String, CaseIterable, Identifiable {
    case aac = "AAC"
    case passthrough = "Passthrough"

    var id: String { rawValue }
}

enum ContainerFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mp4: "mp4"
        case .mov: "mov"
        }
    }
}

enum FPSOption: String, CaseIterable, Identifiable {
    case original = "Original"
    case fps60 = "60"
    case fps30 = "30"
    case fps24 = "24"

    var id: String { rawValue }

    var value: Float? {
        switch self {
        case .original: nil
        case .fps60: 60
        case .fps30: 30
        case .fps24: 24
        }
    }
}

enum SaveBehavior: String, CaseIterable, Identifiable {
    case keepBoth = "Keep Both"
    case replaceOriginal = "Replace Original"
    case askEveryTime = "Ask Every Time"

    var id: String { rawValue }
}

@Observable
class CompressionSettings {
    var resolution: Resolution = .p1080
    var quality: QualityLevel = .balanced
    var codec: VideoCodec = .h265
    var audioBitrate: Int = 192_000
    var audioMode: AudioMode = .aac
    var format: ContainerFormat = .mp4
    var fps: FPSOption = .original
    var preserveMetadata: Bool = true
    var fastStart: Bool = true

    /// Target bitrate calculated from quality level and source info
    func targetBitrate(sourceBitrate: Int, sourceHeight: Int) -> Int {
        let resFactor = pow(Double(resolution.height) / Double(sourceHeight), 2)
        let qualFactor = quality.sizePercentage
        let raw = Double(sourceBitrate) * resFactor * qualFactor
        return max(500_000, Int(raw)) // minimum 500kbps
    }
}
```

- [ ] **Step 2: Create VideoItem.swift**

```swift
// VideoCompressor/Models/VideoItem.swift
import Foundation
import AVFoundation
import SwiftUI

enum ProcessingStatus: Equatable {
    case idle
    case queued
    case processing(progress: Double) // 0.0 - 1.0
    case done(outputURL: URL, outputSize: Int64)
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .queued, .processing: true
        default: false
        }
    }

    var isDone: Bool {
        if case .done = self { return true }
        return false
    }

    var progress: Double {
        switch self {
        case .processing(let p): p
        case .done: 1.0
        default: 0.0
        }
    }
}

@Observable
class VideoItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var asset: AVURLAsset

    // Metadata (populated by ProbeService)
    var duration: TimeInterval = 0
    var fileSize: Int64 = 0
    var width: Int = 0
    var height: Int = 0
    var codecName: String = ""
    var bitrate: Int = 0
    var fps: Float = 0
    var audioChannels: Int = 0

    // Processing state
    var status: ProcessingStatus = .idle
    var thumbnail: Image?

    var fileName: String {
        sourceURL.lastPathComponent
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    init(url: URL) {
        self.sourceURL = url
        self.asset = AVURLAsset(url: url)
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: Cmd+B in Xcode.
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Models/
git commit -m "feat: add CompressionSettings and VideoItem data models"
```

---

## Task 3: ProbeService — Read Video Metadata

**Files:**
- Create: `VideoCompressor/Services/ProbeService.swift`

- [ ] **Step 1: Create ProbeService.swift**

```swift
// VideoCompressor/Services/ProbeService.swift
import AVFoundation
import SwiftUI

enum ProbeService {
    /// Read video metadata from a URL. Populates the VideoItem's properties.
    static func probe(_ item: VideoItem) async throws {
        let asset = item.asset

        // Load duration
        let duration = try await asset.load(.duration)
        item.duration = duration.seconds

        // Load tracks
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        // Video track info
        if let videoTrack = videoTracks.first {
            let size = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            // Apply transform to get actual dimensions (handles rotation)
            let transformedSize = size.applying(transform)
            item.width = Int(abs(transformedSize.width))
            item.height = Int(abs(transformedSize.height))

            let estimatedRate = try await videoTrack.load(.estimatedDataRate)
            item.bitrate = Int(estimatedRate)

            let nominalFPS = try await videoTrack.load(.nominalFrameRate)
            item.fps = nominalFPS

            // Codec name from format descriptions
            let descriptions = try await videoTrack.load(.formatDescriptions)
            if let desc = descriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                item.codecName = codecType.codecName
            }
        }

        // Audio track info
        if let audioTrack = audioTracks.first {
            let descriptions = try await audioTrack.load(.formatDescriptions)
            if let desc = descriptions.first {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                item.audioChannels = Int(asbd?.pointee.mChannelsPerFrame ?? 2)
            }
        }

        // File size
        let resourceValues = try item.sourceURL.resourceValues(forKeys: [.fileSizeKey])
        item.fileSize = Int64(resourceValues.fileSize ?? 0)

        // If bitrate is 0, estimate from file size and duration
        if item.bitrate == 0 && item.duration > 0 {
            item.bitrate = Int(Double(item.fileSize * 8) / item.duration)
        }

        // Generate thumbnail
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let time = CMTime(seconds: min(2.0, item.duration * 0.1), preferredTimescale: 600)
        if let cgImage = try? await generator.image(at: time).image {
            item.thumbnail = Image(decorative: cgImage, scale: 1.0)
        }
    }
}

// Helper: FourCharCode to codec name
extension FourCharCode {
    var codecName: String {
        switch self {
        case kCMVideoCodecType_H264: "H.264"
        case kCMVideoCodecType_HEVC: "H.265"
        case kCMVideoCodecType_MPEG4Video: "MPEG-4"
        case kCMVideoCodecType_AppleProRes422: "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: "ProRes 4444"
        default:
            let chars = [
                Character(UnicodeScalar((self >> 24) & 0xFF)!),
                Character(UnicodeScalar((self >> 16) & 0xFF)!),
                Character(UnicodeScalar((self >> 8) & 0xFF)!),
                Character(UnicodeScalar(self & 0xFF)!),
            ]
            return String(chars).trimmingCharacters(in: .whitespaces)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: Cmd+B. Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Services/ProbeService.swift
git commit -m "feat: add ProbeService for reading video metadata"
```

---

## Task 4: Video Picker (iOS + macOS)

**Files:**
- Create: `VideoCompressor/Views/Shared/VideoPickerButton.swift`
- Create: `VideoCompressor/Views/Shared/VideoThumbnailView.swift`

- [ ] **Step 1: Create VideoPickerButton.swift**

```swift
// VideoCompressor/Views/Shared/VideoPickerButton.swift
import SwiftUI
import PhotosUI

struct VideoPickerButton: View {
    let onPick: ([URL]) -> Void
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false

    var body: some View {
        #if os(iOS)
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 20,
            matching: .videos
        ) {
            pickerLabel
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                await handleSelection(newItems)
            }
        }
        #else
        Button(action: { isImporting = true }) {
            pickerLabel
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let accessed = urls.compactMap { url -> URL? in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    return url
                }
                onPick(accessed)
            case .failure:
                break
            }
        }
        #endif
    }

    private var pickerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
            Text("Browse Files")
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.accentGreen)
        .foregroundStyle(.black)
        .clipShape(Capsule())
        .shadow(color: .accentGreen.opacity(0.3), radius: 10)
    }

    #if os(iOS)
    private func handleSelection(_ items: [PhotosPickerItem]) async {
        var urls: [URL] = []
        for item in items {
            if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                urls.append(movie.url)
            }
        }
        if !urls.isEmpty {
            onPick(urls)
        }
        selectedItems = []
    }
    #endif
}

#if os(iOS)
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to temp directory so we have a stable URL
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return Self(url: temp)
        }
    }
}
#endif
```

- [ ] **Step 2: Create VideoThumbnailView.swift**

```swift
// VideoCompressor/Views/Shared/VideoThumbnailView.swift
import SwiftUI

struct VideoThumbnailView: View {
    let image: Image?
    let width: CGFloat
    let height: CGFloat

    init(_ image: Image?, width: CGFloat = 120, height: CGFloat = 80) {
        self.image = image
        self.width = width
        self.height = height
    }

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.bgCardBorder)
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.textMuted)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 3: Build to verify**

Run: Cmd+B. Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Views/Shared/
git commit -m "feat: add VideoPickerButton and VideoThumbnailView"
```

---

## Task 5: Compression Service

**Files:**
- Create: `VideoCompressor/Services/CompressionService.swift`
- Create: `VideoCompressor/Services/EstimationService.swift`

- [ ] **Step 1: Create CompressionService.swift**

```swift
// VideoCompressor/Services/CompressionService.swift
import AVFoundation
import VideoToolbox

actor CompressionService {
    enum CompressionError: LocalizedError {
        case noVideoTrack
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "No video track found"
            case .exportFailed(let msg): "Export failed: \(msg)"
            case .cancelled: "Compression was cancelled"
            }
        }
    }

    /// Compress a video with the given settings. Reports progress via the callback.
    func compress(
        item: VideoItem,
        settings: CompressionSettings,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = item.asset
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CompressionError.noVideoTrack
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        // Calculate output dimensions
        let targetHeight = settings.resolution.height
        let sourceSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformed = sourceSize.applying(transform)
        let srcW = abs(transformed.width)
        let srcH = abs(transformed.height)

        let scale = CGFloat(targetHeight) / srcH
        let outW = Int(srcW * scale)
        let outH = targetHeight
        // Ensure even dimensions
        let evenW = outW % 2 == 0 ? outW : outW + 1
        let evenH = outH % 2 == 0 ? outH : outH + 1

        // Target bitrate
        let targetBitrate = settings.targetBitrate(
            sourceBitrate: item.bitrate,
            sourceHeight: item.height
        )

        // Output URL
        let outputURL = generateOutputURL(for: item.sourceURL, format: settings.format)

        // Video settings
        let codecKey: AVVideoCodecType = settings.codec == .h265 ? .hevc : .h264
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoAllowFrameReorderingKey: true,
            AVVideoExpectedSourceFrameRateKey: item.fps > 0 ? item.fps : 30,
        ]
        if settings.codec == .h265 {
            compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        } else {
            compressionProps[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codecKey,
            AVVideoWidthKey: evenW,
            AVVideoHeightKey: evenH,
            AVVideoCompressionPropertiesKey: compressionProps,
        ]

        // Audio settings
        var audioSettings: [String: Any]?
        if settings.audioMode == .aac {
            audioSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: min(item.audioChannels, 2),
                AVEncoderBitRateKey: settings.audioBitrate,
            ]
        }

        // Set up reader
        let reader = try AVAssetReader(asset: asset)
        let readerVideoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(readerVideoOutput)

        var readerAudioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks.first, settings.audioMode == .aac {
            let audioOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: min(item.audioChannels, 2),
                ]
            )
            reader.add(audioOutput)
            readerAudioOutput = audioOutput
        }

        // Set up writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: settings.format == .mov ? .mov : .mp4)

        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false
        writerVideoInput.transform = try await videoTrack.load(.preferredTransform)
        writer.add(writerVideoInput)

        var writerAudioInput: AVAssetWriterInput?
        if let audioSettings {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            writerAudioInput = audioInput
        } else if let audioTrack = audioTracks.first, settings.audioMode == .passthrough {
            // Passthrough: copy audio as-is
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            writerAudioInput = audioInput

            // Replace audio reader output with passthrough
            reader.outputs.forEach { output in
                if output == readerAudioOutput {
                    reader.remove(output)
                }
            }
            let passthroughOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(passthroughOutput)
            readerAudioOutput = passthroughOutput
        }

        // Start
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalDuration = item.duration

        // Write video
        await withCheckedContinuation { continuation in
            writerVideoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video.queue")) {
                while writerVideoInput.isReadyForMoreMediaData {
                    if let buffer = readerVideoOutput.copyNextSampleBuffer() {
                        writerVideoInput.append(buffer)
                        let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                        if totalDuration > 0 {
                            let progress = min(pts / totalDuration, 1.0)
                            onProgress(progress)
                        }
                    } else {
                        writerVideoInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        // Write audio
        if let readerAudioOutput, let writerAudioInput {
            await withCheckedContinuation { continuation in
                writerAudioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.queue")) {
                    while writerAudioInput.isReadyForMoreMediaData {
                        if let buffer = readerAudioOutput.copyNextSampleBuffer() {
                            writerAudioInput.append(buffer)
                        } else {
                            writerAudioInput.markAsFinished()
                            continuation.resume()
                            return
                        }
                    }
                }
            }
        }

        // Finish
        await writer.finishWriting()

        if writer.status == .failed {
            throw CompressionError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        return outputURL
    }

    private func generateOutputURL(for sourceURL: URL, format: ContainerFormat) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let ext = format.fileExtension
        var outputURL = dir.appendingPathComponent("\(name)_COMP.\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = dir.appendingPathComponent("\(name)_COMP_\(counter).\(ext)")
            counter += 1
        }
        return outputURL
    }
}
```

- [ ] **Step 2: Create EstimationService.swift**

```swift
// VideoCompressor/Services/EstimationService.swift
import Foundation

enum EstimationService {
    /// Estimate output file size in bytes
    static func estimateSize(
        settings: CompressionSettings,
        sourceSize: Int64,
        sourceHeight: Int,
        sourceBitrate: Int,
        duration: TimeInterval
    ) -> Int64 {
        let resFactor = pow(Double(settings.resolution.height) / Double(max(sourceHeight, 1)), 2)
        let qualFactor = settings.quality.sizePercentage
        let codecFactor: Double = settings.codec == .h265 ? 0.85 : 1.0
        let estimated = Double(sourceSize) * resFactor * qualFactor * codecFactor
        return max(1_000_000, Int64(estimated)) // minimum 1MB
    }

    /// Estimate encoding time in seconds
    static func estimateTime(
        settings: CompressionSettings,
        duration: TimeInterval,
        sourceHeight: Int
    ) -> TimeInterval {
        // Hardware encoding speed estimate (realtime multiplier)
        let realtimeMultiplier: Double
        let isHighRes = sourceHeight > 1080
        switch settings.codec {
        case .h264:
            realtimeMultiplier = isHighRes ? 6.0 : 12.0
        case .h265:
            realtimeMultiplier = isHighRes ? 4.0 : 8.0
        }
        return max(1, duration / realtimeMultiplier)
    }

    /// Format bytes as human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Format duration as "Xm Ys"
    static func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
    }
}
```

- [ ] **Step 3: Build to verify**

Run: Cmd+B. Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Services/
git commit -m "feat: add CompressionService and EstimationService"
```

---

## Task 6: Matrix Grid View

**Files:**
- Create: `VideoCompressor/Views/CompressTab/MatrixGridView.swift`

- [ ] **Step 1: Create MatrixGridView.swift**

```swift
// VideoCompressor/Views/CompressTab/MatrixGridView.swift
import SwiftUI

struct MatrixGridView: View {
    @Binding var selectedResolution: Resolution
    @Binding var selectedQuality: QualityLevel
    var sourceHeight: Int?

    private let columns = Resolution.allCases
    private let rows = QualityLevel.allCases
    private let cellSize: CGFloat = 52

    // Color stops for the gradient: green → lime → yellow → orange → pink → purple
    private let colorStops: [(Double, Double, Double)] = [
        (34, 197, 94),   // green
        (132, 204, 22),  // lime
        (234, 179, 8),   // yellow
        (249, 115, 22),  // orange
        (236, 72, 153),  // pink
        (168, 85, 247),  // purple
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Grid
            HStack(spacing: 0) {
                // Y-axis labels
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Text(row.rawValue)
                            .font(.system(size: 9, weight: row == selectedQuality ? .bold : .regular))
                            .foregroundStyle(row == selectedQuality ? cellColor(for: selectedResolution.columnIndex, row.rowIndex) : .textMuted)
                            .frame(width: 55, height: cellSize)
                    }
                }

                // Grid cells
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            ForEach(columns) { col in
                                let isSelected = col == selectedResolution && row == selectedQuality
                                let isNear = abs(col.columnIndex - selectedResolution.columnIndex) <= 1 &&
                                    abs(row.rowIndex - selectedQuality.rowIndex) <= 1
                                let isDisabled = sourceHeight != nil && col.height > sourceHeight!
                                let color = cellColor(for: col.columnIndex, row.rowIndex)
                                let pct = estimatePercent(col: col.columnIndex, row: row.rowIndex)

                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(color.opacity(isSelected ? 0.55 : isNear ? 0.2 : 0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(color.opacity(isSelected ? 0.9 : 0.15), lineWidth: isSelected ? 2 : 1)
                                        )

                                    Text("\(pct)%")
                                        .font(.system(size: isSelected ? 11 : 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : color.opacity(isNear ? 0.65 : 0.35))

                                    if isSelected {
                                        Circle()
                                            .fill(color.opacity(0.25))
                                            .frame(width: 44, height: 44)
                                            .blur(radius: 8)
                                    }
                                }
                                .frame(width: cellSize, height: cellSize)
                                .padding(1)
                                .opacity(isDisabled ? 0.3 : 1.0)
                                .onTapGesture {
                                    guard !isDisabled else { return }
                                    withAnimation(.spring(duration: 0.3)) {
                                        selectedResolution = col
                                        selectedQuality = row
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // X-axis labels
            HStack(spacing: 0) {
                Spacer().frame(width: 55)
                ForEach(columns) { col in
                    Text(col.rawValue)
                        .font(.system(size: 9, weight: col == selectedResolution ? .bold : .regular))
                        .foregroundStyle(col == selectedResolution ? cellColor(for: col.columnIndex, selectedQuality.rowIndex) : .textMuted)
                        .frame(width: cellSize + 2)
                }
            }
            .padding(.top, 4)
        }
    }

    private func cellColor(for col: Int, _ row: Int) -> Color {
        let t = (Double(col) / Double(max(columns.count - 1, 1)) +
                 Double(row) / Double(max(rows.count - 1, 1))) / 2.0
        let idx = t * Double(colorStops.count - 1)
        let i = min(Int(idx), colorStops.count - 2)
        let f = idx - Double(i)
        let c1 = colorStops[i]
        let c2 = colorStops[i + 1]
        return Color(
            red: (c1.0 + (c2.0 - c1.0) * f) / 255,
            green: (c1.1 + (c2.1 - c1.1) * f) / 255,
            blue: (c1.2 + (c2.2 - c1.2) * f) / 255
        )
    }

    private func estimatePercent(col: Int, row: Int) -> Int {
        let resFactor = pow(Double(columns[col].height) / Double(columns[0].height), 2)
        let qualFactor = rows[row].sizePercentage
        return max(2, Int(resFactor * qualFactor * 100))
    }
}
```

- [ ] **Step 2: Build and preview**

Run: Cmd+B. In Xcode, open the Canvas preview (Cmd+Option+P) to see the matrix.
Expected: 6x6 grid with color gradient from green to purple, cells show percentages.

- [ ] **Step 3: Commit**

```bash
git add Views/CompressTab/MatrixGridView.swift
git commit -m "feat: add MatrixGridView — 2D resolution x quality picker"
```

---

## Task 7: Compress Tab UI (Full Screen)

**Files:**
- Create: `VideoCompressor/Views/CompressTab/CompressView.swift`
- Create: `VideoCompressor/Views/CompressTab/CodecSelectorView.swift`
- Create: `VideoCompressor/Views/CompressTab/AudioControlsView.swift`
- Create: `VideoCompressor/Views/CompressTab/SummaryPanelView.swift`
- Create: `VideoCompressor/Views/CompressTab/ProgressOverlayView.swift`
- Create: `VideoCompressor/Views/CompressTab/CompletionView.swift`

- [ ] **Step 1: Create CodecSelectorView.swift**

```swift
// VideoCompressor/Views/CompressTab/CodecSelectorView.swift
import SwiftUI

struct CodecSelectorView: View {
    @Binding var selectedCodec: VideoCodec

    var body: some View {
        HStack(spacing: 8) {
            ForEach(VideoCodec.allCases) { codec in
                Button {
                    selectedCodec = codec
                } label: {
                    HStack(spacing: 6) {
                        Text(codec.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        if codec.isHardwareAccelerated {
                            Text("HW")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentGreen.opacity(0.2))
                                .foregroundStyle(.accentGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedCodec == codec ? Color.accentGreen.opacity(0.1) : Color.bgCardBorder.opacity(0.3))
                    .foregroundStyle(selectedCodec == codec ? .white : .textSecondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(selectedCodec == codec ? Color.accentGreen : Color.bgCardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 2: Create AudioControlsView.swift**

```swift
// VideoCompressor/Views/CompressTab/AudioControlsView.swift
import SwiftUI

struct AudioControlsView: View {
    @Binding var bitrate: Int
    @Binding var mode: AudioMode
    var audioChannels: Int

    private let bitrateStops = [128_000, 160_000, 192_000, 256_000, 320_000]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Bitrate slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bitrate")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                    Spacer()
                    Text("\(bitrate / 1000)k")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Color.bgCardBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Slider(
                    value: Binding(
                        get: { Double(bitrate) },
                        set: { bitrate = Int($0) }
                    ),
                    in: 128_000...320_000,
                    step: 32_000
                )
                .tint(.accentPurple)
            }

            // Audio codec
            HStack(spacing: 8) {
                Text("Codec")
                    .font(.system(size: 11))
                    .foregroundStyle(.textSecondary)
                Spacer()
                ForEach(AudioMode.allCases) { audioMode in
                    Button {
                        mode = audioMode
                    } label: {
                        Text(audioMode.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(mode == audioMode ? Color.accentPurple.opacity(0.15) : Color.clear)
                            .foregroundStyle(mode == audioMode ? Color.accentPurple : .textMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(mode == audioMode ? Color.accentPurple : Color.bgCardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Channel info
            if audioChannels > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentPurple)
                        .frame(width: 6, height: 6)
                    Text(audioChannels > 2 ? "\(audioChannels)ch Surround" : "Stereo")
                        .font(.system(size: 10))
                        .foregroundStyle(.textMuted)
                    Text("auto-preserved")
                        .font(.system(size: 10))
                        .foregroundStyle(.textMuted.opacity(0.6))
                }
            }
        }
    }
}
```

- [ ] **Step 3: Create SummaryPanelView.swift**

```swift
// VideoCompressor/Views/CompressTab/SummaryPanelView.swift
import SwiftUI

struct SummaryPanelView: View {
    let estimatedSize: Int64
    let originalSize: Int64
    let estimatedTime: TimeInterval
    let settings: CompressionSettings

    private var percentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(estimatedSize) / Double(originalSize) * 100
    }

    private var savings: Double {
        guard originalSize > 0 else { return 0 }
        return (1.0 - Double(estimatedSize) / Double(originalSize)) * 100
    }

    var body: some View {
        VStack(spacing: 12) {
            // Size estimate
            Text("~\(EstimationService.formatBytes(estimatedSize))")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.accentGreen)

            Text("\(Int(percentage))% of original")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.accentGreen.opacity(0.8))

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bgCardBorder)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentGreen)
                        .frame(width: geo.size.width * min(percentage / 100, 1.0))
                }
            }
            .frame(height: 6)

            // Specs grid
            HStack(spacing: 16) {
                specItem("Resolution", settings.resolution.rawValue)
                specItem("Codec", settings.codec.rawValue)
                specItem("Audio", settings.audioMode == .passthrough ? "Copy" : "\(settings.audioBitrate / 1000)k")
                specItem("Format", settings.format.rawValue)
            }
            .padding(.top, 4)

            // Encode time
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text("~\(EstimationService.formatTime(estimatedTime))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.accentYellow)
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bgCardBorder, lineWidth: 1)
        )
    }

    private func specItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.textPrimary)
        }
    }
}
```

- [ ] **Step 4: Create ProgressOverlayView.swift**

```swift
// VideoCompressor/Views/CompressTab/ProgressOverlayView.swift
import SwiftUI

struct ProgressOverlayView: View {
    let items: [VideoItem]

    private var doneCount: Int {
        items.filter(\.status.isDone).count
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Compressing...")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.textPrimary)

            Text("\(doneCount) of \(items.count) files complete")
                .font(.system(size: 13))
                .foregroundStyle(.textMuted)

            VStack(spacing: 12) {
                ForEach(items) { item in
                    fileProgressCard(item)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 500)
    }

    private func fileProgressCard(_ item: VideoItem) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Spacer()
                statusBadge(item.status)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 99)
                        .fill(Color.bgCardBorder)
                    RoundedRectangle(cornerRadius: 99)
                        .fill(progressGradient(item.status))
                        .frame(width: geo.size.width * item.status.progress)
                        .animation(.easeInOut(duration: 0.3), value: item.status.progress)
                }
            }
            .frame(height: 8)

            // Done: show size comparison
            if case .done(_, let outputSize) = item.status {
                HStack {
                    Text("\(item.formattedSize) → \(ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file))")
                        .font(.system(size: 11))
                        .foregroundStyle(.textMuted)
                    Spacer()
                    let saved = item.fileSize > 0 ? Int((1.0 - Double(outputSize) / Double(item.fileSize)) * 100) : 0
                    Text("\(saved)% smaller")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.accentGreen)
                }
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.status.isDone ? Color.accentGreen : Color.bgCardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusBadge(_ status: ProcessingStatus) -> some View {
        switch status {
        case .done:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                Text("Done")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.accentGreen)
        case .processing(let p):
            Text("\(Int(p * 100))%")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.accentCyan)
        case .queued:
            Text("Queued")
                .font(.system(size: 12))
                .foregroundStyle(.textMuted)
        case .error(let msg):
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private func progressGradient(_ status: ProcessingStatus) -> LinearGradient {
        switch status {
        case .done:
            LinearGradient(colors: [.accentGreen], startPoint: .leading, endPoint: .trailing)
        case .queued:
            LinearGradient(colors: [.accentYellow, .accentYellow.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
        default:
            LinearGradient(colors: [.accentCyan, .accentGreen], startPoint: .leading, endPoint: .trailing)
        }
    }
}
```

- [ ] **Step 5: Create CompletionView.swift**

```swift
// VideoCompressor/Views/CompressTab/CompletionView.swift
import SwiftUI

struct CompletionView: View {
    let items: [VideoItem]
    let onDismiss: () -> Void

    private var totalOriginal: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    private var totalCompressed: Int64 {
        items.reduce(0) { sum, item in
            if case .done(_, let size) = item.status { return sum + size }
            return sum
        }
    }

    private var savedPercent: Int {
        guard totalOriginal > 0 else { return 0 }
        return Int((1.0 - Double(totalCompressed) / Double(totalOriginal)) * 100)
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.accentGreen)

            Text("Compression Complete!")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.accentGreen)

            Text("\(items.count) file\(items.count != 1 ? "s" : "") compressed")
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)

            // Stats
            HStack(spacing: 24) {
                statBlock("Before", EstimationService.formatBytes(totalOriginal), .textPrimary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.accentGreen)
                statBlock("After", EstimationService.formatBytes(totalCompressed), .accentGreen)
                statBlock("Saved", "\(savedPercent)%", .accentGreen)
            }
            .padding(16)
            .background(Color.accentGreen.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Got it") {
                onDismiss()
            }
            .font(.system(size: 14, weight: .bold))
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.accentGreen)
            .foregroundStyle(.black)
            .clipShape(Capsule())
        }
        .padding(40)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.accentGreen, lineWidth: 1)
        )
        .shadow(color: .accentGreen.opacity(0.2), radius: 30)
    }

    private func statBlock(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}
```

- [ ] **Step 6: Create CompressView.swift (main orchestrator)**

```swift
// VideoCompressor/Views/CompressTab/CompressView.swift
import SwiftUI

struct CompressView: View {
    @State private var settings = CompressionSettings()
    @State private var items: [VideoItem] = []
    @State private var isCompressing = false
    @State private var isComplete = false
    @State private var expandedAudio = false

    private let compressionService = CompressionService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if isComplete {
                    CompletionView(items: items) {
                        isComplete = false
                        items.removeAll()
                    }
                } else if isCompressing {
                    ProgressOverlayView(items: items)
                } else {
                    mainContent
                }
            }
            .navigationTitle("Compress")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // File picker + file list
                fileSection

                if !items.isEmpty {
                    // Matrix
                    matrixSection

                    // Codec
                    codecSection

                    // Audio
                    audioSection

                    // Summary
                    if let firstItem = items.first {
                        summarySection(for: firstItem)
                    }

                    // Compress button
                    compressButton
                }
            }
            .padding()
        }
    }

    // MARK: - Sections

    private var fileSection: some View {
        VStack(spacing: 12) {
            // Drop zone / picker
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 28))
                    .foregroundStyle(.accentGreen.opacity(0.6))

                VideoPickerButton { urls in
                    addFiles(urls)
                }

                Text("Select videos to compress")
                    .font(.system(size: 13))
                    .foregroundStyle(.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.bgCardBorder, lineWidth: 1)
            )

            // File cards
            ForEach(items) { item in
                HStack(spacing: 12) {
                    VideoThumbnailView(item.thumbnail)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                        Text("\(item.formattedDuration) \u{00B7} \(item.formattedSize) \u{00B7} \(item.width)x\(item.height)")
                            .font(.system(size: 11))
                            .foregroundStyle(.textMuted)
                    }
                    Spacer()
                    Button {
                        items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundStyle(.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.bgCardBorder, lineWidth: 1)
                )
            }
        }
    }

    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Quality & Resolution")
            MatrixGridView(
                selectedResolution: $settings.resolution,
                selectedQuality: $settings.quality,
                sourceHeight: items.first?.height
            )
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bgCardBorder, lineWidth: 1)
        )
    }

    private var codecSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Codec")
            CodecSelectorView(selectedCodec: $settings.codec)
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bgCardBorder, lineWidth: 1)
        )
    }

    private var audioSection: some View {
        DisclosureGroup(isExpanded: $expandedAudio) {
            AudioControlsView(
                bitrate: $settings.audioBitrate,
                mode: $settings.audioMode,
                audioChannels: items.first?.audioChannels ?? 2
            )
        } label: {
            sectionHeader("Audio")
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bgCardBorder, lineWidth: 1)
        )
    }

    private func summarySection(for item: VideoItem) -> some View {
        SummaryPanelView(
            estimatedSize: EstimationService.estimateSize(
                settings: settings,
                sourceSize: item.fileSize,
                sourceHeight: item.height,
                sourceBitrate: item.bitrate,
                duration: item.duration
            ),
            originalSize: item.fileSize,
            estimatedTime: EstimationService.estimateTime(
                settings: settings,
                duration: item.duration,
                sourceHeight: item.height
            ),
            settings: settings
        )
    }

    private var compressButton: some View {
        Button {
            Task { await startCompression() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                Text("Compress All (\(items.count))")
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentGreen)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .accentGreen.opacity(0.3), radius: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.textSecondary)
            .textCase(.uppercase)
            .tracking(1.5)
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls {
            let item = VideoItem(url: url)
            items.append(item)
            Task {
                try? await ProbeService.probe(item)
            }
        }
    }

    private func startCompression() async {
        isCompressing = true
        for item in items {
            item.status = .queued
        }

        for item in items {
            item.status = .processing(progress: 0)
            do {
                let outputURL = try await compressionService.compress(
                    item: item,
                    settings: settings,
                    onProgress: { progress in
                        Task { @MainActor in
                            item.status = .processing(progress: progress)
                        }
                    }
                )
                let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                item.status = .done(outputURL: outputURL, outputSize: outputSize)
            } catch {
                item.status = .error(message: error.localizedDescription)
            }
        }

        isCompressing = false
        isComplete = true
    }
}
```

- [ ] **Step 7: Update VideoCompressorApp.swift to use CompressView**

Replace the placeholder:

```swift
// In VideoCompressorApp.swift, change:
CompressPlaceholderView()
// To:
CompressView()
```

- [ ] **Step 8: Build and run on simulator**

Run: Cmd+R with iPhone 15 Pro simulator.
Expected: Compress tab shows file picker, matrix grid, codec selector, audio controls, summary panel. Selecting a video shows its metadata. Compress button triggers encoding with progress overlay and completion screen.

- [ ] **Step 9: Build and run on physical iPhone**

Expected: Same experience on real device. VideoToolbox hardware encoding should be fast.

- [ ] **Step 10: Commit**

```bash
git add Views/CompressTab/
git commit -m "feat: complete Compress tab with matrix, controls, progress, and completion"
```

---

## Task 8: Photo Library Save

**Files:**
- Create: `VideoCompressor/Services/PhotoLibraryService.swift`

- [ ] **Step 1: Create PhotoLibraryService.swift**

```swift
// VideoCompressor/Services/PhotoLibraryService.swift
import Photos
import UIKit

enum PhotoLibraryService {
    enum SaveError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: "Photo library access denied"
            case .failed(let msg): "Save failed: \(msg)"
            }
        }
    }

    /// Request photo library permission
    static func requestPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    /// Save compressed video to photo library
    static func save(videoAt url: URL) async throws {
        guard await requestPermission() else {
            throw SaveError.denied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    /// Save and optionally delete original
    static func saveAndReplace(compressedURL: URL, originalAssetID: String?) async throws {
        try await save(videoAt: compressedURL)

        if let originalAssetID {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [originalAssetID], options: nil)
            if assets.count > 0 {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add photo library usage description to Info.plist**

In Xcode: Select the project → Target → Info tab → Add:
- Key: `NSPhotoLibraryAddUsageDescription`
- Value: `VideoCompressor needs access to save compressed videos to your photo library.`

- [ ] **Step 3: Build and verify**

Run: Cmd+B. Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Services/PhotoLibraryService.swift
git commit -m "feat: add PhotoLibraryService for saving to camera roll"
```

---

## Milestone Check

At this point you have a **working iOS/macOS app** that:
- Opens with 3 tabs (Compress active, Stitch/MetaClean placeholder)
- Lets you pick videos from Photos (iOS) or file picker (macOS)
- Shows video metadata (duration, resolution, codec, size)
- 2D matrix grid for resolution x quality selection
- Codec, audio, and summary controls
- Full-screen progress overlay during compression
- Completion screen with before/after stats
- Hardware-accelerated H.264/H.265 encoding via VideoToolbox
- Saves to Photos library

**Next plans (separate documents):**
- Phase 3: Stitch tab with visual timeline
- Phase 4: MetaClean tab
- Phase 5: Polish (settings, Netflix-style player, advanced options)
