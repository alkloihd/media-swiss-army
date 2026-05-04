//
//  StitchProjectSortTests.swift
//  VideoCompressorTests
//
//  Pin the sort-by-creation-date semantics: stable sort, nil dates go last,
//  no-op when already sorted.
//

import XCTest
import CoreMedia
import CoreGraphics
@testable import VideoCompressor_iOS

@MainActor
final class StitchProjectSortTests: XCTestCase {

    private func makeClip(name: String, date: Date?) -> StitchClip {
        StitchClip(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/\(name).mov"),
            displayName: name,
            naturalDuration: CMTime(seconds: 1, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            creationDate: date,
            edits: .identity
        )
    }

    func testSortReordersByDate() {
        let project = StitchProject()
        let now = Date()
        let a = makeClip(name: "A", date: now.addingTimeInterval(-200))
        let b = makeClip(name: "B", date: now)
        let c = makeClip(name: "C", date: now.addingTimeInterval(-100))
        project.append(b); project.append(a); project.append(c)

        let changed = project.sortByCreationDate()
        XCTAssertTrue(changed)
        XCTAssertEqual(project.clips.map(\.displayName), ["A", "C", "B"])
    }

    func testSortIsNoOpWhenAlreadyOrdered() {
        let project = StitchProject()
        let now = Date()
        let a = makeClip(name: "A", date: now.addingTimeInterval(-30))
        let b = makeClip(name: "B", date: now.addingTimeInterval(-20))
        let c = makeClip(name: "C", date: now.addingTimeInterval(-10))
        project.append(a); project.append(b); project.append(c)

        let changed = project.sortByCreationDate()
        XCTAssertFalse(changed, "Already sorted — should not report a change.")
        XCTAssertEqual(project.clips.map(\.displayName), ["A", "B", "C"])
    }

    func testNilDatesSortToEnd() {
        let project = StitchProject()
        let now = Date()
        let a = makeClip(name: "A-noDate", date: nil)
        let b = makeClip(name: "B-recent", date: now)
        let c = makeClip(name: "C-noDate", date: nil)
        let d = makeClip(name: "D-old", date: now.addingTimeInterval(-1000))
        project.append(a); project.append(b); project.append(c); project.append(d)

        _ = project.sortByCreationDate()
        // Dated first (oldest → newest), then nil-dated in original relative
        // order (a then c).
        XCTAssertEqual(
            project.clips.map(\.displayName),
            ["D-old", "B-recent", "A-noDate", "C-noDate"]
        )
    }

    func testStableForEqualDates() {
        let project = StitchProject()
        let same = Date()
        let a = makeClip(name: "A", date: same)
        let b = makeClip(name: "B", date: same)
        let c = makeClip(name: "C", date: same)
        project.append(a); project.append(b); project.append(c)

        let changed = project.sortByCreationDate()
        XCTAssertFalse(changed)
        XCTAssertEqual(project.clips.map(\.displayName), ["A", "B", "C"])
    }

    func testEmptyProjectIsSafe() {
        let project = StitchProject()
        let changed = project.sortByCreationDate()
        XCTAssertFalse(changed)
        XCTAssertTrue(project.clips.isEmpty)
    }

    func testSingleClipIsSafe() {
        let project = StitchProject()
        let only = makeClip(name: "Only", date: Date())
        project.append(only)
        let changed = project.sortByCreationDate()
        XCTAssertFalse(changed)
        XCTAssertEqual(project.clips.count, 1)
    }

    func testImportFinalizationAutoSortsOldestFirst() async {
        let project = StitchProject()
        let old = makeClip(name: "Old", date: Date(timeIntervalSince1970: 1_000_000))
        let mid = makeClip(name: "Mid", date: Date(timeIntervalSince1970: 2_000_000))
        let newest = makeClip(name: "Newest", date: Date(timeIntervalSince1970: 3_000_000))

        project.append(newest)
        project.append(mid)
        project.append(old)

        let changed = await StitchTabView.testHook_finalizeImportOrdering(project: project)

        XCTAssertTrue(changed)
        XCTAssertEqual(project.clips.map(\.id), [old.id, mid.id, newest.id])
    }
}
