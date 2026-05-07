//
//  MeshAuroraView.swift
//  VideoCompressor
//
//  Animated empty-state aurora with a cheap linear fallback.
//

import SwiftUI
import UIKit

struct MeshAuroraView: View {
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if AuroraBackend.preferred == .mesh {
                meshBody
            } else {
                LinearAuroraView(tint: tint)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var meshBody: some View {
        if #available(iOS 18.0, *) {
            TimelineView(.animation(
                minimumInterval: 1.0 / AppShape.auroraFrameRate,
                paused: reduceMotion
            )) { context in
                let phase = reduceMotion
                    ? 0
                    : CGFloat(
                        context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: AppShape.auroraDriftPeriodSeconds)
                            / AppShape.auroraDriftPeriodSeconds
                    ) * 2 * .pi
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: meshPoints(phase: phase),
                    colors: AppMesh.palette(tint: tint, scheme: scheme)
                )
            }
        } else {
            LinearAuroraView(tint: tint)
        }
    }

    private func meshPoints(phase: CGFloat) -> [SIMD2<Float>] {
        let dx = Float(cos(phase) * 0.05)
        let dy = Float(sin(phase) * 0.05)
        return [
            SIMD2(0.0, 0.0),
            SIMD2(clamp(0.5 + dx), clamp(0.05 + dy)),
            SIMD2(1.0, 0.0),
            SIMD2(0.0, 0.5),
            SIMD2(0.5, 0.5),
            SIMD2(clamp(0.95 + dx), clamp(0.5 + dy)),
            SIMD2(0.0, 1.0),
            SIMD2(0.5, 1.0),
            SIMD2(1.0, 1.0),
        ]
    }

    private func clamp(_ value: Float) -> Float {
        min(1.0, max(0.0, value))
    }
}

struct LinearAuroraView: View {
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppMesh.backdrop(scheme).ignoresSafeArea()
            TimelineView(.animation(
                minimumInterval: 1.0 / AppShape.auroraFrameRate,
                paused: reduceMotion
            )) { context in
                let phase = reduceMotion
                    ? 0
                    : CGFloat(
                        context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: AppShape.auroraDriftPeriodSeconds)
                            / AppShape.auroraDriftPeriodSeconds
                    ) * 2 * .pi
                LinearGradient(
                    colors: [tint.opacity(0.32), AppMesh.bloom(scheme), .clear],
                    startPoint: UnitPoint(
                        x: 0.5 + 0.2 * cos(phase),
                        y: 0.5 + 0.2 * sin(phase)
                    ),
                    endPoint: UnitPoint(
                        x: 0.5 - 0.2 * cos(phase),
                        y: 0.5 - 0.2 * sin(phase)
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }
}

enum AuroraBackend {
    case mesh
    case linearAnimated

    static var preferred: AuroraBackend {
        guard Thread.isMainThread else { return .linearAnimated }
        return UIScreen.main.maximumFramesPerSecond >= 90 ? .mesh : .linearAnimated
    }
}
