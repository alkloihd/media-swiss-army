# Consolidated audit findings — 2026-05-03

Nine read-only Opus agents audited the codebase across orthogonal dimensions. Their full reports live in this folder:

- `AUDIT-01-concurrency.md` (2C / 4H / 5M / 2L)
- `AUDIT-02-memory-leaks.md` (2C / 4H / 4M / 2L)
- `AUDIT-03-privacy-security.md` (0C / 2H / 5M / 4L)
- `AUDIT-04-performance.md` (1C / 2H / 3M / 3L)
- `AUDIT-05-ux.md` (2C / 5H / 5M / 3L)
- `AUDIT-06-codecs.md` (2C / 5H / 5M / 3L)
- `AUDIT-07-edge-cases.md` (4C / 7H / 7M / 3L)
- `AUDIT-08-feature-gaps.md` (design doc, no severity)
- `AUDIT-09-cache-cleanup-on-cancel-and-export.md` (2C / 6H / 3M / 2L)

Total CRITICAL findings: **15** (some duplicates across audits — e.g. StillVideoBaker single-frame bug surfaced from 3 angles).

---

## Fixed in this PR (commit `<TBD>`)

| # | Audit | Issue | Fix |
|---|---|---|---|
| 1 | Audit-1-C1 / Audit-6-C1 | `StillVideoBaker.markDoneIfPossible()` set `_done` on every read, short-circuiting to one frame | Split into separate `isDone` read + `markDone()` write |
| 2 | Audit-2-F2 | `StillVideoBaker` early-throw paths leaked partial writer + .mov | `bailWithError` helper calls `cancelWriting()` + `removeItem` |
| 3 | Audit-2-F1 | `ClipLongPressPreview` `NotificationCenter` observer leak | Store token in `@State`, remove on `.onDisappear` |
| 4 | Audit-5-C1 | `navigationTitle("Alkloihd Video Swiss-AK")` shipped to home | Renamed to `"Compress"` |
| 5 | Audit-7-C1 | `StitchExporter.runPassthrough` cancel/fail leaked output file | `removeItem` in cancel/failed/unknown branches |
| 6 | Audit-1-C2 | `MetadataService.strip` missing CancelCoordinator → `NSInternalInconsistencyException` on mid-clean cancel | Backported `MetaCleanCancelCoordinator` mirroring CompressionService's |
| 7 | Audit-9-F1 | After save-to-Photos, `Documents/Outputs/` sandbox copy persisted (~600 MB stitch leaks) | `CacheSweeper.deleteIfInWorkingDir(outputURL)` post-save |
| 8 | Audit-9-F2 | Stitch + MetaClean save sites had same leak | Same fix wired into StitchExportSheet + MetaCleanExportSheet |

---

## Deferred to TASK files in this folder

The remaining CRITICAL + HIGH items are scoped as discrete TASK files Codex can pick up.

### CRITICAL deferred

