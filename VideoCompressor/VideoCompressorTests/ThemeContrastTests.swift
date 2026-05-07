//
//  ThemeContrastTests.swift
//  VideoCompressorTests
//
//  WCAG contrast guard for the Calm-Cinema per-tab tint tokens.
//

import XCTest
@testable import VideoCompressor_iOS

final class ThemeContrastTests: XCTestCase {
    func testAllTabTintsMeetAAContrastAgainstMaterialMidpoints() {
        let lightMaterial = RGBToken(red: 0.92, green: 0.92, blue: 0.94)
        let darkMaterial = RGBToken(red: 0.16, green: 0.16, blue: 0.18)

        let cases: [(String, RGBToken, RGBToken)] = [
            ("compress", AppTint.compressLightToken, AppTint.compressDarkToken),
            ("stitch", AppTint.stitchLightToken, AppTint.stitchDarkToken),
            ("metaClean", AppTint.metaCleanLightToken, AppTint.metaCleanDarkToken),
            ("settings", AppTint.settingsLightToken, AppTint.settingsDarkToken),
        ]

        for (name, light, dark) in cases {
            XCTAssertGreaterThanOrEqual(
                contrast(light, lightMaterial),
                4.5,
                "\(name) light"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(dark, darkMaterial),
                4.5,
                "\(name) dark"
            )
        }
    }

    private func contrast(_ a: RGBToken, _ b: RGBToken) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func relativeLuminance(_ token: RGBToken) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(token.red)
            + 0.7152 * channel(token.green)
            + 0.0722 * channel(token.blue)
    }
}
