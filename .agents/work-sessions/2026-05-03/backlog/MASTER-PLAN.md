# MASTER PLAN — Path to $4.99 App Store launch

**Author:** lead session (Claude Opus 4.7), 2026-05-03
**Audience:** Codex, or any agent picking up this repo cold
**Goal:** App Store submission with confidence ≥ 90% across stability / speed / privacy / UX
**Status reference:** main is at `<post-PR-9-merge SHA>`; backlog folder is the live task ledger

---

## How to use this plan

1. Phases are ordered by **dependency**. Don't skip ahead — Phase 2 features assume Phase 1 fixes have landed.
2. Each item links to a TASK file in this folder (some don't exist yet — write them as you start).
3. Open ONE PR per TASK. Test locally with `mcp__xcodebuildmcp__test_sim` before push. Wait for cloud CI green before merging.
4. Time estimates assume Codex working solo with the same XcodeBuildMCP tooling the lead used. They are upper bounds.
5. After every merge, append a 1-line summary to `.agents/work-sessions/<date>/AI-CHAT-LOG.md`.
6. `🛑` markers indicate items that need a human (you, the user) to do — don't try to automate these.

**TestFlight build budget rule:** every push to `main` triggers a TestFlight cycle. Batch related changes into one PR. Aim for ≤ 5 TestFlight builds across this whole plan.

---

## Phase 0 — Confirm starting state (15 min)

- [ ] Merge PR #9 (audit criticals + Codex handoff)
- [ ] Verify TestFlight build #N completes — wait for the ~12 min cycle
- [ ] Install on physical iPhone, smoke-test the 13-item list in `../audits/RED-TEAM-PRE-SHIP.md`
- [ ] If anything new fails, hotfix BEFORE starting Phase 1

---

## Phase 1 — Stop the bleeding (CRITICAL bugs, ~2 days)

These are the audit-flagged correctness issues that would embarrass a paid release.

### 1.1 — Still bake O(1) [TASK-01, ~1.5h]
Currently bake time scales with duration. Single-file change in `StillVideoBaker.bake` + 1 line in `StitchExporter.buildPlan` (use `scaleTimeRange` to stretch). Drop the N-frame loop entirely.

### 1.2 — Aggressive cache cleanup [TASK-99, ~3h]
Cancel paths leak partial files. NSTemporaryDirectory subdirs never swept. Per the user's specific concern: cancel = immediate sweep, save = post-30s sandbox sweep, launch = aggressive sweep. ~5 file edits.

### 1.3 — HDR passthrough [TASK-39, ~3h]
`CompressionService.encode` reader requests 8-bit YCbCr for everything. iPhone HDR HEVC is 10-bit — output washes out to SDR. Add `AVVideoColorPropertiesKey` + 10-bit pixel format detection. Single biggest perceptual regression.

### 1.4 — Audio mix track parity [TASK-32, ~1h]
`buildAudioMix` indexes `audioTracks[i % 2]` but skipped audio-less clips break parity → wrong clips' audio gets ramped. Track audio explicitly per-segment instead of by index.

### 1.5 — Stage filename collision [TASK-33, ~30min]
`stageToStitchInputs` only suffix-collides on existing files; delete-then-reimport aliases stale undo-history references. Add UUID prefix to staged filenames.

### 1.6 — Bake cancellation cleanup [TASK-31, ~30min]
`buildPlan` cancellation between still bakes leaks already-baked .movs (locals never reach the Plan's `bakedStillURLs`). Reorder so URL is appended BEFORE the bake completes (or on throw).

**Phase 1 exit criteria:** all 6 TASKs merged, 138+ tests still green, manual on-device confirm of the cache-cleanup behavior.

---

## Phase 2 — Polish (UX + frontend, ~3 days)

These move the app from "engineering tool" to "$4.99 paid app." Most have audit findings backing them.

### 2.1 — Dev-y copy polish [TASK-04, ~2h]
- "Cleaning N of M" → "Cleaning your photos · 3 of 8"
- Hide debug `print()` calls in release (use `#if DEBUG`)
- Inline editor: deduplicate scissors (header icon OR labeled button, not both)
- Replace `BatchCleanProgress` user-visible labels with friendlier copy

### 2.2 — Onboarding screen [TASK-05, ~3h]
First-launch 3-card paged onboarding ending on the MetaClean tab. Per `AUDIT-08` Part A: "MetaClean is the headline product but it's the third tab; first-time users get zero context."

Cards:
1. "Strip Meta AI fingerprints from your photos and videos. Date, GPS, and camera info stay intact."
2. "Compress before sharing. Apple's hardware encoder. Smart bitrate caps."
3. "Stitch clips together. Native AVFoundation transitions. Fully on-device."

### 2.3 — Settings "What MetaClean does" explainer [TASK-10, ~1h]
Verbatim copy in `AUDIT-08` Part A. New section under Settings explaining the 4 metadata modes + what they keep/strip.

### 2.4 — Long-press preview decision [TASK-12, ~1h or skip]
User asked whether the long-press preview should play in the BOTTOM editor area instead of the `.contextMenu(preview:)` overlay. AUDIT-05 recommends KEEPING the overlay (standard iOS pattern, two different intents: peek vs. edit). Decide and either skip this task or implement the alternative.

### 2.5 — Drop indicator polish [TASK-45, ~30min]
6pt accent bar feels too subtle (AUDIT-05 H7). Bump to 8pt + 12pt animated `.padding(.leading)` on the target clip + accent shadow so neighbors visibly push aside.

### 2.6 — Faster batch MetaClean + single-toast batch save [TASK-03, ~3h]
- Concurrent N=2 batch on Pro phones (DeviceCapabilities pattern from compress)
- Single completion toast at end ("Saved 8 photos to your library") instead of per-file
- Hide engineering "BatchCleanProgress" struct from UI strings

### 2.7 — Frontend simplifications [TASK-46, ~2h]
From AUDIT-08 Part B:
- Cut compress presets visible to Balanced + Small (rest under Advanced)
- Hide CropEditor's normalized X/Y/W/H sliders behind aspect-ratio presets
- Move Settings Performance section into Advanced

**Phase 2 exit criteria:** new user can install and successfully clean a photo without reading any docs. UI has zero engineering-flavored text.

---

## Phase 3 — Pre-launch hardening (~2 days)

Apple-specific gates before submission.

### 3.1 — Privacy manifest [TASK-34, ~1h]
Apple requires `PrivacyInfo.xcprivacy` since 2024. Currently missing. Declare reason codes for: UserDefaults, file timestamps, disk space.

### 3.2 — Photos auth gate [TASK-35, ~30min]
`StitchClipFetcher.fetchAssets` calls Photos read API without preceding authorisation gate. Add `PHPhotoLibrary.authorizationStatus(for:)` check.

### 3.3 — Apple-specific CI checks [TASK-18, ~2h]
Add `xcodebuild test` job on `macos-26` runner to `.github/workflows/ci.yml`. Cloud-side gate on the 138-test target. Catches regressions before merge to main.

### 3.4 — Privacy policy on GitHub Pages [TASK-07, ~1h]
Template already in `../reference/PUBLISHING-AND-MONETIZATION.md` Part 8. Push to `alkloihd.github.io/metaclean/privacy`. Link from App Store Connect + a Settings tab row.

### 3.5 — `SKStoreReviewController` review prompt [TASK-09, ~30min]
Show after 3 successful cleans (`@AppStorage("successfulCleanCount")`). Apple-approved pattern.

### 3.6 — Adaptive Meta-marker registry [TASK-02, ~5h]
JSON-driven `MetaMarkers.json` with binaryAtomMarkers / xmpFingerprints / makerAppleSoftware / deviceModelHints + falsePositiveGuards. The user's headline concern. Schema in TASK-02 file.

**Phase 3 exit criteria:** `xcrun altool` validation passes, privacy manifest validates, App Store Connect review-readiness check returns no errors.

---

## Phase 4 — App Store assets (~1 day, mostly human work)

🛑 Most of this is human-driven. Codex can SCAFFOLD but you finalize.

### 4.1 — App icon [TASK-06, designer hours]
🛑 Need a designer (Figma / Affinity / commission). 1024×1024 master + all sizes. Drop into `Assets.xcassets/AppIcon.appiconset/`.

### 4.2 — Screenshots [TASK-08, ~3h]
🛑 Boot a clean simulator with sample content. 6.7" + 6.1" sizes. 5-8 screenshots, first 3 critical (App Store search results show those without tap). Text overlays explaining each.

### 4.3 — App Preview video [TASK-08, ~2h]
🛑 15-30s screen recording showing pick → scan → tap clean → "Saved to Photos" toast. Hook in first 3s.

### 4.4 — App Store Connect entry [TASK-47, ~30min]
🛑 Create the app entry, set price tier 5 ($4.99), enrol in Apple Small Business Program (15% commission), upload screenshots + preview, submit for review. Walkthrough in `../reference/PUBLISHING-AND-MONETIZATION.md` Part 3.

**Phase 4 exit criteria:** App Store Connect "Ready for Submission" status.

---

## Phase 5 — Wireless device iteration setup (~3h, before Phase 1 ideally)

Saves Apple build credits during all subsequent work.

### 5.1 — `scripts/dev-iterate.sh` + pre-push hook [TASK-17]
Local script that runs lint + xcodebuild test + build_run_device. Git pre-push hook that runs the same checks before allowing `git push` to a remote.

After this lands, the iteration loop becomes:
```
edit → ./scripts/dev-iterate.sh → install on tethered iPhone → test
```
With ZERO Apple build minutes consumed until you `gh pr merge` to main.

**Move to before Phase 1 if you want to save TestFlight cycles.**

---

## Phase 6 — Post-launch roadmap (~2-4 weeks, after launch)

Don't do these before App Store submission. Real usage data informs which to prioritize.

### 6.1 — iOS Share Extension [TASK-14, ~6h]
Backlog file: `../backlog-archive/BACKLOG-share-extension.md` has full spec. Adds "Share to MetaClean" from any app.

### 6.2 — Pro tier IAP $9.99 [TASK-20, 1-2 days]
From `AUDIT-08` Part D. Candidates ranked: batch >50 (strong, 2h), custom marker rules (strong, 1d), Mac Catalyst with Universal Purchase, auto-clean on `PHPhotoLibraryChangeObserver`.

### 6.3 — Mac Catalyst [TASK-21, 1 day]
Universal Purchase. Same $4.99 nets the user the Mac app. Big LTV win.

### 6.4 — Apple Watch quick-clean [TASK-22, 1 day]
Niche but generates press cycles ("Now on Apple Watch").

### 6.5 — Auto-clean on Photos library change [TASK-23, 2-3 days]
`PHPhotoLibraryChangeObserver` watches for new Meta-glasses photos, offers one-tap clean. Becomes the "I never think about it" feature.

### 6.6 — Wipe transition rewrite [TASK-30, 4-6h]
Current crop-rect approach produces a horizontal squish, not a wipe (AUDIT-06 C2). Needs canvas-space animation OR a custom `AVVideoCompositing` class. Defer until users complain.

### 6.7 — Centroid-anchored pinch zoom [TASK-13, 2-3h]
Current pinch is anchor-at-gesture-start. iMovie-style "content stays under your fingers" needs UIScrollView via UIViewRepresentable. Defer.

---

## Time budget summary

| Phase | Estimated effort | Priority |
|---|---|---|
| 0 | 15 min | Required |
| 1 | ~2 days | Required (Phase 1 = ship-blockers) |
| 2 | ~3 days | Required for paid feel |
| 3 | ~2 days | Required for App Store approval |
| 4 | ~1 day human work | Required for submission |
| 5 | ~3h | Strongly recommended (saves Phases 1-3 build credits) |
| 6 | ~2-4 weeks post-launch | Iterative |

**Total to App Store submission:** ~9 working days for Codex + a few hours of human work for assets + portal.

---

## Decision points that need YOU (the user)

These can't be automated. Codex will pause when it hits them.

1. App Store name choice: `MetaClean: AI Glasses Data` (28 chars) vs alternatives in `../reference/PUBLISHING-AND-MONETIZATION.md`
2. Long-press preview UX: keep `.contextMenu` overlay vs move to bottom editor area (Phase 2.4)
3. Pricing: confirm $4.99 vs $2.99 / $6.99 — AUDIT-08 Part D notes $4.99 is the strongest signal
4. App icon design direction (Phase 4.1)
5. Apple Small Business Program enrolment (5 min, you do it in App Store Connect)
6. Domain for privacy policy (default: GitHub Pages on the existing repo)

---

## How Codex picks up

```bash
cd "/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR"
git fetch origin && git checkout main && git pull
cat AGENTS.md                   # primer
cat AGENTS.md | sed -n '/Part 16/,/Part 14/p'   # Codex onboarding
cat .agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md   # this file
cat .agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md

# Pick a task from the current Phase. Branch off main:
git checkout -b feat/<task-slug>

# Iterate (after Phase 5 lands):
./scripts/dev-iterate.sh

# Or use the MCP tools directly:
# mcp__xcodebuildmcp__build_run_device  (wireless install)
# mcp__xcodebuildmcp__test_sim          (138-test target)

# Ship:
git push -u origin feat/<task-slug>
gh pr create --base main --head feat/<task-slug> --title "..." --body "..."
gh pr checks <num> --watch
gh pr merge <num> --merge
```

That's it. The plan is self-driving.
