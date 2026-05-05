//
//  Theme.swift
//  VideoCompressor
//
//  Calm-Cinema visual identity tokens. Keep raw RGB values here so the rest
//  of the app can reference named tints instead of scattering color literals.
//

import SwiftUI

struct RGBToken: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum AppTint {
    // Compress - muted iris violet
    static let compressLightToken = RGBToken(red: 0.42, green: 0.30, blue: 0.78)
    static let compressDarkToken = RGBToken(red: 0.66, green: 0.55, blue: 0.95)

    // Stitch - desaturated mint-teal
    static let stitchLightToken = RGBToken(red: 0.16, green: 0.44, blue: 0.40)
    static let stitchDarkToken = RGBToken(red: 0.42, green: 0.78, blue: 0.70)

    // MetaClean - cool indigo
    static let metaCleanLightToken = RGBToken(red: 0.24, green: 0.31, blue: 0.66)
    static let metaCleanDarkToken = RGBToken(red: 0.52, green: 0.60, blue: 0.92)

    // Settings - graphite
    static let settingsLightToken = RGBToken(red: 0.36, green: 0.40, blue: 0.45)
    static let settingsDarkToken = RGBToken(red: 0.62, green: 0.66, blue: 0.72)

    static func compress(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? compressDarkToken : compressLightToken).color
    }

    static func stitch(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? stitchDarkToken : stitchLightToken).color
    }

    static func metaClean(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? metaCleanDarkToken : metaCleanLightToken).color
    }

    static func settings(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? settingsDarkToken : settingsLightToken).color
    }
}

enum AppMesh {
    static func backdrop(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.06, blue: 0.09)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    static func bloom(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.85, green: 0.55, blue: 0.32).opacity(0.28)
            : Color(red: 0.78, green: 0.50, blue: 0.30).opacity(0.18)
    }

    static func palette(tint: Color, scheme: ColorScheme) -> [Color] {
        let bd = backdrop(scheme)
        return [
            bd, tint.opacity(0.35), bd,
            tint.opacity(0.30), bd, bloom(scheme),
            bd, tint.opacity(0.25), bd,
        ]
    }
}

enum AppShape {
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 20

    static let strokeHairline: CGFloat = 0.5
    static let strokeBorder: CGFloat = 1.0

    static let cardPaddingH: CGFloat = 14
    static let cardPaddingV: CGFloat = 12

    static let auroraDriftPeriodSeconds: Double = 16
    static let auroraFrameRate: Double = 30
    static let scrollTransitionDuration: Double = 0.30
    static let symbolBounceDuration: Double = 0.35
}
