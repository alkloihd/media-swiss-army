//
//  CropEditorView.swift
//  VideoCompressor
//
//  v1 crop editor: four sliders (X, Y, Width, Height) editing a normalized
//  CGRect over the clip's natural size. Uses explicit Binding<Double> getters
//  rather than WritableKeyPath<CGRect, Double> to avoid CGFloat/Double type
//  mismatch. v2 will overlay a draggable rect handle on a preview frame.
//

import SwiftUI
import CoreGraphics

struct CropEditorView: View {
    let clip: StitchClip
    @Binding var edits: ClipEdits

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                cropSlider("X",      value: xBinding,      minimum: 0)
                cropSlider("Y",      value: yBinding,      minimum: 0)
                cropSlider("Width",  value: widthBinding,  minimum: 0.05)
                cropSlider("Height", value: heightBinding, minimum: 0.05)
            }
            .padding(.horizontal, 24)

            Button {
                edits.cropNormalized = nil
            } label: {
                Label("Reset Crop", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)

            Text("v2 will offer an interactive crop rectangle over a preview frame.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Slider builder

    private func cropSlider(
        _ label: String,
        value: Binding<Double>,
        minimum: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
            }
            Slider(value: value, in: minimum...1)
        }
    }

    // MARK: - Explicit CGRect field bindings
    // CGFloat and Double are distinct types; Swift does not synthesize
    // WritableKeyPath<CGRect, Double>, so we use four explicit bindings.

    private var xBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.origin.x ?? 0) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.origin.x = CGFloat(newValue)
                edits.cropNormalized = rect == CGRect(x: 0, y: 0, width: 1, height: 1) ? nil : rect
            }
        )
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.origin.y ?? 0) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.origin.y = CGFloat(newValue)
                edits.cropNormalized = rect == CGRect(x: 0, y: 0, width: 1, height: 1) ? nil : rect
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.size.width ?? 1) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.size.width = CGFloat(newValue)
                edits.cropNormalized = rect == CGRect(x: 0, y: 0, width: 1, height: 1) ? nil : rect
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.size.height ?? 1) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.size.height = CGFloat(newValue)
                edits.cropNormalized = rect == CGRect(x: 0, y: 0, width: 1, height: 1) ? nil : rect
            }
        )
    }
}
