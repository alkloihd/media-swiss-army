# Backlog: iOS Share Extension (Phase 3 Commit 7)

**Deferred from PR #3** — pbxproj surgery for a new target + App Group entitlement + Info.plist migration was deemed too high-risk to land alongside the encoding/UX changes. Opening as its own PR keeps the blast radius small if signing/entitlements break.

## Goal
Let users hit iOS Share from Photos / Files / any app and pipe one or more videos+images directly into Media Swiss Army's compress queue.

## Scope

### New Xcode target: `MediaSwissArmyShare`
- Bundle ID `com.alkloihd.videocompressor.share`
- Display name "Media Swiss Army"
- Min iOS 17.0, Team `9577LMA4J5`
- Standard iOS Share Extension — productType `com.apple.product-type.app-extension`
- Embedded into main app's `Embed Foundation Extensions` build phase

### Files
- `VideoCompressor/MediaSwissArmyShare/ShareViewController.swift` — handles attachments, copies to App Group inbox, fires `mediaswissarmy://share-pending` deep link, completes the request
- `VideoCompressor/MediaSwissArmyShare/Info.plist` — NSExtension config with NSExtensionActivationSupportsMovieWithMaxCount=20 + NSExtensionActivationSupportsImageWithMaxCount=20
- `VideoCompressor/MediaSwissArmyShare/MediaSwissArmyShare.entitlements` — `com.apple.security.application-groups = group.com.alkloihd.videocompressor`

### Main app changes
- Add same App Group entitlement
- Migrate from `INFOPLIST_KEY_*` build settings to a real `Info.plist` so the URL scheme `mediaswissarmy` can be registered. **Diff before/after carefully** — every previously-set INFOPLIST_KEY_* must be preserved (NSCameraUsageDescription, NSPhotoLibraryUsageDescription, NSPhotoLibraryAddUsageDescription, ITSAppUsesNonExemptEncryption=NO, UIBackgroundModes=[audio], CFBundleDisplayName, etc.)
- New `SharedInboxImporter` (already drafted in the original Commit 7 spec) drains the App Group inbox on `.onOpenURL` + every root `.onAppear`
- Wire imported videos into `VideoLibrary.importExternalURLs` and stills into `PhotoCompressionService.importExternalStills` (or similar)

### Risk areas
1. **pbxproj corruption** — adding a new PBXNativeTarget, PBXFileReference, PBXCopyFilesBuildPhase (PlugIns dstSubfolderSpec=13), target dependency, build settings. Mistake = won't build. Validate with `xcodebuild -list` before committing.
2. **Info.plist migration** — the main target currently uses `GENERATE_INFOPLIST_FILE=YES` with `INFOPLIST_KEY_*`. Switching to a real Info.plist means flipping that flag and authoring every key. Easy to miss one (e.g., CFBundleDisplayName already set in pbxproj).
3. **App Group entitlement** — both the main app and share extension need the SAME entitlement. Apple Developer portal needs to know about the App Group ID. May fail TestFlight upload until the Group is registered + linked in App Store Connect.
4. **URL scheme** — `mediaswissarmy://` registration requires `CFBundleURLTypes` with a CFBundleURLSchemes array. Must be in the real Info.plist.

### Recommended approach
- Branch off `main` (post-PR-3 merge)
- Do the pbxproj edits in Xcode itself (safer than editing the file by hand)
- Verify `xcodebuild -list` shows both targets
- Local sim build green
- Push to a new feature branch, open PR
- CI iOS check passes
- Merge → TestFlight build → install on real device → test share sheet from Photos

### Test plan when implementing
- Open Photos → select 3 videos → Share → "Media Swiss Army" → host app launches, all 3 videos appear in compress queue
- Same with 5 HEICs from Photos
- Mixed selection (videos + HEICs)
- Edge case: huge video (>500 MB) — App Group container has size limits, may need streaming copy
- Cold-launch path: kill the app, share to it, app launches and drains inbox via `.onAppear`
- Foreground path: app already open, share to it, app's `.onOpenURL` fires and drains

### Out of scope
- Sharing OUT (sharing compressed output to another app via UIActivityViewController) — that's already there via the system Save / Share buttons
