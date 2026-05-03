# AUDIT-08: Feature Gaps for v1.0 Polish

**Date:** 2026-05-03
**Reviewer:** opus (audit-08, read-only)
**Scope:** the iOS app as a $4.99 paid utility 5 minutes after install. What's missing, what's over-built, where's the moat.

Grounding: `PUBLISHING-AND-MONETIZATION.md`, `BACKLOG-share-extension.md`, `AGENTS.md` Part 15, `VideoCompressor/ios/`. Code services are mature; the SHELL (first-launch, settings explainer, marker registry) is what still feels developer-y.

---

## Part A — Missing v1.0 polish (≤ 1 day each)

### A1. First-launch onboarding (3 paged cards)

3-card paged sheet, gated by `@AppStorage("hasSeenOnboarding_v1")`:

1. **"What's a Meta fingerprint?"** — split-image: normal HEIC vs. Ray-Ban Meta HEIC, marker atom highlighted. Caption: "Photos from Ray-Ban Meta and Oakley Meta glasses carry a hidden marker. MetaClean removes only that marker."
2. **"Three tools, one app."** — Compress / Stitch / MetaClean icons, one line each: "Shrink videos. Stitch clips. Strip Meta markers." MetaClean is the headline.
3. **"Everything stays on your device."** — privacy bullets; "Get started" lands on **MetaClean** (see A3).

Effort: 3-4h.

### A2. Settings → "What this app does" section (verbatim copy)

Add as the FIRST section in `SettingsTabView`, above Background-Encoding:

> **What MetaClean does**
>
> MetaClean strips the hidden fingerprint that Meta AI glasses (Ray-Ban Meta, Oakley Meta) embed in every photo and video. The fingerprint is a binary marker in the file's metadata that tells anyone — Instagram, journalists, scrapers — "this was shot on Meta hardware."
>
> **What gets removed**
> • The Meta fingerprint atom (binary `Comment` / `Description` blob with Ray-Ban / Meta / RayBan markers)
> • XMP packets tagged with the same fingerprint
> • Optional: full strip of GPS, dates, camera info if you tap "Scrub everything"
>
> **What stays**
> Date taken. Location. Camera make and model. Live Photo identifiers. HDR gain map. Color profile. Orientation. Everything that makes your photos work properly in Photos.
>
> **What MetaClean never does**
> No accounts. No cloud. No analytics. No tracking. The only network calls this app makes are App Store updates handled by iOS itself.

Effort: 30min — just `Text` in a `Section`.

### A3. Smart default: open MetaClean tab on first 3 launches

Today: `selectedTab: AppTab = .compress`. The pitch is MetaClean. Use `@AppStorage("launchCount")`; if `< 3`, default to `.metaClean`. Effort: 15min.

### A4. Empty-state CTAs that convert

Replace `EmptyStateView`'s "No videos picked":

- **MetaClean:** "Pick a photo or video. We'll show you what Meta marker is hiding, in 2 seconds." + 56pt "Pick from Photos" (PhotosPicker presented directly).
- **Compress:** "Got a 4K clip too big to text? Pick it. We'll shrink it without making it look bad."
- **Stitch:** "Combine 2+ clips with a crossfade or hard cut."

Each ends with a small "Why MetaClean?" link opening the A2 panel. Effort: 3h.

### A5. "What's New" sheet on update

`@AppStorage("lastSeenVersion")` vs. `Bundle.main.shortVersion`. On mismatch, sheet with curated bullets (NEVER auto-dump CHANGELOG). v1.0 → v1.1 sample: "Faster batch cleaning. Now detects Oakley Meta. New: Mac app." Effort: 2h.

### A6. Review prompt after 3 successful cleans

`SKStoreReviewController.requestReview(in:)` (Apple-rate-limited; never custom dialogs — 4.5.4 rejection risk). Trigger: `successfulCleansSinceLaunch >= 3 && !shownThisVersion`. Effort: 30min.

### A7. "Saved 8 photos" toast after batch

Today batch save round-trips per file. One success toast at batch end, with a "View in Photos" link via `photos-redirect://`. Effort: 1-2h.

### A8. Inline privacy line above PhotosPicker

System `NSPhotoLibraryUsageDescription` is fine, but a one-line caption "Nothing leaves your device" above the picker button reduces permission-prompt drop-off. Effort: 30min.

---

## Part B — Frontend simplifications (≤ 4h each)

### B1. Compress: hide custom, default-show 2 presets

