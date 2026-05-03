# PLAN: Code-from-Anywhere CI/CD to TestFlight

**Date:** 2026-05-03
**Author:** [solo/opus]
**App:** `VideoCompressor_iOS` (bundle `ca.nextclass.VideoCompressor`, team `9577LMA4J5`)
**Goal:** Edit on phone (GitHub mobile / web editor) → push → TestFlight build appears in ~15 min, no Mac required.

---

## Recommendation: Xcode Cloud (primary) + GitHub Actions (fallback documented)

**Pick Xcode Cloud.** Rationale (≤200 words):

The user already has a paid Apple Developer Program ($99/yr, registered 2026-04-09) which includes 25 hours/month of Xcode Cloud free — enough for ~50 TestFlight builds/month. Xcode Cloud is Apple-native: it reads signing config straight from the project (the existing `DEVELOPMENT_TEAM = 9577LMA4J5` + automatic signing keeps working with zero changes), uploads to TestFlight without an API-key dance, and is configured entirely from App Store Connect's website — which works fine from a phone browser. No GitHub Secrets to rotate, no `.p8` to babysit, no `ExportOptions.plist` drift, no `fastlane match` repo to maintain. The "code from phone" loop becomes: edit in GitHub mobile → commit to `main` → Xcode Cloud webhook fires → archive + sign + upload → TestFlight processes → tester email lands. Total ~12-18 min wall clock, zero touch.

GitHub Actions is the right second choice if Xcode Cloud's quota becomes a problem or the user wants the build artifacts stored in GitHub. We document that path as a fallback (workflow YAML below) but don't activate it day one.

**Firebase App Distribution: ruled out.** Distributes via the Firebase App Tester app, not TestFlight. User explicitly said TestFlight. Skip.

**fastlane match + pilot: ruled out for solo dev.** It's the right answer for a team rotating certs across machines, but adds a Ruby toolchain, a private match repo, and cert-rotation ceremony for zero benefit when one person is shipping from one team.

---

## Cost comparison

| Path | Setup time | Per-build cost | Phone loop works? | Existing signing reused? |
|---|---|---|---|---|
| **Xcode Cloud** (recommended) | 15-20 min | Free up to 25 hr/mo (~50 builds), then $14.99/100hr | Yes, push triggers | Yes, zero-touch |
| GitHub Actions + ASC API key | 60-90 min | Free public / $0.16/min macOS for private (~$0.80-1.20/build on macos-14, 5-8 min) | Yes | Yes, but needs cert + profile export to secrets |
| fastlane match + pilot | 90-120 min | Same as GHA | Yes | Replaces with match-managed certs |
| Firebase App Distribution | N/A | Free | N/A — wrong destination | N/A |
| Bitrise/CircleCI | 60 min | $30-50/mo plans | Yes | Yes | 

**Estimated build time on Xcode Cloud:** 8-12 min archive + 3-5 min App Store Connect processing = ~15 min from `git push` to "Build available in TestFlight" email.

---

## App Store Connect prerequisites (one-time, from any browser including phone)

User must complete these before first cloud build. Estimated 20 min total.

1. **Claim the bundle ID** — <https://developer.apple.com/account/resources/identifiers/list> → `+` → App IDs → App → Description "Video Compressor" → Bundle ID Explicit `ca.nextclass.VideoCompressor` → no special capabilities needed → Register.
2. **Create the App Store Connect record** — <https://appstoreconnect.apple.com> → Apps → `+` → New App. Platform iOS, Name "Video Compressor" (fall back to "Video Compressor by NextClass" if taken), Primary Language English (US), Bundle ID select `ca.nextclass.VideoCompressor`, SKU `video-compressor-ios-2026`, Full Access. Create.
3. **Add yourself as Internal Tester** — App page → TestFlight tab → Internal Testing → `+` → Add yourself by Apple ID. (This is the Apple ID on the phone where TestFlight is installed.)

**Defer until needed:**
4. **App Store Connect API key** — only required if falling back to GitHub Actions. Skip for Xcode Cloud.

