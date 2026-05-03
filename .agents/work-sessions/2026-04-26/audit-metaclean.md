# Audit — MetaClean (Multi-File Metadata Removal)

Compiled: 2026-04-26 by [metaclean/general-sonnet]

## Verdict (one sentence)
Multi-file batch processing works end-to-end with surgical Meta-glasses fingerprint stripping intact (binary Comment + Keys:Description/CreationDate), but per-file progress is NOT streamed during the run — the UI sits in a single "Cleaning..." state and only updates after the entire backend loop finishes synchronously, so a 5-file batch with one slow HEIC has no visible progress until the whole HTTP response returns.

## Pipeline trace

### Frontend (public/js/metaclean.js)
- **Entry point:** `initMetaClean()` at `public/js/metaclean.js:279`, registered from `public/js/app.js:21,399`.
- **File ingest:** `addMetaFiles(fileList)` at `public/js/metaclean.js:41` pushes each File into the module-scoped `metacleanFiles` array with status `'pending'`. After ingest, the drop/change handlers (`metaclean.js:325-329, 339-342`) iterate pending entries and call `uploadMetaFile()` *one at a time* (`await` in a `for…of`), so uploads are sequential not parallel.
- **Per-file upload:** `uploadMetaFile(entry)` (`metaclean.js:60-80`) POSTs each file individually to `/api/upload`, transitioning status `pending → uploading → ready`. Each upload re-renders the list (`renderMetaFiles()` after every state change).
- **Batch submit:** `cleanFiles()` (`metaclean.js:89-143`) collects all `'ready'` files and sends them in a *single* `POST /api/metaclean` body containing `{ files: [{path,name},…], mode }`. Awaits the *entire* JSON response before updating any per-file UI.
- **Per-file progress:** None during processing. While the request is in flight, the only UI signal is the global Clean button text changing to `' Cleaning...'` (`metaclean.js:97`). Individual files keep their `'ready'` badge for the entire batch duration. Only after `await fetch(...)` resolves does the loop at `metaclean.js:117-125` zip `data.results[i] → readyFiles[i]` and flip each card to `'done'` or `'error'`.
- **Error handling (per file):** If the backend marks a file with `result.error`, the frontend sets `file.status = 'error'` and `file.error = result.error` (`metaclean.js:122-124`). One file's error does NOT short-circuit the others — the backend continues the loop and the frontend renders each card independently.
- **Top-level error handling:** A failed `fetch` throws and the entire `try` block in `cleanFiles()` falls through to `showNotification('MetaClean failed: …', 'error')` (`metaclean.js:132-134`). In that scenario *no* per-file state updates happen — every card stays on `'ready'`. There is no recovery / retry UI.
- **Tag preview UI:** Built in `renderMetaFiles()` (`metaclean.js:167-245`). Each completed card renders two collapsible buttons — Removed (count + line-through old values) and Preserved (count + values), both default-collapsed (`display: none`) with caret toggling at `metaclean.js:256-268`. Removed list shows `group:tag → oldValue` (truncated to 60 chars). Preserved list shows `group:tag → value` (truncated to 120 chars by `generateReport`). A "Download Clean" link is rendered when `f.result.outputPath` is set.

### Backend (server.js + lib/exiftool.js)
- **API:** `POST /api/metaclean` at `server.js:444-524`.
  - **Request shape:** `{ files: [{ path: string, name: string }, …], mode: 'attribution' | 'privacy' }`.
  - **Mode normalization:** `validMode = mode === 'privacy' ? 'privacy' : 'attribution'` at `server.js:450` — anything other than the literal `'privacy'` falls back to attribution mode (defensive default).
  - **Response shape:** `{ results: [{ path, name, status: 'cleaned'|'clean', success: true, outputPath, removedCount, removed, preserved, preservedCount } | { path, name, success: false, error }, …], mode }`.
