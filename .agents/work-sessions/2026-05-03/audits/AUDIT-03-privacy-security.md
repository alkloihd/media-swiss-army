# Audit 03 — Privacy & Security

**Date:** 2026-05-03
**Auditor:** subagent/opus
**Scope:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/VideoCompressor/` (iOS app)
**Mode:** READ-ONLY

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH     | 2 |
| MEDIUM   | 5 |
| LOW      | 4 |
| **TOTAL**| **11** |

**Headline:** the app is fundamentally well-designed for privacy. No network code, no analytics SDKs, no third-party dependencies, no hardcoded secrets, all processing on-device. The picker layer correctly uses out-of-process `PhotosPicker` for import; full-library `PHPhotoLibrary` access is only requested when actually writing/deleting. The principal gaps are *missing artefacts that Apple now requires* — a `PrivacyInfo.xcprivacy` privacy manifest and a few Info.plist refinements — plus one consequential scope creep on Photos read permission via `StitchClipFetcher`.

---

## Findings

### HIGH-1 — Missing `PrivacyInfo.xcprivacy` privacy manifest (Apple-required since 2024)

**Severity:** HIGH
**File:** `VideoCompressor/` (no file present)
**Evidence:** `find . -name "*.xcprivacy"` returns zero hits; `project.pbxproj` has no `PrivacyInfo.xcprivacy` reference.

Apple has required a privacy manifest since spring 2024 for any app that uses **Required Reason APIs**. The app uses several:

| API used | Source |
|----------|--------|
| `UserDefaults` (`CA92.1` reason category) | `Services/AudioBackgroundKeeper.swift:30`, `Views/SettingsTabView.swift:14`, `Views/PresetPickerView.swift:17` |
| File timestamps (`.contentModificationDateKey`) (`C617.1` / `0A2A.1` category) | `Services/CacheSweeper.swift:109,113` |
| `FileAttributeKey.size` reads — disk space query (`E174.1` reason) is borderline; size-of-our-own-files is fine, but App Store review increasingly flags any disk inspection. | `Services/VideoLibrary.swift:281, 307, 325`, `Services/CompressionService.swift`, etc. |
| `ProcessInfo.thermalState` — not in the Required Reason list, OK. | `Services/DeviceCapabilities.swift:75` |

Without a manifest declaring valid reason codes, App Store Connect will surface a privacy-manifest warning during submission and may auto-reject in the future.

**Fix:** Add `VideoCompressor/ios/PrivacyInfo.xcprivacy` (a plist) declaring:
- `NSPrivacyAccessedAPITypes` with entries for `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1` — access info from same app), `NSPrivacyAccessedAPICategoryFileTimestamp` (reason `C617.1` — display content to the person using the device), `NSPrivacyAccessedAPICategoryDiskSpace` (reason `E174.1` — write or delete file on user's device).
- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`, `NSPrivacyCollectedDataTypes = []` (the app collects nothing).
- Add the file to the app target in `project.pbxproj`.

---

### HIGH-2 — `StitchClipFetcher` quietly elevates Photos scope to read-by-default

**Severity:** HIGH
**Files:**
- `ios/Services/StitchClipFetcher.swift:32, 50`
- `ios/Models/StitchProject.swift:162` (call site)

`PHAsset.fetchAssets(withLocalIdentifiers:options:)` is a Photos library *read* operation. The current authorisation grant chain is:

1. App start: no Photos prompt.
2. PhotosPicker import: out-of-process picker — no app-side authorisation needed.
3. Save-to-Photos: `PhotosSaver.swift:52` requests `.addOnly`.
4. Save+delete: `PhotosSaver.swift:89` requests `.readWrite`.
5. **Stitch → Sort by Date Taken: calls `PHAsset.fetchAssets` directly with no preceding `requestAuthorization` call.**

If the user has never been prompted for `.readWrite` (i.e., they only ever used Compress + Stitch, never the delete-original flow), this fetch returns an empty result silently — that's not a security hole, but it's a UX bug masquerading as one. **More importantly, on iOS 16+ this call will lazily trigger the system to consult the current authorisation state, and if the user has previously authorised `.readWrite` for delete-original, this code will read `localIdentifier`s the user did not consent to expose to this code path.**

Comment on line 22 acknowledges this ("the user has limited Photos access and didn't grant this asset"). The real risk: after a future toggle flip in `PhotosSaver` or a partial revocation in iOS Settings, this is the path that silently "just works" by virtue of an incidental prior grant.