Today: max / balanced / small / streaming + custom. v1.0: visible **Balanced + Small** only; max / streaming / custom under "Advanced." 2h.

### B2. Stitch: ship one transition, hide four

`StitchExporter` supports crossfade / fade-black / wipe / dissolve / none. v1.0 ship **none + crossfade** as a single Toggle ("Smooth transitions"). Logic stays; gate the picker. 1h.

### B3. Stitch: hide split + rotate, keep trim/crop/reorder

Splitting is CapCut mental model — too much for v1.0. Stitch = pick → drag-reorder → optional trim → one global aspect toggle. Crop and rotate behind "Per-clip edits" disclosure. Split gone until v1.2. Services stay. 3-4h.

### B4. Settings: collapse Performance into Advanced

"Device class: Pro (2× encoder)" / "Parallel encodes: 2" are dev-y. Wrap in `DisclosureGroup("Advanced")`. Background-Encoding and Storage stay visible. 30min.

### B5. Hide Inspector behind long-press

`MetadataInspectorView` shows raw atom-by-atom metadata. Default tap = "Clean & Save"; long-press reveals the inspector. 1h.

---

## Part C — Adaptive Meta-marker registry

`MetadataService.isMetaGlassesFingerprint:467` and `PhotoMetadataService.xmpContainsFingerprint:322` both contain hard-coded substrings (`ray-ban`, `rayban`, `meta`, `xmp.metaai`, `meta:`). Future Meta hardware ships → strings miss → core promise silently fails. Design a JSON-driven, signed-remote-refreshable registry.

### Schema (`MetaMarkers.json`)

```json
{
  "version": 7,
  "schemaVersion": 1,
  "lastUpdated": "2026-05-03T00:00:00Z",
  "categories": {
    "binaryAtomMarkers": {
      "atoms": ["com.apple.quicktime.comment", "com.apple.quicktime.description",
                "udta.cmt", "udta.des"],
      "needles": [
        { "id": "rb-meta-1", "pattern": "ray-ban", "matchMode": "substring",
          "minBytes": 4, "addedIn": 1 },
        { "id": "rb-meta-2", "pattern": "rayban", "matchMode": "substring",
          "minBytes": 4, "addedIn": 1 },
        { "id": "oak-meta-1", "pattern": "oakley meta", "matchMode": "substring",
          "minBytes": 8, "addedIn": 6 }
      ]
    },
    "xmpFingerprints": [
      { "id": "xmp-metaai", "namespace": "xmp.MetaAI", "matchMode": "namespace" },
      { "id": "xmp-meta",   "pattern": "xmpns.com/meta/", "matchMode": "substring" }
    ],
    "makerAppleSoftware": [
      { "value": "Ray-Ban Stories", "matchMode": "exact", "addedIn": 1 },
      { "value": "Ray-Ban Meta",    "matchMode": "exact", "addedIn": 4 },
      { "value": "Oakley Meta",     "matchMode": "exact", "addedIn": 6 }
    ],
    "deviceModelHints": [
      { "value": "RB-1", "addedIn": 4 },
      { "value": "OM-1", "addedIn": 6 }
    ]
  },
  "guards": {
    "minimumAtomLengthBytes": 4,
    "rejectIfSurroundedByPlainText": true,
    "rejectIfMatchAppearsInUserComment": true
  }
}
```

Key choices:
- **Match modes**: `substring` / `exact` / `namespace` / `regex` (regex last — slower, harder to validate).
- **`atoms` whitelist**: a needle is only valid in named atom locations. "ray-ban" in `udta.cprt` = user-typed copyright, not a fingerprint.
- **`minBytes`**: a 3-char "meta" in 800 bytes = signal; same in 4 bytes = noise.
- **`addedIn`**: registry version where the needle landed. Enables A/B and rollback.

### Update mechanism: bundled + signed remote

1. **Bundled** floor in app bundle — works offline, day 1.
2. **Remote refresh** fetches `https://alkloihd.github.io/metaclean/markers/MetaMarkers.json` (static GitHub Pages, no server) once per launch with a 24h `URLCache` TTL. Higher `version` than bundled → replace.
3. **Signature**: ship public Ed25519 key in binary; remote payload signed. Reject unsigned/invalid → fall back to bundled. ~80 LOC + `swift-crypto`.
4. **Schema floor**: refuse `schemaVersion > current`. Protects v1.0 client from future-schema breakage.

### False-positive guards

