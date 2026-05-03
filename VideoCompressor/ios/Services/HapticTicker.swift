//
//  HapticTicker.swift
//  VideoCompressor
//
//  Per-slider helper that fires a `UISelectionFeedbackGenerator` "tick"
//  haptic each time a continuously-changing value crosses an integer
//  multiple of `step`. This is the same sensation iOS Camera's shutter
//  dial and `Picker` controls produce — Apple's Human Interface Guidelines
//  call out `.selectionChanged()` as the right tool for "selection
//  navigation through a series of items."
//
//  Usage:
//
//      @State private var trimTicker = HapticTicker(step: 0.5)
//      ...
//      Slider(value: Binding(
//          get: { value },
//          set: { newValue in
//              value = newValue
//              trimTicker.update(newValue)
//          }
//      ))
//      .onAppear { trimTicker.prepare() }
//
//  Call `reset()` at the start of each new drag so the first crossing
//  doesn't fire spuriously from a stale `lastTick`.
//

import UIKit

@MainActor
final class HapticTicker: ObservableObject {
    private let generator = UISelectionFeedbackGenerator()
    private var lastTick: Int = .min
    private let step: Double

    init(step: Double = 0.5) {
        self.step = max(0.01, step)
    }

    /// Pre-warm the generator. Without this, the first tick has ~30 ms
    /// latency; with it, ~5 ms. Call from the view's `onAppear`.
    func prepare() {
        generator.prepare()
    }

    /// Call on every continuous value change (slider setter). Fires the
    /// haptic only when the value crosses an integer multiple of `step`.
    /// On first call after init/reset (lastTick == .min) the bucket is
    /// recorded WITHOUT firing — the user hasn't moved yet, the haptic
    /// would be spurious.
    func update(_ value: Double) {
        let bucket = Int((value / step).rounded(.down))
        guard bucket != lastTick else { return }
        if lastTick != .min {
            generator.selectionChanged()
        }
        lastTick = bucket
        // Re-arm the generator for the next tick. Apple recommends this —
        // without it, latency degrades after a few seconds of idle.
        generator.prepare()
    }

    /// Forget the last-tick state. Call at drag-start so a new gesture
    /// starts fresh and doesn't fire on the bucket the slider was already at.
    func reset() {
        lastTick = .min
    }
}