**Fix:** Before the `PHAsset.fetchAssets` call at `StitchClipFetcher.swift:32, 50`, gate on:
```swift
let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
guard status == .authorized || status == .limited else { return nil }
```
And ideally surface a one-line caption in the StitchTab's "Sort by Date Taken" UI: "Requires Photos access. Tap to grant." with a `requestAuthorization(for: .readWrite)` only on tap.

---

### MEDIUM-1 — `NSPhotoLibraryUsageDescription` unnecessarily broad — implies read access we don't take

**Severity:** MEDIUM
**File:** `VideoCompressor_iOS.xcodeproj/project.pbxproj:405, 439`
**Evidence:**
```
INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Media Swiss Army needs access to your Photos to import videos. When you opt in to delete the original after MetaClean, this access is also used to delete the original from your library. All processing happens on-device.";
```

`NSPhotoLibraryUsageDescription` is the prompt for **legacy full-library read access** (`PHAuthorizationStatus.authorized` for `.readWrite`). The string mentions "import" — but imports happen via out-of-process `PhotosPicker`, which **does not need this key at all**. The key is only needed for the `.readWrite` delete-original flow and for the `StitchClipFetcher` (HIGH-2 above). Saying "to import videos" misrepresents what we actually do, which can be flagged as a misleading purpose string in App Store review.

**Fix:** Rewrite to scope tightly to the delete operation: *"Media Swiss Army needs access to your Photos library to delete originals after MetaClean cleaning, only when you opt in. Import uses the system picker and does not require this access. All processing happens on-device."*

---

### MEDIUM-2 — `ITSAppUsesNonExemptEncryption = NO` declared, but unverified

**Severity:** MEDIUM
**File:** `project.pbxproj:404, 438`

`ITSAppUsesNonExemptEncryption = NO` is a legal declaration to US Bureau of Industry and Security via App Store. The app uses:
- AVFoundation H.264/HEVC encode (uses standard encryption indirectly via OS-provided codecs — exempt).
- ImageIO HEIC encode (same — exempt).
- `replaceItemAt` (uses OS-provided file APIs — exempt).
- No TLS, no `CryptoKit`, no custom crypto.

The declaration is **likely correct** but warrants a comment. If you ever add HTTPS networking (e.g., a Dropbox export), this becomes `YES` with `ITSEncryptionExportComplianceCode` required.

**Fix:** Add a one-line comment in the build config explaining why this is `NO` and a checklist: re-evaluate any time a network framework is imported.

---

### MEDIUM-3 — `UIBackgroundModes = audio` declared globally — Apple privacy-review risk

**Severity:** MEDIUM
**File:** `project.pbxproj:408, 442`

The app declares `UIBackgroundModes = audio` so `AudioBackgroundKeeper` (silent-loop trick for long encodes) can keep the app alive past iOS's ~30 s background ceiling. Apple's app review sometimes scrutinises this — the technique of playing silent audio to extend background life is a known pattern Apple has rejected for some apps.

