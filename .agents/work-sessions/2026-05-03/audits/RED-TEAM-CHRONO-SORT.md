# Red Team — Chronological Photo Sort

Branch: `feat/photo-chronological-sort` (working-tree changes on top of `cca84e2`).
Reviewer: solo/opus, 2026-05-03.

Files reviewed:
- `VideoCompressor/ios/Services/StitchClipFetcher.swift` (new, 40 lines)
- `VideoCompressor/ios/Models/StitchClip.swift` (modified — added 2 fields + init params)
- `VideoCompressor/ios/Models/StitchProject.swift` (added `sortByCreationDate()`)
- `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` (toolbar menu + import-loop capture)
- `VideoCompressor/VideoCompressorTests/StitchProjectSortTests.swift` (new, 6 tests)

Source-context corrections vs. PR description:
- The PR notes claim "after split, both halves have the same creationDate (inherited from original)" and "duplicate copies inherit creationDate." **Neither is true** — see HIGH-1.

---

## CRITICAL

_None._ The shipped behavior is safe; everything here is correctness/UX-grade.

---

## HIGH

| # | File | Line | Issue | Fix |
|---|---|---|---|---|
| H-1 | `ios/Models/StitchProject.swift` | 262–281, 359–368 ; `ios/Views/StitchTab/StitchTimelineView.swift` 178–187 ; `ios/Services/StitchExporter.swift` 100–109 | **Split halves, duplicates, and baked-still clips silently lose `originalAssetID` + `creationDate`.** All four call sites construct `StitchClip(...)` without passing the two new fields, so they default to nil. After a user splits a clip and then taps "Sort by Date Taken", that clip's two halves jump to the end of the timeline (nil-dated) instead of staying together at their original chronological position. Same for duplicates and stills (after the export-time bake, but baked-still clips are short-lived so lower impact). This contradicts the PR description's stated assumption. | At each of the four call sites, pass `originalAssetID: clip.originalAssetID, creationDate: clip.creationDate` (or `originalAssetID: firstHalf.originalAssetID, creationDate: firstHalf.creationDate` for the merge). 4 lines per site. |
| H-2 | `ios/Views/StitchTab/StitchTabView.swift` | 245, 349 | **Per-item serial Photos fetch in the import loop blocks subsequent imports.** `for item in items` is sequential and `await StitchClipFetcher.creationDate(...)` happens inside the loop. For 50 clips, that's 50 sequential `Task.detached` round-trips through the Photos framework on top of the existing video Transferable + AVURLAsset probe. Each `PHAsset.fetchAssets(withLocalIdentifiers:)` is fast (~ms) but the Task hop adds priority-inversion risk and serializes work that has no data dependency. User-visible symptom: import progress stalls at clip N while clip N+1 waits. Note: this is also serialized with the existing AVURLAsset probe, which is the dominant cost — but the new call is extra cost on the same critical path. | Capture `assetID` synchronously outside the Task hop (it's already pure; `item.itemIdentifier` is sync), then either (a) drop the Task.detached and call `PHAsset.fetchAssets` inline since it's already a sync call (the Task hop is misleading — the underlying API is synchronous and fast), or (b) capture `assetID` only at import and resolve all dates lazily in `sortByCreationDate()` in one batch fetch. Option (b) is the cleanest: one call to `PHAsset.fetchAssets(withLocalIdentifiers: [allIDs])` at sort time. |
| H-3 | `ios/Models/StitchClip.swift` | 109–159 | **Synthesised `Hashable` now folds `originalAssetID` + `creationDate` into the hash.** `StitchClip` is `Hashable` and used in tests via `XCTAssertEqual` and likely as `Identifiable` in SwiftUI ForEach. Two clips that were `==` before this change (same id, source, name, etc.) are no longer equal if one captured a date at import and the other didn't. Specifically, `EditHistoryTests` and `StitchClipTests` may compare clip values after a round-trip — a test that constructs a clip without dates and expects equality with one that has them would now fail. Empirically the PR claims 138/138 pass, so this is latent rather than active, but the risk is non-trivial. | Either (a) implement explicit `Equatable` / `Hashable` keyed on `id` only (since `id` is a UUID and unique, that's the natural identity), or (b) accept the synthesised conformance and add a comment noting that two clips with the same id but different dates are now not-equal. Option (a) is more robust. |

