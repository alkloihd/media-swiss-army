# Handoff to Claude in Terminal

> **For the receiving agent:** This document is your full context dump. Read top-to-bottom. After you understand it, ask the user the questions at the end. Then use `/ultraplan` to plan their answers.

---

## TL;DR

You're inheriting a near-launch iOS app called **"Media Swiss Army"** (App Store name will be **"MetaClean: AI Glasses Data"**). The user wants to charge **$4.99 one-time** on the App Store. The headline pitch is **stripping the binary fingerprint that Meta AI glasses (Ray-Ban Meta, Oakley Meta) embed in every photo and video they take** — while preserving date / GPS / camera info / Live Photo data. Compress + Stitch are bonus features.

**Status:** TestFlight-live (4 cycles consumed today), 138 unit tests green, 9-audit pass complete with 7 CRITICALs fixed inline. PR #9 is open with the day's work + a complete Codex onboarding kit. Ready for the next agent (you) to continue.

**The one thing the lead session never did:** visually walk the running app on a simulator or real device. Every test was unit-level. The user reported real-device bugs (HEIC thumbnails, 3302 save errors, dev-y title strings) that no unit test caught. Before declaring anything done, install on the user's actual iPhone and walk the tabs.

---

## What this app is

A SwiftUI + AVFoundation iOS 17+ app with **four tabs**: Compress / Stitch / MetaClean / Settings.

| Tab | Function |
|---|---|
| **Compress** | Drop in videos; HEVC/H.264 encode with smart bitrate caps (balanced 70%, small 40%, streaming 50% of source). VideoToolbox hardware encoder. |
| **Stitch** | Combine clips into one video. Aspect-mode picker (Auto / 9:16 / 16:9 / 1:1) — mismatched orientations letterbox/pillarbox, never crop. Native AVFoundation transitions: None / Crossfade / Fade Black / Wipe / Random. Audio crossfades alongside video. Per-clip undo/redo, split-at-playhead, drag reorder, pinch-zoom timeline, long-press preview. Photo support (1–10 s display per still). Sort by Date Taken. |
| **MetaClean** | The headline product. Strips Meta-glasses fingerprint atoms (binary "Comment"/"Description" with `ray-ban`/`meta`/`rayban` markers; XMP packets with same; `MakerApple Software` like "Ray-Ban Stories"). Default `autoMetaGlasses` mode is surgical — leaves date, GPS, camera info intact. `stripAll` mode nukes everything. Batch clean + replace originals. |
| **Settings** | Audio Background Mode toggle (extends the 30s background-encode ceiling). Cache management with auto-sweep (>7 days). Storage breakdown. |

**App identity:**
- Bundle: `com.alkloihd.videocompressor`
- Apple Team: `9577LMA4J5`
- Home-screen name: `Media Swiss Army`
- App Store name (planned): `MetaClean: AI Glasses Data`
- Min iOS: 17.0

**Repo:** `https://github.com/alkloihd/media-swiss-army`
**Default branch:** `main`
**Local path:** `/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/`

---

## Where everything lives

Two roots, two purposes (per `AGENTS.md` Part 2):

```
docs/                         ← durable, reference-grade
  superpowers/plans/
    YYYY-MM-DD-<slug>.md      ← TDD plans (writing-plans skill format)

.agents/work-sessions/        ← chronological session memory
  YYYY-MM-DD/                 ← per-day folder
    AI-CHAT-LOG.md
    CHANGELOG.md
    audits/                   ← red-team / audit reports
    backlog/                  ← task index + master plan + audit synthesis
    plans/                    ← session-specific plans
    handoffs/                 ← between-session handoffs
    reference/                ← durable docs not yet graduated to docs/
```

**For YOU specifically:**
- This file (`HANDOFF-TO-CLAUDE-TERMINAL.md`) at repo root — read it now
- `AGENTS.md` Part 16 — the Codex onboarding (also covers Claude in terminal)
- `docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md` — your day-1 prompt
- `.agents/work-sessions/2026-05-03/backlog/MASTER-PLAN.md` — phased roadmap
- `.agents/work-sessions/2026-05-03/backlog/AUDIT-CONSOLIDATED-FINDINGS.md` — what's known broken
- `.agents/work-sessions/2026-05-03/PUBLISHING-AND-MONETIZATION.md` — App Store launch strategy
- `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` — your warm-up TDD plan, ready to execute

---

