# Backlog — Phase 3 follow-ups

**Date logged:** 2026-05-03
**Source:** user direction during the stitch+metaclean execution session.

These items are deferred from the phase-2 plan (`PLAN-stitch-metaclean.md`)
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
