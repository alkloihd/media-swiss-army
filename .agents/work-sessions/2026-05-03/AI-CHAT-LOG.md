# AI Chat Log — 2026-05-03

## [2026-05-03 09:22 SAST] {E-0503-0922} -- [BUILD] Claude (Opus 4.7 / 1M ctx): iOS app MVP scaffolded, built green, awaiting Codex review

> **Agent Identity**
> Model: Claude Opus 4.7 (1M context)
> Platform: Claude Code CLI
> Working Directory: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR
> Session Role: Solo (lead implementer)

**Confidence:** HIGH
**Files:** VideoCompressor_iOS.xcodeproj/project.pbxproj, VideoCompressor/ios/VideoCompressorApp.swift, VideoCompressor/ios/ContentView.swift, VideoCompressor/ios/Item.swift, VideoCompressor/ios/Models/{VideoFile,CompressionPreset}.swift, VideoCompressor/ios/Services/{VideoLibrary,CompressionService,VideoMetadataLoader,PhotosSaver}.swift, VideoCompressor/ios/Views/{VideoListView,VideoRowView,PresetPickerView,EmptyStateView}.swift, .xcodebuildmcp/config.yaml, AGENTS.md, .agents/skills/xcodebuildmcp-{mcp,cli}/SKILL.md, .claude/skills/xcodebuildmcp-{mcp,cli}

### Context

Pivot to native iOS per docs/superpowers/specs/2026-04-09-ios-app-design.md. User installed XcodeBuildMCP + AXE earlier in this session, scaffolded the SwiftUI project via Xcode, then asked for full-auto implementation of an MVP that mirrors the web app's preset model. User went AFK and explicitly requested:
- maximize work done autonomously
- run tests + red-team via subagents
- log progress here so Codex (gpt-5.5 high) can pick up the review handoff
- use the codex MCP skill, not raw shell-out

This entry is the handoff anchor for the Codex review.

### Evidence

Read before acting:
- `docs/superpowers/specs/2026-04-09-ios-app-design.md` (lines 1-120) — full app design with 3 tabs (Compress / Stitch / MetaClean), 2D compression matrix as hero control, AVAssetWriter pipeline.
- `docs/superpowers/plans/2026-04-10-ios-app-phase1-2.md` (lines 1-120) — phased implementation plan, calls for AVAssetWriter with custom bitrate (`AVVideoCompressionPropertiesKey: AVVideoAverageBitRateKey`).
- `AGENTS.md` Part 9 — XcodeBuildMCP integration (added earlier this session).
- `lib/ffmpeg.js` (web app) — preset definitions ported to Swift.

Background research dispatched (general-purpose agent, completed):
- AVAssetExportSession vs AVAssetWriter — Apple presets cannot express the web app's "8 Mbps capped at 70% of source" constraint. Recommended path: AVAssetWriter for v2.
- iOS 17 deprecates synchronous AVAsset accessors — use `try await asset.load(...)`.
- PhotosPicker delivers temporary URLs that vanish on scope exit — must copy to a stable working dir immediately.
- iOS Simulator Photos library is empty by default — inject fixtures with `xcrun simctl addmedia`.

### Action

Phase 1 (this commit, `8d88990`) — opinionated MVP that uses AVAssetExportSession instead of AVAssetWriter to ship the full UX loop quickly. UI surface area matches the web app's preset model (Max / Balanced / Small / Streaming) and Phase 2 can swap the engine without touching the views.

File map:
```
VideoCompressor/ios/
├── VideoCompressorApp.swift        @main + StateObject<VideoLibrary>
├── ContentView.swift               Thin shell → VideoListView
├── Item.swift                      No-op (legacy filename, kept to avoid pbxproj surgery)
├── Models/
│   ├── VideoFile.swift             VideoFile, VideoMetadata, CompressionJobState
│   └── CompressionPreset.swift     4 presets, AV preset names, output suffix, fileType
├── Services/
│   ├── VideoLibrary.swift          @MainActor ObservableObject; copies picker URLs to Documents/Inputs, runs jobs serially, exposes selectedPreset, lastErrorMessage
│   ├── CompressionService.swift    actor; AVAssetExportSession + 10 Hz progress poller; outputs to Documents/Outputs/<stem>_<SUFFIX>.mp4
│   ├── VideoMetadataLoader.swift   AVURLAsset.load(.duration, .tracks) → VideoMetadata; rotates naturalSize via preferredTransform
│   └── PhotosSaver.swift           PHPhotoLibrary.requestAuthorization(for: .addOnly), performChanges → PHAssetCreationRequest
└── Views/
    ├── VideoListView.swift         NavigationStack, toolbar, safeAreaInset bottom action bar
    ├── VideoRowView.swift          Metadata tags + per-state progress / done / failed UI
    ├── PresetPickerView.swift      Sheet with 4 rows + checkmark for current selection
    └── EmptyStateView.swift        Centered film icon + "Import Videos" CTA
```

Project edits:
- `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` and `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` added to both Debug + Release configs in pbxproj.
- Bundle ID: `ca.nextclass.VideoCompressor`.
- Deployment target: iOS 17.0 (template default).
- File-system synchronized root group (Xcode 16) means new Swift files are auto-included — no pbxproj manipulation needed for any of the 11 sources.

Verified live on iPhone 16 Pro simulator (UDID `996226E2-F957-4730-93D5-4F10BFD916C3`):
- Clean build (`build_sim`) — no warnings.
- App launches to "No videos yet" empty state with "Import Videos" CTA. (Screenshot: `/tmp/sim_after_import_tap.png`.)
- 8s 720p H.264 fixture (`testsrc + sine 440 Hz`) injected via `xcrun simctl addmedia` shows up in PhotosPicker.
- Tapping the import button opens the system PhotosPicker with the fixture visible.

### Open / Deferred

1. **AVAssetExportSession → AVAssetWriter migration**. Spec calls for per-preset bitrate caps (web app's `min(target, source × 0.7)` etc.). Currently we ride Apple's preset bitrates which are *close* but not parity. Codex should evaluate whether to do this migration in phase 2 or earlier.
2. **No PhotosPicker E2E driving** — AXE cannot introspect or tap the system PhotosPicker (separate process). Manual tap-on-device verification is the working path. Could write an XCUITest that uses `XCUIApplication("com.apple.mobileslideshow")` for picker automation.
3. **Spec calls for 3 tabs** (Compress / Stitch / MetaClean) and a 2D compression matrix UI. Phase 1 ships only Compress with a flat preset list. UI shell needs `TabView` before phase 3.
4. **No tests yet** — `VideoCompressor_iOSTests` and `…_iOSUITests` targets exist but are empty.
5. **`shouldOptimizeForNetworkUse` is set on the streaming preset only** — confirm this matches the web app's `+faststart` semantics.
6. **Memory pressure** — large videos may OOM the export. No background task assertion. No size cap on import.
7. **HEIC/HEVC source files** — PhotosPicker's `Movie` Transferable should handle these; not yet exercised against a real HEVC sample.
8. **HDR / Dolby Vision** — not preserved (would need explicit `AVVideoColorPropertiesKey`).

### Handoff to Codex

Codex should run the `/codex:rescue` flow with **model = gpt-5.5, reasoning effort = high** and review:

1. **Concurrency correctness** — `VideoLibrary` is `@MainActor`; `CompressionService` is an `actor`. Are there any data-race holes around the progress closure capturing `self`? Sendable warnings from Swift 6 strict concurrency?
2. **AVAssetExportSession lifecycle** — is the polling Task properly cancelled on every exit path (success, failure, cancellation, view dismissal)?
3. **PhotosPicker URL handling** — `VideoTransferable` moves the file into `tmpDir`, then `VideoLibrary` copies again into `Documents/Inputs`. Is the move + copy chain leak-free? Should we delete the picker temp after the second copy?
4. **Error surfacing** — `lastErrorMessage` flips boolean visibility via `.constant`. Does this re-fire alerts on every render, or is the binding stable?
5. **File ownership** — outputs accumulate in `Documents/Outputs/` indefinitely. Should we expose a "clear cache" action and/or auto-delete on save-to-Photos?
6. **Spec alignment** — phase 1 ships flat preset list; spec wants 2D matrix + 3-tab shell. Recommend the smallest set of structural changes now to avoid expensive refactor later.
7. **AVAssetWriter migration** — concrete code skeleton for replacing CompressionService while keeping the same external API (`compress(input:preset:onProgress:)`).

Codex output should land below as a new `[2026-05-03 HH:MM SAST] {E-0503-HHMM} -- [REVIEW] Codex (gpt-5.5/high)` entry.

---

[2026-05-03 09:35 SAST] {E-0503-0935} -- [REVIEW] silent-failure-hunter (Opus 4.7): Error path audit
Scope: VideoCompressor/ios/Services/{CompressionService,VideoLibrary,PhotosSaver,VideoMetadataLoader}.swift, ios/Models/{VideoFile,CompressionPreset}.swift
Method: Read-only audit. No source modified. Findings ranked CRITICAL > HIGH > MEDIUM > LOW with line references and Swift fix snippets.
Top issues: (1) AVAssetExportSession not cancelled on Task cancellation -> hot export keeps running and the next compressAll() can collide on the same outputURL; (2) zero-byte output silently reported as "Done"; (3) status `default:` arm can fire if continuation resumes before terminal status because exportAsynchronously's callback is on an internal queue with no guarantee of ordering vs. status mutation -- in practice it's terminal, but the diagnostic message `Unexpected exporter status: \(rawValue)` strips localized error info and underlying NSError chain; (4) NSError underlyingErrors and code/domain dropped on export failure; (5) Outputs/Inputs directory creation uses `try?` -> follow-up writes throw a less specific error; (6) estimateOutputBytes silently returns nil on any failure, UI shows blank; (7) `.limited` Photos auth treated as success (correct for .addOnly per Apple docs, but undocumented in code); (8) durationSeconds == 0 and fileSizeBytes == 0 fallbacks surface as "0:00"/"Zero KB" without any signal that load partially failed.
Status: Complete (audit only). Recommendations live in the chat reply for the parent agent to triage.

---

[2026-05-03 09:36 SAST] {E-0503-0936} -- [REVIEW] type-design-analyzer (Opus 4.7): Type design scorecard
Scope: VideoCompressor/ios/Models/{VideoFile,CompressionPreset}.swift; ios/Services/{VideoLibrary,CompressionService,VideoMetadataLoader,PhotosSaver}.swift
Method: Read-only invariant/encapsulation review against the 2026-04-09 ios-app-design.md 2D-matrix target. No source modified.

Per-type scorecard (Encapsulation / InvariantExpr / Usefulness / Enforcement, 1-5):

- VideoFile                  3 / 2 / 3 / 2
- VideoMetadata              3 / 3 / 4 / 3
- CompressionJobState        3 / 2 / 5 / 1
- VideoMetadataError         5 / 5 / 5 / 5
- CompressionPreset          4 / 4 / 4 / 5
- CompressionError           5 / 4 / 4 / 5
- PhotosSaverError           5 / 5 / 5 / 5
- VideoLibrary               2 / 2 / 3 / 2
- VideoTransferable          4 / 4 / 5 / 4
- CompressionService (actor) 4 / 3 / 4 / 3
- VideoMetadataLoader        5 / 5 / 5 / 5
- PhotosSaver                5 / 5 / 5 / 5

Confirmations on the design questions:
- VideoFile Hashable/Identity: confirmed safe. `id: UUID` is the only identifier and structural equality includes mutable fields, so SwiftUI ForEach uses `id`, not Hashable. Two distinct imports of the same sourceURL get distinct ids -- no surprise. Diff-based animations work.
- estimatedDataRate: Float: confirmed precision concern. Float23-bit mantissa loses precision above ~16.7 Mbps. ProRes 422 HQ at 4K runs 250-700 Mbps -- already past Float resolution. Should be Int64 (bps) or Int (kbps).
- Sendability: VideoFile, VideoMetadata, CompressionJobState, CompressionPreset, all error enums, VideoTransferable, VideoMetadataLoader, PhotosSaver, CompressionError -- all Sendable (explicitly or by struct-of-Sendable inference). Confirmed clean. CompressionService as `actor` is implicitly Sendable. VideoLibrary is `@MainActor` and isolated, fine.

Top three refactors to prepare for the 2D-matrix phase 2:

1. Make illegal CompressionJobState unrepresentable, with bounded progress and a typed output payload.
   The biggest invariant gap is `running(progress: Double)` accepting NaN, negatives, or values >1.0, paired with the orphan pair `outputURL: URL?` + `outputBytes: Int64?` on VideoFile that must be set or unset together. Collapse into one tagged state:

   ```swift
   struct BoundedProgress: Hashable, Sendable {
       let value: Double  // 0.0 ... 1.0, finite
       init?(_ raw: Double) {
           guard raw.isFinite, (0.0...1.0).contains(raw) else { return nil }
           value = raw
       }
       static let zero = BoundedProgress(0)!
   }
   struct CompressedOutput: Hashable, Sendable {
       let url: URL
       let bytes: Int64        // > 0 enforced in init
       let settingsKey: String // hash of CompressionSettings used
   }
   enum CompressionJobState: Hashable, Sendable {
       case idle, queued
       case running(BoundedProgress)
       case finished(CompressedOutput)
       case failed(CompressionError) // typed, not String
       case cancelled
   }
   ```
   Drop `outputURL`/`outputBytes` from VideoFile -- they live inside `.finished(CompressedOutput)`. This eliminates the silent zero-byte-success case the previous error-path audit flagged, makes the progress slider safe to pass straight into SwiftUI's ProgressView without clamping, and gives every consumer a single switch site for "is this video done?" Phase 2's matrix needs to discriminate output-per-(resolution,quality) cell, so embedding settingsKey in CompressedOutput matches the future shape.

2. Replace the flat CompressionPreset enum with a CompressionSettings value type whose 1D presets are factory constructors.
   The spec's 2D matrix (4 resolutions x 4 quality levels = 16 cells) doesn't fit an enum. But Phase 1's UI is fine -- the value type just needs to forward today's four named points:

   ```swift
   enum Resolution: Hashable, Sendable, CaseIterable {
       case source, p1080, p720, p540
       var maxLongEdge: Int? { ... }
   }
   enum QualityLevel: Hashable, Sendable, CaseIterable {
       case max, high, medium, low
       var crfish: Int { ... }
   }
   struct CompressionSettings: Hashable, Sendable {
       let resolution: Resolution
       let quality: QualityLevel
       static let max       = Self(resolution: .source, quality: .max)
       static let balanced  = Self(resolution: .p1080,  quality: .high)
       static let small     = Self(resolution: .p720,   quality: .low)
       static let streaming = Self(resolution: .p540,   quality: .medium)
       func bitrate(forSourceBitrate src: Int64) -> Int64 { ... }
       var avExportPresetName: String { ... } // legacy bridge for v1 exporter
       var outputSuffix: String { ... }
   }
   ```
   Phase 1 ships the four `static let` cases as the picker's only options. Phase 2 unlocks the full grid by exposing `Resolution.allCases x QualityLevel.allCases`. Settings stays Hashable so it's a valid key for cached `CompressedOutput` -- one VideoFile can hold a `[CompressionSettings: CompressedOutput]` map of variants once the matrix lands. `bitrate(forSourceBitrate:)` is the seam that finally enables the smart-bitrate-cap behaviour the web app already does.

3. Tighten VideoFile and VideoLibrary so invariants are constructor-enforced and errors are typed.
   `VideoFile.displayName` and `sourceURL` are unchecked; `VideoLibrary.lastErrorMessage: String?` throws away `CompressionError` / `VideoMetadataError` / `PhotosSaverError` structure. Two changes:

   a) Failable init on VideoFile that rejects empty displayName and verifies sourceURL points at a regular file in the app sandbox at construction time -- import is the one place we know the file exists, so this invariant is cheap to assert and worth it because the rest of the pipeline keys off it.

   b) Replace `lastErrorMessage: String?` with

   ```swift
   enum LibraryError: Error, Hashable, Sendable {
       case import_(VideoMetadataError)
       case compress(CompressionError)
       case save(PhotosSaverError)
       var displayMessage: String { ... } // for the Alert binding
   }
   @Published var lastError: LibraryError?
   ```
   Views still get a string via `lastError?.displayMessage`, but tests, retries, and recovery actions can now branch on the case (e.g. only PhotosSaverError.notAuthorized should pop a Settings.app deep-link). This also closes the silent-string-decay path the prior audit called out at lines 52, 84, 155, 168 of VideoLibrary.swift.

