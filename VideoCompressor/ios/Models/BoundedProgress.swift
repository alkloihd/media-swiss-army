//
//  BoundedProgress.swift
//  VideoCompressor
//
//  A `Double` value provably in `0.0...1.0`. NaN, negative, and >1.0 are
//  clamped at construction time. This makes illegal progress values
//  unrepresentable at the call site — `ProgressView(value:)` and
//  arithmetic remain safe.

import Foundation

struct BoundedProgress: Hashable, Sendable, Comparable {
    let value: Double

    init(_ raw: Double) {
        if raw.isNaN || raw < 0 { self.value = 0 }
        else if raw > 1 { self.value = 1 }
        else { self.value = raw }
    }

    static let zero = BoundedProgress(0)
    static let complete = BoundedProgress(1)

    static func < (lhs: BoundedProgress, rhs: BoundedProgress) -> Bool {
        lhs.value < rhs.value
    }

    /// Convenience: `Int(progress.percent)` → 0…100
    var percent: Int { Int((value * 100).rounded()) }
}
