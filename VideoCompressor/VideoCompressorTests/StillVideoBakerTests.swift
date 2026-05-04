//
//  StillVideoBakerTests.swift
//  VideoCompressorTests
//
//  Pins still-image bake correctness across the constant-time refactor.
//

import XCTest
import AVFoundation
import UIKit
@testable import VideoCompressor_iOS

final class StillVideoBakerTests: XCTestCase {

    private func makeFixturePNG(width: CGFloat = 32, height: CGFloat = 32) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("baker-fixture-\(UUID().uuidString.prefix(6)).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    func testBakeProducesNonEmptyPlayableFile() async throws {
        let baker = StillVideoBaker()
        let inputURL = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let result = try await baker.bake(still: inputURL)
        defer { try? FileManager.default.removeItem(at: result.url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: result.url.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(bytes, 1024)

        let asset = AVURLAsset(url: result.url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        XCTAssertGreaterThan(seconds, 0.5)
        XCTAssertLessThan(seconds, 2.0)
    }

    func testBakeUsesOneSecondOutputForLargeStill() async throws {
        let baker = StillVideoBaker()
        let inputURL = try makeFixturePNG(width: 96, height: 64)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let result = try await baker.bake(still: inputURL)
        defer { try? FileManager.default.removeItem(at: result.url) }

        let asset = AVURLAsset(url: result.url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 1.0, accuracy: 0.2)
        XCTAssertEqual(result.size.width, 96, accuracy: 0.5)
        XCTAssertEqual(result.size.height, 64, accuracy: 0.5)
    }
}