- **Batch loop:** `for (const file of files)` at `server.js:453`. Per-file try/catch at `server.js:464-521` ensures each ExifTool failure is caught and pushed as an `{ success: false, error: err.message }` entry — the loop continues with the next file. The HTTP response is sent ONCE at the end (`res.json(...)` at `server.js:523`), so the client cannot see per-file completion mid-batch.
- **Per-file WebSocket broadcasts:** The backend DOES broadcast `metaclean-complete` (server.js:482, 504) and `metaclean-error` (server.js:519) via the existing `broadcast()` helper after each file. **But the frontend never subscribes to these messages** — `public/js/metaclean.js` has no WebSocket / `progress` listener. So the per-file events are emitted but unused. Confirmed by absence of `ws`/`onmessage`/`progress` handlers in metaclean.js.
- **ExifTool spawn:** `lib/exiftool.js:180-213` (`writeCleanCopy`). Uses `execFileAsync(tool.path, args, { timeout: 30000 })`. Args are built by appending `-Group:Tag=` for each removal, plus `-overwrite_original`, then the output path. Source is first copied via `fs/promises.copyFile` (line 206), then ExifTool strips on the copy.
- **Privacy-mode flags vs. attribution:** Both modes share the same ExifTool invocation; the difference is purely in *which* tags get computed for stripping by `computeRemovals()`. There are no extra command-line flags for privacy mode. Privacy adds removals for: `UserComment`, `ImageUniqueID`, `SerialNumber`, `InternalSerialNumber`, anything starting with `SubSec`, `Description`/`Caption-Abstract`/`ImageDescription` if they match the Meta pattern, `AndroidVersion`/`AndroidModel`, and crucially anything starting with `GPS`.
- **GPS-strip-in-privacy-mode logic:** `lib/exiftool.js:164-167`. The check is literally:
  ```
  if (tag.startsWith('GPS')) {
    removals.push({ group, tag, fullKey, oldValue: strValue });
    continue;
  }
  ```
  This runs only inside the `if (mode === 'privacy')` block (line 134), so attribution mode preserves GPS — which matches the documented contract ("attribution removes branding, privacy adds GPS+UUIDs"). The 2026-03-05 chat-log fix is intact.
- **Meta glasses Comment-binary strip:** `lib/exiftool.js:101-120`. Implementation:
  - Pre-scan: `const hasMetaAttribution = Object.values(metadata).some((v) => META_PATTERN.test(String(v)));` (line 102)
  - Per-tag check: `const isBinaryInMetaFile = hasMetaAttribution && strValue.startsWith('(Binary data');` (line 116)
  - Strip rule: `if (isAttributionTag && (META_PATTERN.test(strValue) || isBinaryInMetaFile))` (line 117)
  - This is the `a3ad413` fix — present and unchanged.
- **Description/CreationDate strip (Meta files):** `lib/exiftool.js:122-131`:
  ```
  if (
    hasMetaAttribution &&
    (tag === 'Description' || tag === 'CreationDate') &&
    group === 'Keys'
  ) { removals.push(...); continue; }
  ```
  This is the `be6e360` fix — present and unchanged. Runs in BOTH modes (it sits above the `mode === 'privacy'` block).
- **Output naming:** `lib/exiftool.js:184-194`. Pattern: `{name}_CLEAN{ext}` in `dirname(inputPath)`. Collision handling increments suffix: `_CLEAN_2`, `_CLEAN_3`, etc.
- **Output location:** Next to source (`dir = dirname(inputPath)`), as required. **Note:** when files are uploaded via the browser, `inputPath` lives in `UPLOAD_DIR` (`/tmp/.../video-compressor-uploads/`), so the `_CLEAN` copy lands in the temp dir alongside the upload — not in `~/Movies/Video Compressor Output` like compressed files. The frontend offers Download Clean but no auto-move to a user-visible folder. This differs from the compress flow which moves uploaded outputs to `OUTPUT_DIR` (`server.js:296-303`).

## Concerns checklist
| # | Concern | Verified? | Evidence (file:line) | Notes |
|---|---|---|---|---|
| 1 | Multi-file batch processed | YES | server.js:453-521 (for loop), public/js/metaclean.js:101-108 (single POST with all files) | Loop is sequential server-side; no Promise.all parallelism. |
| 2 | Per-file progress reported | **NO (visible)** | public/js/metaclean.js:117-125, server.js:482,504,519 | Backend emits per-file WS events but frontend never listens; UI only updates after full HTTP response returns. |
| 3 | HEIC + MOV + MP4 + JPG mixed input handled | YES | index.html:481 (accept attr), lib/exiftool.js:59-74 (format-agnostic ExifTool JSON read) | No format-specific code paths; ExifTool handles all four. accept="image/*,video/*,.heic,.heif,.mov,.mp4,.jpg,.jpeg,.png". |
| 4 | Privacy mode strips GPS | YES | lib/exiftool.js:164-167 | `tag.startsWith('GPS')` inside the `if (mode === 'privacy')` block. |
| 5 | Meta glasses Comment-binary stripped | YES | lib/exiftool.js:102, 116-117 | Pre-scan + `(Binary data` prefix detection — `a3ad413` fix intact. |
| 6 | Description/CreationDate stripped on Meta files | YES | lib/exiftool.js:122-131 | Triggered by `hasMetaAttribution && group==='Keys'` — `be6e360` fix intact. Runs in both modes. |
| 7 | Per-file error doesn't kill batch | YES (backend); PARTIAL (frontend) | server.js:464-520 (try/catch per file), public/js/metaclean.js:117-125 | Backend correctly continues. Frontend correctly maps errors per-file. BUT if the OUTER fetch throws (network error), every card stays on `'ready'` with no per-file feedback — only a global notification (metaclean.js:132-134). |
| 8 | Output `_CLEAN` next to source | YES (with caveat) | lib/exiftool.js:184-194 | Suffix correct. "Next to source" = next to the *path passed to the API*, which for browser uploads is `/tmp/.../video-compressor-uploads/`, not the user's Movies folder. Different from compress flow (`server.js:296-303`). |
| 9 | Removed/Preserved tag UI is expandable | YES | public/js/metaclean.js:180-225, 256-268 | Two collapsible buttons (Removed / Preserved), default-collapsed, caret flips ▶/▼ on toggle. |
| 10 | isSafePath() guards on the endpoint | YES | server.js:455-462 | Per-file check inside the loop. Pushes `{ error: 'Access denied' }` and continues rather than 403-ing the whole batch. Also: missing-file check at server.js:459. |