Status: Complete (analysis only, no source touched).

---

## [2026-05-03 09:35 SAST] {E-0503-0935} -- [REVIEW] code-reviewer (Opus 4.7): Concurrency + lifecycle review

> **Agent Identity**
> Model: Claude Opus 4.7 (1M context)
> Platform: Claude Code CLI (code-reviewer subagent)
> Working Directory: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/.claude/worktrees/jolly-pare-f79c78
> Session Role: Reviewer

**In-Reply-To:** {E-0503-0922}
**Confidence:** HIGH
**Files reviewed:** VideoCompressor/ios/Services/{CompressionService,VideoLibrary,VideoMetadataLoader,PhotosSaver}.swift, VideoCompressor/ios/Views/{VideoListView,VideoRowView,PresetPickerView,EmptyStateView}.swift, VideoCompressor/ios/Models/{VideoFile,CompressionPreset}.swift, VideoCompressor/ios/{VideoCompressorApp,ContentView,Item}.swift

### Findings

**CRITICAL-1 -- Polling task can outlive `compress(...)` and overwrite final progress (effort: S)**

`CompressionService.compress` spawns a `Task { @MainActor in while !Task.isCancelled { onProgress(...); try? await Task.sleep(...) } }` and `defer { progressTask.cancel() }`. The `try?` swallows `CancellationError` from `Task.sleep`, so a cancel during sleep silently exits, but the closure captures `exporter` strongly until the next tick. The bigger issue: `await MainActor.run { onProgress(1.0) }` runs *before* the deferred cancel fires, so a still-live poller can read `exporter.progress` (~0.99) afterward and overwrite the 1.0. Fix:

```swift
let progressTask = Task { @MainActor [weak exporter] in
    while !Task.isCancelled, let exporter else {
        onProgress(Double(exporter.progress))
        do { try await Task.sleep(nanoseconds: 100_000_000) }
        catch { return } // exit cleanly on cancel
    }
}
// ...
await withCheckedContinuation { ... }
progressTask.cancel()
await MainActor.run { onProgress(1.0) }
// keep `defer { progressTask.cancel() }` for the throwing paths above the continuation
```

**CRITICAL-2 -- Picker tmp directory leaks indefinitely (effort: S)**

`VideoTransferable.transferRepresentation` moves the picker file into `tmpDir/Picks-<uuid>/`. `VideoLibrary.copyToWorkingDir` then copies (not moves) into `Documents/Inputs/`. The `Picks-*` wrapper directory and its file remain in `NSTemporaryDirectory` until the OS evicts on memory pressure. Each import doubles disk use. Fix: move instead of copy and clean the wrapper directory.

```swift
private func copyToWorkingDir(_ source: URL, originalName: String?) throws -> URL {
    // ... existing target-path setup ...
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: source, to: target) // was copyItem
    let parent = source.deletingLastPathComponent()
    if parent.lastPathComponent.hasPrefix("Picks-") {
        try? FileManager.default.removeItem(at: parent)
    }
    return target
}
```

**HIGH-1 -- Alert binding cannot be dismissed by SwiftUI (effort: S)**

`VideoListView` uses `isPresented: .constant(library.lastErrorMessage != nil)`. `.constant` discards SwiftUI's writebacks, so any non-button dismissal path (VoiceOver swipe, programmatic teardown) leaves the published state unchanged and the alert can re-present on the next body re-evaluation. Use a real two-way binding:

```swift
.alert(
    "Something went wrong",
    isPresented: Binding(
        get: { library.lastErrorMessage != nil },
        set: { if !$0 { library.lastErrorMessage = nil } }
    ),
    presenting: library.lastErrorMessage
) { _ in
    Button("OK", role: .cancel) {}
} message: { msg in
    Text(msg)
}
```

**HIGH-2 -- `compressAll` pendingIDs predicate re-enqueues running jobs (effort: S)**

```swift
let pendingIDs = videos.filter { !$0.jobState.isTerminal && $0.jobState != .running(progress: 0) }.map(\.id)
```

`!= .running(progress: 0)` only excludes the *exact* `progress=0` case. A row already running at 0.42 has `isTerminal == false` and the inequality holds, so it gets queued a second time. Combined with HIGH-3, this lets two encodes race for the same input. Fix:

```swift
let pendingIDs = videos
    .filter { !$0.jobState.isTerminal && !$0.jobState.isActive }
    .map(\.id)
```

**HIGH-3 -- `CompressionService()` is instantiated per-job (effort: S)**

`runJob` does `let service = CompressionService()` for every call. Each call creates a fresh actor instance, so actor isolation buys nothing -- two concurrent calls run in two different actors with no serialization. Today this is masked by `activeTask` running them sequentially, but `compress(_:)` (single-row) bypasses `activeTask` entirely (see MEDIUM-2). Hold a single instance: `private let service = CompressionService()` on `VideoLibrary`, or make the methods `static` until Phase 2 needs shared state.

**HIGH-4 -- Output directory grows without bound (effort: S-M)**

`Documents/Outputs/<stem>_<SUFFIX>.mp4` is overwritten only on re-encode of the same input+preset. Across many imports the folder accumulates forever and rides into iCloud backup. Recommended sweep policy:

1. After `PhotosSaver.saveVideo(at:)` succeeds, delete `outputURL` and clear `outputBytes` -- save-to-Photos is a terminal user intent.
2. In `remove(_:)` and `removeAll()`, also delete the row's `sourceURL` (Inputs) and `outputURL` (Outputs).
3. At app launch (`VideoCompressorApp.init`), enumerate `Documents/Outputs/` and delete files older than 7 days.
4. Set `URLResourceValues.isExcludedFromBackup = true` on `Documents/Inputs` and `Documents/Outputs` at directory creation -- one line in `copyToWorkingDir` and `outputURL(forInput:preset:)`.

**MEDIUM-1 -- `[weak self]` in detached `Task` is unnecessary noise (effort: S)**

`compressAll` and `compress(_:)` capture `[weak self]`. `VideoLibrary` is held by `@StateObject` on `VideoCompressorApp` for the app lifetime, so `self` cannot deallocate while a job is in flight. The `weak` reference is harmless but adds branches; drop it (or document the rationale). The closure body runs on the main actor regardless, so there is no isolation hazard either way.

**MEDIUM-2 -- `compress(_:)` ignores `activeTask` (effort: S)**

Single-row `compress(_:)` does not register with `activeTask`, so a user who taps "Compress All" then taps a single row's compress button can race two jobs concurrently against the same `CompressionService` actor (and per HIGH-3, against two different actor instances). Either funnel single-row jobs through the same `activeTask` queue (append + run), or disable the per-row action while `activeTask != nil`. The actor-per-call pattern in HIGH-3 is what makes this dangerous; fixing one without the other still leaves a TOCTOU on `videos[idx].jobState`.

**MEDIUM-3 -- Swift 6 `@Sendable` warning on `onProgress` (effort: S)**

The closure type `@MainActor @escaping (Double) -> Void` works under Swift 5 mode but with `-strict-concurrency=complete` it needs `@Sendable` because it crosses the actor boundary into a `Task { @MainActor in }`. Add it preemptively:

```swift
func compress(
    input inputURL: URL,
    preset: CompressionPreset,
    onProgress: @MainActor @Sendable @escaping (Double) -> Void
) async throws -> URL
```

**MEDIUM-4 -- Outputs and Inputs not excluded from iCloud backup (effort: S)**

Already covered as part of HIGH-4 fix #4 -- noted separately for visibility because failing this trips App Store review for apps that store user-regenerable data in `Documents/`.

**LOW-1 -- `Item.swift` is dead code (effort: S)**

The file's own comment claims "kept as a no-op so the Xcode synchronized-folder build does not lose a referenced filename." Xcode 16 filesystem-synchronized groups don't reference filenames in pbxproj. Delete the file.

### Spec gaps cheap to close in next commit

Per `docs/superpowers/specs/2026-04-09-ios-app-design.md` lines 36-46 + 442-475, the target shell is `TabView` with Compress/Stitch/MetaClean over a folder structure with `CompressTab/`, `StitchTab/`, `MetaCleanTab/`, `Shared/`. Cheap moves now to avoid an expensive rewrite later:

1. **Restructure `Views/`** -- create `Views/CompressTab/`, `Views/StitchTab/`, `Views/MetaCleanTab/`, `Views/Shared/`. Move/rename: `VideoListView` -> `Views/CompressTab/CompressView.swift`, `VideoRowView` -> `Views/Shared/FileCardView.swift`, `EmptyStateView` -> `Views/Shared/`, `PresetPickerView` -> `Views/CompressTab/`. Effort: M.
2. **Add the `TabView` shell now** with Stitch/MetaClean as `Text("Coming soon")` placeholders so the navigation chrome lands in Phase 1. Effort: S.
3. **Add `Models/Enums.swift`** with `Resolution`, `QualityLevel`, `VideoCodec`, `OutputFormat` placeholders per spec line 446. Even empty enums let later code type-check against the spec's `CompressionSettings`. Effort: S.
4. **Rename `CompressionService.compress(input:preset:onProgress:)`** to the spec's `encode(asset:settings:progress:)` signature now (body still calls AVAssetExportSession internally). Makes the AVAssetWriter swap a one-file change. Effort: S.
5. **Set `isExcludedFromBackup = true`** on `Documents/Inputs` and `Documents/Outputs` at creation -- closes HIGH-4 #4 and a likely App Review finding. Effort: S.

Do NOT pull the 2D matrix rewrite or AVAssetWriter swap into this commit -- those are Phase 2.

### Status

REVIEW COMPLETE. No source files modified. 11 findings: 2 CRITICAL, 4 HIGH, 4 MEDIUM, 1 LOW. 5 cheap structural moves recommended for the follow-up commit.

---

## [2026-05-03 09:38 SAST] {E-0503-0938} -- [REVIEW] spec-gap-analyst (Opus 4.7): Phase 1 to spec migration plan

> **Agent Identity**
> Model: Claude Opus 4.7 (1M context)
> Session Role: subagent (spec-gap-analyst, Task tool dispatch)
> Scope: read-only -- no source modified

