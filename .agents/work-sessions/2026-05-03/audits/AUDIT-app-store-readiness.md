# App Store / TestFlight Readiness Audit — Media Swiss Army

**Verdict:** **YES — after 2 fixes** (App Icon PNG + `ITSAppUsesNonExemptEncryption`). All other items are pre-public-launch or polish; TestFlight internal will accept the build today once those two land.

**Audited commit:** `45778ed` on `feature/metaclean-stitch`
**Bundle ID:** `ca.nextclass.VideoCompressor`  · **Display name:** "Media Swiss Army" · **Team:** `9577LMA4J5` · **Deployment target:** iOS **18.0** (not 17.0 — verified pbxproj L324, L381) · **Devices:** iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).

---

## Blockers (must fix before tapping Upload)

### B1. App Icon is empty (only `Contents.json`, no PNG)
- **Location:** `VideoCompressor/ios/Assets.xcassets/AppIcon.appiconset/`
- **Detail:** Only `Contents.json` is present (3 universal 1024×1024 slots: any/dark/tinted). No `.png` files.
- **Impact:** App Store Connect rejects archives missing the marketing icon ("Missing marketing icon — apps must include a 1024x1024px icon"). TestFlight uploads will be **rejected at the `altool`/Transporter validation step**, not on review.
- **Fix:** Drop a 1024×1024 PNG (no alpha, no transparency, sRGB) into the `.appiconset` and reference it from `Contents.json`. Generating dark + tinted variants is optional but recommended for iOS 18 — fall back to omitting those entries if unavailable. Use Bakery / Icon Set Creator / Figma export.

### B2. Encryption export-compliance flag not declared
- **Location:** pbxproj L402–L417 (Debug) / L434–L449 (Release) — `INFOPLIST_KEY_*` block.
- **Detail:** `ITSAppUsesNonExemptEncryption` is absent. Without it, every TestFlight upload prompts the "Export Compliance" form in App Store Connect before the build can be distributed. App uses only Apple-provided crypto (HTTPS/AVFoundation/Photos) which is exempt.
- **Fix:** Add to both Debug and Release build settings:
  ```
  INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
  ```
  This sets `ITSAppUsesNonExemptEncryption=false` in the generated Info.plist and silences the per-upload prompt.

---

## Pre-App-Store-submission (TestFlight will accept; fix before public launch)

### P1. `NSPhotoLibraryUsageDescription` still says "Video Compressor"
- **Location:** pbxproj L404 / L436. String: *"Video Compressor needs access to your Photos to import videos…"*
- **Fix:** Replace "Video Compressor" with "Media Swiss Army" so the system permission alert matches the app name the user sees on their home screen. Apple reviewers explicitly call out mismatches as "misleading metadata" (Guideline 2.3.7).

### P2. App display name truncates on home screen
- "Media Swiss Army" = 16 chars. iPhone home-screen labels truncate at ~12 chars → renders as "Media Swiss…" on most devices.
- **Fix (optional):** Either accept truncation, or set a shorter `CFBundleDisplayName` like `MSA`, `MediaSwiss`, or `Swiss Army`. Marketing name on App Store can stay "Media Swiss Army."

### P3. App Store Connect listing prep
- App description, keywords, support URL, privacy policy URL (required even for "no data collected" apps), 6.5"/6.9" screenshot sets, App Store category (Photo & Video).
- **Privacy nutrition label answers:** Data Not Collected; No Tracking; No Third-Party SDKs. (Verified by codebase scan — see N1.)
- **Privacy policy URL:** required field. Single static page on `nextclass.ca` saying "Media Swiss Army processes all media on-device. We collect no data." is sufficient.

### P4. Beta App Review for external testers
- Internal testers (up to 100, must be on the team in App Store Connect) install **instantly** — no review.
- External testers (public TestFlight link, up to 10,000) require a one-time **Beta App Review** (~24h, reuses App Review criteria). Resubmit only when changing what-to-test text or major version.

### P5. Bundle ID claim
- `ca.nextclass.VideoCompressor` may not yet be registered. Per `TESTFLIGHT.md`, register at <https://developer.apple.com/account/resources/identifiers/list> first. Reverse-DNS for `nextclass.ca` is unique to the user's team — should not collide. If it does, fall back to `ca.nextclass.MediaSwissArmy`.

---

## Network / Tracking / Capabilities (clean — no findings)

### N1. No network access
- Searched all Swift sources: zero `URLSession`, zero `URLRequest`, zero `http(s)://` literals. The single `URL(string:)` call (`VideoCompressor/ios/Views/VideoListView.swift:65`) is `UIApplication.openSettingsURLString` — opens iOS Settings, not the network. No third-party SDK imports (only Apple frameworks: SwiftUI, AVFoundation, AVKit, Photos, PhotosUI, UIKit, Combine, SwiftData, CoreImage, UniformTypeIdentifiers, VideoToolbox, os, CoreMedia, CoreGraphics).
- Apple-verifiable claim: "All processing happens on-device" holds.