## Gaps & risks
- **server.js:444-524 / public/js/metaclean.js:101-108** — *No streaming progress.* The `/api/metaclean` endpoint runs the entire batch synchronously inside the request handler and returns one giant JSON. With a 5-file batch that includes a multi-GB MOV, the user sees a static "Cleaning..." button with no per-file feedback for potentially minutes. The infrastructure is half-built: `broadcast()` already emits `metaclean-complete`/`metaclean-error` per file (server.js:482,504,519), but `metaclean.js` has no WebSocket subscription to consume them. **Severity: P1 noticeable.** Adding a `progress.js`-style listener on `metaclean-complete`/`metaclean-error` would flip individual cards in real time without backend changes.
- **public/js/metaclean.js:132-134** — *Outer-fetch error swallows per-file state.* If the network drops or the backend crashes mid-batch, the UI shows only a toast and every card remains stuck on `'ready'`. There's no retry button or per-file error attribution. **Severity: P2 nice-to-have.** Not common in localhost use.
- **public/js/metaclean.js:60-80, 326-329, 339-342** — *Sequential uploads.* Each file is uploaded one at a time via `await uploadMetaFile(entry)` in a `for…of`. For a batch of 10+ files this serializes upload time. Multer (`server.js:139` uses `upload.array('file', 20)`) supports up to 20 files in one POST, but the frontend never uses that capability. **Severity: P2 nice-to-have.**
- **lib/exiftool.js:184-194 / server.js (no MetaClean output remap)** — *Uploaded-file outputs land in temp dir.* When the browser uploads a HEIC, `inputPath` is `/tmp/.../video-compressor-uploads/<uuid>.heic` and `_CLEAN` is written there. The user's only path to retrieve it is the "Download Clean" link. Stale-upload cleanup at startup (`server.js:39-55`) calls `unlink` on every file in `UPLOAD_DIR` — meaning a `_CLEAN` left from a prior session gets nuked next server start. The compress flow has a special case (`server.js:296-303`) that moves uploaded outputs to `~/Movies/Video Compressor Output`; the MetaClean flow lacks this. **Severity: P1 noticeable** for users who compress + clean in different sessions and don't immediately download.
- **lib/exiftool.js:73** — *ExifTool JSON parse assumes single-file output.* `Array.isArray(parsed) ? parsed[0] : parsed` discards index 1+ silently. For the current call path (one file at a time) this is fine, but if a future change ever passes multiple paths to one ExifTool invocation it would silently lose data. **Severity: P2 nice-to-have, pre-existing.**
- **lib/exiftool.js:211** — *`execFileAsync` 30s timeout is per-spawn.* For a multi-GB Meta-glasses MOV, ExifTool I/O on the copy step (`copyFile` at line 206) plus the strip step (line 211) might exceed 30s on slow disks, throwing a timeout error that the per-file handler will surface as `{ error: 'Command failed: …' }`. The batch would continue but that file would silently fail. **Severity: P2 nice-to-have.**
- **public/js/metaclean.js:184-188** — *Inline styles, no CSS class.* The Removed/Preserved expand buttons use `style="..."` attributes rather than reusable themed classes (e.g. `.themed-tag-toggle`). Mostly a code-style concern, not a bug. Theme variables ARE referenced (`var(--status-error-text)` etc.), so dark/light mode still works. **Severity: P2 nice-to-have.**
- **public/js/metaclean.js:159-165** — *No `'cleaning'` status.* statusMap has `pending/uploading/ready/done/error` but nothing for "currently being processed by ExifTool." Combined with the no-streaming-progress issue above, a batch in flight visually looks identical to a batch that hasn't started. **Severity: P1 noticeable.**

## Recommendations
None — this is read-only. Documented above; no code changes per audit scope.
