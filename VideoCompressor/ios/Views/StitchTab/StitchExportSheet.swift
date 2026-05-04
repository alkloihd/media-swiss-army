//
//  StitchExportSheet.swift
//  VideoCompressor
//
//  Modal sheet that lets the user pick a compression preset, kick off the
//  stitch export, watch progress, and (on success) save the result to
//  Photos. Mirrors the row format used by `PresetPickerView` so the two
//  pickers feel like one consistent control.
//

import SwiftUI
import UIKit

struct StitchExportSheet: View {
    @ObservedObject var project: StitchProject
    @Environment(\.dismiss) private var dismiss

    /// Local draft separate from any global selection. Stitch users may want
    /// a different preset than their last single-file compression.
    @State private var draftSettings: CompressionSettings = .balanced
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: String?
    @State private var saveStatus: SaveStatus = .unsaved

    static func shouldShowExportAgain(for state: StitchExportState) -> Bool {
        if case .finished = state { return true }
        return false
    }

    static func canSaveFinishedOutput(
        _ output: CompressedOutput,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        fileExists(output.url)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                presetList
                Divider()
                progressFooter
            }
            .navigationTitle("Stitch & Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if project.isExporting {
                            project.cancelExport()
                        }
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(project.isExporting)
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
        }
    }

    // MARK: - Preset list

    @ViewBuilder
    private var presetList: some View {
        List(CompressionSettings.phase1Presets) { setting in
            Button {
                draftSettings = setting
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: setting.symbolName)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setting.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(setting.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if draftSettings == setting {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(project.isExporting)
        }
        .listStyle(.plain)
    }

    // MARK: - Footer (action button + progress + result)

    @ViewBuilder
    private var progressFooter: some View {
        VStack(spacing: 12) {
            switch project.exportState {
            case .idle, .cancelled:
                exportButton
            case .building:
                ProgressView()
                Text("Building composition…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .preparing(let current, let total):
                // Photo-bake phase — sub-second on Pro phones, can be a few
                // seconds with many large stills. Determinate bar reads as
                // "Preparing 3 of 8 photos" rather than a frozen spinner.
                ProgressView(
                    value: total > 0 ? Double(current) / Double(total) : 0
                )
                Text("Preparing \(current) of \(total) photo\(total == 1 ? "" : "s")…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Cancel Export") {
                    project.cancelExport()
                }
                .font(.subheadline)
            case .encoding(let progress):
                ProgressView(value: progress.value)
                Text("Encoding · \(progress.percent)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Cancel Export") {
                    project.cancelExport()
                }
                .font(.subheadline)
            case .finished(let output):
                finishedView(output: output)
            case .failed(let error):
                Label(error.displayMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .font(.callout)
                exportButton  // allow retry
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var exportButton: some View {
        Button {
            project.export(settings: draftSettings)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!project.canExport)
        .accessibilityIdentifier("stitchExportRunButton")
    }

    @ViewBuilder
    private func finishedView(output: CompressedOutput) -> some View {
        let canSave = Self.canSaveFinishedOutput(output)

        VStack(spacing: 8) {
            Label("Done · \(output.sizeLabel)", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.body.weight(.semibold))

            if let note = output.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if canSave {
                switch saveStatus {
                case .unsaved:
                    Button {
                        runSaveToPhotos(url: output.url)
                    } label: {
                        Label("Save to Photos", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("stitchSaveToPhotosButton")
                case .saving:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Saving…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .saved:
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body.weight(.semibold))
                        .symbolEffect(.bounce, value: saveStatus)
                case .saveFailed:
                    Button {
                        runSaveToPhotos(url: output.url)
                    } label: {
                        Label("Retry Save to Photos", systemImage: "exclamationmark.triangle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("stitchSaveToPhotosButton")
                }
            } else {
                Label("Output cleaned up", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if Self.shouldShowExportAgain(for: project.exportState) {
                Button {
                    rerunExport()
                } label: {
                    Label("Export Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stitchExportAgainButton")
            }
        }
    }

    private func rerunExport() {
        saveTask?.cancel()
        saveTask = nil
        saveError = nil
        saveStatus = .unsaved
        project.export(settings: draftSettings)
    }

    private func runSaveToPhotos(url: URL) {
        saveError = nil
        saveStatus = .saving
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await PhotosSaver.saveVideo(at: url)
                saveStatus = .saved
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Audit-9-F2 fix: stitched output is now safely in Photos.
                // Keep the sandbox copy briefly for immediate share/retry
                // flows, then sweep it from Documents/StitchOutputs/.
                Task.detached(priority: .utility) {
                    await CacheSweeper.shared.sweepAfterSave(url)
                }
            } catch {
                if !Task.isCancelled {
                    saveStatus = .saveFailed(reason: error.localizedDescription)
                    saveError = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

#Preview {
    StitchExportSheet(project: StitchProject())
}
