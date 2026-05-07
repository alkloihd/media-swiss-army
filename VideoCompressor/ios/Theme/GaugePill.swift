//
//  GaugePill.swift
//  VideoCompressor
//
//  Compact save/progress/result capsule.
//

import SwiftUI
import UIKit

enum GaugePillState: Equatable {
    case saving(progress: Double)
    case saved
    case failed(message: String)
}

struct GaugePill: View {
    let state: GaugePillState
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .appMaterialBackground(
            .regularMaterial,
            fallback: Color(.secondarySystemBackground),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(strokeColor, lineWidth: AppShape.strokeHairline))
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .saving(let progress):
            Gauge(value: min(1.0, max(0.0, progress))) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .scaleEffect(0.55)
                .frame(width: 18, height: 18)
                .tint(tint)
        case .saved:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: state)
                .symbolEffectsRemoved(reduceMotion)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var label: String {
        switch state {
        case .saving:
            return "Saving"
        case .saved:
            return "Saved"
        case .failed(let message):
            return message.isEmpty ? "Failed" : message
        }
    }

    private var strokeColor: Color {
        switch state {
        case .saving:
            return tint.opacity(0.35)
        case .saved:
            return Color.green.opacity(0.35)
        case .failed:
            return Color.red.opacity(0.35)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .saving(let progress):
            return "Saving, \(Int(min(1.0, max(0.0, progress)) * 100)) percent"
        case .saved:
            return "Saved to Photos"
        case .failed(let message):
            return "Save failed: \(message.isEmpty ? "Failed" : message)"
        }
    }
}