## Story of today (start to finish)

The user joined the session this morning with the app already on TestFlight (Build 13). Today's session was a series of bug-fix waves driven by what the user noticed when testing the actual TestFlight builds on their iPhone 17 Pro Max.

### Wave 1 — Phase 3 work (PRs #3, #4, #5, #6)

The morning's work was already in flight from a prior session — I came in mid-stream. We landed:

- **PR #3** (Phase 3 Stitch UX + Photos as first-class) — AVAssetWriter migration with smart bitrate caps (replaced AVAssetExportSession's fixed-bitrate that was producing 1.2 GB outputs from 600 MB sources), Audio Background Mode opt-in (extends 30s background ceiling), Cache management actor, Multi-clip parallel encode on Pro phones, Save-to-Photos confirmation, iMovie-style drag-reorder + live trim preview, Photos as first-class media (HEIC/JPEG dual-load).
- **PR #5** — Stitch aspect-mode fix. User reported landscape clips cropped when stitched with portrait. New `StitchAspectMode` enum with Auto/9:16/16:9/1:1 modes. iPhone `preferredTransform` now captured at import. 18 new tests pinning the no-crop math.
- **PR #6** — Inline editor (no modal) + per-clip undo/redo + split + remove parts + 5 native transitions + audio crossfade + CRITICAL split-file-safety fix (after split, both halves shared `sourceURL`; old `remove()` deleted the file the surviving half needed).

### Wave 2 — User testing surfaced bugs (PR #7)

User testing showed:
- HEIC thumbnails appeared as warning triangles
- Inline editor showed black for HEIC instead of the still
- "Compression failed: photo clips can't be exported" on stitch with stills
- Split button was discoverable enough but easy to miss

Fixed in PR #7:
- `StillVideoBaker` service: bakes a still image into a temp .mov at plan-build, so the rest of the composition pipeline treats stills uniformly
- Re-enabled `.any(of: [.videos, .images])` in stitch picker
- HEIC thumbnails via CGImageSource
- Stills get a static `Image` view, not black VideoPlayer
- Duration slider (1–10 s) for stills with tick haptics
- Prominent "Split at Playhead" labeled button in addition to the toolbar icon
- Haptic system: `Haptics` service + `HapticTicker` per-slider tick feedback
- Pinch-to-zoom on timeline `[0.5×, 2.5×]`
- Long-press preview pane via `.contextMenu(menuItems:preview:)` — auto-plays muted video / shows still
- Extended context menu: Duplicate / Move-to-Start / Move-to-End / Delete

### Wave 3 — Sort + drop indicator + bake progress (PR #8)

User wanted:
- "What order does it put photos in? Can we sort chronologically?"
- "Drag-drop doesn't show where the clip will land"
- "Building composition" feels frozen

Fixed in PR #8:
- `StitchClip` gains `originalAssetID` + `creationDate` fields (defaulted nil)
- `StitchClipFetcher.creationDates(forAssetIDs:)` batch Photos lookup
- `StitchProject.sortByCreationDateAsync()` — fetch missing dates in one batch then stable-sort
- Toolbar Menu with "Sort by Date Taken"
- Drop-target indicator: 6pt accent-colored insertion bar to the LEFT of the target tile + selection-tick haptic on hover
- New `.preparing(current:total:)` export state with determinate progress bar during still-baking phase

### Wave 4 — 9-agent comprehensive audit (PR #9 — pending merge)

Per user request, I launched 9 read-only audit agents in parallel covering: concurrency, memory leaks, privacy/security, performance, UX, codecs/encoding, edge cases, feature gaps, cache cleanup. Results: **15 CRITICAL findings** (some duplicated across audits).

