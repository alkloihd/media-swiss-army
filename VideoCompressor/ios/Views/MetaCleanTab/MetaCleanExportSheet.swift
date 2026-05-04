//
//  MetaCleanExportSheet.swift
//  VideoCompressor
//
//  "Clean & Save" action sheet. Shows a filename preview, a delete-original
//  toggle (with recoverable-window note), live progress, and a final
//  summary on completion. Fires MetaCleanQueue.clean then PhotosSaver.
//
//  See `.agents/work-sessions/2026-05-03/plans/PLAN-stitch-metaclean.md` task M4.
//

import SwiftUI
import UIKit

struct MetaCleanExportSheet: View {
    @ObservedObject var queue: MetaCleanQueue
    let item: MetaCleanItem
    /// Called after a successful save (dismiss both sheet and inspector).
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saveStatus: SaveStatus = .unsaved

    var body: some View {
        NavigationStack {
            Form {
                Section("Output") {
                    LabeledContent("Filename", value: outputFilename)
                    Text("Cleaned file is saved with a `_CLEAN` suffix to your Photos library.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Original") {
                    Toggle("Delete original after save", isOn: $queue.deleteOriginalAfterSave)
                        .tint(.red)
                    if item.originalAssetID == nil {
                        Text("Delete-original is unavailable — the asset identifier was not captured at import (Photos access may be limited).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("iOS will ask you to confirm. Original moves to Recently Deleted (recoverable for 30 days).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section { progressFooter }
            }
            .navigationTitle("Clean & Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clean & Save") { run() }
                        .disabled(isWorking)
                }
            }
        }
    }

    // MARK: - Helpers

    private var outputFilename: String {
        let stem = item.sourceURL.deletingPathExtension().lastPathComponent
        let ext = item.sourceURL.pathExtension
        // Preserve source extension — an image cleaned shouldn't display
        // as `.mp4`, a `.mov` shouldn't display as `.mp4`, etc.
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return "\(stem)_CLEAN\(suffix)"
    }

    private var isWorking: Bool {
        if case .cleaning = queue.cleanState { return true }
        return false
    }

    @ViewBuilder
    private var progressFooter: some View {
        switch queue.cleanState {
        case .cleaning:
            ProgressView(value: queue.cleanProgress.value)
            Text("Cleaning… \(queue.cleanProgress.percent)%")
                .font(.caption.monospacedDigit())
        case .finished(let result):
            switch saveStatus {
            case .unsaved:
                Label(
                    "Cleaned \(result.sizeLabel) — tap Clean & Save again to save",
                    systemImage: "checkmark.seal.fill"
                )
                .foregroundStyle(.green)
            case .saving:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving to Photos…")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            case .saved:
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: saveStatus)
            case .saveFailed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        case .failed(let err):
            Label(err.displayMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    // MARK: - Action

    private func run() {
        // Reset any previous save-state so the footer re-animates on retry.
        saveStatus = .unsaved
        let deleteEnabled = queue.deleteOriginalAfterSave && item.originalAssetID != nil
        queue.clean(item.id) { result in
            Task { @MainActor in
                switch result {
                case .success(let metaResult):
                    self.saveStatus = .saving
                    do {
                        try await PhotosSaver.saveAndOptionallyDeleteOriginal(
                            cleanedURL: metaResult.cleanedURL,
                            originalAssetID: deleteEnabled ? item.originalAssetID : nil
                        )
                        self.saveStatus = .saved
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        // Audit-9-F3 fix: cleaned output is now in Photos.
                        // Keep it briefly for immediate share/retry flows,
                        // while removing the staged input copy right away.
                        let outputURL = metaResult.cleanedURL
                        let inputURL = item.sourceURL
                        Task.detached(priority: .utility) {
                            await CacheSweeper.shared.sweepAfterSave(outputURL)
                            await CacheSweeper.shared.deleteIfInWorkingDir(inputURL)
                        }
                        self.onDone()
                        self.dismiss()
                    } catch {
                        self.saveStatus = .saveFailed(reason: error.localizedDescription)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                case .failure:
                    // cleanState is already .failed — progressFooter shows the error.
                    break
                }
            }
        }
    }
}
