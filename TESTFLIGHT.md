# TestFlight Deployment Guide — VideoCompressor iOS

**Goal:** Get the iOS Video Compressor app onto your iPhone (and friends' iPhones) via TestFlight, the cleanest way to ship pre-release builds without the App Store review process.

**Bundle ID:** `ca.nextclass.VideoCompressor`
**Apple Developer Program:** Paid ($99/yr) — required for TestFlight
**Prereqs:** macOS Developer Mode enabled ✓, Xcode signing Team set ✓, AXE installed ✓

---

## One-time setup (~10 minutes)

### Step 1: Claim the bundle ID in App Store Connect

1. Open <https://appstoreconnect.apple.com> in a browser, sign in with your paid Apple Developer account
2. Click **Apps** → **+** (top left) → **New App**
3. Fill in:
   - **Platform**: iOS
   - **Name**: `Video Compressor` (must be globally unique on the App Store; if taken, try `Video Compressor Pro` or similar)
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: select `ca.nextclass.VideoCompressor` from the dropdown — if it doesn't appear, register it first at <https://developer.apple.com/account/resources/identifiers/list> as an "App ID"
   - **SKU**: any unique string — `video-compressor-ios-2026` is fine
   - **User Access**: Full Access
4. Click **Create**

### Step 2: Add yourself as an Internal Tester

1. In the new app's page, click the **TestFlight** tab (top of the screen)
2. **Internal Testing** → **Add Internal Testers**
3. Add your own Apple ID email + anyone else you want (up to 100, all need to be in your developer team or have an App Store Connect role)
4. They'll get an email with a TestFlight install link once a build is uploaded

### Step 3: Verify Xcode signing is configured

Already done earlier this session, but to double-check:

1. Open `VideoCompressor/VideoCompressor_iOS.xcodeproj` in Xcode
2. Select the `VideoCompressor_iOS` target → **Signing & Capabilities**
3. Confirm:
   - "Automatically manage signing" is ticked
   - **Team** dropdown shows your paid developer team (NOT "Personal Team")
   - **Bundle Identifier** = `ca.nextclass.VideoCompressor`

---

## Building + uploading a build (~5 minutes per build)

There are two paths. Path A is what I (Claude) can do for you via XcodeBuildMCP. Path B is the manual Xcode Organizer flow if anything goes sideways.

### Path A — fully automated via Claude Code (recommended)

Just ask me:

> "Archive and upload a TestFlight build"

I'll run the equivalent of:

```bash
# 1. Increment build number (each upload needs a unique build number)
xcrun agvtool next-version -all

# 2. Archive
xcodebuild archive \
  -project VideoCompressor/VideoCompressor_iOS.xcodeproj \
  -scheme VideoCompressor_iOS \
  -configuration Release \
  -archivePath /tmp/VideoCompressor.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Automatic

# 3. Export the .ipa for App Store distribution
cat > /tmp/ExportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath /tmp/VideoCompressor.xcarchive \
  -exportPath /tmp/export \
  -exportOptionsPlist /tmp/ExportOptions.plist

# 4. Upload to App Store Connect
xcrun altool --upload-app \
  --type ios \
  --file /tmp/export/VideoCompressor_iOS.ipa \
  --apiKey YOUR_KEY \
  --apiIssuer YOUR_ISSUER
```

For step 4 you'll need an App Store Connect API key (one-time): App Store Connect → Users and Access → **Keys** tab → **+** → name it "Claude Code Upload", role: **Developer**, download the `.p8`. Save the file at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`. Tell me the key ID + issuer ID once and I'll cache them in `.xcodebuildmcp/secrets.yaml` (gitignored).

### Path B — manual Xcode Organizer

If Path A errors out on your specific setup:

1. Open the `.xcodeproj` in Xcode
2. Top menu: **Product** → **Destination** → **Any iOS Device (arm64)**
3. Top menu: **Product** → **Archive**. Wait ~2 minutes.
4. The Organizer window opens automatically. Select the new archive.
5. Click **Distribute App** → **App Store Connect** → **Upload** → next, next, next, **Upload**.
6. Wait ~5 min for processing. You'll get an email when it's done.

---

## After upload (~10 minutes wait)

1. Apple emails you "Processing complete" or "Issues found".
2. If issues: usually missing icon assets or Info.plist keys. I'll fix and resubmit.
3. If clean: go to App Store Connect → your app → **TestFlight** tab → the new build appears under **Builds**.
4. Click the build → fill in **Test Information** (just **What to Test** description is needed for internal testers).
5. Internal testers get an automatic email with a TestFlight install link.
6. They install the **TestFlight** app from the App Store on their phone, sign in with the email Apple invited, and the build appears.

---

## Beta release notes template

Save this in `docs/release-notes/<build-number>.md` per release:

```
## Build 1 (initial)

What's new:
- First TestFlight build of the iOS Video Compressor.
- Phase 1: pick videos from Photos, choose a preset (Max / Balanced / Small / Streaming), compress on-device.
- 3-tab shell — Stitch and MetaClean coming in upcoming builds.

What to test:
- Pick 1-3 videos from your camera roll, hit Compress All, watch the progress bar.
- Tap the save icon next to a finished video to save it back to Photos.
- Try each preset on the same video and see file-size delta.

Known issues:
- AVAssetExportSession bitrates are Apple's defaults, not the web app's
  smart-cap math (replaces in build 5).
- Stitch and MetaClean tabs show a placeholder.
```

---

## Common gotchas

| Problem | Fix |
|---|---|
| "No signing certificate found" on archive | Open Xcode once, target → Signing → tick Automatic → re-pick Team |
| "Bundle ID is not available" in App Store Connect | Someone else claimed `ca.nextclass.VideoCompressor`. Pick another like `ca.nextclass.VideoCompressorApp` and update the project setting. |
| Build processing stuck >30 min | Sometimes Apple is slow. Check <https://developer.apple.com/system-status/>. Don't re-upload until you confirm it failed. |
| Tester can't see build | They must accept the invite email AND have TestFlight app installed AND sign in with the SAME Apple ID that got the invite. |
| Internal testers cap at 100 | After that, switch to External Testing — requires a one-time "Beta App Review" (~24 hours) but unlocks 10,000 testers. |

---

## Recurring build cadence

Once Path A is working, the loop becomes:

1. You: "Ship a TestFlight build"
2. Me: archive + upload (~3 min)
3. You: wait for "processing complete" email
4. Testers: get auto-notified

No App Store Review required for internal testers. Each build is good for 90 days, then expires.

---

**Next action:** Once you're back at the Mac, ask me to start with Step 1 above (App Store Connect new app + bundle ID claim). The rest can run automated.