- `minimumAtomLengthBytes`: needle must live in atom of ≥ N bytes.
- `rejectIfSurroundedByPlainText`: > 50% printable ASCII outside the needle ⇒ user-typed prose ⇒ skip. Already de-facto in `xmpContainsFingerprint`; codify.
- `rejectIfMatchAppearsInUserComment`: never strip owner-authored atoms (`iso6709`, `cprt`, user `comment`) regardless of match.
- Unit tests in `VideoCompressorTests` with two fixture files (real Ray-Ban Meta MOV + a non-Meta MOV that mentions "meta" in a comment); only the first should fire.

### Opt-in user feedback loop

Settings → "Help improve detection." When ON, after a clean returns no markers: "Was this a Ray-Ban Meta or Oakley Meta photo?" Tapping yes shows a sheet with the metadata-only payload (no pixels, no GPS) and a "Send anonymized sample" button. Backend = a free Cloudflare Worker writing to a private bucket. Markers ship in the next bundled `MetaMarkers.json`. Costs $0/month at v1.0 scale.

---

## Part D — Pro tier ($9.99 IAP) candidates

**D1. Batch >50 files (free capped at 50/batch) — STRONG.** Free covers the 95% one-off case. Photographers and journalists clean 200-file shoots. Single `Bool` gate. 2h.

**D2. Custom marker rules — STRONG.** Pro users add their own atom-needle pairs to a local `UserMarkers.json`. UI in Settings → "Custom markers (Pro)." Reuses the Part C registry. 1 day.

**D3. Mac app via Catalyst — STRONG, slow burn.** Photographers shoot Meta, edit on Mac. Catalyst gets you 80% there in ~1-2 weeks of polish. Universal Purchase ⇒ Pro unlocks both platforms in one transaction. Adds platform lock-in.

**D4. Auto-clean on Photos library change — STRETCH (defer to v1.2).** `PHPhotoLibraryChangeObserver` fires on new asset; if Meta marker present, notification "Found Meta marker in 1 new photo. Clean it?" Pro because background-time. 2-3 days; needs careful battery/UX. Defer.

Skip: **Apple Watch quick-clean** is a press-cycle play, not revenue. Photos aren't on Watch. Skip until requested.

---

## Part E — Anti-features (NEVER add)

- **E1. Cloud upload "for convenience."** One byte off-device ⇒ App Store description becomes a lie. Privacy is the moat. No version of "optional cloud" survives App Privacy disclosure without breaking the pitch.
- **E2. Required account.** Pitch is "no accounts." Sign-in-with-Apple as OPT-IN for Pro entitlement is fine via `Transaction.currentEntitlements`; required login is a regression.
- **E3. Ads.** A $4.99 paid app with ads = worst of both worlds.
- **E4. Subscription on the base app.** Recurring billing breaks trust on a one-shot utility. Second one-time IAP ($9.99) is fine; subscriptions are not.
- **E5. Auto-save without picker round-trip.** Even opt-in. Creates 5.1.1 review risk; user-control narrative requires the confirm.
- **E6. AI auto-tagging / Vision smart features.** Pitch is "we strip metadata, we don't add to it." On-device ML still triggers App Privacy personalization disclosure.
- **E7. Telemetry of any kind, including crash reports, until v1.1+.** No Crashlytics, Sentry, or `MetricKit`-to-server. The moat isn't re-buildable once breached.
- **E8. Watermarks on free-tier output.** A watermarked privacy-cleaned file is MORE identifiable — breaks the premise.
- **E9. Expanding to non-Meta brands.** Snap Spectacles, RayNeo, Vision Pro each have their own footprints. Add only when (a) a real user asks AND (b) the registry handles them cleanly. "MetaClean" → "Privacy Stripper #1,002" is brand suicide.

---

## Prioritized v1.0 punchlist (~3 days)

A1 (4h) → A2 (30m) → A3 (15m) → A4 (3h) → B1+B2+B3 (6h) → B4 (30m) → B5 (1h) → A6 (30m) → A7 (2h) → Part C registry (8h) → A5 (2h).

Sequence rationale: A1-A4 first (first-impression). Then B-simplifications. Then Part C (technical moat). Pro tier (Part D) post-launch.

**Bottom line.** The codebase is a paid app underneath. The shell — first 60 seconds — is still a developer utility. ~3 days of UI polish + 1 day on the marker registry crosses the line. Biggest payoff is Part C: without it, every Meta hardware refresh quietly breaks the core promise.
