# Backlog — Phase 3 follow-ups

**Date logged:** 2026-05-03
**Source:** user direction during the stitch+metaclean execution session.

These items are deferred from the phase-2 plan (`../plans/PLAN-stitch-metaclean.md`)
and should be picked up in phase 3. Each is large enough to deserve its
own plan + agent team. Note them here so they don't fall on the floor.

---

## 1. Photos in the Stitch timeline (with configurable still duration)

**User direction (verbatim):**
> "for the stich tool i want to be able to add photos with a particualr time
> allowed (3 seconds default) but anywhere from 0.5 seconds to 10 seconds for
> photos would be nice with a little scroll wheel or something? even the
> video edit / clip / trip should be easiliy configurable by time with live
> preview of the start finish somehow if you want to get a team of agents to
> work on how to do that and implement it after, note it for now"

### Requirements
- Stitch timeline accepts both videos and stills (HEIC, JPEG, PNG).
- Each still has its own duration in [0.5 s, 10.0 s], default 3.0 s.
- Picker presents a scroll-wheel / stepper / wheel-style control inline on
  each photo's row to set duration without opening the full editor.
- The video trim/crop editor (commit 3 of phase 2) gains live preview of
  the in/out frames. Currently it's a dual-`Slider` with a numeric label;
  v2 should show the actual frame at trimStart and trimEnd as the user
  drags.

### Implementation sketch
- Extend `StitchClip` so `naturalDuration` and `naturalSize` can come from
  a still image (treat the still as a 1-frame clip). Add a new field
  `stillDuration: Double?` defaulting to nil for videos, 3.0 for stills.
- Update `StitchClip.trimmedRange` so for stills it returns
  `CMTimeRange(start: .zero, duration: stillDurationCMTime)`.
- `StitchExporter.buildPlan` gains a still-image branch: insert the image
  as a video track frame using `AVVideoCompositionCoreAnimationTool` or
  use `AVAssetWriterInputPixelBufferAdaptor` to write the still into a
  fixed-duration video segment that gets concat'd with the rest.
- `PhotosPicker` already supports `matching: .any(of: [.videos, .images])`
  — switch the import filter.
- New SwiftUI control: `DurationStepper` — `Slider` + numeric readout
  (or a `ScrollView` + `LazyHStack` of tick marks for the wheel feel).
- `TrimEditorView` v2: replace the static `formatTime` label with a
  `VideoPlayer` cropped to the in-frame; or use `AVAssetImageGenerator`
  for thumbnails at the in/out points refreshed at 10 Hz while dragging.

### Effort estimate
- Stills in timeline: M (1 d)
- Duration stepper UI: S (2-4 h)
- Live trim preview frames: M (1 d)
- Total: ~2.5 days. Best done as a 3-commit sequence: model + import,
  duration UI, live preview.

---

## 2. iOS Share Extension to receive batch from Photos / Files

**User direction (verbatim):**
> "it would be nice if i could batch select from my photo library a bunch of
> stuff and send it to the app for processing witih differnt functions
> (compress, stitch, metaclean) all as a batch job sending them there, is
> that easy to do? you know so the app shows up in my suggested app drawer
> after selecting and "sharing" or whatever the ios option is"

### Requirements
- App appears in the iOS Share Sheet when the user multi-selects videos
  in Photos and taps the share button.
- After tapping the app icon in Share Sheet, the user picks one of:
  Compress / Stitch / MetaClean.
- The selected videos route directly into the corresponding tab's queue.

### Implementation sketch
This is a separate **App Extension** target in the Xcode project, not a
view inside the main app. The pattern:

- Add a new target `MediaSwissShareExtension` (Share Extension template).
- Both the main app and the extension belong to an **App Group**
  (`group.ca.nextclass.MediaSwissArmy`) so they share a sandbox.
