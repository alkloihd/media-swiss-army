//
//  CardStyle.swift
//  VideoCompressor
//
//  Shared material card chrome for Calm-Cinema surfaces.
//

import SwiftUI
import UIKit

struct CardStyle: ViewModifier {
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppShape.cardPaddingH)
            .padding(.vertical, AppShape.cardPaddingV)
            .appMaterialBackground(
                .thickMaterial,
                fallback: Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: AppShape.radiusM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppShape.radiusM)
                    .strokeBorder(
                        tint.opacity(scheme == .dark ? 0.18 : 0.10),
                        lineWidth: AppShape.strokeHairline
                    )
            )
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.40 : 0.06),
                radius: 6,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func cardStyle(tint: Color) -> some View {
        modifier(CardStyle(tint: tint))
    }
}
