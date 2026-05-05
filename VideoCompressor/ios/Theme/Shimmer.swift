//
//  Shimmer.swift
//  VideoCompressor
//
//  Slow inspection shimmer for MetaClean scanning states.
//

import SwiftUI

struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -220

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.45), .white.opacity(0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: reduceMotion ? 0 : phase)
                .blendMode(.plusLighter)
                .mask(content)
            }
            .task(id: reduceMotion) {
                phase = reduceMotion ? 0 : -220
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 220
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(Shimmer())
    }
}
