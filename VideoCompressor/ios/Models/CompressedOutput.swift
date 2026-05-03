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
    let settings: CompressionSettings

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
