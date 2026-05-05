//
//  ThemeComponentRenderTests.swift
//  VideoCompressorTests
//
//  Smoke tests for reusable Calm-Cinema SwiftUI components.
//

import SwiftUI
import XCTest
@testable import VideoCompressor_iOS

@MainActor
final class ThemeComponentRenderTests: XCTestCase {
    func testThemeComponentsRenderNonEmptyImages() throws {
        try assertRenderable(MeshAuroraView(tint: .red).frame(width: 200, height: 200))
        try assertRenderable(GaugePill(state: .saving(progress: 0.5), tint: .blue))
        try assertRenderable(GaugePill(state: .saved, tint: .blue))
        try assertRenderable(GaugePill(state: .failed(message: "Failed"), tint: .blue))
        try assertRenderable(Text("hi").shimmer())
        try assertRenderable(Text("hi").cardStyle(tint: .green))
    }

    private func assertRenderable<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let renderer = ImageRenderer(content: view.frame(width: 240, height: 180))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, file: file, line: line)
        let data = try XCTUnwrap(image.pngData(), file: file, line: line)
        XCTAssertGreaterThan(data.count, 1_024, file: file, line: line)
    }
}
