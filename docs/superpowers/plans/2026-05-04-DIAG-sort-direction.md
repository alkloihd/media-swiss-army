# DIAG: Sort Direction Bug — Stitch Tab Imports Newest-First

**File:** `docs/superpowers/plans/2026-05-04-DIAG-sort-direction.md`
**Date:** 2026-05-04
**Investigator:** diagnostic agent (claude-sonnet-4-6)

---

## 1. Symptom

> "the default order seems to be in reverse chronological newest to latest and should be oldest to newest"

When the user imports photos/videos via PhotosPicker into the Stitch tab, the clips appear in newest-first order. The user expects oldest-first by default.

---

## 2. Where the Order Comes From

### The sort comparator is CORRECT (ascending = oldest-first)

`StitchProject.swift:136`:
```swift
case let (.some(l), .some(r)) where l != r: return l < r
```
`l < r` means earlier date sorts first. The direction of the sort itself is not the bug.

### The sort is NEVER called automatically on import

`StitchTabView.swift:134–139` — the `.onChange(of: pickerItems)` handler:
```swift
.onChange(of: pickerItems) { _, newItems in
    guard !newItems.isEmpty else { return }
    let items = newItems
    pickerItems = []
    Task { await importClips(items) }   // ← no sort call after this
}
```

`StitchTabView.swift:242–375` — `importClips(_:)` appends each clip with `project.append(clip)` then exits. There is **no call to `sortByCreationDateAsync()`** at the end of the function.

`StitchTabView.swift:93–101` — the only call to `sortByCreationDateAsync()` is inside the toolbar menu action button:
```swift
Button {
    Task {
        let changed = await project.sortByCreationDateAsync()
        ...
    }
} label: {
    Label("Sort by Date Taken", systemImage: "calendar")
}
```

### Why the order looks newest-first

PhotosPicker (`PHPickerViewController`) presents the photo library in reverse chronological order by default (most recent at top). When the user selects multiple items from that presentation, the system delivers them in **selection order**, which for a casual multi-select from the top of the library will be newest-first. The clips are appended in that delivery order without any reordering.

---

## 3. Root Cause

**Finding (c):** `sortByCreationDateAsync()` exists and has the correct comparator (`<`, ascending), but it only fires as an explicit user gesture ("Sort by Date Taken" toolbar menu). It is never called automatically after `importClips()` completes. The default clip order after import equals the delivery order from PhotosPicker, which is newest-first for the typical case (selecting from the top of the default Recents album).

There is no sort called at import in either `importClips` (StitchTabView.swift:242) or `VideoLibrary.importPickedItems` (VideoLibrary.swift:77). The compress tab (`VideoLibrary`) does not sort at all — but sort order is irrelevant there since compress processes files independently.

---

## 4. Recommended Fix

### Option A — Auto-sort on import (recommended default behaviour)

Add a `sortByCreationDateAsync()` call at the end of `importClips(_:)` in `StitchTabView.swift`, after the `for` loop finishes:

```swift
// At line 374, after the closing brace of the for-item loop:
    }   // end for item in items

    // Auto-sort by capture date after every import batch.
    // This gives oldest-first order by default, matching the
    // user's mental model of a chronological video timeline.
    await project.sortByCreationDateAsync()
```

The `sortByCreationDateAsync()` already handles:
- Batch PHAsset date lookup (one call for all N clips, not N serial calls)
- Clips with no `originalAssetID` (drag-drop, share extension) sort to the end stably
- Returns false and skips UI update if the order didn't change

**Cost:** One batch Photos fetch (`PHAsset.fetchAssets(withLocalIdentifiers:[allIDs])`) at the end of import. For 50 clips this is ~1–5 ms. Already proven in the existing toolbar action path.

### Option B — Settings preference (if auto-sort should be opt-in)

Expose a Settings toggle backed by `@AppStorage("sortByDateOnImport")` defaulting to `true`. In `importClips(_:)`:

```swift
@AppStorage("sortByDateOnImport") private var sortByDateOnImport = true

// After the for loop:
if sortByDateOnImport {
    await project.sortByCreationDateAsync()
}
```

Add a row in `SettingsTabView.swift` under a "Stitch" section.

**Recommendation:** Default to Option A (always auto-sort). The user's mental model of a stitch timeline is inherently chronological, and the existing manual "Sort by Date Taken" toolbar action can still be used to re-sort after manual reordering. If a future user requests "preserve my selection order", a Settings toggle can be added then. YAGNI favours Option A now.

---

## 5. Cluster Assignment

**Cluster 2 — Stitch Correctness** (`2026-05-04-phase1-cluster2-stitch-correctness.md`).

The auto-sort-on-import is a correctness/defaults issue for the Stitch timeline, directly in scope for the Cluster 2 work that already addresses `sortByCreationDateAsync` and the H-1 split/duplicate inheritance fixes. The one-line change at StitchTabView.swift:374 can be shipped alongside those fixes.

If Cluster 2 is already closed, absorb into **Cluster 3 — UX Polish** as a UX defaults quality-of-life fix.

This is NOT a Cluster 0 hotfix because the sort comparator direction is correct; only the auto-trigger is missing.

---

## 6. Pre-existing Red-Team Coverage

`RED-TEAM-CHRONO-SORT.md` reviewed this PR and found **0 CRITICAL, 3 HIGH** issues — none of which is the auto-sort-on-import omission. The red team focused on: split/duplicate clip date inheritance (H-1), serial Photos fetching in the import loop (H-2), and Hashable conformance (H-3). The "no auto-sort on import" behaviour was not flagged as a defect because the PR spec described the sort as an explicit menu action only.

The current bug report changes the spec: **the sort should be the default**, not an opt-in gesture.

---

## 7. Manual iPhone Test

1. Open the Stitch tab with an empty project.
2. Tap "+" and import 5 photos taken on different dates (mix old and recent).
3. Without tapping any menu button, verify the timeline shows clips in **oldest-first** order (earliest date at the left/top).
4. Drag two clips to swap them, then tap "Sort by Date Taken" from the sort menu — verify it re-sorts correctly.
5. Import a video via Files (share extension, no PHAsset ID) — verify it sorts to the **end** of the timeline, after all date-bearing clips.