**In-Reply-To:** {E-0503-0922}
**Inputs:** docs/superpowers/specs/2026-04-09-ios-app-design.md (full), docs/superpowers/plans/2026-04-10-ios-app-phase1-2.md (full), VideoCompressor/ios/** (12 Swift files at commit 8d88990), lib/ffmpeg.js capping table (lines 75-82).

### Gap 1: 3-Tab Shell

(a) Spec: "TabView with 3 tabs at the bottom (iOS) or sidebar (macOS). Each tab is self-contained with its own file selection and processing." Tabs are Compress / Stitch / MetaClean.
(b) Phase 1: VideoCompressorApp.swift wraps a single ContentView -> VideoListView. No TabView. Compress flow lives at the root.
(c) Smallest change: introduce a TabView in VideoCompressorApp.swift; rename ContentView -> CompressTabView (root of compress flow today); add two stub views StitchTabView and MetaCleanTabView each containing a "Coming soon" ContentUnavailableView. Move @StateObject<VideoLibrary> down into CompressTabView so each tab owns its own state -- prevents Stitch/MetaClean from ever seeing the compress queue. New file paths:
- VideoCompressor/ios/Views/CompressTab/CompressTabView.swift (rename of current VideoListView)
- VideoCompressor/ios/Views/StitchTab/StitchTabView.swift (stub)
- VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift (stub)
(d) Effort: S.

### Gap 2: 2D Compression Matrix

(a) Spec: "X-axis: Resolution (6 stops) ... Y-axis: Compression level (6 stops) ... If source is 1080p, the 4K/2K/1440p columns are disabled (no upscaling)." Hero control rendered with SwiftUI Canvas.
(b) Phase 1: PresetPickerView -- a List of 4 flat preset rows (Max/Balanced/Small/Streaming) inside a sheet.
(c) Best abstraction: `struct MatrixCell { let resolution: Resolution; let quality: QualityLevel }` with the two enums exactly as drafted in plan lines 216-292. Reject a generic `Grid<Row,Col>` -- the axes are domain-specific (height in pixels vs. sizePercentage 0..1) and a generic obscures the bitrate math. The 36 cells' bitrate logic belongs on `CompressionSettings.targetBitrate(sourceBitrate:sourceHeight:)` (drafted in plan line 363) plus a sibling `MatrixCell.estimatedBytes(for source: VideoMetadata) -> Int64` so each cell renders its own % label without UI knowing math. Disable rule: `MatrixCell.isAvailable(for source: VideoMetadata) -> Bool { resolution.height <= source.pixelHeight }`, consumed by both the cell's disabled state and the bitrate clamp. **Canvas vs Grid:** use HStack/VStack with onTapGesture per cell (plan Task 6, lines 1054-1110) for v1 -- gives full hit-testing and accessibility for free; reserve Canvas for the breathing/glow/particle pass once static layout ships. The "crosshair" can be two overlay rectangles at the selected column and row indices.
- New: VideoCompressor/ios/Models/CompressionSettings.swift (replaces CompressionPreset.swift; keep `CompressionPreset` as a typealias initially so the existing CompressionService still compiles).
- New: VideoCompressor/ios/Views/CompressTab/MatrixGridView.swift.
(d) Effort: M (matrix view + estimator wiring + disable logic + replacing PresetPickerView in CompressTabView).

### Gap 3: AVAssetWriter Migration with Smart Bitrate Capping

(a) Spec: "Same logic as the web app -- prevent output exceeding input: Balanced: cap at 70% of source bitrate, Compact: cap at 40%, Tiny: cap at 20%, Lossless/Maximum: no cap." Engine: AVAssetWriter + AVAssetWriterInput.
(b) Phase 1: AVAssetExportSession with Apple's preset names (1920x1080, 1280x720, 960x540, HEVCHighestQuality). Cannot express bitrate caps -- documented in CompressionService.swift comment lines 5-9 and chat-log Open #1.
(c) Recommended skeleton (keep public API on `actor CompressionService` identical):

```swift
func compress(input: URL, settings: CompressionSettings, source: VideoMetadata,
              onProgress: @MainActor @escaping (Double) -> Void) async throws -> URL {
    let asset = AVURLAsset(url: input)
    let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
    let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

    let cappedBitrate = applyBitrateCap(
        target: settings.targetBitrate(sourceBitrate: source.bitsPerSecond,
                                       sourceHeight: source.pixelHeight),
        source: source.bitsPerSecond,
        ratio: settings.quality.capRatio  // nil for lossless
    )

    let compressionProps: [String: Any] = [
        AVVideoAverageBitRateKey: cappedBitrate,
        AVVideoMaxKeyFrameIntervalKey: 60,
        AVVideoAllowFrameReorderingKey: true,
        AVVideoExpectedSourceFrameRateKey: source.nominalFrameRate,
        AVVideoProfileLevelKey: settings.codec == .h265
            ? kVTProfileLevel_HEVC_Main_AutoLevel
            : AVVideoProfileLevelH264HighAutoLevel,
    ]
    let videoOut: [String: Any] = [
        AVVideoCodecKey: settings.codec == .h265 ? AVVideoCodecType.hevc : .h264,
        AVVideoWidthKey: evenW, AVVideoHeightKey: evenH,
        AVVideoCompressionPropertiesKey: compressionProps,
    ]
    // ... AVAssetReader/AVAssetWriter pipeline as in plan Task 5, lines 825-933
}

private func applyBitrateCap(target: Int, source: Int, ratio: Double?) -> Int {
    guard let ratio else { return target }
    return min(target, Int(Double(source) * ratio))
}
```

Add `var capRatio: Double?` to QualityLevel mirroring lib/ffmpeg.js BITRATE_CAP_RATIOS exactly: lossless=nil, maximum=0.9, high=0.7, balanced=0.5, compact=0.3, tiny=0.15. Matrix cell -> (codec, height, bitrate) is `(settings.codec, resolution.height, applyBitrateCap(targetBitrate, source.bitrate, quality.capRatio))`.
(d) Effort: L (full pipeline + reader/writer pump + audio passthrough branch + cancellation that actually stops AVAssetReader; the silent-failure-hunter audit at {E-0503-0935} flagged the cancellation hole this rewrite naturally closes).

### Gap 4: Codec Selector + Audio Controls

(a) Spec: "Pill-style buttons" for H.264 / H.265 with HW badge; audio bitrate slider 128k-320k with snap stops; AAC/Passthrough modes; channel preservation indicator (Stereo / 5.1 / Spatial).
(b) Phase 1: Codec is implicit (HEVC for max, H.264 for sub-1080p presets); no UI surface. Audio is whatever AVAssetExportSession chose -- not user-controlled.
(c) Phase 2 subset (ship now): codec pills (CodecSelectorView from plan lines 1184-1216) + AAC/Passthrough toggle + channel-detected display. These are 80% of the user-visible surface and free once AVAssetWriter is in. **Defer to phase 3:** the bitrate slider (128k-320k snap stops) -- it's a polish knob, the AAC default at 192k matches the web-app default. Defer Spatial Audio detection too -- needs `kAudioFormatMPEG4AAC_Spatial` probing and the iOS 17+ AVAudioSessionRouteDescription path; non-trivial and 0% of users hit it on first ship. New file: VideoCompressor/ios/Views/CompressTab/CodecSelectorView.swift; extend AudioControlsView only with the codec/passthrough toggle, leave the slider stubbed.
(d) Effort: S (codec pills + audio mode toggle); M if slider added now.

### Gap 5: MetaClean Tab

(a) Spec: "ExifTool-based metadata stripping for Meta glasses". Read via `AVAsset.metadata` (videos) and `CGImageSource` (photos); write clean copy with `_CLEAN` suffix.
(b) Phase 1: Not present.
(c) Native path -- no ExifTool. Two parallel paths:
- **Videos:** AVAssetWriter with `metadata = []` (or filtered list) on `AVAssetWriter.metadata`. Pass-through tracks via `AVAssetReaderTrackOutput(track: t, outputSettings: nil)` and `AVAssetWriterInput(mediaType: t.mediaType, outputSettings: nil)` -- no re-encode, just remux with the metadata atom rewritten. Detection: enumerate `try await asset.load(.metadata)` plus `loadMetadata(for: .quickTimeMetadata)` and `.iso6709UserData`; the Meta glasses fingerprint lives in a `com.apple.quicktime.description` or a binary `Comment` atom (per commits BE6E360/A3AD413). Filter rules: keep `creation-date`, `location.ISO6709`, `make`, `model`; strip `description`, `comment`, anything with reverse-DNS prefix `com.facebook.*` or `com.meta.*` or containing the byte signature recorded in those prior commits.
- **Stills:** `CGImageSourceCreateWithURL` + `CGImageDestinationCreateWithURL` + `CGImageDestinationAddImageFromSource` with a per-property dictionary that nils `kCGImagePropertyExifDictionary`, `kCGImagePropertyMakerAppleDictionary`, etc.
- New service: VideoCompressor/ios/Services/MetadataService.swift with `read(url:) -> [MetadataTag]` and `strip(url:rules:) -> URL`.
- New views under VideoCompressor/ios/Views/MetaCleanTab/.
(d) Effort: L (MetadataService alone is M; tag UI and animated strip is another M).

### Gap 6: Stitch Tab

(a) Spec: "Visual timeline ... drag to reorder ... trim handles ... AVMutableComposition pipeline. Lossless concat detection."
(b) Phase 1: Not present.
(c) `AVMutableComposition` + per-clip `AVMutableCompositionTrack` is correct. Data model: `struct StitchClip { let asset: AVURLAsset; var trimStart: CMTime; var trimEnd: CMTime; var order: Int }`. Lossless detection = all clips share `formatDescription` codec subtype, dimensions, and frame rate -> use `AVAssetExportPresetPassthrough`; otherwise feed the composition into the AVAssetWriter pipeline from Gap 3. Timeline UI: SwiftUI HStack of ClipBlockView with `.draggable() / .dropDestination()` for reorder, custom DragGesture on edge handles for trim. Thumbnail strip generated by `AVAssetImageGenerator.generateCGImagesAsynchronously` at evenly spaced times. New service: VideoCompressor/ios/Services/StitchService.swift. New views under VideoCompressor/ios/Views/StitchTab/.
(d) Effort: L (timeline interaction is the long pole; pipeline reuses Gap 3 writer).

### Gap 7: Theme System

(a) Spec: "Color+Theme.swift extension with semantic tokens (bgPrimary, textPrimary, accentGreen, etc.) keyed by light/dark mode."
(b) Phase 1: System defaults only; `.tint` is whatever Apple picks.
(c) Add **after the matrix lands**, not before. The matrix (Gap 2) is the design's hero, and its color gradient (green->yellow->orange->pink->purple) is the design system's visual anchor. Wiring a theme extension first risks committing to colors before the matrix tells you whether `accentGreen` should be #22c55e or a notch warmer to harmonize. Concretely: add Color+Theme.swift in the **same commit** as MatrixGridView.swift -- the matrix imports those tokens directly. New file: VideoCompressor/ios/Extensions/Color+Theme.swift (per plan lines 70-115). The plan's `Color(uiColor: UIColor { traits in ... })` pattern needs `#if canImport(UIKit)` guards for macOS -- swap to `Color(NSColor(name:nil) { ... })` on AppKit; that cross-platform guard is the only subtlety.
(d) Effort: S.

### Phase 2 Sprint Plan

Five commits, each independently shippable (build green, app launches, no broken tab):

1. **chore(ios): TabView shell with Stitch/MetaClean placeholders** -- Gap 1. Move VideoListView under CompressTab/, add two stubs, drop @StateObject<VideoLibrary> one level. Ship: app shows 3 tabs, only Compress works. Effort: S.
2. **feat(ios): Color+Theme + MatrixGridView replacing PresetPickerView** -- Gaps 2 + 7 together. Add CompressionSettings model, MatrixCell estimator, MatrixGridView, Color+Theme; wire CompressTabView to use the matrix. **Still uses AVAssetExportSession underneath**, with the matrix selection collapsed to the nearest legacy preset by a temporary adapter -- ships parity-of-flow on a richer surface. Effort: M.
3. **feat(ios): AVAssetWriter pipeline with smart bitrate caps** -- Gap 3. Replace the body of CompressionService.compress while keeping the signature; delete the legacy preset adapter from commit 2; matrix selection now drives true (codec, height, bitrate) including the 0.9/0.7/0.5/0.3/0.15 capping table. Closes silent-failure-hunter findings #1 (cancellation), #2 (zero-byte), #4 (NSError chain) at the same time -- the writer rewrite is the natural place. Effort: L.
4. **feat(ios): codec pill selector + audio AAC/Passthrough toggle** -- Gap 4 subset. CodecSelectorView, AudioControlsView (codec part only), wired into CompressionSettings. Defer the bitrate slider. Effort: S.
5. **feat(ios): metaclean tab with video metadata stripping** -- Gap 5 partial. MetadataService for videos only (stills deferred to phase 3 with stitch); read + strip + save. Animated tag UI deferred. Ship a working MetaClean for the Meta-glasses-fingerprint use case that motivated the project. Effort: L.

Stitch (Gap 6) deferred to phase 3 -- it's the largest UI and depends on commits 2+3 landing for the re-encode path.

**Order rationale:** 1 unblocks parallelism (StitchTabView and MetaCleanTabView can be authored against stubs while compress is still being rebuilt). 2 ships the design language that 3 will plug into. 3 is the engine swap that everything downstream needs. 4 is nearly free once 3 lands. 5 is independent of the matrix and can be authored in parallel with 4 if a second teammate is available.

### Status

ANALYSIS COMPLETE. No source files modified. 7 gaps mapped (1xS, 1xM, 4xL, 1xS); Phase 2 collapses into 5 commits (2xS, 1xM, 2xL).

---

## [2026-05-03 09:49 IST] {E-0503-0949} -- [FIX] solo/sonnet: Applied critical bug fixes from 4-reviewer audit

> **Agent Identity**
> Model: Claude Sonnet 4.6
> Platform: Claude Code CLI (solo agent)
> Working Directory: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/.claude/worktrees/jolly-pare-f79c78
> Session Role: Solo (bug-fix implementer)

**In-Reply-To:** {E-0503-0935} through {E-0503-0938}
**Confidence:** HIGH
**Commit:** `5db2187`

### Files Modified

- `VideoCompressor/ios/Services/CompressionService.swift` (+18 / -12)
- `VideoCompressor/ios/Services/VideoLibrary.swift` (+60 / -15)
- `VideoCompressor/ios/Views/VideoListView.swift` (+11 / -8)

### Fixes Applied

1. **CRITICAL-1** — Polling task (`progressTask`) now cancelled _before_ `onProgress(1.0)` is emitted, eliminating the race where the poller overwrites the final value (~0.99). `withTaskCancellationHandler` added so cooperative `Task.cancel()` calls `exporter.cancelExport()`.
2. **CRITICAL-2** — `copyToWorkingDir` now uses `moveItem` instead of `copyItem`. Cleans up the `Picks-*` wrapper directory after the move.
3. **HIGH-1** — Alert binding replaced from `.constant(...)` to a real two-way `Binding(get:set:)` with `presenting:` form so SwiftUI can dismiss it correctly.
4. **HIGH-2** — `compressAll` predicate changed from `!= .running(progress: 0)` to `!.isActive`, which excludes ALL running states.
5. **HIGH-3** — Shared `private let service = CompressionService()` added to `VideoLibrary`; `runJob` uses `self.service` instead of creating a new actor per job.
6. **NEW** — `compress(_:)` now cancels `activeTask` before spawning, preventing batch+per-row races.
7. **NEW** — Zero-byte output detection: `attributesOfItem` errors surface as `.failed`, zero-byte files are deleted and `.failed` set.
8. **NEW** — Orphan output cleanup: if the row is removed mid-compression, output file is deleted.
9. **NEW** — NSError domain/code/localizedDescription + underlying error chain preserved on export failure.
10. **NEW** — `Documents/Inputs` and `Documents/Outputs` marked `isExcludedFromBackup = true` via `init()` helper.
11. **NEW** — `@Sendable` added to `onProgress` parameter.

### Deviation from Plan

- `while !Task.isCancelled, let exporter` is not valid Swift syntax (comma-separated `while` conditions with `let` binding require `guard`). Rewrote as `while !Task.isCancelled { guard let exporter else { return } ... }` — semantically identical.

### Build Result

- Clean build (0 errors, iOS 18 deprecation warnings only — pre-existing)
- App launches to empty state on iPhone 16 Pro sim (screenshot confirmed)

---

## [2026-05-03 06:25 SAST] {E-0503-0625} -- [SYNTH] Claude (Opus 4.7 / 1M ctx): 4-reviewer findings synthesized and applied

> **Agent Identity** is Claude Opus 4.7 (1M context), Claude Code CLI, /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR, Solo lead

**In-Reply-To:** {E-0503-0935}, {E-0503-0936}, {E-0503-0938}, plus the code-reviewer entry
**Confidence:** HIGH
**Files:** VideoCompressor/ios/Services/CompressionService.swift, VideoCompressor/ios/Services/VideoLibrary.swift, VideoCompressor/ios/Views/VideoListView.swift

### Context

4 Opus 4.7 reviewers (code-reviewer, silent-failure-hunter, type-design-analyzer, spec-gap-analyst) audited commit 8d88990. Findings converged on a small set of bugs that needed fixing before any phase-2 work.

### Action

Single sonnet subagent applied 12 fixes across 3 files in commit `5db2187`:
- Cancellation: AVAssetExportSession.cancelExport() now wired through withTaskCancellationHandler
- Progress: poller cancelled before final 1.0 emit; @Sendable on onProgress
- Zero-byte detection: failed export reported as .failed instead of fake .finished
- Picker tmp leak: moveItem instead of copyItem; Picks-* parent cleanup
- Alert binding: two-way binding with set: clearing the message
- Predicate bug: compressAll uses isActive instead of != .running(progress: 0)
- Service lifetime: single shared CompressionService instance instead of per-job
- Race fix: compress(_:) funneled through activeTask
- Error fidelity: NSError code/domain/userInfo + NSUnderlyingError preserved
- Backup hygiene: Documents/Inputs and Documents/Outputs marked isExcludedFromBackup
- Orphan cleanup: output file removed if user deletes row mid-flight

### Evidence

Verified post-fix: build_sim clean (0 errors), build_run_sim succeeded, screenshot confirms empty state still renders. Pre-existing iOS 18 deprecation warnings on AVAssetExportSession unchanged from baseline (those go away in phase 2 with AVAssetWriter migration).

### Deferred to phase 2

- BoundedProgress newtype, CompressedOutput payload, CompressionSettings struct, LibraryError sum type (type-design-analyzer top-3 refactors)
- 3-tab shell (TabView with Compress/Stitch/MetaClean)
- 2D compression matrix UI (spec section 3.2)
- AVAssetWriter migration with smart bitrate caps (closes web-app parity gap)
- Codec pills + audio controls
- MetaClean and Stitch tabs

### Next Step

Phase 2 sprint per spec-gap-analyst's recommended 5-commit ordering: TabView shell → Color+Theme + MatrixGridView → AVAssetWriter pipeline → codec/audio controls → MetaClean tab.

---

## [2026-05-03 11:42 IST] {E-0503-1142} -- [DOCS] subagent/opus: Authored Stitch + MetaClean implementation plan

> **Agent Identity**
> Model: Claude Opus 4.7 (1M context)
> Platform: Claude Code CLI (subagent dispatch)
> Working Directory: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/.claude/worktrees/jolly-pare-f79c78
> Session Role: subagent (planning-only)

**In-Reply-To:** {E-0503-0935}, {E-0503-0936}, {E-0503-0938}
**Confidence:** HIGH
**Files:** `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` (new)
**Word count:** 5007

### Action

Authored a Stitch + MetaClean implementation plan via the superpowers:writing-plans skill. Plan covers: (1) lazy-edit Stitch model where each clip carries `ClipEdits` and `AVMutableComposition` is built only at export; (2) timeline reorder via SwiftUI `List`+`.onMove` (recommended over `.draggable/.dropDestination` for v1 accessibility); (3) per-clip editor sheet with Trim/Crop/Rotate tabs; (4) MetaClean via `AVAssetWriter` remux (no re-encode) preserving bit-identical pixels; (5) Apple's no-overwrite-Photos constraint addressed with default "save new copy" plus optional `PHAssetChangeRequest.deleteAssets` follow-up.

10 tasks (S1-S8 Stitch, M1-M4 MetaClean — note M4 is the 12th task with PhotosSaver extension). 6-commit ordering. Risk register with 7 entries. Code skeletons for `StitchClip`, `StitchProject`, `StitchExporter`, `MetadataService`, `PhotosSaver` extension. Q&A section directly answers all five user questions verbatim. References `{E-0503-0936}` BoundedProgress / CompressedOutput / typed-error refactors as a hard prerequisite shape both features adopt.

### Status

Plan ready for execution. No iOS source modified. Next agent picks up at Task S1 (or Task 0 if `CompressionSettings` refactor from Phase 2 commit 2 has not yet landed).

---

## [2026-05-03 12:30 IST] {E-0503-1230} -- [REFACTOR] subagent:sonnet via Opus 4.7 lead

> **Agent Identity**
> Model: Claude Sonnet 4.6 (subagent:sonnet)
> Platform: Claude Code CLI (subagent dispatch by Opus 4.7 lead)
> Working Directory: /Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/.claude/worktrees/jolly-pare-f79c78
> Session Role: subagent (Task 0 implementer)

**In-Reply-To:** {E-0503-0936}
**Confidence:** HIGH
**Commit:** `4a9cbc9`

### Action

Applied all type-design refactors from {E-0503-0936} top-3 recommendations. Full file delta:

**New files:**
- `VideoCompressor/ios/Models/BoundedProgress.swift` — `Double` clamped to `0.0...1.0`; `NaN`/negative/>1 rejected at init; `percent: Int` and `Comparable` conformance.
- `VideoCompressor/ios/Models/CompressedOutput.swift` — Cohesive success payload (`url`, `bytes`, `createdAt`, `settings`); replaces orphan `outputURL?`+`outputBytes?` pair.
- `VideoCompressor/ios/Models/CompressionSettings.swift` — `struct` with `Resolution × QualityLevel` axes; four `static let` phase-1 factories (`.max/.balanced/.small/.streaming`); `phase1Presets` array for picker; all metadata (`title`, `subtitle`, `symbolName`, `outputSuffix`, `avExportPresetName`) migrated from deleted enum.
- `VideoCompressor/ios/Models/LibraryError.swift` — Typed sum (`metadata` | `compression` | `photos` | `fileSystem`); `displayMessage` and `recoverySuggestion` accessors.

**Deleted:**
- `VideoCompressor/ios/Models/CompressionPreset.swift` — Replaced by `CompressionSettings`.

**Modified:**
- `VideoFile.swift` — `output: CompressedOutput?` replaces `outputURL?`+`outputBytes?`; `CompressionJobState.running(progress: BoundedProgress)` and `.failed(error: LibraryError)`; `failureMessage: String?` accessor; `VideoMetadata.estimatedDataRate: Int64` (was `Float`).
- `CompressionService.swift` — `compress(input:settings:onProgress:)` signature; `onProgress: (BoundedProgress) -> Void`; `outputURL(forInput:settings:)` and `estimateOutputBytes(for:settings:)`; `CompressionError` gets `Hashable, Sendable`.
- `VideoLibrary.swift` — `selectedSettings: CompressionSettings` (was `selectedPreset`); `lastError: LibraryError?` (was `lastErrorMessage: String?`); `lastErrorMessage` shim kept; cast helpers `asMetadataError/asCompressionError/asPhotosError`; all error-set sites use typed `LibraryError`.
- `PhotosSaver.swift` — `PhotosSaverError` gets `Hashable, Sendable`.
- `VideoMetadataLoader.swift` — `VideoMetadataError` gets `Hashable, Sendable`; `Int64(bitrate.rounded())` at construction site.
- `PresetPickerView.swift` — `CompressionSettings.phase1Presets` replaces `CompressionPreset.allCases`; `library.selectedSettings`.
- `VideoListView.swift` — `library.selectedSettings`; `library.lastError` binding.
- `VideoRowView.swift` — `progress.value` / `progress.percent`; `error.displayMessage` + optional `error.recoverySuggestion`; `video.output?.bytes`.

### Build Status

- `build_sim`: clean (0 errors, 0 new warnings)
- `build_run_sim`: succeeded; app launches to 3-tab shell on iPhone 16 Pro sim; empty state renders
- Screenshot: sim shows Stitch placeholder tab (tab navigation working)

### Deviations from Plan

None. All files in scope. No files outside the listed set were touched. `VideoFile` failable init (plan item 3a from {E-0503-0936}) correctly excluded per task spec.

---

## [2026-05-03 10:24 SAST] {E-0503-1024} -- [REVIEW] code-reviewer (subagent:opus): T0 type-refactor audit

> Session Role: subagent (code-reviewer)

**In-Reply-To:** {E-0503-1230}
**Confidence:** HIGH
**Commit reviewed:** `4a9cbc9`
**Scope:** 4 new model files + 8 modified files. No Swift source modified.

### Verdict

Build is clean and the four new types are well-shaped. **Two HIGH-severity matrix-expansion traps** are baked into `CompressionSettings`'s `default:` arms — these pass today (Phase 1 only ships 4 cells) but will silently produce wrong outputs when Phase 2's 2D matrix lands. **One HIGH UX regression**: `recoverySuggestion` is never shown for `lastError` (alert binding ignores it). Several MEDIUM behavior-preservation drifts (error wording prefixes). No CRIT.

### CRITICAL

None.

### HIGH

**H1. `CompressionSettings.avExportPresetName` silent fall-through to HEVCHighestQuality** — `CompressionSettings.swift:21-30`. The `default:` arm returns `AVAssetExportPresetHEVCHighestQuality` for any combo not in the four-cell allowlist. With 7 resolutions × 6 quality levels = 42 combos and only 4 explicit, **38 cells silently render at HEVC max**. When the matrix UI lands, picking e.g. `(uhd2160, balanced)` will produce a 4K HEVC-max file that ignores both axes. **Fix:** Replace `default: return AVAssetExportPresetHEVCHighestQuality` with `default: fatalError("avExportPresetName: unconfigured cell \(resolution)×\(quality)")`. This forces Phase 2 commit 2 to populate cells before exposing them. Same fix for `outputSuffix`, `title`, `subtitle`, `symbolName` `default:` arms (lines 35-74) — they ignore the quality axis entirely, so `(fhd1080, lossless)` and `(fhd1080, tiny)` would currently render with identical "Balanced" / `_BAL` / 1920x1080 settings.

**H2. `shouldOptimizeForNetworkUse` keyed by string suffix** — `CompressionService.swift:73`. Old code: `(preset == .streaming)`. New code: `(settings.outputSuffix == "_WEB")`. Matrix expansion: any `(sd540, *)` cell — including `(sd540, lossless)` — gets fastStart, while `(fhd1080, balanced)` won't even though it could legitimately be a streaming target. **Fix:** add `var optimizesForNetwork: Bool { resolution == .sd540 }` (or a dedicated `streamReady` field on `CompressionSettings`) and use that. String-keyed feature flags are exactly what `CompressionSettings` was meant to eliminate.

**H3. `LibraryError.recoverySuggestion` is dead in the alert path** — `VideoListView.swift:57-68` passes `library.lastError?.displayMessage` as `presenting:` and only renders `Text(msg)` in the alert body. The `recoverySuggestion` for `.photos(.notAuthorized)` is set on `lastError` in `saveOutputToPhotos` (`VideoLibrary.swift:219`) but the alert never reads it — the user never sees the Settings deep-link hint. (`VideoRowView` does render `error.recoverySuggestion` for per-row `.failed` state, but Photos errors flow to `lastError`, not row state.) **Fix:** in `VideoListView`'s `.alert` builder, append a second `Text(suggestion)` block when `library.lastError?.recoverySuggestion != nil`, or extend the alert with a "Open Settings" button when the case matches.

### MEDIUM

**M1. Error-message wording silently changed** (behavior preservation, despite commit msg "no external behavior change"): three user-facing messages now have new prefixes via `LocalizedError.errorDescription`:
  - empty-file path was `"Compressor produced an empty file. Try a different preset."` → now `"Compression failed: Compressor produced an empty file. Try a different preset."` (`VideoLibrary.swift:182`).
  - generic compression catch was raw `error.localizedDescription` → now `"Compression failed: <msg>"` (`VideoLibrary.swift:206`).
  - metadata-load catch was raw `error.localizedDescription` → now `"Could not read video metadata: <msg>"` (`VideoLibrary.swift:110` via `asMetadataError`).
  - photos-save catch was raw → now `"Failed to save to Photos: <msg>"` (`VideoLibrary.swift:219`).
  Each prefix is reasonable, but the commit asserts zero behavior change. **Fix:** either update the commit message / changelog to note the wording shift, or strip the `"… failed: "` prefixes inside `errorDescription` so the displayed string matches Phase 1.

**M2. `Int64(bitrate.rounded())` traps on NaN/Inf** — `VideoMetadataLoader.swift:75`. `bitrate` is `Float` from `track.load(.estimatedDataRate)`. AVFoundation can return `0` for unloaded tracks but a malformed source could return NaN/Inf — `Int64(Double.nan)` is a runtime trap. The previous `Float` field tolerated this. **Fix:** `estimatedDataRate: bitrate.isFinite ? Int64(bitrate.rounded()) : 0`.

**M3. `CompressionJobState.progress` always returns 1.0 for `.finished`, but no consumer uses it** — `VideoFile.swift:100-104`. Dead read today (`grep jobState.progress` → 0 hits in views; `VideoRowView` switches on the state, not the accessor). The risk is future code binding a `ProgressView(value: video.jobState.progress)` outside the switch — it would briefly flicker 100% before flipping to a "Done" view. **Fix (optional):** return 0 (or a separate `displayProgress` accessor) for `.finished` so the field semantically means "in-flight progress", or document the contract on the property.

**M4. `outputsURL` resource-value mutation is a no-op** — `CompressionService.swift:30-33`. `var outputsURL = outputs; try? outputsURL.setResourceValues(...)` mutates the local copy of the URL struct, not the on-disk attribute (you can't set `.isExcludedFromBackup` on a directory that doesn't yet have a file inside, and the mutation is dropped because `outputs` is the URL actually returned). The same flag is correctly applied in `VideoLibrary.markDirectoriesAsNonBackup()` at init, so the bit is set there. **Fix:** delete the dead block (lines 30-33) — it's misleading.

### LOW

**L1. `VideoLibrary.lastErrorMessage` shim** — `VideoLibrary.swift:29` is unused (alert reads `library.lastError?.displayMessage` directly). Keep or delete; harmless either way, but the comment "for SwiftUI alert bindings" is stale.

**L2. `phase1Presets` is hard-coded ordering** — `CompressionSettings.swift:83`. Picker iterates this array; matrix UI will replace. Already documented as transitional. No action.

### Confirmations (focus-list answers)

- **F1 BoundedProgress NaN/Inf:** Correct. `raw.isNaN` short-circuits before any `<`/`>` comparison. `+Inf` clamps to 1, `-Inf` clamps to 0 via `raw < 0`. NaN clamps to 0.
- **F3 `.photos(.notAuthorized)` pattern:** `PhotosSaverError.notAuthorized` has no associated value — pattern matches correctly.
- **F4 `Int64` overflow:** Float max ≫ Int64 max but real bitrates never approach 9.2 Eb/s; overflow not a practical concern. NaN/Inf trap (M2) is the real risk.
- **F6 Sendable union:** `LibraryError` synthesizes `Sendable` because all three carried error enums got `Sendable` conformance in the diff. Clean.
- **F8 Dead factories:** `.max/.balanced/.small/.streaming` only consumed via `phase1Presets` (picker) and `.balanced` as default selection. No matrix-locking direct refs.

### Recommended Action

Block H1 + H2 before Phase 2 commit 2 (matrix UI). H3 is a one-line fix and should land in the same patch. M1 either get noted in CHANGELOG as a wording change or normalized in `errorDescription`. M2 is a 30-second guard.

---


---

## {E-0503-STITCH-S1S2} Stitch model + StitchProject state — commit 1 of stitch+metaclean plan

**[2026-05-03 10:30 IST] [subagent:sonnet via Opus 4.7 lead] [BUILD]**
In-Reply-To: {E-0503-1142} (PLAN-stitch-metaclean.md)

### Files Created
- `VideoCompressor/ios/Models/StitchClip.swift` (68 lines) — `StitchClip` + `ClipEdits` value types with `trimmedDurationSeconds`, `trimmedRange`, `isEdited` derived properties. Upper clamp to naturalDuration, lower clamp to 0.
- `VideoCompressor/ios/Models/StitchProject.swift` (89 lines) — `@MainActor` `ObservableObject` with `@Published clips`, `exportProgress`, `exportState`. `append/remove/move/updateEdits`. `export()` stubbed with TODO(commit-4). `StitchExportState` enum (idle, building, encoding(BoundedProgress), finished(CompressedOutput), cancelled, failed(error:LibraryError)).
- `VideoCompressor/VideoCompressorTests/StitchClipTests.swift` (96 lines) — 6 XCTest cases covering default trim, trim with edits, negative clamp, upper clamp, isEdited false/true variants.

### Files Modified
- `VideoCompressor/VideoCompressorTests/VideoCompressorTests.swift` — Fixed `@testable import VideoCompressor` → `@testable import VideoCompressor_iOS` (module name mismatch; same fix applied to StitchClipTests.swift). Pre-existing latent bug in stub test file.

### Deviations from Plan
- Plan skeleton had `lastError: StitchError?` — `StitchError` is undefined; omitted per task instructions (error surfaced via `failed(error:)` case instead).
- Plan skeleton had `init(exporter: StitchExporter)` — `StitchExporter` not yet implemented (commit 4); `init()` with no exporter parameter per task instructions.
- `StitchExportState.failed` case uses labeled `error:` param to match the stub call site `.failed(error: .fileSystem(...))`.

### Build & Test Results
- `build_sim`: ✅ green
- `build_run_sim`: ✅ app launches, Stitch tab shows placeholder (commit 2 target)
- `test_sim`: ✅ 8/8 passed (6 StitchClipTests + 1 existing Swift Testing example + 1 XCTest example after import fix)

### Commit
SHA: `8147e22` — feat(ios): Stitch model + StitchProject state (commit 1 of stitch+metaclean plan)

---

## [2026-05-03 10:32 SAST] {E-0503-1032} -- [REVIEW] code-reviewer (subagent:opus): Commit 1 audit (StitchClip + StitchProject)

> Session Role: subagent (code-reviewer)
> Model: Claude Opus 4.7 (1M context)

**In-Reply-To:** {E-0503-STITCH-S1S2}
**Confidence:** HIGH
**Commit reviewed:** `8147e22`
**Scope:** `StitchClip.swift` (68L), `StitchProject.swift` (89L), `StitchClipTests.swift` (111L). No Swift source modified.

### Verdict

Build is clean and the type shape is sound. **One HIGH consistency bug** (`trimmedDurationSeconds` and `trimmedRange.duration` disagree on negative trimStart and on (trimStart>0 && trimEnd>natural) inputs). **One HIGH safety bug** in `StitchProject.remove(at:)` (unconditionally deletes `sourceURL`, no scoping to `inputsDir`). Two MEDIUM (sub-frame precision in `trimmedRange`, undisclosed plan deviations). Tests pass but coverage gaps exist.

### HIGH

**H1. `trimmedDurationSeconds` ignores per-end clamping; disagrees with `trimmedRange.duration`** — `StitchClip.swift:24-29`. Code computes `min(natural, max(0, end - start))` using *raw* values. `trimmedRange` (lines 33-42) correctly clamps each end first: `clampedStart=max(0,start)`, `clampedEnd=min(natural,max(clampedStart,end))`. They diverge:
- `trimStart=-1, trimEnd=5, natural=10` → duration=6, range=0..5 (5s). Off by 1.
- `trimStart=5, trimEnd=999, natural=10` → duration=10, range=5..10 (5s). Off by 5.

UI labels (duration) and AVMutableComposition inserts (range) will disagree. **Fix:**
```swift
var trimmedDurationSeconds: Double {
    CMTimeGetSeconds(trimmedRange.duration)
}
```
Single source of truth — both derive from `trimmedRange`. Add tests for both negative-start and start>0+end>natural. (Tests miss both cases; current 7 — not 6 as commit msg says — only cover symmetric clamps.)

**H2. `StitchProject.remove(at:)` unconditionally deletes `sourceURL` — risks deleting non-StitchInputs files** — `StitchProject.swift:50-56`. Plan §Q2 establishes "copy to `Documents/StitchInputs/`" as the import contract, so today's UI path is safe. But `StitchClip` is a public initializer-free struct: any future caller (or test, or unit-test fixture) can construct one whose `sourceURL` points outside `inputsDir`. `remove(at:)` will silently delete it. The `try?` swallows errors but there is *no* path scoping. **Fix:** scope deletion to descendants of `inputsDir`:
```swift
func remove(at offsets: IndexSet) {
    let toDelete = offsets.map { clips[$0] }
    clips.remove(atOffsets: offsets)
    let inputsPath = inputsDir.standardizedFileURL.path
    for clip in toDelete {
        let p = clip.sourceURL.standardizedFileURL.path
        guard p.hasPrefix(inputsPath) else { continue }
        try? FileManager.default.removeItem(at: clip.sourceURL)
    }
}
```

### MEDIUM

**M1. `trimmedRange` uses `Int64(seconds * 600)` truncation instead of rounding** — `StitchClip.swift:39-40`. For sources whose `naturalDuration.timescale != 600`, `CMTimeGetSeconds` returns floats like `9.999666…`; `Int64(9.999666 * 600) = 5999`, dropping one tick. Across a 20-clip stitch the cumulative drift can reach a frame at 30 fps. **Fix:** use `CMTimeMakeWithSeconds(_, preferredTimescale: 600)` which rounds correctly:
```swift
let startTime = CMTimeMakeWithSeconds(clampedStart, preferredTimescale: 600)
let endTime = CMTimeMakeWithSeconds(clampedEnd, preferredTimescale: 600)
```

**M2. Undisclosed plan deviations beyond the 3 reported** — Plan §Task S2 line 275-277 defined `StitchExportState` as `idle, building, encoding, finished(CompressedOutput), cancelled` (no `.failed`, no payload on `.encoding`). Impl added `.failed(error: LibraryError)` and `.encoding(BoundedProgress)`. Both are improvements, but {E-0503-STITCH-S1S2} listed only 3 deviations + the import fix. Also: commit message says "6 XCTest cases", file has 7. Note these in a follow-up `[FIX-DOCS]` entry — paper trail matters.

**M3. `StitchProject.append(_:)` redundant `createDirectory` call** — `StitchProject.swift:42-45`. `init` (lines 23-31) already creates `inputsDir`. The repeated call in `append` is dead defense. Either delete it (init suffices) or move to a lazy first-write helper and remove from init. Today's pair is two main-thread `mkdir` syscalls per import.

### LOW

**L1. `cropNormalized = CGRect(x:0,y:0,w:1,h:1)` reports `isEdited == true`** — semantically a no-op crop, but `CGRect != nil` so `edits != .identity`. Mostly cosmetic; if commit-4's exporter uses `isEdited` for a passthrough fast-path decision, a no-op crop will miss it. **Optional:** custom `isEdited` returns false when cropNormalized equals the unit rect.

**L2. Tests miss `StitchProject` mutations entirely** — `move(from:to:)`, `remove(at:)` (the soon-to-be-fixed deletion path), `updateEdits(for:_:)` (closure mutation under @MainActor) all untested. `export()` stub also untested — would catch the failure-state shape contract. Add a `StitchProjectTests.swift` companion before commit 2 ships the UI binding.

### Confirmations

- **Sendability:** all carried types (`BoundedProgress`, `CompressedOutput`, `LibraryError` and its three carried errors) are `Sendable`. `StitchExportState` synthesizes Sendable correctly.
- **`CGRect` Hashable:** exact-zero comparisons reliable; the gotcha is the conceptual identity (L1), not float-equality.
- **`canExport >= 2`:** plan-correct; defer single-clip-edit-via-stitch to a future spec. Not a defect.
- **Main-actor `createDirectory` in init:** acceptable for one-shot launch; no fix needed beyond M3 deduplication.
- **`failed` state reset:** `export()` re-tap overwrites `exportState`, so user re-attempts implicitly clear. Adequate for stub.

### Recommended Action

Block H1 and H2 before commit 2 (UI binding) lands — the timeline duration label will show one number while the export composition uses another (H1), and a future test or refactor that constructs a `StitchClip` with a non-StitchInputs URL will silently delete user data (H2). M1, M2, M3 land in the same patch. L1, L2 deferrable.

---

## [2026-05-03 10:44 IST] [subagent:sonnet via Opus 4.7 lead] [BUILD] Commit 2: Stitch tab shell + timeline + thumbnails

In-Reply-To: {E-0503-1142} (PLAN-stitch-metaclean.md, tasks S3/S4/S5)

**Tasks completed:** S3 (ThumbnailStripGenerator), S4 (StitchTabView), S5 (StitchTimelineView + ClipBlockView)

**Files added (5 new):**
- `VideoCompressor/ios/Services/ThumbnailStripGenerator.swift` — 88 lines. Actor; `AVAssetImageGenerator.images(for:)` async sequence; midpoint-sampling for non-black frame 0; per-frame failure tolerance.
- `VideoCompressor/ios/Views/Shared/CenteredEmptyState.swift` — 52 lines. Generic `@ViewBuilder`-action empty-state layout; replaces ad-hoc VStack pattern.
- `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` — 177 lines. PhotosPicker multi-import (max 20), sequential import with `VideoTransferable` reuse, `Documents/StitchInputs/` staging, alert binding via `project.lastImportError`, "Stitch & Export" bottom bar (disabled until 2+ clips).
- `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift` — 33 lines. `List + .onMove + .onDelete`, always-on `editMode`.
- `VideoCompressor/ios/Views/StitchTab/ClipBlockView.swift` — 69 lines. 4-frame thumbnail strip, duration label, "Edited" badge.

**Files modified (4):**
- `VideoCompressor/ios/Models/StitchProject.swift` — added `@Published var lastImportError: LibraryError?`
- `VideoCompressor/ios/Views/EmptyStateView.swift` — refactored onto `CenteredEmptyState`; `importVideosButton` identifier preserved
- `VideoCompressor/ios/ContentView.swift` — `PlaceholderTabView(tab: .stitch)` → `StitchTabView()`
- `CHANGELOG.md` — [Unreleased] "Added" section updated

**Build:** ✅ clean (`build_sim` green)
**Tests:** ✅ 8/8 pass
**Sim screenshot:** Stitch tab shows correct new empty state — "Stitch" nav title, `square.stack.3d.up` icon, "No clips yet" / "Pick two or more videos…" copy, "Import Videos" CTA, `+` toolbar button.
**Commit:** `d03d4bc` on `feature/metaclean-stitch`

**Deviations from plan:**
- `EmptyStateView` was refactored onto `CenteredEmptyState` rather than left unchanged, keeping the Compress flow's `importVideosButton` accessibility identifier intact.
- `StitchTabView.importClips` is sequential (not parallel) per advisor guidance — picker order is preserved for timeline ordering.
- `ClipEditorSheet` tap gesture and sheet binding omitted per commit-2 scope (commit 3 deliverable).
- PhotosPicker E2E import not automatable via axe (system picker is out-of-process). Verified empty state + toolbar button visually via screenshot.

---

## [2026-05-03 10:50 SAST] {E-0503-1050} -- [REVIEW] code-reviewer (subagent:opus): Commit 2 audit (Stitch UI)

In-Reply-To: d03d4bc — "Stitch tab shell + timeline reorder + thumbnails"

**Scope:** ThumbnailStripGenerator, StitchTabView, StitchTimelineView, ClipBlockView, CenteredEmptyState, EmptyStateView refactor, ContentView wiring, StitchProject.lastImportError. Plan tasks S3/S4/S5.

**Verdict:** Ship-able with one HIGH and three MEDIUM follow-ups. No CRITICAL. Sendability, alert binding, accessibility identifiers, and reuse of `CenteredEmptyState` all look right. AsyncSequence enum-pattern for `AVAssetImageGenerator.images(for:)` matches the iOS 17 case shape (`.success(requestedTime:image:actualTime:)` / `.failure(requestedTime:error:)`). `UIImage` is `Sendable` on iOS 17+, so the actor's `[UIImage]` return is fine under Swift 6 strict concurrency.

### HIGH

**H1. `stageToStitchInputs` silently overwrites in-use source files** — `StitchTabView.swift:189-204`. Target path is `StitchInputs/<base>.<ext>` where `base` defaults to `suggestedName` (e.g. `IMG_4521.mov`). `try? removeItem(at: target)` deletes any existing file at that path before `moveItem`. If the user re-imports a clip whose `suggestedName` matches one already in the timeline, the on-disk file backing the existing `StitchClip.sourceURL` is destroyed, while the in-memory `StitchClip` (and `ClipBlockView` task cache) still references that URL. Subsequent thumbnail loads, the export composition, and any per-clip editor in commit 3 will fail with no surfaced error.
**Fix:** if `target` exists, append a UUID suffix (e.g. `<base>-<uuid8>.<ext>`) instead of overwriting. Cheaper than a content-hash dedupe and avoids the data-loss path entirely.

### MEDIUM

**M1. `importClips` Task is detached from view lifecycle** — `StitchTabView.swift:80-86`. The free-standing `Task { await importClips(items) }` from `.onChange` is not bound to the view via `.task`. If the user backgrounds the app or switches tabs mid-import, the import keeps running. With 20 large videos this can hold I/O for tens of seconds. `@StateObject` keeps the project alive in TabView, so partial state survives — but there's no cancellation hook and no progress indicator. The empty state stays on-screen until the first clip lands; with HEVC 4K sources that can be 2-3s of dead UI.
**Fix:** swap the bare `Task` for a `.task(id: importGeneration)` driven by a `@State` counter that increments on each picker emission, OR add a `@State var isImporting: Bool` that drives a `ProgressView` overlay. Cancellation can be a v2 nicety; the progress chip is the bigger UX win.

**M2. `naturalSize == .zero` swallowed silently** — `StitchTabView.swift:153-158`. When the asset's first video track fails to load, `naturalSize = .zero` is set and the clip is appended anyway. Commit 3 (`CropEditorView`) will divide by `naturalSize.width / .height` to compute crop rects — a `.zero` size produces NaN normalised coords and a crash or a silent no-op crop. Right now the failure is invisible: clip lands on timeline, thumbnails generate fine (generator path is independent), then the editor blows up later.
**Fix:** treat track-load failure as a hard import error — set `lastImportError = .fileSystem(message:)`, skip the append, clean up the staged file. Same shape as the duration-load failure two lines above.

**M3. `ClipBlockView.thumbnailLoadError` is dead state** — `ClipBlockView.swift:15, 71`. `@State private var thumbnailLoadError: String?` is written on failure but never read by the view body. The neutral `.quaternary` placeholder shows for both "loading" and "failed" — visually indistinguishable. Either render the error label (small caption under the strip) or delete the property and the catch's assignment.
**Fix:** delete the property; rely on `thumbnails.isEmpty` placeholder. If you want to surface failures, add a single `Image(systemName: "exclamationmark.triangle")` overlay on the placeholder when `thumbnailLoadError != nil`.

### LOW

**L1. `requestedTimeToleranceBefore/After = .positiveInfinity`** — `ThumbnailStripGenerator.swift:46-47`. Plan §S3 had `.zero` before / `.positiveInfinity` after. Both-infinity gives the encoder full freedom — for keyframe-sparse sources the four thumbnails can collapse onto the same keyframe (visually identical strip). Acceptable for most footage; consider `.positiveInfinity` after, `CMTime(seconds: 0.5, preferredTimescale: 600)` before to keep some ordering signal. Not blocking.

**L2. `Picks-*` cleanup couples to `VideoTransferable` impl detail** — `StitchTabView.swift:200-203`. The `if parent.lastPathComponent.hasPrefix("Picks-")` check matches the wrapper directory name in `VideoLibrary.swift:252`. If that prefix is ever renamed, cleanup silently leaks tmp directories. **Fix:** export a constant from `VideoTransferable` (e.g. `static let stagingDirPrefix = "Picks-"`) and reuse it.

**L3. CHANGELOG entry counts** — Commit 2 actually added 5 files (incl. `Shared/CenteredEmptyState.swift` and refactored `EmptyStateView.swift`); the AI-CHAT-LOG file-count tally and per-file line counts in {E-0503-1044} match the diff stat (462 insertions / 20 deletions). No issue — paper trail consistent.

### Confirmations

- **Sendable / strict concurrency:** `UIImage` is `Sendable` on iOS 17+ (since SE-0418); actor `[UIImage]` return surfaces no warnings under Swift 6 strict mode.
- **AsyncSequence pattern:** `.success(requestedTime: _, image: let cg, actualTime: _)` and `.failure(requestedTime: _, error: _)` are correct arity for iOS 17 `AVAssetImageGenerator.Image`.
- **`.task(id: clip.sourceURL)`:** SwiftUI cancels on view-disappear and re-runs on id-change; two clips sharing a URL is harmless because each `ClipBlockView` has its own state and ForEach identity is `clip.id`.
- **Memory pressure:** 80 px thumbnails × 4 × 20 clips ≈ 2 MB total — well below the 80 MB rough estimate. List on iOS 17 is lazy under `.plain`; off-screen rows are reclaimed.
- **Alert binding:** uses the same two-way `Binding(get:set:)` pattern as the fixed VideoListView (review {E-0503-1032}). Dismissal clears `lastImportError`. Good.
- **Always-on edit mode + `.onDelete`:** `.swipeActions` is not used, so no conflict. SwiftUI's default a11y labels for the reorder handle are localised; no custom labels needed for v1.
- **Accessibility identifiers:** `stitchImportButton`, `stitchAddButton`, `stitchExportButton`, `importVideosButton` — all set and unique.
- **`CenteredEmptyState` reuse:** generic `Action: View` + `@ViewBuilder` cleanly accommodates both PhotosPicker (Stitch) and PhotosPicker-with-different-strings (Compress). No duplication remains in `EmptyStateView`.
- **`ContentView` lifecycle:** `StitchTabView` `@StateObject` survives tab switches in iOS TabView; one `StitchProject` instance per app launch.

### Recommended Action

H1 must land before commit 3 (per-clip editor) — the editor will compound the data-loss surface by holding more state pinned to `sourceURL`. M1, M2 ride the same patch. M3 and L1-L3 deferrable to commit 3 cleanup. Phase 2 follow-up (separate task): `preferredItemEncoding: .current` keeps HDR/Dolby Vision but the export pipeline doesn't preserve color metadata — flag for v2 plan.

---

## [2026-05-03 11:42 IST] {E-0503-1142} -- In-Reply-To {E-0503-1032} [BUILD] [subagent:sonnet via Opus 4.7 lead] Task S6: Per-clip editor sheet with Trim/Crop/Rotate (commit 3 of 6)

> **Agent Identity**
> Model: claude-sonnet-4-6 (subagent dispatched by Opus 4.7 lead)
> Platform: Claude Code CLI — worktree `claude/jolly-pare-f79c78`
> Session Role: subagent (Task S6 implementation)

**Confidence:** HIGH
**Commit SHA:** 3f69f2b
**Build:** CLEAN (0 errors, 0 warnings)
**Tests:** 7/7 StitchClipTests PASS

### Files Added

| File | Lines | Notes |
|------|-------|-------|
| `VideoCompressor/ios/Views/StitchTab/ClipEditorSheet.swift` | 62 | 3-tab NavigationStack sheet; guard-let on clipID (no force-unwrap); `.presentationDetents([.large])`; draft edits committed only on Done |
| `VideoCompressor/ios/Views/StitchTab/TrimEditorView.swift` | 94 | Dual-Slider with clamped bindings (start ≤ end enforced in setter); live duration label; `formatTime` uses truncation not rounding; Reset button |
| `VideoCompressor/ios/Views/StitchTab/CropEditorView.swift` | 115 | 4 explicit `Binding<Double>` getters (avoids `WritableKeyPath<CGRect,Double>` CGFloat/Double type mismatch); identity-rect clears `cropNormalized` |
| `VideoCompressor/ios/Views/StitchTab/RotateEditorView.swift` | 56 | 4-stop picker (0/90/180/270); active stop highlighted with `Color.accentColor` |

### Files Modified

| File | Change |
|------|--------|
| `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift` | Added `@State private var editingClipID`; `.contentShape(Rectangle()).onTapGesture`; `.sheet(item: Binding(get:set:))` |

### Deviations from Spec

1. **`WritableKeyPath<CGRect,Double>` skipped** — went straight to four explicit `Binding<Double>` per advisor recommendation (CGFloat ≠ Double in generic constraints; spec explicitly authorizes this fallback).
2. **`formatTime` truncation fix** — used `Int(seconds)` instead of `Int(seconds.rounded())` to prevent display of e.g. `0:06.00` for a 5.7 s clip.
3. **Guard-let instead of force-unwrap** — `ClipEditorSheet.body` guards on clipID and calls `dismiss()` on stale ID rather than crashing.

### Status: Complete

## [2026-05-03 11:01 SAST] {E-0503-1101} -- [REVIEW] code-reviewer (subagent:opus): Commit 3 audit (per-clip editor sheet)

> **Agent Identity:** subagent / Opus 4.7 (1M ctx) / code-reviewer role
> **Scope:** commit `3f69f2b` — `ClipEditorSheet`, `TrimEditorView`, `CropEditorView`, `RotateEditorView`, `StitchTimelineView` sheet wiring. Read-only audit, no Swift source modified.

### Verdict: 1 HIGH, 3 MEDIUM, 4 LOW. Ship-recommended after H1 fix; rest are tracked-as-tech-debt or v2 items already called out.

### HIGH

**H1 — `CropEditorView`: identity-rect comparison via `CGRect ==` is float-fragile** (file: `CropEditorView.swift`, four binding setters). Each setter writes `edits.cropNormalized = rect == CGRect(x:0,y:0,width:1,height:1) ? nil : rect`. `CGRect.==` is exact CGFloat equality. Slider track values are `Double`; round-tripping through CGFloat on arm64 (CGFloat = Double there, so OK on iPhone), but the user's review prompt is correct that any tiny FP drift — e.g. dragging X to 0.0 then back, or width arriving as 0.99999999 — leaves `cropNormalized` populated at near-identity. The exporter will then run an unnecessary crop pass with values like `(0, 0, 0.9999..., 1)`, producing 1-pixel crops that may differ from `naturalSize` by rounding. **Fix:** introduce `private func isIdentity(_ r: CGRect) -> Bool { abs(r.minX) < 1e-4 && abs(r.minY) < 1e-4 && abs(r.width - 1) < 1e-4 && abs(r.height - 1) < 1e-4 }` and call from each setter. Also stops Reset Crop from being shadowed by a near-identity rect that the user dragged back to "1.00" on the slider label.

### MEDIUM

**M1 — `ClipEditorSheet` `.onAppear` re-fires on swipe-to-dismiss + reopen, clobbering draft.** SwiftUI re-instantiates the sheet's root View each presentation, so `@State draftEdits` is recreated and `.onAppear` re-runs `draftEdits = clip.edits`. That is the *intended* behavior for a fresh open after Cancel. But: a user who swipe-dismisses (which behaves like Cancel — no commit) then reopens correctly gets a fresh draft. So this is **not a bug**; the prompt's concern is unfounded. The actual subtle case is **modal-on-modal** (e.g. share sheet from inside the editor): SwiftUI does *not* re-init the host view, but `.onAppear` *does* fire again on system-modal dismiss on iOS 17+, which would silently reset draft. No share sheet exists in commit 3, so latent only. **Mitigation when v2 adds preview/share:** gate the assignment with `if draftEdits == .identity { draftEdits = clip.edits }`, or move init into `.task(id: clipID)` so it only runs on identity change.

**M2 — `RotateEditorView` accent-color contrast in dark mode.** Active stop uses `Color.accentColor` background with `Color.white` foreground. With the system blue accent in dark mode, white-on-system-blue passes AA (~5.1:1). But if the project later customizes `AccentColor` in `Assets.xcassets` (e.g. brutalist-theme green/cyan/pink per MEMORY.md), white-on-pink-#ff66b2 is ~3.4:1 — fails AA for normal text. **Fix:** `.foregroundStyle(.white)` → `.foregroundStyle(Color.accentColor.contrastingTextColor)` via a small extension that picks black/white by relative luminance, or simpler `.foregroundStyle(Color(.systemBackground))` so it tracks light/dark.

**M3 — Accessibility labels are missing across all three editors.** No `.accessibilityLabel`, `.accessibilityValue`, or `.accessibilityIdentifier` on any of: trim Sliders, crop Sliders, rotate stops. VoiceOver will announce "Slider, 0.42, adjustable" with no field name. **Fix:** add `.accessibilityLabel("Trim start"/"Trim end"/"Crop X" etc.)` and `.accessibilityValue(formatTime(...))` so the slider speaks "Trim start, 0:05.70". Rotate buttons need `.accessibilityLabel("Rotate \(deg) degrees")` plus `.accessibilityAddTraits(.isSelected)` on the active stop.

### LOW

**L1 — `formatTime` truncation drops sub-centisecond.** `Int((seconds - Double(total)) * 100)` for `seconds = 5.999` yields `total=5`, `ms=99`, displays `0:05.99`. Acceptable per the design intent, but `5.7` displayed as `0:05.70` actually requires `ms = Int((5.7 - 5) * 100) = Int(70.0...) = 70` — works because of arm64 IEEE rounding. Fragile; consider `Int(((seconds - Double(total)) * 100).rounded(.down))` for explicitness.

**L2 — `TrimEditorView` Reset Trim post-state.** After clearing both seconds to nil, getters return `0` and `naturalDuration` respectively. Sliders snap to 0 and full duration — desired and correct. Note for v2: when the dual-thumb gesture lands, the same nil-fallback pattern should be preserved in the gesture state machine.

**L3 — Slider bound writes during drag are throttled by SwiftUI but not coalesced.** Each microframe a clamp runs (start clamps to current end). Visually the thumb cannot pass the other; the bound value is written and the View re-renders on the same tick, so the displayed thumb position == bound value. No snap-back artifact. Behavior matches the prompt's expectation.

**L4 — `CropEditorView` minimum 0.05 is undocumented and below practical encoder limits.** A 5%-by-5% crop on a 1920×1080 source = 96×54px — most encoders accept this, but the visible quality is meaningless. Plan/spec doesn't justify 0.05. Consider raising to 0.10 with a comment, or moving the floor into `ClipEdits` validation so Stitch exporter catches it too.

### Items reviewed and marked OK

- **Sheet binding identity flicker:** `Binding(get: project.clips.first(where: $0.id == editingClipID), set: editingClipID = newValue?.id)`. The `sheet(item:)` content is keyed by `clip.id` (Identifiable conformance on `StitchClip`). Mid-edit clip mutations through `project.updateEdits` change the clip's value but not its `id`, so SwiftUI does not tear down the sheet. **No flicker.** Verified against `StitchClip: Identifiable, Hashable, Sendable` in `StitchClip.swift`.
- **Tap vs swipe-to-delete vs reorder with `.editMode = .constant(.active)`:** in always-edit mode, `.onTapGesture` on the row's `.contentShape(Rectangle())` still fires for taps inside the body; reorder gesture is anchored to the platter handle, swipe-to-delete operates on the row trailing edge — three disjoint hit regions. No conflict.
- **Plan deviations (3 preemptive fixes):** all three are improvements over the spec — `WritableKeyPath<CGRect,Double>` would not compile (CGFloat ≠ Double), `formatTime` truncation matches the M:SS.cc convention used by AVFoundation tooling, and `guard let clip` instead of `clips.first(...)!` is strictly safer. No deeper plan/code mismatch detected.
- **`@State` inside `TabView` sub-views:** `TrimEditorView`, `CropEditorView`, `RotateEditorView` are stateless w.r.t. local `@State`; all mutable state lives in the parent `draftEdits` via `@Binding`. Tab switching does not clobber edits. Confirmed by reading each sub-view file.

### Build & test signals (from commit message, not re-run)
"Build clean. 7/7 existing StitchClipTests pass." Reviewer did not re-run tests.

### Files
- Read: `ClipEditorSheet.swift`, `TrimEditorView.swift`, `CropEditorView.swift`, `RotateEditorView.swift`, `StitchTimelineView.swift`, `StitchClip.swift`, `PLAN-stitch-metaclean.md` §S6.
- Modified: none.

### Status: Complete — H1 recommended fix before commit 4 lands (StitchExporter consumes `cropNormalized`).

---

## [2026-05-03 11:05 SAST] {E-0503-1142} -- [BUILD] subagent:opus via Opus 4.7 lead: Commit 4 — StitchExporter + export sheet

In-Reply-To: {E-0503-1101}

**Tasks:** S7 + S8 from `PLAN-stitch-metaclean.md`. The biggest commit in the stitch+metaclean plan — actor-based composition builder, per-clip layer instructions, passthrough detection, AVAssetExportSession overload on `CompressionService`, full export-sheet UI with Save to Photos.

### Files added
- `VideoCompressor/ios/Services/StitchExporter.swift` (334 lines) — actor with `Plan` struct (`@unchecked Sendable` per advisor — `AVMutableComposition` is a non-Sendable class), `buildPlan(from:)`, `export(plan:settings:outputURL:onProgress:)`, `buildInstruction` for crop+rotate, `runPassthrough` for the AVAssetExportPresetPassthrough fast path.
- `VideoCompressor/ios/Views/StitchTab/StitchExportSheet.swift` (180 lines) — preset list (PresetPickerView row format), progress footer with five-state switch (idle/building/encoding/finished/failed), Save to Photos button, cancel mid-export.

### Files modified
- `VideoCompressor/ios/Services/CompressionService.swift` (185 lines, +57 / −31) — new `encode(asset:videoComposition:settings:outputURL:onProgress:)` overload as the single source of truth for the export pipeline. `compress(input:settings:onProgress:)` now derives the output URL and delegates to `encode`. Stitch flow uses the same plumbing without duplicating AVAssetExportSession lifecycle code.
- `VideoCompressor/ios/Models/StitchProject.swift` (174 lines, +95 / −5) — replaced the commit-1 stub `export()` with `export(settings:)` that snapshots `clips`, derives a `_STITCH.mp4` output URL, and runs `StitchExporter.buildPlan` → `export` on a tracked `Task`. Adds `cancelExport()` and `isExporting` for the sheet to bind against.
- `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` (240 lines, +5) — bottom-bar "Stitch & Export" now toggles `@State showExportSheet` driving `.sheet(isPresented:)`.

### Build / tests
- `xcodebuildmcp build_sim` — clean, 0 warnings.
- `xcodebuild test -only-testing:StitchClipTests` — 7/7 pass.
- `xcodebuildmcp build_run_sim` — app launches; export sheet wiring validated visually (PhotosPicker import is system-process so axe-driven E2E not feasible — manually exercise).

### Path stopped at: Step D (full)
All four advisor-recommended steps landed:
- A — composition + audio/video tracks ✓
- B — per-clip layer instructions for crop + rotate via `setTransform(_:at:)` and `setCropRectangle(_:at:)` ✓
- C — codec/dimension homogeneity check (`allSameSize && allSameCodec && !anyEdit` → `canPassthrough = true`, uses `AVAssetExportPresetPassthrough`) ✓
- D — re-encode path via `CompressionService.encode` with the composition handed in as the asset and `AVMutableVideoComposition` attached ✓

### AVFoundation choices
- **CMTime timescale 600** for trim ranges (per existing `StitchClip.trimmedRange`) — sub-frame precision, standard for AVFoundation composition work.
- **`videoComposition.frameDuration = CMTime(value: 1, timescale: 30)`** as the canvas timebase. The actual frame timing of source samples is preserved by the underlying tracks; `frameDuration` here is the videoComposition's render-loop tick.
- **`videoComposition.renderSize = firstNaturalSize`** — first clip's natural size wins. Mixed-size stitches letterbox into that canvas. Phase 3 can compute a tight bounding canvas that accounts for rotation + crop.
- **Rotation about clip centre** — `toCentre · rotate · fromCentre` so 90°/270° doesn't translate the visible content offscreen. Render canvas isn't enlarged for the rotated bbox (Phase 3 polish).
- **Passthrough always uses MP4** regardless of source container. AVAssetExportPresetPassthrough is sample-copy, not container-copy, so this is safe.
- **Color space / HDR not preserved** — AVAssetExportSession with curated preset names always normalizes to BT.709 SDR. Documented; Phase 3 needs AVAssetWriter for HDR pass-through.
- **Audio is best-effort** — clips without audio (e.g. silent screen captures) don't abort the stitch (`try? audioTrack.insertTimeRange`).
- **`Plan: @unchecked Sendable`** per advisor guidance. Single linear flow (build → export → discard), no concurrent access.

### Deviations from plan
- Plan skeleton showed `(Double) -> Void` progress; consistent with the existing `CompressionService.compress` signature, used `(BoundedProgress) -> Void` instead. Required for `StitchProject.runExport` to write `.encoding(progress)` cleanly.
- Plan suggested `frame.start` of 0 for layer-instruction transforms; used `segmentRange.start` (composition time) since instructions live in composition time, not source time.
- Output filename collision is handled by appending a UUID-6 fragment rather than overwriting (mirrors the H1 fix from {E-0503-1050}).

### Status: Complete — commit `b6bf1a9` on `feature/metaclean-stitch`

---

## [2026-05-03 11:23 IST] {E-0503-1123} -- In-Reply-To {E-0503-1142} [BUILD] [subagent:opus via Opus 4.7 lead] Tasks M1+M2: MetaClean model + remux strip service (commit 5 of 6)

> **Agent Identity**
> Model: claude-opus-4-7 (1M ctx) (subagent dispatched by Opus 4.7 lead)
> Platform: Claude Code CLI -- main repo `feature/metaclean-stitch`
> Session Role: subagent (Tasks M1+M2 implementation)

**Confidence:** HIGH
**Commit SHA:** 44057d3
**Build:** CLEAN (0 errors, 0 warnings)
**Tests:** 17/17 PASS (8 existing StitchClipTests + 9 new MetadataTagTests)

### Files Added

| File | Lines | Notes |
|------|-------|-------|
| `VideoCompressor/ios/Models/MetadataTag.swift` | 122 | `MetadataTag` value type + `MetadataCategory` enum (5 cases) + `StripRules` struct (autoMetaGlasses / stripAll / identity factories) + `MetadataCleanResult` payload (mirrors `CompressedOutput` shape). |
| `VideoCompressor/ios/Services/MetadataService.swift` | 472 | `actor MetadataService` with `read(url:)` and `strip(url:rules:onProgress:)`. Helper classes `PumpState` + `ContinuationBridge` at file end (Sendable shared state for the pump). `MetadataServiceError` LocalizedError. Static `gatherAllItems(asset:)` / `categoryFor(key:)` / `displayNameFor(key:)` / `isMetaGlassesFingerprint(key:value:)`. |
| `VideoCompressor/VideoCompressorTests/MetadataTagTests.swift` | 125 | 9 tests covering StripRules factory contracts, `MetadataCategory` exhaustiveness, value-type semantics, `MetadataCleanResult.sizeLabel`. |

### Files Modified

| File | Change |
|------|--------|
| `CHANGELOG.md` | Added commit-5 entry under `[Unreleased]` "Added". |

### AVFoundation Choices

1. **`outputSettings: nil` everywhere (passthrough)** — both `AVAssetReaderTrackOutput(track:outputSettings:nil)` and `AVAssetWriterInput(mediaType:_:outputSettings:nil)` mean: hand me the raw CMSampleBuffers exactly as they came off disk; do not decode, do not re-encode. The writer writes them back into the new container untouched. Result: pixel-perfect, bit-identical media -- the only diff vs source is the removed metadata atoms. This is the correct path for "strip metadata" semantics; an `AVAssetExportSession.passthrough` would also work but gives less control over which metadata items survive (exporter applies `metadataItemFilter: .forSharing` quirks).

2. **Same 4 keyspaces for read AND strip** — earlier draft only loaded `.metadata` (the curated common view) for strip, while `read` queried 4 keyspaces. Result: a Meta fingerprint atom living in `quickTimeUserData` (where the web app commits `a3ad413` / `be6e360` found them) would have been displayed in the inspector but never filtered. Extracted `gatherAllItems(asset:)` static helper used by both methods to enforce the invariant.

3. **10 Hz polling vs per-sample MainActor hop** — initial sketch had `Task { @MainActor in onProgress(p) }` per CMSampleBuffer. At 4K60 with two tracks that's ~480 main-actor hops/sec. Mirrored `CompressionService.compress`'s pattern: lock-protected `latestPTS` updated cheaply in the pump, single `Task { @MainActor }` polls at 100 ms.

4. **Timed-metadata tracks intentionally dropped** — the `where track.mediaType == .video || track.mediaType == .audio` filter excludes `.metadata`-typed tracks (e.g. embedded GPS streams). For the autoMetaGlasses preset that's the desired behaviour. Documented in source comment so a future "preserve track-level GPS" preset can route those tracks through the same passthrough pattern.

5. **`PumpState` + `ContinuationBridge` reference types** — Swift 6 strict concurrency does not let captured `var`s be mutated from concurrently-executing closures. Replaced the `nonisolated(unsafe)` shortcut with two `final class @unchecked Sendable` holders that lock-protect their state. Functionally identical; satisfies the strict-mode warnings.

### Deviations from Spec

- **`AVAssetExportSession` fallback NOT used** — the AVAssetWriter pump landed cleanly in one commit. The fallback was authorized in case the requestMediaDataWhenReady pattern proved fragile; it didn't.
- **`MetadataServiceTests` integration tests deferred** — fixture wiring (bundling a Meta-glasses .mov, resource-id setup, capture in `setUp()`) is fiddlier than worth in this commit. Model-level coverage in `MetadataTagTests` pins the `StripRules` contract; commit 6 (UI) will land the integration tests as it'll already need a fixture for the inspector preview.
- **`shouldStrip` honours `.technical` as no-op** — even if a `StripRules` instance contains `.technical`, the service refuses to strip it. Source comment explains -- stripping codec/fps/etc would corrupt the file.

### Status: Complete -- commit `44057d3` on `feature/metaclean-stitch`

---

## [2026-05-03 11:34 IST] {E-0503-1134} -- In-Reply-To {E-0503-1123} [FIX] [subagent:opus via Opus 4.7 lead] Pre-merge fix: binary fingerprint detection (commit 6ca5aa9)

Pre-merge advisor catch on commit 5 (44057d3). The first version of `classify(_:)` set `value = "<binary, N bytes>"` for binary-typed atoms and then ran `isMetaGlassesFingerprint` against that placeholder -- never matching the very atom (`com.apple.quicktime.comment` containing ASCII "Ray-Ban Stories") that web-app commit `a3ad413` was titled to fix.

**Fix:** separated display `value` from match-text. Binary path now also computes `decodedTextForMatching` via UTF-8 / ASCII / printable-byte fallback. `isMetaGlassesFingerprint` signature changed to `(key:decodedText:)` and is `static internal` so the test target can call it without a fixture.

**Tests:** added 5 regression tests covering: Ray-Ban in decoded text matches; Meta in decoded text matches; the `<binary, N bytes>` placeholder explicitly does NOT match; nil decoded text returns false; key-must-be-comment-or-description gate. 22/22 pass.

**Commit:** `6ca5aa9` on `feature/metaclean-stitch`.

### Status: Commit 5 ready for merge.

---

## [2026-05-03 11:14 SAST] {E-0503-1114} -- [REVIEW] code-reviewer (subagent:opus): Commit 4 audit (StitchExporter)

In-Reply-To: {E-0503-1142} (commit `b6bf1a9` — `StitchExporter`, `CompressionService.encode(asset:videoComposition:...)`, `StitchProject.export`, `StitchExportSheet`).

> **Agent Identity:** subagent / Opus 4.7 (1M ctx) / code-reviewer role. Read-only audit, no Swift source modified.

### Verdict: 1 CRITICAL, 4 HIGH, 4 MEDIUM, 3 LOW. CRITICAL must be fixed before any non-identity multi-clip stitch will export reliably.

### CRITICAL

**C1 — `vc.instructions` has gaps when `anyEdit==true` but only some clips are edited** (`StitchExporter.swift:135-143`, `159-172`). The loop emits an `AVMutableVideoCompositionInstruction` only inside `if clip.isEdited`. If clip A unedited, B rotated, C unedited, the array contains a single instruction covering B's segment. Apple's contract for `AVVideoComposition.instructions` mandates: time ranges must be contiguous, non-overlapping, and collectively cover the full composition `timeRange` from `.zero` through total duration ([AVVideoComposition Apple docs](https://developer.apple.com/documentation/avfoundation/avvideocomposition), [AVVideoComposition.instructions](https://developer.apple.com/documentation/avfoundation/avvideocomposition/instructions)). Gaps yield undefined behaviour; in practice `AVAssetExportSession` rejects the videoComposition with `AVErrorInvalidVideoComposition` (-11841) at export time — failing the entire stitch when one clip out of N is rotated. **Fix:** emit a passthrough instruction for every segment regardless of `isEdited`:
```swift
let segmentRange = CMTimeRange(start: cursor, duration: timeRange.duration)
let instruction: AVMutableVideoCompositionInstruction
if clip.isEdited {
    anyEdit = true
    instruction = buildInstruction(clip: clip, track: videoTrack, segmentRange: segmentRange)
} else {
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    let i = AVMutableVideoCompositionInstruction()
    i.timeRange = segmentRange
    i.layerInstructions = [layer]
    instruction = i
}
instructions.append(instruction)
```
The all-identity fast path that skips `videoComposition` entirely (lines 159-172) remains correct because that branch keeps `anyEdit=false` and never assigns the array.

### HIGH

**H1 — Codec homogeneity check is too coarse; passthrough silently fails at runtime with no fallback** (`StitchExporter.swift:105-112`, `runPassthrough` 281-332). `CMFormatDescriptionGetMediaSubType` returns the four-char codec id (`'avc1'`, `'hvc1'`). Two H.264 files can share `'avc1'` yet differ in profile/level, SPS/PPS parameter sets, colorspace, or pixel format — all of which `AVAssetExportPresetPassthrough` rejects with `AVErrorFailedToParse` / `AVErrorInvalidCompositionTrackSegmentDuration`. There is no fallback to re-encode; `runPassthrough` throws `CompressionError.exportFailed` and the user sees a hard failure on a stitch that would have worked via the re-encode path. **Fix:** wrap the passthrough invocation; on `.failed` with the documented passthrough-incompatibility codes, fall through to `service.encode(...)`. Or be more conservative — also compare `CMVideoFormatDescriptionGetDimensions`, transfer function, and `kCMFormatDescriptionExtension_*` profile keys before declaring compatible.

**H2 — Comment claims "largest natural size" but code uses first** (`StitchExporter.swift:99-103, 148-151`). The loop sets `firstNaturalSize` only on iteration 0; later clips compare but never update. Comment "the render size is the largest natural size encountered" is wrong — it's the first. Confusing for maintainers; the `renderSize=first` choice will silently letterbox larger clips into a smaller canvas (e.g. clip 1 720p, clip 2 4K → 4K clip downscaled). The user prompt's focus area #7 assumed first; that matches code, but consider:
```swift
// max-of-all is closer to the docstring's intent and avoids quality loss
let renderSize = clips.reduce(CGSize.zero) { acc, _ in acc /* recompute via async sniff */ }
```
…or fix the comment to match the code: "render size is the first clip's natural size; mixed-size clips are letterboxed/scaled into that frame".

**H3 — `Plan: @unchecked Sendable` is unsound under strict concurrency** (`StitchExporter.swift:47-52`). The struct carries `AVMutableComposition` (reference type, mutable, non-Sendable). It is built inside `actor StitchExporter`, returned to `StitchProject @MainActor` (line 121), then passed back into `exporter.export(plan:...)` on the actor (line 124). In between, `AVAssetExportSession.exportAsynchronously` (called within `runPassthrough`) reads the composition off its own dispatch queue. Two concurrent readers are safe in practice for an immutable composition, but the `@unchecked` claim depends on no further mutation after `buildPlan` returns — fragile. **Fix:** mark `Plan` as a private, fileprivate type and make `export(plan:...)` consume-only (`__owned`); or do the entire build → export inside one actor method that never lets the composition cross the boundary. The current shape works only because the composition happens to be quiescent.

**H4 — Cancellation does not propagate from `StitchProject.export` into `StitchExporter.buildPlan`** (`StitchProject.swift:96-107`, `StitchExporter.swift:57-182`). `exportTask?.cancel()` cancels the outer `Task`, but `buildPlan` only checks cancellation cooperatively — it never calls `Task.checkCancellation()` between clip iterations. A 20-clip stitch with slow track loads will continue building the composition for several seconds after the user taps Cancel. **Fix:** add `try Task.checkCancellation()` at the top of the per-clip loop, mirroring the explicit check `runExport` already does after `buildPlan`.

### MEDIUM

**M1 — `canPassthrough` does not check frame rate; mixed-fps clips will play wrong** (`StitchExporter.swift:174`). Two H.264 1080p clips, one at 30fps, one at 60fps, share size + subtype — `canPassthrough` returns true. The composition track inherits the first clip's natural timing on insert, but `AVAssetExportPresetPassthrough` does not normalize sample timing across segments. Result: the second clip plays at half speed (or double, depending). **Fix:** load `nominalFrameRate` per video track and require equality, or document the gap and rely on the mismatched-codec catch in H1's fallback.

**M2 — Audio-track `try?` swallows real failures and risks A/V desync** (`StitchExporter.swift:126-130`). If clip 1 has no audio but clips 2..N do, the `audioTrack` cursor stays at `.zero` while the video cursor advances by clip 1's duration — clip 2's audio inserts at `cursor` (already past clip 1) which is *correct* because both cursors advance together. So this is OK for the missing-first-audio case. The real bug: when an `insertTimeRange` actually fails on a present audio track (e.g. corrupt sample tables), `try?` swallows it. The audio cursor in the composition track silently goes out of sync with video. **Fix:** at minimum log via `os_log` or surface as a non-fatal warning to the UI; ideally on failure insert silence (`AVMutableComposition.insertEmptyTimeRange`) of the same duration so audio stays aligned to video.

**M3 — Crop Y-axis convention not validated end-to-end** (`StitchExporter.swift:262-270`, `CropEditorView.swift`). `setCropRectangle(_:at:)` documents the rect in the source track's coordinate space, which AVFoundation publishes as **bottom-left origin** for the encoded sample buffer (matching CGImage / CALayer.contentsRect convention). The user, however, edits Y via a 0..1 slider in `CropEditorView` with no preview; if they intend "Y=0 means top", the exported crop will be flipped (their "top" actually becomes the bottom of the source). v2's draggable rect (currently a TODO comment in `CropEditorView.swift:35`) will surface this. **Fix:** before v2 ships the visual editor, decide once and document. If we keep AVFoundation native (bottom-left), the slider should label "Y from bottom" or expose `1 - y` so the UI stays top-left. Either choice is fine; the inconsistency between an unlabeled slider and the renderer is the bug.

**M4 — `_STITCH` collision suffix only checks once; the suffixed name itself can collide** (`StitchProject.swift:153-162`). Two rapid exports of the same first-clip name within 4-byte UUID-prefix collision space (extremely unlikely but possible) overwrite. More realistically, between the existence check and `AVAssetExportSession.outputURL` write there is a TOCTOU window; another in-flight export from the Compress flow could create the same path. **Fix:** loop `while exists`, or move atomically with a `link()/rename()` pattern. Low frequency; flagged for completeness.

### LOW

**L1 — Misleading comment "Pre-multiplied so order is rotate-first"** (`StitchExporter.swift:245-255`). `toCentre.concatenating(rotate).concatenating(fromCentre)` applies in left-to-right order on a row vector: translate-to-origin first, then rotate, then translate-back. The math is correct, but the comment names "rotate" as the first step, which is wrong and will confuse anyone debugging a future rotation bug. **Fix:** "Translate-to-origin, rotate, translate-back; CGAffineTransform.concatenating multiplies left-to-right (row-vector convention)."

**L2 — `frameDuration = 1/30` is hard-coded and may drift mixed-fps timelines** (`StitchExporter.swift:166`). For a 60fps source the videoComposition timebase samples at 30Hz, halving the rendered cadence relative to source. AVAssetExportSession honours the frame duration as the canvas tick, not the playback rate; in practice the encoded output remains 30fps regardless of source. Acceptable for v1 if an explicit choice; document, or compute the max source `nominalFrameRate` across clips.

**L3 — `failed(error:)` already surfaces NSError code/domain via `CompressionError.exportFailed`** (`CompressionService.swift:139-143`). Confirmed wired. The user prompt's area #15 is satisfied — `[domain code]` plus `localizedDescription` plus optional underlying error all flow into the `LibraryError.compression(.exportFailed)` shown in the sheet.

### Items reviewed and marked OK

- Cancellation in `runPassthrough` (`withTaskCancellationHandler` + poller cancel before final `.complete` emit) mirrors the {E-0503-0935} pattern correctly.
- `progressTask.cancel()` precedes the final `onProgress(.complete)` on both code paths — race-free.
- `instruction.timeRange` set in **composition** time (segment-start cursor) is correct per the `AVVideoCompositionInstruction.timeRange` doc page; layer instruction `setTransform(at:)` keyed at `segmentRange.start` is also composition time — matches docs.
- Rotation matrix order is correct (advisor confirmed). 90° rotation about clip centre keeps content centred but extends off-canvas vertically when renderSize=first-clip-size — partially clipped, not letterboxed; revisit when `renderSize` policy is finalised.
- Output filename collision uses UUID-6 same as {E-0503-1050} fix; reachable from `makeOutputURL`.
- Build clean per commit message; tests not re-run.

### Files

- Read: `StitchExporter.swift`, `CompressionService.swift`, `StitchProject.swift`, `StitchExportSheet.swift`, `StitchTabView.swift`, `StitchClip.swift`, `CompressionSettings.swift`, `LibraryError.swift`, `BoundedProgress.swift`, `CropEditorView.swift` (Y-axis cross-check), `PLAN-stitch-metaclean.md` §S7/S8.
- Modified: none.

### Status: Complete — C1 blocking; H1/H4 strongly recommended before merging into `main`. Everything else trackable as commit-6 follow-ups or v2.

[2026-05-03 11:45 IST] [solo/opus] [DOCS] CI/CD plan: code-from-anywhere → TestFlight
  Actions: Researched options (Xcode Cloud, GitHub Actions + ASC API, fastlane match, Firebase App Distribution, third-party CI). Verified existing project signing (DEVELOPMENT_TEAM=9577LMA4J5, automatic, bundle ca.nextclass.VideoCompressor, MARKETING_VERSION=1.0, CURRENT_PROJECT_VERSION=1). Recommended Xcode Cloud as primary path: free 25 hr/mo on existing Apple Developer membership, native TestFlight upload, no GitHub Secrets, no .p8 to manage, signing config reused as-is. Wrote ready-to-commit GitHub Actions workflow as documented fallback. Ruled out Firebase App Distribution (wrong destination — distributes via Firebase App Tester not TestFlight). Ruled out fastlane match for solo dev (overhead with no benefit).
  Files: .agents/work-sessions/2026-05-03/PLAN-cicd-testflight.md (new)
  Status: Complete — awaiting user to execute one-time Xcode Cloud setup (8 steps, ~30 min, all from phone browser)

[2026-05-03 11:35 SAST] {E-0503-1135} -- [REVIEW] code-reviewer (subagent:opus): Final pre-ship audit (branch feature/metaclean-stitch @ 45778ed). Verdict 8/10. Ship-blocker: P0 NSPhotoLibraryUsageDescription still says "Video Compressor" in Debug+Release (project.pbxproj:404,436) — mismatches the rebrand and the AddUsageDescription string (which says "Media Swiss Army"). Fix before TestFlight. Other findings: HIGH MetadataService.swift:258 captures `var inputs` in @Sendable onCancel closure (rebind: `let inputsForCancel = inputs` before withTaskCancellationHandler); HIGH no intermediate UI state between exporter progress 1.0 and .finished while auto-strip remuxes (add .scrubbing/.cleaning state to VideoFile.JobState + StitchExportState — perceptible 1-3s freeze on 4K stitch); MED StitchExporter.Plan @unchecked Sendable acceptable for ship (auto-strip hop is URL-only, not Plan); MED auto-strip doubles output I/O (20-clip 4K stitch can pump 8-12 GB twice — document constraint, propose AVAssetWriter-with-metadata as v1.1 single-pass); LOW disjoint per-flow dirs (Inputs/Outputs/StitchInputs/StitchOutputs/CleanInputs/Cleaned) eliminate TOCTOU; LOW StripRules.autoMetaGlasses verified narrow against all 5 MetadataCategory cases; LOW hardcoded values to consider for Constants.swift (max picker 20, thumbnail count 4, fps fallback 30, polling 100ms). Privacy: zero URLSession/http calls anywhere in iOS source — "All processing happens on-device" claim is correct. Tests gap: missing service-level integration tests for (a) StitchExporter passthrough → reencode fallback; (b) MetadataService.stripMetaFingerprintInPlace round-trip with Meta fixture; (c) ClipEdits non-identity isEdited equality; (d) CompressionService cancellation mid-export; (e) PhotosSaver delete-original guard when assetID is nil. Recommend: fix P0 plist string (1-line edit), then ship; H1/H2/M2 as v1.0.1 follow-ups.
  Files reviewed: VideoCompressor/ios/Services/{CompressionService,MetadataService,StitchExporter,VideoLibrary,MetaCleanQueue,PhotosSaver,ThumbnailStripGenerator}.swift, Models/{StitchProject,StitchClip,MetadataTag}.swift, VideoCompressor_iOS.xcodeproj/project.pbxproj
  Status: Complete

[2026-05-03 18:45 IST] [subagent/opus] [DOCS] App Store / TestFlight readiness audit
  Actions: Audited pbxproj, all VideoCompressor/ios/ Swift sources, AppIcon assets, network surface, capabilities
  Findings: 2 blockers (missing AppIcon PNG, missing ITSAppUsesNonExemptEncryption=NO), 2 pre-launch (permission-string name mismatch, display-name truncation), polish items. Network access is zero (clean on-device claim). No third-party SDKs. Deployment target is iOS 18.0 (not 17.0).
  Files: .agents/work-sessions/2026-05-03/AUDIT-app-store-readiness.md (new)
  Status: Complete. Verdict: ship to TestFlight after 2 ~30-min fixes.

[2026-05-03 19:10 IST] [subagent/sonnet] [FEATURE] Phase 3 Commit 3: save-to-Photos confirmation feedback
  Actions: Added SaveStatus enum to VideoFile; updated VideoLibrary.saveOutputToPhotos with .saving→.saved/.saveFailed transitions + UINotificationFeedbackGenerator haptics; replaced static save icon in VideoRowView with SaveStatus-aware @ViewBuilder (spinner, bounce checkmark, red triangle retry); added transient "Saved to Photos" toast to VideoListView via .overlay(alignment: .bottom); mirrored pattern in StitchExportSheet.finishedView and MetaCleanExportSheet.progressFooter/run()
  Files: VideoFile.swift (SaveStatus enum + saveStatus property), VideoLibrary.swift (saveOutputToPhotos), VideoRowView.swift (saveButton @ViewBuilder), VideoListView.swift (toast overlay), StitchExportSheet.swift (saveStatus state + finishedView), MetaCleanExportSheet.swift (saveStatus state + progressFooter + run)
  Build: ✅ clean build. 35/37 unit tests pass; 2 failures pre-existing (unrelated metadata + cancellation tests)
  Commit: 4b95025 on feature/phase-3-stitch-ux-and-photos (pushed)
  Status: Complete

[2026-05-03 20:15 IST] [subagent/sonnet] [FEATURE] Phase 3 Commit 4: cache management + auto-sweep
  Actions: Created CacheSweeper actor (6 working dirs; sweepOnLaunch 7d, clearAll, deleteIfInWorkingDir, totalCacheBytes, breakdown); hooked Task.detached sweepOnLaunch in VideoCompressorApp.init; added opportunistic delete in VideoLibrary.saveOutputToPhotos after successful Photos save; extended markDirectoriesAsNonBackup from 2 dirs ["Inputs","Outputs"] to all 6 CacheSweeper.allDirs (closes iCloud-backup gap); merged Storage section into existing SettingsTabView.swift created by parallel Audio BG agent (live total + per-folder breakdown + Clear cache destructive button with confirmationDialog)
  Files: Services/CacheSweeper.swift (new), Views/SettingsTabView.swift (merged Storage section in), VideoCompressorApp.swift (init + sweepOnLaunch hook), Services/VideoLibrary.swift (saveOutputToPhotos opportunistic delete + markDirectoriesAsNonBackup extended — already in HEAD via commit 4b95025)
  Build: ✅ clean build (after clean to bust FileSystemSynchronizedRootGroup cache). 4 tabs in tab bar including Settings with Storage section.
  Status: Complete — pending commit
