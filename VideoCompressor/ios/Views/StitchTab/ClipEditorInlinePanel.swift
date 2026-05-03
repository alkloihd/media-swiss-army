//
//  ClipEditorInlinePanel.swift
//  VideoCompressor
//
//  Inline replacement for the modal `ClipEditorSheet`. Renders directly in
//  the StitchTab body, below the timeline, so editing doesn't require a
//  modal. Tapping a different clip switches the panel's content; tapping
//  the X close button (or the same clip again) collapses it.
//
//  Layout:
//    ┌────────────────────────────────────────────┐
//    │ Clip Name              ⟲  ⟳  ✂︎  ↺  ✕     │  ← header + toolbar
//    ├────────────────────────────────────────────┤
//    │  [video player] ← AVPlayer w/ scrubber     │
//    │  [playhead slider]                          │
//    │  [trim slider — DualThumbSlider]            │
//    │  [duration label]                           │
//    └────────────────────────────────────────────┘
//
//  Toolbar actions:
//    ⟲  Undo            (project.undo)
//    ⟳  Redo            (project.redo)
//    ✂︎  Split at playhead (project.split)
//    ↺  Reset edits     (project.resetEdits)
//    ✕  Close panel     (selection cleared)
//

import SwiftUI
import AVKit
import AVFoundation

struct ClipEditorInlinePanel: View {
    @ObservedObject var project: StitchProject
    let clipID: StitchClip.ID
    var onClose: () -> Void

    @State private var player: AVPlayer
    @State private var playheadSeconds: Double = 0
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false
    @State private var startSnapshotForUndo: ClipEdits?
    @State private var endSnapshotForUndo: ClipEdits?
    /// Periodic time observer token — must be removed on disappear / clip swap
    /// or the AVPlayer leaks.
    @State private var timeObserverToken: Any?

    init(project: StitchProject, clipID: StitchClip.ID, onClose: @escaping () -> Void) {
        self.project = project
        self.clipID = clipID
        self.onClose = onClose
        if let clip = project.clips.first(where: { $0.id == clipID }) {
            self._player = State(initialValue: AVPlayer(url: clip.sourceURL))
        } else {
            self._player = State(initialValue: AVPlayer())
        }
    }

    private var clip: StitchClip? {
        project.clips.first(where: { $0.id == clipID })
    }

    private var naturalDuration: Double {
        clip.map { CMTimeGetSeconds($0.naturalDuration) } ?? 0
    }

    private var currentStart: Double { clip?.edits.trimStartSeconds ?? 0 }
    private var currentEnd: Double { clip?.edits.trimEndSeconds ?? naturalDuration }

