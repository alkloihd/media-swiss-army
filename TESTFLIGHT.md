# TestFlight Deployment Guide — Media Swiss Army (iOS)

**App display name:** Media Swiss Army
**Bundle ID:** `ca.nextclass.VideoCompressor`
**Apple Developer Program:** Paid ($99/yr) — required for TestFlight + Xcode Cloud
**Recommended CI:** **Xcode Cloud** (Apple's native CI; included free with paid membership)
**Fallback CI:** GitHub Actions (documented in `.agents/work-sessions/2026-05-03/plans/PLAN-cicd-testflight.md`)

---

## Recommended path: Xcode Cloud (set up entirely from your phone)

Xcode Cloud is Apple's CI/CD service built into App Store Connect. Your $99/yr membership includes 25 hours/month free — easily 50+ TestFlight builds. **No GitHub Secrets, no `.p8` files, no signing ceremony.** Apple manages everything.

The full step-by-step plan (with exact App Store Connect URLs and screenshots-worth-of-detail) is at:

**`.agents/work-sessions/2026-05-03/plans/PLAN-cicd-testflight.md`**

It walks through (all from `appstoreconnect.apple.com` on phone Safari):

1. Claim bundle ID `ca.nextclass.VideoCompressor` and create the "Media Swiss Army" app record
2. Add yourself as Internal Tester
3. Connect Xcode Cloud to the GitHub repo
4. Create a workflow: trigger on push to `main` (or any branch you choose) → build with Xcode 16 → archive → upload to TestFlight
5. First build runs ~15 min; you get TestFlight email; install on phone

After setup, the loop is: **edit code on phone via GitHub mobile or web → push → ~15 min later TestFlight notification.** Pure phone-driven dev.

### One-time prerequisites already complete on this branch ✓

- App icon (3 placeholder PNGs in `Assets.xcassets/AppIcon.appiconset/`) — replace with branded icon when convenient
- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (silences per-upload export-compliance prompt)
- `INFOPLIST_KEY_CFBundleDisplayName = "Media Swiss Army"`
- All `NS*UsageDescription` strings reference "Media Swiss Army" not the old name
- Signing wired (`DEVELOPMENT_TEAM = 9577LMA4J5`, automatic management)
- Privacy claim verifiable: zero network code (grep-confirmed in pre-ship audit)

### After your first internal-testing build

External testers (up to 10,000) need a one-time Apple "Beta App Review" (~24 h). Internal testers (up to 100) skip this and install instantly.

---

## Fallback path: GitHub Actions

Use this only if Xcode Cloud's free tier becomes a problem. Full workflow YAML, secret list, and setup steps are in **`.agents/work-sessions/2026-05-03/plans/PLAN-cicd-testflight.md`** under "Fallback approach". Switching paths later is a one-day migration.

---

## Manual archive + upload (Mac required, no CI)

Ignore this section if Xcode Cloud is set up. Kept here for emergency local builds.

1. Open `VideoCompressor/VideoCompressor_iOS.xcodeproj` in Xcode
2. Product menu → Destination → Any iOS Device (arm64)
3. Product → Archive (~2 min)
4. Organizer opens automatically → select archive → **Distribute App** → **App Store Connect** → **Upload** → next/next/next
5. Wait ~5 min for Apple processing → email when ready
6. App Store Connect → your app → **TestFlight** tab → fill **What to Test** description
7. Internal testers get auto-notified

---

## Common gotchas

| Problem                                                                     | Fix                                                                                           |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| "No signing certificate found" on archive                                   | Open Xcode once, target → Signing → tick Automatic → re-pick Team                             |
| Bundle ID `ca.nextclass.VideoCompressor` already taken in App Store Connect | Claim `com.alkloihd.metaclean` instead and update `PRODUCT_BUNDLE_IDENTIFIER` in pbxproj      |
| Build processing stuck >30 min                                              | Apple is slow occasionally. Check <https://developer.apple.com/system-status/>.               |
| Tester can't see build                                                      | Must accept invite email AND have TestFlight app installed AND sign in with the SAME Apple ID |
| Internal testers cap at 100                                                 | Switch to External Testing (10,000 cap) — requires one-time Beta App Review                   |

---

## What's deferred

Not blocking TestFlight ship; addressable in v1.0.1+:

- **Photos as first-class media** — compress / stitch / metaclean for stills (HEIC/JPEG). See `.agents/work-sessions/2026-05-03/backlog-archive/BACKLOG-stitch-photos-and-share-extension.md` §3.5.
- **iOS Share Extension** — receive batch from Photos share sheet directly into Compress/Stitch/MetaClean queues. See backlog §2.
- **Live trim preview** in `TrimEditorView` — currently dual-Slider; v2 should show actual frame at trim points.
- **Scrubbing UI state** during the auto-strip Meta-fingerprint pass (~1-3s after compression). See pre-ship audit `{E-0503-1135}` H2.
- **Streaming-strip optimization** to fold metadata strip into the export pass (eliminates double I/O on 4K stitches).

---

## Beta release notes template

Save per release at `.agents/work-sessions/<date>/release-notes-<build>.md`:

```
## Build 1 — first TestFlight

What's new:
- Three-tab iOS app: Compress / Stitch / MetaClean
- Compress: pick videos from Photos, choose preset (Max/Balanced/Small/Streaming), compress on-device via VideoToolbox
- Stitch: visual timeline with press-and-hold reorder, per-clip trim/crop/rotate, all processing held until export
- MetaClean: scan + selectively strip metadata; "Auto" mode targets only the Meta AI / Ray-Ban fingerprint atom
- Auto-strip Meta fingerprint runs automatically on every Compress and Stitch output (no user action needed)
- Save back to Photos with optional "Delete original" toggle (MetaClean)

What to test:
- Pick 1-3 videos from your camera roll, hit Compress All, watch progress bar, save to Photos
- Stitch tab: pick 2+ clips, drag-reorder, trim one, hit Stitch & Export
- MetaClean: pick a Meta-glasses video if you have one; the fingerprint should be detected and stripped
- Try each preset on the same video and compare file size

Known issues:
- AVAssetExportSession bitrates are Apple's defaults, not the web app's smart-cap math (Phase 3)
- Photos as first-class media (compress/stitch stills, photo metadata strip) — coming in next build
- Trim editor uses dual-Slider; live-frame preview ships in v1.0.1
```
