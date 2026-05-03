//
//  CompressedOutput.swift
//  VideoCompressor
//
//  Cohesive payload representing a successful compression result. Replaces
//  the orphan pair `outputURL: URL?` + `outputBytes: Int64?` on `VideoFile`
//  (those two were always set/unset together; collapsing them prevents
//  half-set states).

import Foundation

struct CompressedOutput: Hashable, Sendable {
    let url: URL
    let bytes: Int64
    let createdAt: Date
    /// nil for photo outputs (Phase 3 commit 5) — `CompressionSettings` is
    /// video-only. Photo outputs carry their settings indirectly via the
    /// filename suffix; the row UI doesn't need this field for savings calc.
    let settings: CompressionSettings?

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