- The Share Extension's `ShareViewController.swift`:
  - Implements `SLComposeServiceViewController` or a custom SwiftUI view
    presenting the 3 buttons: Compress / Stitch / MetaClean.
  - On selection, copies each `NSItemProvider` payload (video URL) into
    the App Group's container under `Inbox/<destination>/<uuid>.mov`.
  - Calls `extensionContext?.completeRequest(returningItems:)` to dismiss.
- Main app on launch and on foreground:
  - Scans `Inbox/Compress/`, `Inbox/Stitch/`, `Inbox/MetaClean/`.
  - Moves any new files into the appropriate working dir
    (`Documents/Inputs/`, `Documents/StitchInputs/`, `Documents/CleanInputs/`).
  - Switches the TabView selection to the matching tab.
  - Triggers a refresh of the corresponding ObservableObject so the new
    items appear immediately.
- Info.plist on the extension declares `NSExtensionAttributes →
  NSExtensionActivationRule` with predicates:
  ```
  SUBQUERY (extensionItems, $item, SUBQUERY ($item.attachments, $a,
    ANY $a.registeredTypeIdentifiers UTI-CONFORMS-TO "public.movie")
    .@count > 0).@count > 0
  ```
  So it only appears for video shares (limit selection to ≤ 20 to match
  the in-app PhotosPicker cap).

### Constraints worth flagging
- Share Extension memory budget is tight (~120 MB on iPhone, often less).
  We can't decode video here; we MUST defer all work to the main app via
  the App Group inbox.
- The free Apple Developer account does not allow App Groups. User has
  the paid $99/yr account so this is fine.
- App Group capability needs to be enabled on the main app and the
  extension; new entitlement file required. The free target template
  generates this for you.
- Extension auto-launch of the main app: not directly supported, but we
  can use `extensionContext?.open(URL(string: "mediaswiss://...")!)` —
  custom URL scheme — to deep-link the user back into the main app on
  the right tab.

### Effort estimate
- New Xcode target + App Group setup: S (2-4 h)
- Share Extension UI + payload handoff: M (1 d)
- Main app inbox watcher + tab switching: S (2-4 h)
- Custom URL scheme + deep link: S (2-4 h)
- E2E test on real device: S (a few hours including paid-account
  certificate work)
- **Total: ~2 days**, best as one focused agent-team session.

---

## 3. Auto-strip Meta fingerprint everywhere (LANDED)

This was implemented in commit immediately after phase-2:
- `StripRules.autoMetaGlasses` narrowed to fingerprint-only.
- `MetadataService.stripMetaFingerprintInPlace(at:)` helper.
- Hooked into `VideoLibrary.runJob` (Compress) and
  `StitchProject.runExport` (Stitch).
- MetaClean tab default mode unchanged; it now narrowly removes only the
  fingerprint atom unless the user picks "Strip All".

---

## 3.5. Photos as first-class media (Phase 3 expansion)

**User direction (verbatim):**
> "i want photos to be a native feature of the app, compressing them
> (without reducing quality), and stitching. as well as removing stupid
> meta meta data sinc ethey take ownership of those photos too"

This subsumes and expands item 1 above. Photos should be operable across
all three tabs:

### Compress photos (without reducing quality)

- HEIC re-encode at the same effective quality is a no-op — Apple's HEIC
  encoder is already at the format's quality ceiling for source-resolution
  output. The win for "compress without losing quality" is:
  1. **Re-encode JPEG → HEIC** at quality 0.9-1.0 (HEIC is ~50% smaller
     than JPEG at equivalent perceptual quality).
  2. **Strip thumbnail and preview JPEGs** embedded in HEIC containers
     (Photos.app keeps a 320×240 preview alongside the full-res image —
     significant size for batch operations).
  3. **Optional resolution clamp**: 4K phone photos are usually 4032×3024
     (~12 MP). Phone-screen-suitable presets (5 MP, 8 MP) save material
     bytes with imperceptible loss.
- Implementation: `CGImageSource` + `CGImageDestination` with
  `kCGImageDestinationLossyCompressionQuality: 0.92` and
  `AVFileType.heic` as output. No new infrastructure; sits behind the
  same `CompressionSettings` shape (extend QualityLevel for stills).

