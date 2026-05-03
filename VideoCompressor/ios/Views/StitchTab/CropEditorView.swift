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
    // Each setter normalizes to nil when the rect is approximately the
    // identity (full frame) so the exporter's passthrough fast-path stays
    // available — exact CGFloat equality is float-fragile (closes review
    // {E-0503-1101} H1).

    private static let identityEpsilon: CGFloat = 1e-4

    private static func isApproximatelyIdentity(_ r: CGRect) -> Bool {
        abs(r.minX) < identityEpsilon
            && abs(r.minY) < identityEpsilon
            && abs(r.width  - 1) < identityEpsilon
            && abs(r.height - 1) < identityEpsilon
    }

    private func commit(_ rect: CGRect) {
        edits.cropNormalized = Self.isApproximatelyIdentity(rect) ? nil : rect
    }

    private var xBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.origin.x ?? 0) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.origin.x = CGFloat(newValue)
                commit(rect)
            }
        )
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.origin.y ?? 0) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.origin.y = CGFloat(newValue)
                commit(rect)
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.size.width ?? 1) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.size.width = CGFloat(newValue)
                commit(rect)
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(edits.cropNormalized?.size.height ?? 1) },
            set: { newValue in
                var rect = edits.cropNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                rect.size.height = CGFloat(newValue)
                commit(rect)
            }
        )
    }
}
