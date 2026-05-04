//
//  CropEditorView.swift
//  VideoCompressor
//
//  Aspect-preset crop controls for Stitch clips. Replaces the old XYWH
//  sliders with discrete, centered crop presets.
//

import SwiftUI
import CoreGraphics

struct CropEditorView: View {
    let clip: StitchClip
    @Binding var edits: ClipEdits

    enum AspectPreset: String, CaseIterable, Hashable {
        case free
        case square
        case portrait916
        case landscape169

        var label: String {
            switch self {
            case .free:         return "Free"
            case .square:       return "Square"
            case .portrait916:  return "9:16"
            case .landscape169: return "16:9"
            }
        }

        var symbolName: String {
            switch self {
            case .free:         return "crop"
            case .square:       return "square"
            case .portrait916:  return "rectangle.portrait"
            case .landscape169: return "rectangle"
            }
        }

        var ratio: CGFloat? {
            switch self {
            case .free:         return nil
            case .square:       return 1
            case .portrait916:  return 9.0 / 16.0
            case .landscape169: return 16.0 / 9.0
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            CropPresetButtonGrid(
                currentCrop: edits.cropNormalized,
                naturalSize: clip.naturalSize,
                displaySize: clip.displaySize
            ) { preset in
                edits.cropNormalized = Self.cropRect(
                    for: preset,
                    naturalSize: clip.naturalSize,
                    displaySize: clip.displaySize
                )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 24)
    }

    static func cropRect(
        for preset: AspectPreset,
        naturalSize: CGSize
    ) -> CGRect? {
        cropRect(for: preset, naturalSize: naturalSize, displaySize: naturalSize)
    }

    static func cropRect(
        for preset: AspectPreset,
        naturalSize: CGSize,
        displaySize: CGSize
    ) -> CGRect? {
        guard var targetRatio = preset.ratio else { return nil }
        guard naturalSize.width > 0, naturalSize.height > 0 else { return nil }

        if isRotated(naturalSize: naturalSize, displaySize: displaySize) {
            targetRatio = 1 / targetRatio
        }

        let sourceRatio = naturalSize.width / naturalSize.height
        let rect: CGRect
        if targetRatio >= sourceRatio {
            let height = sourceRatio / targetRatio
            rect = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            let width = targetRatio / sourceRatio
            rect = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }

        let clamped = clamp(rect)
        return isApproximatelyIdentity(clamped) ? nil : clamped
    }

    private static let identityEpsilon: CGFloat = 1e-3

    static func isApproximatelyEqual(_ a: CGRect?, _ b: CGRect?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.minX - rhs.minX) < identityEpsilon
                && abs(lhs.minY - rhs.minY) < identityEpsilon
                && abs(lhs.width - rhs.width) < identityEpsilon
                && abs(lhs.height - rhs.height) < identityEpsilon
        default:
            return false
        }
    }

    private static func isApproximatelyIdentity(_ rect: CGRect) -> Bool {
        isApproximatelyEqual(rect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func isRotated(naturalSize: CGSize, displaySize: CGSize) -> Bool {
        guard displaySize.width > 0, displaySize.height > 0 else { return false }
        let naturalLandscape = naturalSize.width > naturalSize.height
        let displayLandscape = displaySize.width > displaySize.height
        return naturalLandscape != displayLandscape
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        let x = min(1, max(0, rect.minX))
        let y = min(1, max(0, rect.minY))
        let width = min(1 - x, max(0, rect.width))
        let height = min(1 - y, max(0, rect.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct CropPresetButtonGrid: View {
    let currentCrop: CGRect?
    let naturalSize: CGSize
    let displaySize: CGSize
    var apply: (CropEditorView.AspectPreset) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CropEditorView.AspectPreset.allCases, id: \.self) { preset in
                let selected = isSelected(preset)
                Button {
                    apply(preset)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: preset.symbolName)
                            .font(.title3)
                        Text(preset.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cropPreset_\(preset.rawValue)")
            }
        }
    }

    private func isSelected(_ preset: CropEditorView.AspectPreset) -> Bool {
        let target = CropEditorView.cropRect(
            for: preset,
            naturalSize: naturalSize,
            displaySize: displaySize
        )
        return CropEditorView.isApproximatelyEqual(currentCrop, target)
    }
}