### Stitch with photos

- See item 1 above.

### MetaClean for photos (HEIC / JPEG)

- CGImageSource exposes EXIF, IPTC, GPS, XMP, MakerNote, and (critically)
  Apple/Meta-specific dictionaries via:
  - `kCGImagePropertyExifDictionary`
  - `kCGImagePropertyTIFFDictionary`
  - `kCGImagePropertyGPSDictionary`
  - `kCGImagePropertyMakerAppleDictionary`
  - `kCGImagePropertyXMPData` (where Meta tends to embed ownership /
    "AI-generated" / image-source provenance fields per Adobe XMP and
    C2PA-related schemas)
- Strip via `CGImageDestinationAddImageFromSource` with a properties
  dictionary that explicitly nukes the offending keys. CGImage operations
  preserve pixel quality byte-for-byte if the source format is preserved.
- Heuristic for "Meta fingerprint" in stills: scan XMP packet for
  - `xmp.MetaAI`, `meta:`, `RayBan`, `c2pa`, `ManifestStore` markers
  - `kCGImagePropertyMakerApple` software-string contains "Meta" or
    "Ray-Ban"
- Implementation lives in a new `PhotoMetadataService` actor mirroring
  the existing `MetadataService` for video. Same `MetadataTag` /
  `StripRules` model — the inspector UI is unchanged.

### Effort estimate (additive on top of item 1)

- `PhotoMetadataService.read` + `.strip`: M (1 d)
- `PhotoCompressionService`: M (1 d)
- Routing: extend `VideoLibrary` to handle stills OR fork into a generic
  `MediaLibrary` (recommended): M (1 d, mostly type plumbing)
- Stitch with stills (item 1): M (1 d)
- **Total: ~4 days** for full photo parity. Best as a 4-commit phase 3
  sequence, executable by an opus agent team given the well-scoped
  AVFoundation / ImageIO surface area.

### Risks

- HEIC encoder availability — present on every iOS 17+ device but not
  on macOS Catalyst targets without explicit linking (irrelevant for
  iOS-only ship).
- Photos library returns HEIC files only when "Most Compatible" is OFF
  in iOS Camera settings; otherwise the Picker delivers JPEG. Detect
  format from the URL extension and branch.
- Live Photos: `.movie` Transferable returns the video sidecar but a
  Live Photo is two files (HEIC + MOV). v1 should treat as still and
  ignore the motion sidecar; document.

---

## 4. App rename (LANDED)

- Home-screen label: **Media Swiss Army** (CFBundleDisplayName).
- Compress tab navigation title: **Alkloihd Video Swiss-AK**.
- Bundle ID and Xcode product name unchanged
  (`ca.nextclass.VideoCompressor` / `VideoCompressor_iOS`) so the existing
  signing setup keeps working.

If user wanted these flipped, the change is two lines (one in the pbxproj,
one in `VideoListView.swift`).

---

## Phase 3 sprint suggestion

When ready to tackle phase 3, the sequence would be:

| # | Item | Effort |
|---|------|--------|
| 1 | App Group + Share Extension scaffold | S |
| 2 | Share Extension UI + main-app inbox handoff | M |
| 3 | Photos in Stitch (model + import filter + duration stepper) | M |
| 4 | Live trim preview frames (TrimEditorView v2) | M |
| 5 | Final phase-3 red team + TestFlight build | M |

Roughly one full day of agent time, plus user-side "open Xcode once to
add the Share Extension target" if XcodeBuildMCP can't scaffold one
(check via `xcodebuildmcp project-scaffolding scaffold-extension --help`
when phase 3 starts).

---

## 6. Trim editor live-preview behavior (Build 11 user spec)

User direction 2026-05-03 14:14:
> "for the stitch i guess let's add live preview of each clip when we
> click it to edit and trim so it auto plays from the start after each
> trim and if trimming the end it auto plays the last 2 seconds of the
> clip on movement that should be easy right? can we auto compact
> though after so you work more efficiently"

