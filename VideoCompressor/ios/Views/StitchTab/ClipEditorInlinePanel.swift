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
    /// Tick haptics — fire on each value-bucket crossing during continuous
    /// drag. Trim handles snap to 0.5 s; playhead fires every 1.0 s; still
    /// duration is already 0.5 s step-quantised by the slider itself.
    @StateObject private var trimStartTicker = HapticTicker(step: 0.5)
    @StateObject private var trimEndTicker = HapticTicker(step: 0.5)
    @StateObject private var playheadTicker = HapticTicker(step: 1.0)
    @StateObject private var stillDurationTicker = HapticTicker(step: 0.5)

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

                // Stills get a static image preview; videos get the AVPlayer.
                // Without this branch, AVPlayer(url: heicURL) renders a black
                // rectangle and feels broken (closes hotfix May 2026).
                if clip.kind == .still {
                    StillPreview(url: clip.sourceURL)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if clip.kind == .still {
                    stillDurationControl(clip: clip)
                } else {
                    Text(durationLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    playheadSlider
                    splitButtonRow
                    trimSlider

                    splitHint
                }
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

    // MARK: - Still duration control

    @ViewBuilder
    private func stillDurationControl(clip: StitchClip) -> some View {
        let duration = clip.edits.stillDuration ?? 3.0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Display duration")
                    .font(.subheadline)
                Spacer()
                Text("\(String(format: "%.1f", duration)) s")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Slider(
                value: Binding(
                    get: { duration },
                    set: { newValue in
                        let clamped = min(10.0, max(1.0, newValue))
                        // Snapshot pre-drag for undo on the very first set.
                        if startSnapshotForUndo == nil {
                            startSnapshotForUndo = clip.edits
                        }
                        project.updateEdits(for: clipID) {
                            $0.stillDuration = clamped
                        }
                        stillDurationTicker.update(clamped)
                    }
                ),
                in: 1.0 ... 10.0,
                step: 0.5
            ) { editing in
                if editing {
                    stillDurationTicker.reset()
                } else if let snap = startSnapshotForUndo, snap != self.clip?.edits {
                    project.commitHistorySnapshot(for: clipID, previous: snap)
                    startSnapshotForUndo = nil
                    Haptics.tapLight()
                }
            }
            Text("Plays for \(String(format: "%.1f", duration)) seconds in the stitched video. Range: 1–10 s.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
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
                    playheadTicker.update(newValue)
                }
            ),
            in: 0 ... max(naturalDuration, 0.1)
        ) { editing in
            isDraggingPlayhead = editing
            if editing {
                player.pause()
                playheadTicker.reset()
            }
        }
        .accessibilityIdentifier("clipEditorPlayheadSlider")
    }

    // MARK: - Split button row (prominent action right under the playhead)

    @ViewBuilder
    private var splitButtonRow: some View {
        HStack {
            Button {
                splitAtPlayhead()
            } label: {
                Label("Split at Playhead", systemImage: "scissors")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canSplitAtPlayhead)
            .accessibilityIdentifier("clipEditorSplitButton")
        }
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
                    trimStartTicker.update(clamped)
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
                    trimEndTicker.update(clamped)
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
                startSnapshotForUndo = clip?.edits
                trimStartTicker.reset()
            }
            if wasDragging && !dragging {
                if let snap = startSnapshotForUndo, snap != clip?.edits {
                    project.commitHistorySnapshot(for: clipID, previous: snap)
                    Haptics.tapLight()
                }
                startSnapshotForUndo = nil
            }
        }
        .onChange(of: isDraggingEnd) { wasDragging, dragging in
            if dragging && !wasDragging {
                endSnapshotForUndo = clip?.edits
                trimEndTicker.reset()
            }
            if wasDragging && !dragging {
                if let snap = endSnapshotForUndo, snap != clip?.edits {
                    project.commitHistorySnapshot(for: clipID, previous: snap)
                    Haptics.tapLight()
                }
                endSnapshotForUndo = nil
            }
        }
    }

    // MARK: - Split hint

    @ViewBuilder
    private var splitHint: some View {
        if canSplitAtPlayhead {
            Text("Tap **Split at Playhead** to cut here. To remove a section, split at both ends and long-press the middle clip → Delete.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Drag the playhead (top slider) into the trim window to enable Split.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
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
        // Pre-warm haptic generators — first-tick latency drops from ~30 ms
        // to ~5 ms. Apple's recommended pattern.
        trimStartTicker.prepare()
        trimEndTicker.prepare()
        playheadTicker.prepare()
        stillDurationTicker.prepare()

        // Stills don't render through AVPlayer — skip the time observer
        // (saves ~30 main-thread callbacks per second for a player that's
        // never visible).
        guard clip?.kind != .still else { return }
        attachTimeObserver()
        seekTo(currentStart)
    }

    private func swapClip() {
        teardown()
        guard let clip = clip else { return }
        if clip.kind == .still {
            // Don't bother loading the still URL into AVPlayer — the
            // VideoPlayer view isn't rendered for stills. StillPreview
            // handles the visible frame via ImageIO instead.
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: clip.sourceURL))
        attachTimeObserver()
        seekTo(currentStart)
        playheadSeconds = currentStart
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

// MARK: - StillPreview

/// Loads and displays a still image (HEIC / JPEG / PNG) from disk via
/// ImageIO. Used by the inline editor when the selected clip is a still —
/// AVPlayer renders black for non-movie URLs so we can't reuse VideoPlayer.
private struct StillPreview: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(src) > 0 else {
                return nil
            }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            else { return nil }
            return UIImage(cgImage: cg)
        }.value
        await MainActor.run { self.image = result }
    }
}
