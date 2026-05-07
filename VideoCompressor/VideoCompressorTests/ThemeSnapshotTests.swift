//
//  ThemeSnapshotTests.swift
//  VideoCompressorTests
//
//  Render smoke tests for the Cluster 3.5 visual redo surfaces.
//

import SwiftUI
import UIKit
import XCTest
@testable import VideoCompressor_iOS

@MainActor
final class ThemeSnapshotTests: XCTestCase {
    func testEmptyStateRendersInLightAndDark() throws {
        try assertRenderable(
            EmptyStateView(
                pickerItems: .constant([]),
                tint: AppTint.compress(.light)
            )
            .environment(\.colorScheme, .light)
        )

        try assertRenderable(
            EmptyStateView(
                pickerItems: .constant([]),
                tint: AppTint.compress(.dark)
            )
            .environment(\.colorScheme, .dark)
        )
    }

    func testVideoCardRendersWithLocalFixture() throws {
        let video = VideoFile(
            sourceURL: URL(fileURLWithPath: "/tmp/theme-snapshot-missing.mov"),
            displayName: "Weekend Meta Glasses Clip.mov",
            importedAt: Date(timeIntervalSince1970: 1_704_067_200),
            kind: .video,
            metadata: VideoMetadata(
                durationSeconds: 42,
                pixelWidth: 3840,
                pixelHeight: 2160,
                nominalFrameRate: 30,
                codec: "hvc1",
                estimatedDataRate: 18_000_000,
                fileSizeBytes: 124_000_000
            ),
            jobState: .finished,
            output: CompressedOutput(
                url: URL(fileURLWithPath: "/tmp/theme-snapshot-output.mov"),
                bytes: 34_000_000,
                createdAt: Date(timeIntervalSince1970: 1_704_067_260),
                settings: .balanced,
                note: "Exported with Balanced"
            ),
            saveStatus: .unsaved
        )

        try assertRenderable(
            VideoCardView(video: video)
                .environmentObject(VideoLibrary.preview())
                .environment(\.colorScheme, .dark),
            width: 360,
            height: 320
        )
    }

    func testMetaCleanRowsRenderScanningAndCleanedStates() throws {
        try assertRenderable(
            MetaCleanRowView(
                item: metaCleanItem(tags: [], cleanResult: nil),
                tint: AppTint.metaClean(.light)
            )
            .environment(\.colorScheme, .light)
        )

        let stripped = metadataTag(
            key: "com.apple.quicktime.comment",
            displayName: "Meta fingerprint",
            value: "<binary, 256 bytes>",
            category: .custom,
            isMetaFingerprint: true
        )

        try assertRenderable(
            MetaCleanRowView(
                item: metaCleanItem(
                    tags: [stripped],
                    cleanResult: MetadataCleanResult(
                        cleanedURL: URL(fileURLWithPath: "/tmp/theme-snapshot-clean.mov"),
                        bytes: 22_000_000,
                        tagsStripped: [stripped],
                        tagsKept: []
                    )
                ),
                tint: AppTint.metaClean(.dark)
            )
            .environment(\.colorScheme, .dark)
        )
    }

    func testCenteredStitchEmptyStateRenders() throws {
        try assertRenderable(
            CenteredEmptyState(
                systemImage: "square.stack.3d.up",
                title: "Build a stitch",
                message: "Import photos or videos, then arrange them in the timeline.",
                tint: AppTint.stitch(.light)
            ) {
                Button("Import") {}
                    .buttonStyle(.borderedProminent)
            }
            .environment(\.colorScheme, .light)
        )
    }

    func testOnboardingPagesRender() throws {
        for page in 0..<3 {
            try assertRenderable(
                OnboardingView(initialPage: page, onFinish: {})
                    .environment(\.colorScheme, page == 1 ? .light : .dark),
                width: 390,
                height: 844
            )
        }
    }

    func testSettingsHelpSectionRendersFeatureGuidance() throws {
        XCTAssertEqual(
            SettingsHelpTopic.all.map(\.title),
            ["Compress", "Stitch", "MetaClean", "Settings"]
        )

        try assertRenderable(
            SettingsHelpSection(tint: AppTint.settings(.light))
                .environment(\.colorScheme, .light),
            width: 360,
            height: 460
        )
    }

    private func assertRenderable<V: View>(
        _ view: V,
        width: CGFloat = 360,
        height: CGFloat = 240,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, file: file, line: line)
        let data = try XCTUnwrap(image.pngData(), file: file, line: line)
        XCTAssertGreaterThan(data.count, 1_024, file: file, line: line)
    }

    private func metaCleanItem(
        tags: [MetadataTag],
        cleanResult: MetadataCleanResult?
    ) -> MetaCleanItem {
        MetaCleanItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            sourceURL: URL(fileURLWithPath: "/tmp/theme-snapshot-source.mov"),
            displayName: "Meta glasses export.mov",
            kind: .video,
            originalAssetID: nil,
            tags: tags,
            scanError: nil,
            cleanResult: cleanResult
        )
    }

    private func metadataTag(
        key: String,
        displayName: String,
        value: String,
        category: MetadataCategory,
        isMetaFingerprint: Bool
    ) -> MetadataTag {
        MetadataTag(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            key: key,
            displayName: displayName,
            value: value,
            category: category,
            isMetaFingerprint: isMetaFingerprint
        )
    }
}