### Behavior
- **Tap a clip in the timeline** → editor sheet opens with an
  `AVPlayerViewController` (or custom `AVPlayer` view) docked at the top
  showing the clip.
- **Drag the trim-START handle**:
  - Player seeks to the new in-point on every drag tick
  - When user releases, player auto-plays from the new in-point
- **Drag the trim-END handle**:
  - Player seeks to `(newEndPoint - 2 sec)` on every drag tick
  - When user releases, player auto-plays the last 2 sec up to the new
    out-point, then stops
- "Easy" because `AVPlayer.seek(to:tolerance:)` + `play()` is two API
  calls. The slider-to-player wiring is small.

### "Auto compact" interpretation
Two possible reads — implement both, since they're cheap:
1. **Auto-dismiss editor on Done** — already does this in current build,
   confirm.
2. **Auto-apply edits live (no Done button needed)** — the parent
   `StitchProject.updateEdits` is called continuously as the user drags,
   not only on Done. Cancel discards a snapshot. This makes the workflow
   "drag, see result, drag again" without modal commits.

If unclear when implementing, default to interpretation #2 since it's
the more iMovie-like flow.

### Effort
M (~half day).
- Add `AVPlayerViewController` to TrimEditorView
- Wire seek-on-drag via Slider's `onChange`
- Auto-play on release via `Slider`'s editing-changed callback
- Live-apply edits to the parent project
- Visual: dock the player at the top of the editor sheet, sliders below

---

## 7. Save-to-Photos confirmation feedback (Build 12 user feedback)

User direction 2026-05-03 14:30:
> "When I press save to photos there's no indication it's saved to the
> gallery"

### Behavior
- After tapping save: trigger `UINotificationFeedbackGenerator.success` haptic
- Icon transitions: `square.and.arrow.down` → animated checkmark for ~2 sec → settled "saved" state (different icon: `checkmark.circle.fill` with green tint)
- Optional: thin toast at the bottom: "Saved to Photos" with a fade
- On error: same haptic but `.error` style + toast with reason

### Files to touch
- `Views/VideoRowView.swift` (Compress save icon)
- `Views/MetaCleanTab/MetaCleanRowView.swift` if there's a save action there
- `Views/StitchTab/StitchExportSheet.swift` for the stitch save button

### Effort
S (~30 min). Pure SwiftUI animation + haptic feedback.

---

## 8. Temp file lifecycle / cache management (Build 12 user feedback)

User direction 2026-05-03 14:30:
> "what happens to the temp files etc?"

### Current state
Files accumulate forever in:
- `Documents/Inputs/`        (Compress picker imports)
- `Documents/Outputs/`       (Compress encoder outputs)
- `Documents/StitchInputs/`  (Stitch picker imports)
- `Documents/StitchOutputs/` (Stitch encoder outputs)
- `Documents/CleanInputs/`   (MetaClean picker imports)
- `Documents/Cleaned/`       (MetaClean remux outputs)

`isExcludedFromBackup = true` is already set on Inputs + Outputs (per Build 5db2187).
Need to extend that to the 4 other dirs (StitchInputs/Outputs, CleanInputs, Cleaned).

### Sweep policy

**Auto-sweep at lifecycle hooks**:
- On successful save-to-Photos for a Compress item: delete `sourceURL` from Inputs/ (user has the original in Photos already, our copy is redundant)
- On row removal (already partially implemented): delete output too if it exists
- On app launch: enumerate all 6 dirs, delete files modified > 7 days ago

**Manual control**:
- Add a Settings tab (or attach to existing About / overflow menu) with:
  - Total cache size shown live
  - Per-folder breakdown (videos imported / compressed / stitch / cleaned)
  - "Clear cache" button → confirmation alert → wipe all 6 dirs

### Files to touch
- New: `Views/Shared/CacheManagerView.swift`
- New: `Services/CacheSweeper.swift` (actor; launch sweep + per-folder size enumerate)
- `VideoCompressorApp.swift`: hook `CacheSweeper.sweepOnLaunch()` in `init`
- Each `runJob` / `saveOutputToPhotos` post-flight: opportunistic deletion

