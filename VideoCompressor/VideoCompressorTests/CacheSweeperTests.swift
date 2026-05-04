//
//  CacheSweeperTests.swift
//  VideoCompressorTests
//
//  Pins cache cleanup safety and lifecycle hooks.
//

import XCTest
@testable import VideoCompressor_iOS

final class CacheSweeperTests: XCTestCase {

    private func makeSentinel(in subdir: String) throws -> URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent("sentinel-\(UUID().uuidString.prefix(6)).bin")
        try Data(repeating: 0xAB, count: 1024).write(to: url)
        return url
    }

    func testDeleteIfInWorkingDirRemovesFileInsideOutputs() async throws {
        let sentinel = try makeSentinel(in: "Outputs")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))

        await CacheSweeper.shared.deleteIfInWorkingDir(sentinel)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testDeleteIfInWorkingDirIgnoresFileOutsideSandbox() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("foreign-\(UUID().uuidString.prefix(6)).bin")
        try Data(repeating: 0, count: 16).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        await CacheSweeper.shared.deleteIfInWorkingDir(outside)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSweepOnCancelRemovesPredictedOutput() async throws {
        let sentinel = try makeSentinel(in: "Outputs")

        await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: sentinel)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testSweepOnCancelHandlesNilSafely() async {
        await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: nil)
    }

    func testSweepAfterSaveDeletesAfterDelay() async throws {
        let sentinel = try makeSentinel(in: "Outputs")

        await CacheSweeper.shared.sweepAfterSave(sentinel, delay: .milliseconds(1))

        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testClearAllRemovesStillBakesTmpDir() async throws {
        let bakes = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillBakes", isDirectory: true)
        try FileManager.default.createDirectory(at: bakes, withIntermediateDirectories: true)
        let file = bakes.appendingPathComponent("test-\(UUID().uuidString.prefix(6)).mov")
        try Data(repeating: 0, count: 16).write(to: file)

        await CacheSweeper.shared.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testSweepOnCancelRemovesPhotoCleanWrapper() async throws {
        let wrapper = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoClean-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        let output = wrapper.appendingPathComponent("cleaned.png")
        try Data(repeating: 0, count: 16).write(to: output)

        await CacheSweeper.shared.sweepOnCancel(predictedOutputURL: output)

        XCTAssertFalse(FileManager.default.fileExists(atPath: wrapper.path))
    }

    func testBreakdownIncludesTmpWhenManagedTmpHasContent() async throws {
        let bakes = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillBakes", isDirectory: true)
        try FileManager.default.createDirectory(at: bakes, withIntermediateDirectories: true)
        let file = bakes.appendingPathComponent("tmp-row-\(UUID().uuidString.prefix(6)).mov")
        try Data(repeating: 0, count: 1024).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let stats = await CacheSweeper.shared.breakdown()

        XCTAssertTrue(stats.contains { $0.name == "tmp" && $0.bytes > 0 })
    }
}