    var body: some View {
        if let clip = clip {
            VStack(spacing: 10) {
                header(clip: clip)
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(durationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                playheadSlider
                trimSlider

                splitHint
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .background(.bar)
            .onAppear { onAppearWithClip() }
            .onDisappear { teardown() }
            .onChange(of: clipID) { _, _ in swapClip() }
        } else {
            // Clip vanished mid-edit (deleted from timeline). Auto-close.
            Color.clear.onAppear { onClose() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(clip: StitchClip) -> some View {
        HStack(spacing: 8) {
            Text(clip.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()

            Button {
                project.undo(for: clipID)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!project.canUndo(for: clipID))
            .accessibilityLabel("Undo")
            .accessibilityIdentifier("clipEditorUndo")

            Button {
                project.redo(for: clipID)
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!project.canRedo(for: clipID))
            .accessibilityLabel("Redo")
            .accessibilityIdentifier("clipEditorRedo")

            Button {
                splitAtPlayhead()
            } label: {
                Image(systemName: "scissors")
            }
            .disabled(!canSplitAtPlayhead)
            .accessibilityLabel("Split at playhead")
            .accessibilityIdentifier("clipEditorSplit")

            Button {
                project.resetEdits(for: clipID)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset edits")
            .accessibilityIdentifier("clipEditorReset")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close editor")
            .accessibilityIdentifier("clipEditorClose")
        }
        .font(.title3)
        .padding(.top, 10)
    }

    // MARK: - Playhead slider

    @ViewBuilder
    private var playheadSlider: some View {
        Slider(
            value: Binding(
                get: { playheadSeconds },
                set: { newValue in
                    playheadSeconds = newValue
                    seekTo(newValue)
                }
            ),
            in: 0 ... max(naturalDuration, 0.1)
        ) { editing in
            isDraggingPlayhead = editing
            if editing {
                player.pause()
            }
        }
        .accessibilityIdentifier("clipEditorPlayheadSlider")
    }

    // MARK: - Trim slider

    @ViewBuilder
    private var trimSlider: some View {
        DualThumbSlider(
            start: Binding(
                get: { currentStart },
                set: { newValue in
                    let clamped = max(0, min(newValue, currentEnd - 0.1))
                    project.updateEdits(for: clipID) {
                        $0.trimStartSeconds = clamped
                    }
                    seekTo(clamped)
                }
            ),
            end: Binding(
                get: { currentEnd },
                set: { newValue in
                    let clamped = max(currentStart + 0.1, min(newValue, naturalDuration))
                    project.updateEdits(for: clipID) {
                        $0.trimEndSeconds = clamped
                    }
                    seekTo(max(currentStart, clamped - 2.0))
                }
            ),
            range: 0 ... max(naturalDuration, 0.1),
            isDraggingStart: $isDraggingStart,
            isDraggingEnd: $isDraggingEnd
        )
        .frame(height: 36)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("clipEditorTrimSlider")
        .onChange(of: isDraggingStart) { wasDragging, dragging in
            if dragging && !wasDragging {
                // Drag started — snapshot the pre-edit state for undo.
                startSnapshotForUndo = clip?.edits
            }
            if wasDragging && !dragging {
                // Drag ended — commit the snapshot if it differs from now.
                if let snap = startSnapshotForUndo, snap != clip?.edits {
                    project.commitHistorySnapshot(for: clipID, previous: snap)
                }
                startSnapshotForUndo = nil
            }
        }
        .onChange(of: isDraggingEnd) { wasDragging, dragging in
            if dragging && !wasDragging {
                endSnapshotForUndo = clip?.edits
            }
            if wasDragging && !dragging {
                if let snap = endSnapshotForUndo, snap != clip?.edits {
                    project.commitHistorySnapshot(for: clipID, previous: snap)
                }
                endSnapshotForUndo = nil
            }
        }
    }

    // MARK: - Split hint

    @ViewBuilder
    private var splitHint: some View {
        Text("Drag the playhead to a moment, then tap ✂︎ to split. To remove a section, split at both ends, then long-press the middle clip and Delete.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Computed

    private var canSplitAtPlayhead: Bool {
        // Splittable when playhead is strictly inside the trim window with
        // a 0.1s margin (mirrors StitchProject.split's guard).
        playheadSeconds > currentStart + 0.1 && playheadSeconds < currentEnd - 0.1
    }

    private var durationLabel: String {
        let dur = max(0, currentEnd - currentStart)
        let m = Int(dur) / 60
        let s = Int(dur) % 60
        let cs = Int((dur - Double(Int(dur))) * 100)
        return String(format: "Trim %d:%02d.%02d / Playhead %.2f s",
                      m, s, cs, playheadSeconds)
    }

    // MARK: - Actions

    private func splitAtPlayhead() {
        guard canSplitAtPlayhead else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if project.split(clipID: clipID, atSeconds: playheadSeconds) {
            // After a split, the second half has a different ID; the first
            // retains `clipID`. Selection stays on `clipID` (now the first
            // half) automatically. Reseat the player at the new (truncated)
            // end if the playhead was inside the now-second-half range.
            playheadSeconds = currentEnd
            seekTo(currentEnd)
        }
    }

    // MARK: - Player wiring

    private func onAppearWithClip() {
        attachTimeObserver()
        seekTo(currentStart)
    }

    private func swapClip() {
        teardown()
        if let clip = clip {
            player.replaceCurrentItem(with: AVPlayerItem(url: clip.sourceURL))
            attachTimeObserver()
            seekTo(currentStart)
            playheadSeconds = currentStart
        }
    }

    private func teardown() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player.pause()
    }

    private func attachTimeObserver() {
        // 30 Hz scrubber updates — fast enough to feel live, slow enough to
        // not dominate main-thread work.
        let interval = CMTime(value: 1, timescale: 30)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            // Don't fight the user while they're scrubbing manually.
            if !isDraggingPlayhead {
                playheadSeconds = CMTimeGetSeconds(time)
            }
        }
    }

    private func seekTo(_ seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