---

## MEDIUM

| # | File | Line | Issue | Fix |
|---|---|---|---|---|
| M-1 | `ios/Services/StitchClipFetcher.swift` | 31–38 | **`Task.detached(priority: .userInitiated)` for a sub-millisecond synchronous call is overkill** and adds two context switches per clip. `PHAsset.fetchAssets(withLocalIdentifiers:options:)` is a synchronous in-memory lookup against the Photos library cache; it does not block on disk I/O for the metadata subset (creationDate is in the cache). The Task hop converts a microsecond op into a hundred-microsecond op and complicates the cancellation model. | Remove `Task.detached`. Make the function `static func creationDate(forAssetID:) -> Date?` (synchronous). Callers can wrap in a Task themselves if they need it off-main. |
| M-2 | `ios/Views/StitchTab/StitchTabView.swift` | 90 | **Toolbar menu visibility flips at exactly `clips.count == 2`.** When the user adds a second clip and then deletes it, the sort menu appears and disappears, causing a layout shift in the toolbar. SwiftUI animates this jankily with the default toolbar transitions. Minor UX wart. | Change `if project.clips.count >= 2` to always render the Menu but disable the button when `< 2`: `.disabled(project.clips.count < 2)`. The menu glyph stays put; only the affordance state changes. |
| M-3 | `ios/Models/StitchProject.swift` | 127–145 | **`sortByCreationDate` runs while an export is in flight.** There is no `guard !isExporting else { return false }` check. The export already snapshots `clipsSnapshot = clips` (line 383), so the in-flight composition itself is safe — but the user has just re-ordered the timeline they think they're exporting, and the next export will use the new order. Confusing. | Add `guard !isExporting else { return false }` at the top of `sortByCreationDate()`, OR disable the toolbar menu while `project.isExporting`. The latter is more discoverable. |
| M-4 | `VideoCompressorTests/StitchProjectSortTests.swift` | 17–27 | **No test covers split/duplicate inheritance** (which doesn't currently work, per H-1). Once H-1 is fixed, a regression test is needed: split a dated clip, sort, assert both halves group together. | Add `testSplitHalvesShareCreationDate()` and `testDuplicateInheritsCreationDate()`. ~20 lines each. |
| M-5 | `ios/Models/StitchProject.swift` | 132 | **Index-tuple stable-sort works but is not the idiomatic Swift approach.** Swift's `sorted(by:)` is documented as **not** stable. The current code compensates by adding the original index as a tiebreaker — that's correct, but a future refactorer might "simplify" it back to `clips.sort { $0.creationDate ?? .distantFuture < $1.creationDate ?? .distantFuture }` and silently lose stability. | Add a comment immediately above the closure: `// Swift's sort is NOT stable — the index tiebreaker below provides stability.` Or extract a private `stableSorted` helper. |

---

## LOW

| # | File | Line | Issue | Fix |
|---|---|---|---|---|
| L-1 | `ios/Services/StitchClipFetcher.swift` | 18 | `enum StitchClipFetcher` with one `static` method. Acceptable Swift idiom for a namespace; just noting it. No fix needed. | n/a |
| L-2 | `ios/Models/StitchProject.swift` | 134 | The pattern `case let (.some(l), .some(r)) where l != r: return l < r` followed by `default: return lhs.offset < rhs.offset` correctly handles the equal-date case, but the control flow is dense. A reader has to think about why `(some, some) where l == r` falls through to `default`. | Add inline comment: `// equal dates fall through to default → preserve original index order`. |
| L-3 | `ios/Views/StitchTab/StitchTabView.swift` | 95 | `Haptics.notifyWarning()` when the sort is a no-op. `notifyWarning` (the system "uh-oh" pattern) is too strong for "your clips are already in date order." Consider `Haptics.tapLight()` or no haptic at all. | Soften to `tapLight` or omit. |
| L-4 | `VideoCompressorTests/StitchProjectSortTests.swift` | 73–84 | `testStableForEqualDates` asserts `XCTAssertFalse(changed)` — but with three identical-date clips already in stable order, `before == after`, so the function correctly returns false. Verified by reading sortByCreationDate: it computes `before` and `after` arrays of ids and compares. ✓ | n/a |
| L-5 | `ios/Models/StitchClip.swift` | 130 | Comment says `originalAssetID` is "iOS 16+" — confirm the deployment target is ≥ iOS 16 (PhotosPicker requires it anyway). | Verify in `Info.plist` / project settings. Likely fine. |
| L-6 | `ios/Services/StitchClipFetcher.swift` | 36 | `return nil as Date?` — the `as Date?` cast is unnecessary; the closure return type is inferred from the explicit `nil` in the surrounding match. Stylistic. | `return nil` works after explicit return type. |

---

## OK / non-issues

- **Sort is O(n log n) and stable.** Verified by the index-tuple tiebreaker pattern. For 50 clips, sort runs in microseconds on the main actor — no main-thread concern. (D/B section of brief.)
- **No leak in `Task.detached` pattern.** The closure captures only `assetID` (a `String`), no self/project. The `.value` await is structured, so the Task lifetime is bounded by the caller. (C section.)
- **Selection survives reorder.** `selectedClipID` is a `UUID` (line 25 of StitchTabView), and views all key off `clip.id` rather than position. Sorting cannot orphan the selection. (E section.)
- **`PHAsset.fetchAssets(withLocalIdentifiers:)` works under `.limited` access** for assets the user has granted; returns empty `firstObject = nil` for non-granted IDs, which is handled by the `guard` on line 36. Same graceful-nil for deleted assets. (D/E section.)
- **No new exfiltration vector.** `originalAssetID` is in-memory only, never serialized, never transmitted. App Privacy Details require no update — `creationDate` is a derived attribute of the photo the user already disclosed access to. (D section.)
- **In-flight export composition is safe.** `runExport` snapshots `clips` into `clipsSnapshot` before any await, so a re-sort during encoding cannot scramble the in-flight composition (line 383). M-3 is about user perception, not data integrity.
- **Drag-drop / share extension imports** end up with `assetID = nil` and `creationDate = nil` — they sort to the end with stable relative order, exactly per spec.
- **Burst photos with identical timestamps** preserve relative import order via the index tiebreaker (`testStableForEqualDates` confirms).
- **Identical asset imported twice** gets the same `creationDate`, and both clips have distinct UUIDs so they're independent in the timeline. Sort places them adjacent with stable relative order. File ref-counting in `remove(at:)` was already correct (PR #6).

---

## Recommended ship triage

**Block ship until H-1 is fixed.** Split + duplicate are first-class features in this app; a sort that reorders split halves to opposite ends of the timeline will surprise users immediately. The fix is a 4-line patch across 4 sites — no architectural change. Add the M-4 regression test alongside.

**Address before ship if time allows:**
- H-2 (batch fetch at sort time) — concrete UX bottleneck for 50-clip imports, but mitigated by the existing AVURLAsset probe already dominating import latency. Acceptable to defer if H-1 is in.
- M-2 (toolbar flicker) — small but visible.
- M-3 (sort during export guard) — one-line guard, defensible to add now.

**Defer post-ship:**
- H-3 (explicit Equatable on `id`) — latent and tests pass. Add a brief comment now; full refactor later.
- M-1 (drop Task.detached) — perf nit only.
- L-1 through L-6 — polish.

**Summary: 0 CRITICAL, 3 HIGH, 5 MEDIUM, 6 LOW.** Ship-blocker is H-1.
