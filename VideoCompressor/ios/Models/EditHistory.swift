//
//  EditHistory.swift
//  VideoCompressor
//
//  Per-clip undo/redo for the inline stitch editor.
//
//  Design notes:
//  - One `EditHistory` instance per clip ID lives in `StitchProject.histories`.
//    Each clip keeps its own stacks; switching the selected clip in the
//    inline editor switches which history is the active undo/redo target.
//  - We DO NOT record every drag-delta — only "committed" snapshots produced
//    when a drag interaction completes (DualThumbSlider's `isDragging` flips
//    false). Otherwise a 5-second trim drag would emit ~300 history entries.
//  - Capacity is bounded (default 32) to keep memory bounded across long
//    edit sessions. Oldest entries drop off the back of the undo stack.
//  - This is a value-typed reducer-like API — the type doesn't own
//    `current`. Callers (StitchProject) own the canonical edits and ask
//    EditHistory for "should I commit?", "what's the previous?", etc.
//
//  Phase 3 follow-up commit (post-aspect-ratio).
//

import Foundation

struct EditHistory: Hashable, Sendable {
    /// Edits the user can revert TO via Undo. Most-recent at the end.
    private(set) var undoStack: [ClipEdits]
    /// Edits previously undone, available via Redo. Most-recent at the end.
    private(set) var redoStack: [ClipEdits]
    /// Maximum entries kept in either stack. Drop oldest when exceeded.
    let capacity: Int

    init(capacity: Int = 32) {
        self.undoStack = []
        self.redoStack = []
        self.capacity = max(2, capacity)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { undoStack.isEmpty && redoStack.isEmpty }

    // MARK: - Mutations

    /// Record `previous` as the state to return to via Undo. Clears the
    /// redo stack — once the user makes a fresh change, we throw away the
    /// previously-undone branch (standard editor semantics).
    ///
    /// Caller must compute "previous" themselves (i.e., snapshot the edits
    /// BEFORE applying the new value). EditHistory does not look at the
    /// current edits.
    mutating func commit(previous: ClipEdits) {
        // Coalesce identical successive snapshots — releasing a thumb at
        // the same value should not bloat the stack.
        if let last = undoStack.last, last == previous { return }
        undoStack.append(previous)
        if undoStack.count > capacity {
            undoStack.removeFirst(undoStack.count - capacity)
        }
        redoStack.removeAll(keepingCapacity: false)
    }

    /// Pop the most recent undo entry. Caller is expected to apply the
    /// returned value as the new edits AND push the previous "current"
    /// onto the redo stack via `pushRedo(current:)` so a Redo can return.
    mutating func popUndo() -> ClipEdits? {
        undoStack.popLast()
    }

    /// Pop the most recent redo entry. Caller pushes the previous current
    /// onto the undo stack via `pushUndo(current:)` so further Undo works.
    mutating func popRedo() -> ClipEdits? {
        redoStack.popLast()
    }

    mutating func pushUndo(current: ClipEdits) {
        // No coalescing here — caller is responsible for ensuring monotone
        // progression. (Coalescing happens in `commit`.)
        undoStack.append(current)
        if undoStack.count > capacity {
            undoStack.removeFirst(undoStack.count - capacity)
        }
    }

    mutating func pushRedo(current: ClipEdits) {
        redoStack.append(current)
        if redoStack.count > capacity {
            redoStack.removeFirst(redoStack.count - capacity)
        }
    }

    /// Reset clears both stacks. Call after a "Reset to Identity" action
    /// where the user explicitly threw away all edit history.
    mutating func reset() {
        undoStack.removeAll(keepingCapacity: false)
        redoStack.removeAll(keepingCapacity: false)
    }
}