| Audit | Issue | TASK file |
|---|---|---|
| Audit-5-C2 | No first-launch onboarding (MetaClean is the headline; users land on Compress with zero context) | `TASK-05-onboarding-screen.md` |
| Audit-6-C2 | Wipe transition is a horizontal squish, not a wipe (crop-rect is in source-pixel space, gets re-scaled by aspect-fit) | `TASK-30-wipe-transition-rewrite.md` |
| Audit-7-C2 | `buildPlan` cancellation between still bakes leaks already-baked .movs (locals never reach the Plan's `bakedStillURLs`) | `TASK-31-bake-cancel-cleanup.md` |
| Audit-7-C3 | `buildAudioMix` indexes `audioTracks[i % 2]` but skipped clips break parity → wrong clips' audio gets ramped | `TASK-32-audio-mix-track-parity.md` |
| Audit-7-C4 | `stageToStitchInputs` only suffix-collides on existing files; delete-then-reimport aliases stale undo-history references | `TASK-33-stage-collision-fix.md` |

### HIGH deferred

| Audit | Issue | TASK file |
|---|---|---|
| Audit-2-F3..F7 | Multiple cancel paths leak partial files + temp dirs | `TASK-99-cache-cleanup-on-cancel-and-save.md` (already exists, has full breakdown) |
| Audit-3-H1 | Apple `PrivacyInfo.xcprivacy` manifest missing — required since 2024 for many APIs | `TASK-34-privacy-manifest.md` |
| Audit-3-H2 | `StitchClipFetcher` Photos read without auth gate | `TASK-35-photos-auth-gate.md` |
| Audit-4-A | `StillVideoBaker` writes N frames serially; can be 2-frame O(1) via Apple's two-frame trick or `scaleTimeRange` | `TASK-01-still-bake-constant-time.md` (already exists) |
| Audit-4-B | `buildPlan` clip-iteration runs 6× serial awaits per clip under indeterminate `.building` spinner | `TASK-36-build-plan-progress.md` |
| Audit-4-H2 | Pinch-zoom rebuilds `.frame(width:)` on every gesture frame → layout thrash. Switch to `.scaleEffect(zoom)` | `TASK-37-pinch-zoom-scaleEffect.md` |
| Audit-5-H1 | "Cleaning N of M" copy is dev-y | `TASK-04-dev-y-copy-polish.md` (already exists) |
| Audit-5-H2 | Inline editor has duplicated scissors (header icon + prominent button) | `TASK-04-dev-y-copy-polish.md` |
| Audit-5-H4 | `CropEditorView` ships normalized X/Y/W/H float sliders (own footer admits "v2 surface") | `TASK-38-crop-editor-rewrite.md` |
| Audit-6-H1 | HDR (10-bit / BT.2020 / HLG) silently downgraded — washes out video | `TASK-39-hdr-passthrough.md` (BIG perceptual regression) |
| Audit-6-H2 | Audio bitrate disagreement: encoder 192 kbps vs estimator 128 kbps | `TASK-40-audio-bitrate-alignment.md` |
| Audit-6-H3 | Color primaries / transfer / YCbCr matrix not preserved | (folded into TASK-39) |
| Audit-6-H4 | Max preset re-encodes at source bitrate without 90% cap → output ≥ source | `TASK-41-max-preset-cap.md` |
| Audit-6-H5 | Audio mix volume ramp comment misleading; potential `setVolume(1.0)` vs `fromStartVolume: 0.0` conflict | (folded into TASK-32) |
| Audit-7-H3 | Transitions longer than clips silently produce broken output (cursor underflow) | `TASK-42-short-clip-transition-clamp.md` |
| Audit-7-H6 | No retry button on `AVErrorOperationInterrupted -11847` | `TASK-43-retry-on-interrupt.md` |
| Audit-7-H7 | No free-space check before export | `TASK-44-disk-space-check.md` |
| Audit-9-F4..F8 | Multiple cancel-path leaks + NSTemporaryDirectory not swept | `TASK-99-cache-cleanup-on-cancel-and-save.md` |

---

## Already-good zones (audits explicitly verified clean)

- Codec selection (HEVC/H.264 split per preset) ✅
- preferredTransform application ✅
- A/B-roll cursor pull-back math ✅
- `shouldKeepTrack(.metadata)` for iPhone GPS streams ✅
- autoMetaGlasses XMP gating with `fileHasFingerprint` ✅
- `cleanedURL` extension preservation ✅
- Writer fileType matching ✅
- BGRA bitmap info ✅
- AVAssetReaderAudioMixOutput plumbing ✅
- Limited Photos auth degradation in `saveAndOptionallyDeleteOriginal` ✅
- Identical-files-imported-twice ref-counted delete in `StitchProject.remove(at:)` ✅
- Mixed orientation + per-clip aspect-fit ✅
- Audio-less videos in compress ✅
- App is fundamentally privacy-clean: no network, no third-party SDKs, no secrets ✅
- PhotosPicker out-of-process picker used everywhere correctly ✅
- `PHPhotoLibrary.requestAuthorization` correctly scoped (`.addOnly` for save, `.readWrite` only for delete-original) ✅
- Cancellation through `withTaskCancellationHandler` correctly shaped in compress ✅

---

## Codex working order suggestion

1. **TASK-01** (still bake O(1)) — biggest perf win, single file change
2. **TASK-99** (cache cleanup on cancel + save + launch) — addresses user's specific concern across 5+ paths
3. **TASK-04** (dev-y copy polish) — small wins, App Store readiness
4. **TASK-05** (onboarding) — required for $4.99 paid app feel
5. **TASK-39** (HDR passthrough) — biggest perceptual regression
6. **TASK-02** (Meta marker registry) — the moat feature
7. **TASK-30** (wipe transition rewrite) — visual correctness
8. Everything else after a real on-device test cycle reveals what users notice
