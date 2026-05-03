//
//  TrimEditorView.swift
//  VideoCompressor
//
//  Phase 3 commit 6 — live-preview trim editor.
//  VideoPlayer docked at top + custom DualThumbSlider below.
//  Edits are applied to the project immediately (no Done button modality).
//  Auto-play behaviour per user spec:
//    • Release trim-start drag → seek to new in-point, play forward
//    • Release trim-end drag   → seek to (newEnd - 2 s), play 2 s, pause
//

import SwiftUI
import AVKit
import AVFoundation

// ---------------------------------------------------------------------------
// MARK: - TrimEditorView
// ---------------------------------------------------------------------------

struct TrimEditorView: View {
    let clip: StitchClip
    @Binding var edits: ClipEdits
    @ObservedObject var project: StitchProject

    @State private var player: AVPlayer
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    /// Auto-play task for the "play last 2 s then pause" behaviour on end-handle release.
    @State private var autoPlayTask: Task<Void, Never>?

    init(clip: StitchClip, edits: Binding<ClipEdits>, project: StitchProject) {
        self.clip = clip
        self._edits = edits
        self.project = project
        self._player = State(initialValue: AVPlayer(url: clip.sourceURL))
    }

    private var naturalDuration: Double {
        CMTimeGetSeconds(clip.naturalDuration)
    }

    private var currentStart: Double { edits.trimStartSeconds ?? 0 }
    private var currentEnd: Double { edits.trimEndSeconds ?? naturalDuration }

    var body: some View {
        VStack(spacing: 16) {
            // ── Video player ──────────────────────────────────────────────
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 240)
                .padding(.horizontal, 8)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // ── Live duration label ───────────────────────────────────────
            Text(durationLabel)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            // ── Dual-thumb scrubber ───────────────────────────────────────
            DualThumbSlider(
                start: Binding(
                    get: { currentStart },
                    set: { newValue in
                        let clamped = max(0, min(newValue, currentEnd - 0.1))
                        edits.trimStartSeconds = clamped
                        seekTo(clamped)
                    }
                ),
                end: Binding(
                    get: { currentEnd },
                    set: { newValue in
                        let clamped = max(currentStart + 0.1, min(newValue, naturalDuration))
                        edits.trimEndSeconds = clamped
                        seekTo(max(currentStart, clamped - 2.0))
                    }
                ),
                range: 0 ... naturalDuration,
                isDraggingStart: $isDraggingStart,
                isDraggingEnd: $isDraggingEnd
            )
            .padding(.horizontal, 24)
            // ── Auto-play on thumb release ────────────────────────────────
            .onChange(of: isDraggingStart) { _, dragging in
                guard !dragging else { return }
                cancelAutoPlay()
                let seekTime = CMTime(seconds: currentStart, preferredTimescale: 600)
                Task { @MainActor in
                    await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    guard !Task.isCancelled else { return }
                    player.play()
                }
            }
            .onChange(of: isDraggingEnd) { _, dragging in
                guard !dragging else { return }
                cancelAutoPlay()
                let twoBefore = max(currentStart, currentEnd - 2.0)
                let seekTime = CMTime(seconds: twoBefore, preferredTimescale: 600)
                autoPlayTask = Task { @MainActor in
                    await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    guard !Task.isCancelled else { return }
                    player.play()
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    player.pause()
                }
            }

            // ── Reset trim ────────────────────────────────────────────────
            Button {
                edits.trimStartSeconds = nil
                edits.trimEndSeconds = nil
                seekTo(0)
            } label: {
                Label("Reset Trim", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 24)
        .onAppear {
            seekTo(currentStart)
        }
        .onDisappear {
            player.pause()
            cancelAutoPlay()
        }
    }

    // MARK: - Helpers

    private func seekTo(_ seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero)
    }

    private func cancelAutoPlay() {
        autoPlayTask?.cancel()
        autoPlayTask = nil
    }

    private var durationLabel: String {
        let dur = max(0, currentEnd - currentStart)
        let total = Int(dur)
        let m = total / 60
        let s = total % 60
        let cs = Int((dur - Double(total)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
}

// ---------------------------------------------------------------------------
// MARK: - DualThumbSlider
// ---------------------------------------------------------------------------
// Custom two-thumb slider. The DragGesture reports *cumulative* translation
// from the gesture's start point, so we capture the value at drag-start
// (`dragOrigin`) to avoid the thumb flying off the track.

struct DualThumbSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let range: ClosedRange<Double>
    @Binding var isDraggingStart: Bool
    @Binding var isDraggingEnd: Bool

    // Captures the binding value when the drag gesture begins so that
    // subsequent translation deltas are applied relative to the start.
    @State private var startDragOrigin: Double? = nil
    @State private var endDragOrigin: Double? = nil

    private let thumbDiameter: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let startX = ((start - range.lowerBound) / span) * width
            let endX = ((end - range.lowerBound) / span) * width

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 6)

                // Selected range highlight
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, endX - startX), height: 6)
                    .offset(x: startX)

                // Start thumb
                thumbView(
                    x: startX,
                    trackWidth: width,
                    span: span,
                    currentValue: start,
                    isDragging: $isDraggingStart,
                    dragOrigin: $startDragOrigin
                ) { newValue in
                    start = max(range.lowerBound, min(newValue, end - 0.1))
                }

                // End thumb
                thumbView(
                    x: endX,
                    trackWidth: width,
                    span: span,
                    currentValue: end,
                    isDragging: $isDraggingEnd,
                    dragOrigin: $endDragOrigin
                ) { newValue in
                    end = max(start + 0.1, min(newValue, range.upperBound))
                }
            }
        }
        .frame(height: thumbDiameter + 8) // enough hit area
    }

    @ViewBuilder
    private func thumbView(
        x: CGFloat,
        trackWidth: CGFloat,
        span: Double,
        currentValue: Double,
        isDragging: Binding<Bool>,
        dragOrigin: Binding<Double?>,
        onValueChange: @escaping (Double) -> Void
    ) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .offset(x: x - thumbDiameter / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin.wrappedValue == nil {
                            // Capture the binding's current value at gesture start
                            // so translation is applied relative to that baseline.
                            isDragging.wrappedValue = true
                            dragOrigin.wrappedValue = currentValue
                        }
                        guard let origin = dragOrigin.wrappedValue else { return }
                        let delta = Double(value.translation.width) * span / Double(trackWidth)
                        onValueChange(origin + delta)
                    }
                    .onEnded { _ in
                        isDragging.wrappedValue = false
                        dragOrigin.wrappedValue = nil
                    }
            )
    }
}