The mitigation is in place (it's user-opt-in via `allowBackgroundEncoding` in Settings, default OFF) — but the Info.plist key is *always* set, so reviewers will see it. A reviewer who decides "this is a video encoding app, why does it need the audio background mode" can ask for a justification.

**Fix:** Two options:
1. **Recommended:** Delete the `audio` background mode entirely; rely on `UIApplication.beginBackgroundTask` (already used at `VideoLibrary.swift:253`). Users with multi-minute encodes lose the "background continuation" feature, but that's a fair trade for a faster App Store approval. Document in `Settings` UI: "Long encodes need the app foregrounded."
2. If the feature is essential: prepare a written justification for App Review explaining audio is used as a system signal to keep the encode running, no audio is actually played, the user opts in.

---

### MEDIUM-4 — `AudioBackgroundKeeper` does not deactivate audio session on encode failure

**Severity:** MEDIUM
**File:** `ios/Services/AudioBackgroundKeeper.swift:67-71`
**Evidence:**
```swift
private func stopAudio() {
    audioPlayer?.stop()
    audioPlayer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
}
```

`begin()` / `end()` is correctly refcounted. But the `defer` block in `VideoLibrary.runJob` (line 257-262) only runs when the function returns/throws normally. If the process is killed (e.g., out-of-memory during encode) the audio session stays active. Combined with MEDIUM-3, this means an OOM during a long encode could leave a silent audio session running until next launch — privacy-adjacent (the user sees the audio mode indicator) and a reviewer red flag.

**Fix:** Register a `UIApplication.willTerminateNotification` and `UIApplication.didReceiveMemoryWarningNotification` observer in `AudioBackgroundKeeper`; force-stop in either case. Also reset `refCount` and `audioPlayer` defensively in `begin()` if the audio session is somehow already active without our refcount knowing.

---

### MEDIUM-5 — `Documents/` working dirs are user-visible via Files.app — privacy leak surface

**Severity:** MEDIUM
**Files:**
- `ios/Services/VideoLibrary.swift:55-67` (creates `Documents/Inputs`, etc.)
- All 6 `CacheSweeper.allDirs` directories (`CacheSweeper.swift:28-32`)

Files in `Documents/` are exposed to the user via Files.app and via iTunes File Sharing if `LSSupportsOpeningDocumentsInPlace` or `UIFileSharingEnabled` is set (neither is, so file sharing is OFF). However, `Documents/` is **always** visible in the Files.app under "On My iPhone → Media Swiss Army" by default once the app has any `Documents/` content — and the app stores both `Inputs/` (user's source videos) and `Cleaned/` (post-strip) there.

This is *not* a sandbox escape, but it means a user who passes their phone to a friend can have all their imported / cleaned videos browsed via the Files app. For a privacy-focused app, this is a reasonable surprise to flag.

**Fix:** Move the working directories to `Application Support/` (also iCloud-backup-excluded with the same `setResourceValues` call you already make):
```swift
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
```
`Application Support/` is not user-visible in Files.app. `Documents/` should be reserved for content the user is intentionally creating/exporting. The non-backup flag is preserved.

---

### LOW-1 — `NSPhotoLibraryAddUsageDescription` could be more specific

**Severity:** LOW
**File:** `project.pbxproj:403, 437`
**Evidence:**
```
INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Media Swiss Army saves cleaned and compressed videos to your Photos library."
```

OK as written; could mention "and photos" since stills are now supported (Phase 3, `PhotoCompressionService`). User mentioned in the codebase comments that photos are now in scope. Minor.

**Fix:** *"Media Swiss Army saves cleaned and compressed videos and photos to your Photos library."*

---

### LOW-2 — `displayName` from PhotosPicker `suggestedName` is reflected back in user-visible toasts without sanitisation

**Severity:** LOW
**Files:**
- `ios/Services/VideoLibrary.swift:88, 105, 124-126` (uses `originalName?.replacingOccurrences(of: "/", with: "_")`)
- `ios/Services/VideoLibrary.swift:477` (error path uses `error.localizedDescription` — system-supplied, OK)

`suggestedName` is sanitised against `/` to prevent path traversal, but **other characters** that could affect the file system are not (`..`, `\0`, control characters, leading `.`). On iOS the sandboxed `Documents/Inputs` dir limits the blast radius — at worst a user could craft a Photos asset name that produces an unusual filename. Not exploitable today, but the sanitisation is incomplete.

**Fix:** Replace the inline sanitisation with a stricter helper:
```swift
let safe = originalName.map { name in
    let allowed = CharacterSet.alphanumerics
        .union(.init(charactersIn: " ._-+()"))
    return name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        .reduce(into: "") { $0.append($1) }
} ?? "video-\(UUID().uuidString.prefix(8))"
```
Cap length to ~120 chars too — extreme-length names in Photos library can produce filesystem errors.

---

### LOW-3 — `error.localizedDescription` from FileManager / AVFoundation surfaces system file paths in user-facing alerts

**Severity:** LOW
**Files:**
- `ios/Services/PhotosSaver.swift:65, 106, 121` — surfaces full-path errors
- `ios/Services/VideoLibrary.swift:286, 477` — same
- `ios/Services/CompressionService.swift` — many sites

`error.localizedDescription` on iOS file errors usually contains the offending URL path (e.g., `"The file "abc.mp4" couldn't be opened because there's no such file in /private/var/mobile/Containers/Data/.../Documents/Inputs"`). This leaks the sandbox container UUID into user-visible alerts. Not an external-facing leak (the user sees their own data), but combined with screenshot-sharing or accessibility recordings, the container UUID can become a stable identifier.

**Fix:** Wrap `error.localizedDescription` with a sanitiser that strips `/private/var/.../Containers/.../Data/Application/<UUID>/` prefixes, leaving only the relative path (`Documents/Inputs/abc.mp4`). One helper function, applied everywhere we put errors into `lastError`.

---

### LOW-4 — `kCGImagePropertyIPTCDictionary` strip is incomplete (PNG XMP not nulled, EXIF GPS via TIFF stays)

**Severity:** LOW
**File:** `ios/Services/PhotoMetadataService.swift:347-399` (`buildRemoveDict`)

The strip dict is comprehensive for **JPEG/HEIC** but PNG metadata is partly stored in `kCGImagePropertyPNGDictionary` (e.g., `tEXt`, `iTXt` chunks) which is **never nulled** here — meaning a malicious PNG with location embedded in `tEXt` would slip past `.location` strip. Also, EXIF GPS coordinates are typically stored under `kCGImagePropertyGPSDictionary` (correctly nulled at line 356) but a copy can also live in `kCGImagePropertyTIFFDictionary` under `GPSInfo` ifs the encoder put it there — the current code only nulls TIFF in `device` mode, not `location` mode.

**Fix:** Extend `buildRemoveDict`:
```swift
if rules.stripCategories.contains(.location) {
    dict[kCGImagePropertyGPSDictionary] = kCFNull as Any
    dict[kCGImagePropertyPNGDictionary] = kCFNull as Any  // PNG GPS via tEXt
}
if rules.stripCategories.contains(.custom) {
    dict[kCGImagePropertyPNGDictionary] = kCFNull as Any
}
```

---

## Confirmation of items that are CORRECT

For the record — these were checked and pass:

| Concern | Status |
|---------|--------|
| App Privacy compliance (network, analytics, third-party SDKs) | **PASS** — `grep` for `URLSession`, `URLRequest`, `URLSessionDataTask`, etc. returns zero hits. No third-party dependencies. The app makes zero network requests. App Privacy declaration should be: *Data Not Collected*. |
| Photos library scope — uses `PhotosPicker` (out-of-process)? | **PASS** — all four pickers (`VideoListView.swift:34`, `EmptyStateView.swift:21`, `MetaCleanTabView.swift:33,67`, `StitchTabView.swift:36,78`) use `PhotosPicker` with `selection:` only. No `photoLibrary:` parameter, so the system picker runs out-of-process. |
| File path safety — sandbox escape via untrusted URL? | **PASS** — sourceURLs come exclusively from `PhotosPickerItem.loadTransferable`, which only ever returns paths inside the app's tmp/Documents containers. `StitchProject.remove(at:)` (line 88-103) explicitly scopes deletion to `inputsDir.standardizedFileURL.path` prefix. `CacheSweeper.deleteIfInWorkingDir` (line 91-101) does the same. No production code constructs `URL(fileURLWithPath:)` from user input. |
| Hardcoded paths / secrets | **PASS** — `grep` for `/Users/`, `localhost`, `api[_-]?key`, `secret`, `Bearer ` returns zero hits in production code. (Tests use `/tmp/` fixtures, fine.) |
| Camera / Microphone usage descriptions accidentally triggered | **PASS** — no `AVCaptureDevice` import. `AVAudioSession.setCategory(.playback)` does NOT trigger the microphone permission; only `.record` / `.playAndRecord` would. The keeper's silent-audio loop is playback only. |
| Photos write scope `.addOnly` for save, `.readWrite` only for delete | **PASS** — `PhotosSaver.swift:52` uses `.addOnly` for plain save; `PhotosSaver.swift:88-89` correctly conditionalises on `originalAssetID != nil` to upgrade to `.readWrite` only when delete-original is opted in. |
| Meta-glasses fingerprint detection on-device | **PASS** — both `MetadataService.read/strip` (video) and `PhotoMetadataService.read/strip` (image) operate purely on `AVURLAsset` / `CGImageSource`. No network calls. The fingerprint marker list is hardcoded (`MetadataService.swift:467-472`, `PhotoMetadataService.swift:310-330`); detection logic is local string-matching. |
| App Group entitlements not set inappropriately | **PASS** — no `.entitlements` file exists; `grep` for `com.apple.security.application-groups` in `project.pbxproj` returns zero. No App Group is configured. (When share extension lands per backlog, this will need re-review.) |

---

## Recommended priority order for fixes

1. **HIGH-1** (privacy manifest) — required for App Store; trivial to add (~50 lines of plist).
2. **HIGH-2** (StitchClipFetcher gate) — small code change, fixes a real authorisation-elevation surprise.
3. **MEDIUM-3** (`UIBackgroundModes = audio`) — strategic; review with PM whether feature is worth the App-Review friction.
4. **MEDIUM-1** (Photo library purpose string) — five-minute edit, prevents review delay.
5. **MEDIUM-5** (move to `Application Support/`) — small refactor; tangible privacy win.
6. **MEDIUM-4** (audio session safety net) — defensive, low risk to add.
7. **LOW-1..4** — opportunistic clean-ups.

---

**End of audit.**
