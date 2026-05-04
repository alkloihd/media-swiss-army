//
//  StitchExporterScaleTests.swift
//  VideoCompressorTests
//
//  Verifies still-image bakes stay constant-time while the composition
//  stretches the baked 1-second movie to the user's chosen still duration.
//

import XCTest
import AVFoundation
import UIKit
@testable import VideoCompressor_iOS

final class StitchExporterScaleTests: XCTestCase {

    private func makeFixturePNG(width: CGFloat = 32, height: CGFloat = 48) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitch-scale-\(UUID().uuidString.prefix(6)).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    private func makeStillClip(url: URL, duration: Double) -> StitchClip {
        var edits = ClipEdits.identity
        edits.stillDuration = duration
        return StitchClip(
            id: UUID(),
            sourceURL: url,
            displayName: url.lastPathComponent,
            naturalDuration: CMTime(seconds: duration, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 48),
            kind: .still,
            preferredTransform: .identity,
            edits: edits
        )
    }

    private func stillBakeDirectoryContents() -> Set<String> {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillBakes", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(urls.map(\.lastPathComponent))
    }

    func testStillBakeRemainsOneSecondWhileCompositionUsesStillDuration() async throws {
        let source = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: source) }

        let plan = try await StitchExporter().buildPlan(
            from: [makeStillClip(url: source, duration: 4.0)],
            aspectMode: .portrait
        )
        defer {
            for url in plan.bakedStillURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        XCTAssertEqual(plan.bakedStillURLs.count, 1)
        let bakedAsset = AVURLAsset(url: try XCTUnwrap(plan.bakedStillURLs.first))
        let bakedDuration = try await bakedAsset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(bakedDuration), 1.0, accuracy: 0.2)
        XCTAssertEqual(CMTimeGetSeconds(plan.composition.duration), 4.0, accuracy: 0.2)
    }

    func testBuildPlanCleansBakedStillIfLaterClipFails() async throws {
        let source = try makeFixturePNG()
        defer { try? FileManager.default.removeItem(at: source) }

        let missingVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString.prefix(6)).mp4")
        let badVideo = StitchClip(
            id: UUID(),
            sourceURL: missingVideoURL,
            displayName: missingVideoURL.lastPathComponent,
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 32, height: 48),
            kind: .video,
            preferredTransform: .identity,
            edits: .identity
        )

        let before = stillBakeDirectoryContents()
        do {
            _ = try await StitchExporter().buildPlan(
                from: [makeStillClip(url: source, duration: 4.0), badVideo],
                aspectMode: .portrait
            )
            XCTFail("Expected buildPlan to fail on the missing video clip.")
        } catch {
            let after = stillBakeDirectoryContents()
            XCTAssertEqual(after, before)
        }
    }
}