---

## Xcode Cloud setup (one-time, can be done from phone browser)

Done from <https://appstoreconnect.apple.com>:

1. Open the Video Compressor app → **Xcode Cloud** tab → **Get Started**.
2. **Connect source code** → GitHub → authorize Apple's GitHub app on the repo containing `VideoCompressor_iOS.xcodeproj`. Select the repo.
3. **Create Workflow** named `TestFlight`. Configure:
   - **Branch Changes** start condition: `main` (or whatever branch you push from on the phone).
   - **Environment**: Xcode 16, macOS Sequoia (latest stable).
   - **Action: Archive** → iOS, scheme `VideoCompressor_iOS`, configuration Release.
   - **Post-Action: TestFlight Internal Testing** → group "App Store Connect Users" (auto-created) → check the testers added in prereq step 3.
4. **Save**. Xcode Cloud writes a hidden `ci_scripts/` hook into the repo on first run if you opt in to custom scripts; otherwise nothing is added. The workflow lives in App Store Connect, not in the repo.
5. **First run**: push any commit to `main`, or click "Start Build" in the workflow page. Watch the live log on the same page (also works on phone browser).

**Build number bumping:** Xcode Cloud automatically sets `CFBundleVersion` (the build number) to the cloud build number on every run, overriding the local `CURRENT_PROJECT_VERSION = 1`. No agvtool, no commits-back-to-main, no `Info.plist` edits. `MARKETING_VERSION` stays at whatever you set in the project (currently `1.0`); bump it manually when you ship a new version.

**Phone loop after setup:** GitHub mobile app → edit a Swift file → commit to `main` → close phone → 15 min later TestFlight emails the tester invite. That's it.

---

## GitHub Actions fallback (do NOT activate unless Xcode Cloud quota is exhausted)

If you ever want to move off Xcode Cloud, here is the ready-to-commit workflow plus a script. Both files go in the repo only when you're ready to switch.

### `.github/workflows/testflight.yml`

```yaml
name: TestFlight

on:
  push:
    branches: [main]
    paths:
      - 'VideoCompressor/**'
      - '.github/workflows/testflight.yml'
  workflow_dispatch:

concurrency:
  group: testflight
  cancel-in-progress: false

jobs:
  archive-and-upload:
    runs-on: macos-14
    timeout-minutes: 45
    env:
      XCODE_PROJECT: VideoCompressor/VideoCompressor_iOS.xcodeproj
      SCHEME: VideoCompressor_iOS
      TEAM_ID: 9577LMA4J5
      BUNDLE_ID: ca.nextclass.VideoCompressor
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 16
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Decode signing assets into a temporary keychain
        env:
          BUILD_CERT_P12_BASE64: ${{ secrets.BUILD_CERT_P12_BASE64 }}
          BUILD_CERT_PASSWORD: ${{ secrets.BUILD_CERT_PASSWORD }}
          PROVISIONING_PROFILE_BASE64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          set -euo pipefail
          CERT_PATH=$RUNNER_TEMP/build.p12
          PROFILE_PATH=$RUNNER_TEMP/build.mobileprovision
          KEYCHAIN=$RUNNER_TEMP/build.keychain-db

          echo -n "$BUILD_CERT_P12_BASE64" | base64 --decode -o "$CERT_PATH"
          echo -n "$PROVISIONING_PROFILE_BASE64" | base64 --decode -o "$PROFILE_PATH"

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security import "$CERT_PATH" -P "$BUILD_CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
          security list-keychain -d user -s "$KEYCHAIN" login.keychain
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' /dev/stdin <<<"$(security cms -D -i "$PROFILE_PATH")")
          cp "$PROFILE_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/"$UUID".mobileprovision

      - name: Set unique build number from run number
        run: |
          BUILD_NUM=$((100 + GITHUB_RUN_NUMBER))
          /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" \
            VideoCompressor/VideoCompressor_iOS/Info.plist || \
          xcrun agvtool new-version -all "$BUILD_NUM"
          echo "BUILD_NUM=$BUILD_NUM" >> "$GITHUB_ENV"

      - name: Archive
        run: |
          xcodebuild -project "$XCODE_PROJECT" \
            -scheme "$SCHEME" \
            -configuration Release \
            -destination "generic/platform=iOS" \
            -archivePath "$RUNNER_TEMP/app.xcarchive" \
            -allowProvisioningUpdates \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            archive | xcbeautify

      - name: Export IPA
        run: |
          cat > "$RUNNER_TEMP/export.plist" <<EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0"><dict>
            <key>method</key><string>app-store-connect</string>
            <key>teamID</key><string>$TEAM_ID</string>
            <key>signingStyle</key><string>manual</string>
            <key>uploadBitcode</key><false/>
            <key>uploadSymbols</key><true/>
          </dict></plist>
          EOF
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/app.xcarchive" \
            -exportPath "$RUNNER_TEMP/export" \
            -exportOptionsPlist "$RUNNER_TEMP/export.plist" | xcbeautify

      - name: Upload to TestFlight
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_P8_BASE64: ${{ secrets.ASC_KEY_P8_BASE64 }}
        run: |
          mkdir -p ~/.appstoreconnect/private_keys
          echo -n "$ASC_KEY_P8_BASE64" | base64 --decode \
            > ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
          IPA=$(ls "$RUNNER_TEMP"/export/*.ipa | head -1)
          xcrun altool --upload-app -f "$IPA" -t ios \
            --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

      - name: Summary
        if: always()
        run: |
          echo "## TestFlight build $BUILD_NUM" >> "$GITHUB_STEP_SUMMARY"
          echo "Bundle: $BUNDLE_ID" >> "$GITHUB_STEP_SUMMARY"
          echo "Team: $TEAM_ID" >> "$GITHUB_STEP_SUMMARY"
```