### Effort
M (~half day). Mostly straightforward filesystem + UI.

---

## 9. Advanced mode + size preview (Build 12 user feedback)

User direction 2026-05-03 14:30:
> "have an advanced mode so we can see what will happen and the actual
> file size differences? WhatsApp seems to do a way better job and still
> preserves quality what can we do to improve the small"

### Standard mode improvements
On the preset picker sheet, for each preset row, show LIVE preview computed against the FIRST imported video's metadata:
- "Output: ~XX MB" using `CompressionSettings.bitrate(forSourceBitrate:) × duration / 8`
- "Codec: HEVC" or "H.264" (from `settings.videoCodec`)
- "Resolution: 1080p" (if downscaled) or "Source" (if .source)
- "Estimated time: ~Xm" (rough heuristic: 1 sec encode per 4 sec of 1080p HEVC source on modern phones)

### Advanced mode (new screen, accessed via "Advanced..." button below preset list)

Custom-tune section with these knobs:
- **Codec**: H.264 / HEVC pill picker
- **Bitrate** slider: 500 kbps → 50 Mbps (log scale)
- **Resolution** picker: source / 4K / 1440p / 1080p / 720p / 540p / 480p / custom (W×H)
- **Audio bitrate** slider: 64 / 96 / 128 / 192 / 256 / 320 kbps + Passthrough toggle
- **Encoder profile** pill: Baseline / Main / High (H.264) or Main / Main10 (HEVC)
- **Keyframe interval** slider: 1 sec / 2 sec / 4 sec
- Live size estimate at the top of the sheet, updates as user drags
- "Save as Preset" button → user-defined named preset shows in standard list

### Why WhatsApp looks better at small sizes
- HEVC instead of H.264 (1.5× more efficient at the same quality)
- Slightly slower encoder preset (medium vs fast) — Apple VideoToolbox doesn't expose this knob directly but can be approximated via `AVVideoExpectedSourceFrameRateKey` tuning
- 2-pass encoding for known target sizes (Apple's API doesn't expose 2-pass; workaround = run twice at different bitrates and pick the closer match)
- Tighter keyframe intervals (we use 60-frame GOP; WhatsApp tends to be 90-120 frame for static scenes)

For phase 3, just adopting HEVC + correct bitrate caps via Commit 1 will already close most of the WhatsApp gap. The Advanced knobs let power users go further.

### Files to touch
- New: `Views/AdvancedSettingsView.swift`
- `Views/PresetPickerView.swift`: add live size estimate per row + "Advanced..." button
- `Models/CompressionSettings.swift`: add a `.custom(...)` case OR a sibling `CustomCompressionSettings` struct for user-defined tuning
- `Services/CompressionService.swift`: ensure the encoder respects the custom values

### Effort
L (~1 day). Settings UI is straightforward; the live estimate calc is fast; the Advanced screen is the bulk of the work.

---

## Phase 3 commit ordering update (post-Build-12 testing feedback)

Inserting items 7, 8, 9 into the existing 7-commit plan from `../handoffs/HANDOFF-v2.md`:

| # | Commit | Source |
|---|---|---|
| 1 | AVAssetWriter + smart bitrate caps | original — running NOW |
| 2 | Audio Background Mode opt-in | original |
| 3 | Save-to-Photos confirmation feedback | NEW (item 7) |
| 4 | Cache management + auto-sweep | NEW (item 8) |
| 5 | Photos as first-class | original (item 3.5) |
| 6 | iMovie drag + live trim preview | original (items 5+6) |
| 7 | Advanced mode + size preview | NEW (item 9) |
| 8 | iOS Share Extension | original (item 2) |
| 9 | Multi-clip parallel encode | original |
| 10 | Final red team + sim E2E | original |

10 commits now, ~5-7 days agent time. All on the same `feature/phase-3-stitch-ux-and-photos` branch — no auto-deploy until everything green and merged.