Fixed inline in PR #9:
1. **StillVideoBaker single-frame bug** (3 audits flagged this) — my own regression: a `markDoneIfPossible` re-entry guard was setting `_done = true` on every read, so the inner while-loop bailed after frame 0. Stills were baking to 1 frame instead of N. Fixed by splitting into `isDone` (read-only) + `markDone()` (set-only).
2. **StillVideoBaker writer cleanup on early throw** — early-throw paths leaked the partially-started writer + an empty .mov. New `bailWithError` helper.
3. **ClipLongPressPreview NotificationCenter observer leak** — block-form `addObserver` token was discarded. Every long-press leaked one AVPlayer. Fixed with `@State` token + removeObserver on disappear + weak self-reference in closure.
4. **Home-tab title was "Alkloihd Video Swiss-AK"** — would have been instant App Store rejection. Now "Compress".
5. **Stitch passthrough cancel/fail leaked output file** — re-encode path cleaned up; passthrough didn't.
6. **MetadataService.strip missing CancelCoordinator** — same registration-vs-cancel race CompressionService had. Mid-clean cancel could throw `NSInternalInconsistencyException`. Backported the proven CancelCoordinator pattern.
7. **Sandbox cleanup after save-to-Photos** (user's specific concern) — `Documents/Outputs/`, `Documents/StitchOutputs/`, `Documents/Cleaned/` sandbox copies persisted after save. A 600 MB stitched .mp4 leaked indefinitely. Now `CacheSweeper.deleteIfInWorkingDir` runs post-save in all three flows.

### Wave 5 — Codex hand-off prep

While PR #9 was being prepared, I:
- Wrote the comprehensive audit synthesis (`AUDIT-CONSOLIDATED-FINDINGS.md`)
- Wrote `MASTER-PLAN.md` covering Phases 1-6 to App Store launch
- Wrote a detailed TDD plan for Phase 1.1 (Still bake O(1)) at `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md` using the `superpowers:writing-plans` skill format
- Wrote `docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md` — Codex's day-1 prompt with MCP verification, read order, warm-up plan, working contract
- Updated `AGENTS.md` Part 16 with full Codex onboarding (signing IDs, MCP setup, sim hygiene, GitHub CLI, branch strategy)
- Updated `AGENTS.md` Part 2 with the new docs/ + .agents/work-sessions/ layout
- Reorganized today's session folder into clean subfolders (audits/, plans/, handoffs/, backlog/, reference/) — done by a separate Sonnet agent

---

## What's tested vs not tested

### Verified ✅
- **138 unit tests** pass on iPhone 16 Pro simulator. Coverage: model layer (StitchClip, ClipEdits, EditHistory, CompressionSettings, MetadataTag, etc.), smart bitrate cap math, aspect-fit transform math, cancellation race fix, sort-by-date logic, split + remove + edit history, photo metadata classification.
- **Build green** for iOS Simulator.
- **App boots** when launched in the simulator.
- **TestFlight build green** for PR #6 + PR #7 + PR #8 (4 successful cloud cycles today).

### NOT verified (real gap)
- **Visual sim walkthrough** — never opened the simulator window and clicked through the tabs. The user surfaced bugs that no unit test could catch.
- **End-to-end compression** of a real video with measurable size before/after.
- **End-to-end stitch export** with the new still-baking path.
- **End-to-end MetaClean strip** on a real Ray-Ban Meta video.
- **Real device behavior** (only the user has done this, and only for prior PRs).
- **Today's audit-fix changes** — tested only via unit tests, not visually.

**This is the priority for you (the receiving agent): visually walk the app before declaring anything done.**

---

## What's left to do

`MASTER-PLAN.md` has the full breakdown. Highlights:

### Phase 1 — Critical bugs (~2 days for Codex)
1.1 ✅ Still bake O(1) — TDD plan ready at `docs/superpowers/plans/2026-05-03-still-bake-constant-time.md`
1.2 Aggressive cache cleanup on cancel + per-stage (TASK-99 spec exists)
1.3 HDR passthrough — currently 10-bit HEIC HDR is silently downgraded to SDR (Audit-6-H1)
1.4 Audio mix track parity — `audioTracks[i % 2]` indexing breaks when audio-less clips skip the parity
1.5 Stage filename collision in `stageToStitchInputs`
1.6 Bake cancellation cleanup — already-baked .movs leak when cancellation fires mid-loop

### Phase 2 — UX polish (~3 days)
- Dev-y copy polish ("Cleaning N of M" → "Cleaning your photos · 3 of 8", debug `print()` calls under `#if DEBUG`, deduplicate scissors button)
- First-launch onboarding screen (3 cards explaining MetaClean as the headline)
- Settings tab "What MetaClean does" explainer
- Faster batch MetaClean + single-toast batch save
- Frontend simplifications (cut compress presets visible to 2, hide CropEditor sliders, etc.)

### Phase 3 — App Store hardening (~2 days)
- `PrivacyInfo.xcprivacy` manifest (required by Apple since 2024)
- StitchClipFetcher Photos auth gate
- Apple-specific cloud CI (`xcodebuild test` on macos-26)
- Privacy policy on GitHub Pages
- `SKStoreReviewController` review prompt after 3 successful cleans
- **Adaptive Meta-marker JSON registry** — the user's headline concern; current detector is hard-coded `ray-ban`/`meta`/`rayban` strings. JSON design in TASK-02.

### Phase 4 — App Store assets (~1 day human work)
- App icon (1024×1024 — needs a designer)
- Screenshots + App Preview video
- App Store Connect entry, $4.99 pricing, Apple Small Business Program enrolment

### Phase 5 — Wireless device iteration (~3h, do BEFORE Phase 1 to save Apple build minutes)
- `scripts/dev-iterate.sh` + git pre-push hook
- After this: edit → run script → app installs on tethered iPhone with ZERO Apple build minutes consumed

### Phase 6 — Post-launch
- iOS Share Extension
- Pro tier IAP $9.99 (batch >50, custom marker rules)
- Mac Catalyst (Universal Purchase)
- Apple Watch quick-clean
- Auto-clean on Photos library change (`PHPhotoLibraryChangeObserver`)
- Wipe transition rewrite (current is a horizontal squish, not a wipe — Audit-6-C2)
- Centroid-anchored pinch zoom (iMovie-style)

---

## Critical patterns the lead session established

When you write code, follow these or break them with intent:

1. **Actor isolation** — `actor StitchExporter`, `actor MetadataService`, `actor StillVideoBaker`, etc. Single-thread the heavy work. Use `@MainActor` for view-bound state.
2. **CancelCoordinator pattern** — `CompressionService.swift` has the canonical implementation. Any place that uses `withTaskCancellationHandler` + `requestMediaDataWhenReady` needs this guard. `MetadataService` got it backported in PR #9.
3. **`@unchecked Sendable` classes with NSLock** — used for state shared across DispatchQueue + actor boundaries. See `FrameCounter`, `PumpState`, `ContinuationBridge`, `CancelCoordinator`.
4. **PBXFileSystemSynchronizedRootGroup** — `VideoCompressor/ios/` and `VideoCompressor/VideoCompressorTests/` auto-include new Swift files. After adding a file, run `mcp__xcodebuildmcp__clean` to flush the cache and re-test.
5. **Smart bitrate caps** — `CompressionSettings.bitrate(forSourceBitrate:)` is the source of truth. `CompressionEstimator` uses the same math for the "size estimate" UI.
6. **Ref-counted source-file deletion** — `StitchProject.remove(at:)` only deletes the on-disk file when no other clip references it (split halves share `sourceURL`).
7. **Tick haptics via `UISelectionFeedbackGenerator`** — see `Haptics.swift` and `HapticTicker.swift`. DON'T introduce CoreHaptics unless the user explicitly asks.
8. **Built-in AVFoundation transitions only** — `setOpacityRamp`, `setVolumeRamp`, `setCropRectangleRamp`. DON'T introduce a custom `AVVideoCompositing` class without sign-off.

---

## How the agent ecosystem works

The user has Claude Code AND Codex. Both can work on this repo independently. The lead session was Claude Code; you may be Claude in the terminal, Codex, or another Claude Code session.

**The MCP server `xcodebuildmcp` is the key.** It gives any agent the ability to drive Xcode builds, run tests, install on simulator or physical device, capture screenshots — without you needing to babysit Xcode. Set it up via `AGENTS.md` Part 16.

**Branching protocol:**
- Always branch off `main`. Never push to `main` directly.
- One PR per task. CI must pass (4 checks) before merge.
- `gh pr merge` triggers a TestFlight cycle. Apple build minutes are limited; aim for ≤ 5 cycles per phase.
- Local sim test passes before push.

**Don't** call `xcodebuildmcp__session_set_defaults` — multiple agents can race and break each other. Use `extraArgs` with explicit `-project` paths if you must override.

---

## Open questions for the user

These are decisions the user needs to make before you can plan further work. Ask them ALL at the start of your conversation:

### Marketing / positioning
1. **App Store name confirmation:** "MetaClean: AI Glasses Data" (28 chars) is the current candidate. Alternatives: "MetaClean — Strip AI Glasses" (28), "MetaClean for Ray-Ban + Meta" (29). Which?
2. **Pricing confirmation:** $4.99 one-time. Is this still the plan, or considering $2.99 / $6.99 / $9.99 / freemium?
3. **Apple Small Business Program enrolment** (drops Apple's commission from 30% → 15%). Has the user enrolled? If not, this is a 5-minute task they can do in App Store Connect right now.

### UX decisions
4. **Long-press preview placement:** today it's a `.contextMenu(menuItems:preview:)` overlay (standard iOS). The user once asked if it should play in the BOTTOM editor area instead. Audit-05 recommends keeping the overlay (different intents: peek vs. edit). Decide now: keep overlay, or move to bottom?
5. **Hide which compress presets behind "Advanced"?** Audit-08 recommends showing only "Balanced" + "Small" by default. User's call.
6. **Hide CropEditor's normalized X/Y/W/H sliders?** Audit-05 H4 calls them "v2 surface" — too dev-y. User's call: hide entirely, or move to Advanced?

### Feature scope decisions
7. **Adaptive Meta-marker registry (TASK-02):** the user has flagged this as the headline feature. Confirm priority: do this in Phase 1.7 (before App Store submission), or defer to v1.1? Adding more device markers (Oakley Meta, future devices) means the detector keeps working without app updates.
8. **iOS Share Extension:** backlog. The user asked for this back in PR #6 era. Defer to v1.1 (Phase 6.1)?
9. **Pro tier IAP $9.99** — Audit-08 recommends 2-4 candidates: batch >50, custom marker rules, Mac Catalyst Universal Purchase, auto-clean on library change. Which subset for the FIRST Pro tier?

### Workflow decisions
10. **Local-device iteration setup (Phase 5):** before doing more code work, set up `scripts/dev-iterate.sh` + git pre-push hook so we save Apple build minutes? This is ~3h work and will save many minutes during Phases 1-3.
11. **TestFlight cadence:** the user has limited Apple build minutes. Aim for ≤ how many TestFlight cycles per phase?

### Real-device testing
12. **Smoke test plan:** after Phase 1 lands and merges to main, what's the user's testing workflow? Will they install via TestFlight, or via tethered USB after Phase 5 lands?
13. **Real-device iPhone available now?** Phase 5 needs the user's iPhone tethered to set up wireless deploy.

---

## Suggested first steps for you (Claude in Terminal)

1. **Read `AGENTS.md` Part 16** — your full onboarding.
2. **Run the MCP verification checklist** in `docs/superpowers/plans/2026-05-03-CODEX-KICKSTARTER.md` Step 1. Confirm `mcp__xcodebuildmcp__test_sim` returns 138/138.
3. **Ask the user** the 13 questions above.
4. **Use `/ultraplan`** with their answers to produce a comprehensive next-N-phase plan.
5. **Save plans** to `docs/superpowers/plans/<date>-<slug>.md`.
6. **Visually walk the app** on the simulator BEFORE writing any new code. The lead session never did this; the user will surface real bugs you couldn't otherwise see.

---

## What you should NOT do

- Don't push to `main` directly.
- Don't call `xcodebuildmcp__session_set_defaults` (race condition with parallel sessions).
- Don't run more than 2 background agents in parallel (sim resource contention).
- Don't introduce CoreHaptics or custom `AVVideoCompositing`.
- Don't touch `.github/workflows/testflight.yml` (App Store Connect API key wiring).
- Don't merge a PR with any CRITICAL audit finding unfixed.
- Don't trust unit tests alone — visually verify on sim before declaring done.

---

## A note on tone

The user is a solo dev who's been moving fast all day with multiple agents in parallel. They've got an iPhone 17 Pro Max and have been tethering for testing. They want this app on the App Store soon. They're price-conscious about Apple build minutes. They appreciate honesty about what's tested vs not (the lead session over-promised early on; they pushed back; we adjusted).

Be honest, be direct, point at file:line evidence, don't run away with parallelism, ask before doing destructive things, batch UI changes into single PRs to save build cycles.

---

## TLDR for the impatient

1. Read `AGENTS.md` Part 16
2. Verify `xcodebuildmcp__test_sim` works → 138/138
3. Read `MASTER-PLAN.md` and the 9 audit reports
4. Ask the user the 13 questions in this doc
5. `/ultraplan` their answers
6. Walk the app visually on the simulator
7. Pick Phase 1.1 (already has a TDD plan written for you), execute it as a warm-up
8. Then iterate

Good luck. The hard problems (codecs, transitions, picker UX) are solved. What's left is mostly polish and one big design call (the Meta-marker registry).