### Required GitHub Secrets (only for fallback path)

| Secret | How to obtain |
|---|---|
| `BUILD_CERT_P12_BASE64` | On Mac: Keychain Access → My Certificates → "Apple Distribution: …" → Export `.p12` with password → `base64 -i cert.p12 \| pbcopy` |
| `BUILD_CERT_PASSWORD` | The password you set when exporting `.p12` |
| `PROVISIONING_PROFILE_BASE64` | <https://developer.apple.com/account/resources/profiles/list> → `+` → App Store distribution → bundle `ca.nextclass.VideoCompressor` → cert from above → download → `base64 -i profile.mobileprovision \| pbcopy` |
| `KEYCHAIN_PASSWORD` | Any random string, e.g. `openssl rand -hex 16` |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → `+` → name "GitHub CI" → role "App Manager" → download `.p8` once. Key ID shown on the row. |
| `ASC_ISSUER_ID` | Same page, displayed at top above the keys table. |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_<KEY_ID>.p8 \| pbcopy` |

Add via GitHub web UI: repo → Settings → Secrets and variables → Actions → New repository secret. All seven can be added from a phone browser.

**Build number strategy (GHA):** `BUILD_NUM = 100 + github.run_number`. Strictly monotonic across all runs of the workflow. No commits-back-to-main, no version drift. Starting offset 100 leaves headroom in case you ever uploaded manual builds 1-99.

---

## Step-by-step user setup (recommended Xcode Cloud path)

All steps work from a phone browser; nothing requires the Mac.

1. **Claim bundle ID** — developer.apple.com/account → Identifiers → `+` → App IDs → `ca.nextclass.VideoCompressor`. (5 min)
2. **Create app record** — appstoreconnect.apple.com → Apps → `+` → fill fields per "App Store Connect prerequisites" above. (5 min)
3. **Add internal tester** — TestFlight tab → Internal Testing → add your Apple ID. (1 min)
4. **Push code to GitHub** if not already there. (Skip if `main` already exists.)
5. **Connect Xcode Cloud** — App page → Xcode Cloud tab → Get Started → connect GitHub → authorize Apple's GitHub app on the repo. (5 min)
6. **Create workflow** "TestFlight": branch `main`, action Archive (scheme `VideoCompressor_iOS`, Release), post-action "TestFlight Internal Testing" → check yourself. Save. (3 min)
7. **First build** — Either push a commit, or click "Start Build" on the workflow page. Watch the log.
8. **Install TestFlight** on the phone (App Store), sign in with the same Apple ID added as internal tester. When the build finishes, accept the email invite, build appears in TestFlight app, hit Install.

Total wall clock from zero to first TestFlight install on phone: **~30 min one-time + ~15 min/build thereafter.**

---

## Claude remote control compatibility

User mentioned wanting to also drive Claude Code remotely. Options ranked:

1. **GitHub Codespaces + Claude Code in browser** — open the repo in a Codespace from the GitHub mobile app or any browser, install Claude Code in the Codespace's terminal, edit + commit + push. Free 60 hr/month on Codespaces personal tier. **Recommended.**
2. **Anthropic Claude Code on a cloud VM** (e.g. a small EC2 / Hetzner box) — `ssh` from a phone via Termius or Blink Shell, run Claude Code there. More flexible (custom toolchain, persistent shell), but you maintain the VM.
3. **claude.ai web with the GitHub MCP connector** — chat-driven edits committed via PRs. Lowest friction but slowest for code-heavy work.

None of these affect the CI/CD pipeline — they're upstream of `git push`. Xcode Cloud doesn't care whether the commit came from Xcode, GitHub mobile, a Codespace, or a phone-driven LLM.

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Bundle ID `ca.nextclass.VideoCompressor` already claimed by someone else | Low (custom domain) | Have to pick a new ID and update one project setting | Try register first; fall back to `ca.nextclass.VideoCompressorApp` |
| Xcode Cloud quota (25 hr/mo) exhausted | Low at solo cadence | $14.99 for next 100 hrs, or switch to GHA fallback | Monitor usage on workflow page; fallback workflow already specced above |
| TestFlight processing stalled / "missing compliance" prompt | Medium first time | First build needs export-compliance answer in App Store Connect (one-time) | Set `ITSAppUsesNonExemptEncryption = false` in Info.plist (the app uses only Apple's standard cryptography) — kills the prompt |
| Automatic signing cert rotation in 1 year | Low | Xcode Cloud handles automatically; GHA fallback would need new `.p12` | Note in `.agents/` to redo `BUILD_CERT_P12_BASE64` annually if on GHA |
| App Store Review surprise on first External tester batch | Medium | Up to 24 hr delay for Beta App Review | Stay on Internal testers (≤100) until ready; Internal needs no review |
| `MARKETING_VERSION` collision (uploading 1.0 build N then trying to ship 1.0 to App Store later) | Medium | Apple rejects duplicate `(version, build)` tuples | Bump `MARKETING_VERSION` in project before shipping a "real" 1.0; TestFlight builds at 0.9.x for now |
| User edits Info.plist on phone and breaks XML | Low | Build fails fast on Xcode Cloud, no harm | The CI failure email is the safety net |
| Push to `main` accidentally ships a TestFlight build mid-development | Medium | Wastes 1 build slot in the 100/day Apple limit (you'll never hit it) | Use a `release` branch instead of `main` if cadence becomes a problem; one-line change to workflow start condition |

---

## What's left to do (handoff)

- [ ] User: complete the 8-step setup above (~30 min, all from phone).
- [ ] User: confirm the App Store Connect "Name" they want — "Video Compressor" may collide; suggest "Video Compressor by NextClass" pre-emptively.
- [ ] After first successful build: bump `MARKETING_VERSION` to `0.9.0` in the project file so the 1.0 release tag stays available for the real launch.
- [ ] Defer GitHub Actions fallback until Xcode Cloud demonstrates a problem; keep this plan file as the spec.

---

**Bottom line:** Xcode Cloud, free tier, zero new files in the repo, signing config already correct, ~30 min one-time setup all doable from a phone, ~15 min phone-edit-to-TestFlight loop after that.