### N2. No ATT / `NSUserTrackingUsageDescription` needed
- No advertising IDs, analytics SDKs, fingerprinting, or `AppTransportSecurity` exceptions. ATT prompt not required.

### N3. No entitlements file, no extra capabilities
- No `.entitlements` file present, and pbxproj declares no capabilities beyond defaults. Photos access is enabled solely via the `NSPhotoLibrary*UsageDescription` keys in Info.plist + the runtime `PHPhotoLibrary` API. Clean.

### N4. Other usage descriptions — none required
- No microphone, camera, location, contacts, calendar, motion, or local-network access. App correctly omits those `NS*UsageDescription` keys (declaring them without using the API is also a rejection vector).

---

## Polish (nice to have)

- **PL1.** Add a launch screen storyboard or Info.plist `UILaunchScreen` block with app branding — currently uses `UILaunchScreen_Generation = YES` (auto-generated blank screen). Apple accepts blank, but a branded one is friendlier.
- **PL2.** No hardcoded `/Users/rishaal` paths in Swift sources (verified). Safe for CI.
- **PL3.** iPad layout: `TARGETED_DEVICE_FAMILY = "1,2"` enables iPad. SwiftUI sheets/`NavigationStack` generally adapt, but worth a quick run on an iPad sim — verify the Stitch timeline and MetaClean tag inspector don't horizontal-clip in landscape on iPad.
- **PL4.** Mac Catalyst not enabled (correct — would force a separate review).
- **PL5.** iOS 18 floor: appropriate. App uses iOS 17+ async APIs (`AVURLAsset.load(_:)`, `loadTransferable`); iOS 18 floor is even safer. Consider lowering to 17.0 only if data shows >5% of target users are on iOS 17 and you want them.
- **PL6.** Tests target uses `IPHONEOS_DEPLOYMENT_TARGET = 18.0` consistent with app. Good.
- **PL7.** `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`. The TestFlight workflow needs `agvtool next-version -all` before each upload (already documented in `TESTFLIGHT.md`).

---

## Pre-submission Checklist (run once before first upload)

1. Drop 1024×1024 PNG into `Assets.xcassets/AppIcon.appiconset/` and update `Contents.json` `filename` keys.
2. Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;` to both Debug + Release in pbxproj (or set under Target → Info in Xcode).
3. Update `NSPhotoLibraryUsageDescription` string: replace "Video Compressor" with "Media Swiss Army".
4. Register `ca.nextclass.VideoCompressor` as App ID in `developer.apple.com` if not already.
5. Create the app record in App Store Connect with bundle ID `ca.nextclass.VideoCompressor`, name "Media Swiss Army" (claim — fall back to "Media Swiss Army Pro" if taken), category Photo & Video.
6. Add yourself + co-testers to TestFlight → Internal Testing.
7. Build a clean Release archive (`xcodebuild archive` per `TESTFLIGHT.md`); confirm no warnings, no missing-icon error.
8. `xcrun agvtool next-version -all` to bump build number.
9. Upload via Transporter or `altool`; wait ~10 min for processing email.
10. Test internal install on your iPhone before inviting others.
11. (External testers only) Fill in Beta App Review form: demo account = N/A, contact info, "What to Test" notes, sign-in not required.
12. Privacy nutrition label in ASC: select "Data Not Collected" and "Tracking → No."

---

## Sample TestFlight "What to Test" notes

```
Media Swiss Army v1.0 — first TestFlight build. Three tools, all on-device:

• Compress: tap +, pick a video from Photos, choose a preset (Small / Balanced /
  Max), and the compressed copy saves back to Photos with a _COMP suffix.
• Stitch: pick 2+ clips, reorder them by dragging, optional per-clip trim/crop/
  rotate, then export a single video to Photos.
• MetaClean: pick a video, see all metadata tags (GPS, dates, camera, device
  fingerprints), tap to remove the ones you don't want, save a clean copy.

Please report: any crashes, exports that hang past 5 minutes, Photos permission
prompts that look wrong, or visual glitches in the timeline editor. No accounts,
no sign-in, no network — if you see any network activity, that's a bug.
```

---

## Anticipated review-rejection categories + mitigation

| Category | Risk | Mitigation |
|---|---|---|
| 2.1 App Completeness — placeholder icon | **High** until B1 fixed | Ship real icon. |
| 2.3.7 Misleading metadata — name mismatch in permission string | Med | P1 fix. |
| 2.5.1 Private API / undocumented framework | None | Apple frameworks only. |
| 4.0 Design — minimum functionality | Low | Three distinct tools, real utility. |
| 5.1.1(i) Data collection without prompt | None | Collects nothing. |
| 5.1.2 Data minimization — Photos broad access | Low | Already justify in usage string + on-device claim. |
| 5.1.5 Location & health | None | Not used. |
| Encryption export compliance | Med until B2 fixed | Set flag = NO. |

---

**Bottom line:** ship-blocking work is ~30 minutes (icon + plist key + permission string copy edit). Everything else is pre-public-launch admin (App Store Connect listing, privacy policy URL) the user owns, not code.
