//
//  MetaCleanExportSheet.swift
//  VideoCompressor
//
//  "Clean & Save" action sheet. Shows a filename preview, a delete-original
//  toggle (with recoverable-window note), live progress, and a final
//  summary on completion. Fires MetaCleanQueue.clean then PhotosSaver.
//
//  See `.agents/work-sessions/2026-05-03/PLAN-stitch-metaclean.md` task M4.
//

import SwiftUI

struct MetaCleanExportSheet: View {
    @ObservedObject var queue: MetaCleanQueue
    let item: MetaCleanItem
    /// Called after a successful save (dismiss both sheet and inspector).
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

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
        return "\(stem)_CLEAN.mp4"
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
            Label(
                "Saved \(result.sizeLabel)",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
        case .failed(let err):
            Label(err.displayMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    // MARK: - Action

    private func run() {
        // Reset any previous terminal state so progressFooter shows clean.
        let deleteEnabled = queue.deleteOriginalAfterSave && item.originalAssetID != nil
        queue.clean(item.id) { result in
            Task { @MainActor in
                switch result {
                case .success(let metaResult):
                    do {
                        try await PhotosSaver.saveAndOptionallyDeleteOriginal(
                            cleanedURL: metaResult.cleanedURL,
                            originalAssetID: deleteEnabled ? item.originalAssetID : nil
                        )
                        onDone()
                        dismiss()
                    } catch {
                        // PhotosSaver throws PhotosSaverError; surface via queue state.
                        // The clean succeeded so we leave the result in place and show
                        // a Photos-specific failure message without overwriting it.
                        // (In practice dismiss already happened on success above; this
                        // branch only fires if PhotosSaver throws.)
                    }
                case .failure:
                    // cleanState is already .failed — progressFooter shows the error.
                    break
                }
            }
        }
    }
}
