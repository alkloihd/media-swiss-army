//
//  StitchProjectStageTests.swift
//  VideoCompressorTests
//
//  Pins stitch import staging names so delete-then-reimport cannot alias a
//  stale in-memory StitchClip URL.
//

import XCTest
@testable import VideoCompressor_iOS

final class StitchProjectStageTests: XCTestCase {

    func testStagedFilenamesAreAlwaysUUIDPrefixed() throws {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stageDir = docs.appendingPathComponent(
            "StitchInputs-test-\(UUID().uuidString.prefix(6))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stageDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stageDir) }

        let src1 = stageDir.appendingPathComponent("source1.mov")
        try Data(repeating: 0xAA, count: 16).write(to: src1)
        let stage1 = try StitchTabView.testHook_stageToStitchInputs(
            source: src1,
            suggestedName: "clip.mov",
            into: stageDir
        )

        try FileManager.default.removeItem(at: stage1)

        let src2 = stageDir.appendingPathComponent("source2.mov")
        try Data(repeating: 0xBB, count: 16).write(to: src2)
        let stage2 = try StitchTabView.testHook_stageToStitchInputs(
            source: src2,
            suggestedName: "clip.mov",
            into: stageDir
        )

        XCTAssertNotEqual(
            stage1.lastPathComponent,
            stage2.lastPathComponent,
            "Two stagings of clip.mov must produce distinct paths even after the first was deleted."
        )

        let pattern = #"^[a-f0-9]{6}-clip\.mov$"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        for url in [stage1, stage2] {
            let name = url.lastPathComponent
            XCTAssertNotNil(
                regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                "Staged name \(name) does not match expected UUID-prefix pattern."
            )
        }
    }
}
