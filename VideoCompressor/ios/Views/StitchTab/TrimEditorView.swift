//
//  TrimEditorView.swift
//  VideoCompressor
//
//  v1 trim editor: two Sliders (start and end handles) with a live duration
//  label. Clamped bindings prevent start from exceeding end. v2 will replace
//  with a custom dual-thumb gesture per plan risk R6.
//

import SwiftUI
import AVFoundation

struct TrimEditorView: View {
    let clip: StitchClip
    @Binding var edits: ClipEdits

    /// Natural duration of the clip in seconds.
    private var naturalDuration: Double {
        CMTimeGetSeconds(clip.naturalDuration)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Live duration label as user trims.
            Text(durationLabel)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(edits.trimStartSeconds ?? 0))
                        .font(.caption.monospacedDigit())
                }
                Slider(
                    value: Binding(
                        get: { edits.trimStartSeconds ?? 0 },
                        set: { newStart in
                            // Clamp: start must not exceed current end.
                            let currentEnd = edits.trimEndSeconds ?? naturalDuration
                            edits.trimStartSeconds = min(newStart, currentEnd)
                        }
                    ),
                    in: 0...naturalDuration
                )

                HStack {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(edits.trimEndSeconds ?? naturalDuration))
                        .font(.caption.monospacedDigit())
                }
                Slider(
                    value: Binding(
                        get: { edits.trimEndSeconds ?? naturalDuration },
                        set: { newEnd in
                            // Clamp: end must not go below current start.
                            let currentStart = edits.trimStartSeconds ?? 0
                            edits.trimEndSeconds = max(newEnd, currentStart)
                        }
                    ),
                    in: 0...naturalDuration
                )
            }
            .padding(.horizontal, 24)

            Button {
                edits.trimStartSeconds = nil
                edits.trimEndSeconds = nil
            } label: {
                Label("Reset Trim", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 24)
    }

    private var durationLabel: String {
        // Mirrors StitchClip.trimmedDurationSeconds logic so label is always
        // consistent with what the exporter will actually use.
        let start = edits.trimStartSeconds ?? 0
        let end = edits.trimEndSeconds ?? naturalDuration
        let clampedStart = max(0, min(start, naturalDuration))
        let clampedEnd = min(naturalDuration, max(clampedStart, end))
        return formatTime(clampedEnd - clampedStart)
    }

    /// Formats seconds as M:SS.cc (centiseconds). Uses truncation (not
    /// rounding) so that e.g. 5.7s shows "0:05.70" not "0:06.00".
    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)   // truncate, not round
        let m = total / 60
        let s = total % 60
        let ms = Int((seconds - Double(total)) * 100)
        return String(format: "%d:%02d.%02d", m, s, ms)
    }
}
