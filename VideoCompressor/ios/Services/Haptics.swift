//
//  Haptics.swift
//  VideoCompressor
//
//  Thin wrapper over UIKit's UI*FeedbackGenerator family. Kept centralised
//  so we have one place to swap in CoreHaptics later if a custom pattern
//  becomes worthwhile (e.g. for the export-complete celebration), and so
//  every feature uses the same API surface.
//
//  Apple's HIG on haptics: "Use haptics sparingly. Overuse breaks the spell."
//  Apply rule of thumb: tap feedback on confirmed user actions, selection
//  ticks on continuous gesture quantisation boundaries, success/error on
//  task completion. Never on hover / passive UI.
//

import UIKit

@MainActor
enum Haptics {

    // MARK: - Impact (discrete actions)

    /// Light tap. Use for "I tapped a button and it did the small thing"
    /// — Split, Reset, undo, redo.
    static func tapLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap. Use for confirmed structural actions — Save to Photos,
    /// Replace originals, Stitch & Export started.
    static func tapMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Rigid tap. Use for irreversible-feeling boundaries — drag-end snap,
    /// "you've pushed past the edge" feedback.
    static func tapRigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Selection (continuous gesture ticks)

    /// "Tick" feedback for a continuous gesture crossing a quantised
    /// boundary (slider hitting each tick, scrubber crossing each second
    /// mark, picker rolling between options). Using the recommended
    /// generator-prepare-then-fire pattern: pre-warming reduces
    /// first-tick latency from ~30ms to ~5ms.
    private static var selectionGenerator: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    static func selectionTick() {
        selectionGenerator.selectionChanged()
        // Re-prepare for the next tick. Apple docs recommend this — without
        // it the second tick latency degrades after ~3 seconds of idle.
        selectionGenerator.prepare()
    }

    // MARK: - Notification (success / failure)

    /// Success ding. Use for export-complete, save-to-Photos-success,
    /// clean-batch-finished. Do NOT use for routine taps — overuse trains
    /// users to ignore it.
    static func notifySuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func notifyError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func notifyWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
