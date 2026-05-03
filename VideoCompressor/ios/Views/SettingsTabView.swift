//
//  SettingsTabView.swift
//  VideoCompressor
//
//  Settings tab — opt-in controls for power-user features.
//  Sections:
//    • Background encoding toggle (Audio Background Mode)
//    • Storage (cache management — Phase 3 commit 4)
//

import SwiftUI

struct SettingsTabView: View {
    @AppStorage("allowBackgroundEncoding") private var allowBackgroundEncoding = false

    // Storage section state
    @State private var formattedCacheSize: String = "—"
    @State private var folderStats: [CacheSweeper.FolderStat] = []
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Background encoding
                Section {
                    Toggle("Allow encoding in background", isOn: $allowBackgroundEncoding)
                } footer: {
                    Text(
                        "When on, compression and stitch jobs continue while the screen is locked or you switch apps. " +
                        "The app uses iOS's audio background mode (silently — no sound is played) to stay alive. " +
                        "When active, you may see Media Swiss Army on the lock screen's Now Playing widget."
                    )
                }

                // MARK: Storage
                Section("Storage") {
                    HStack {
                        Text("App cache")
                        Spacer()
                        Text(formattedCacheSize)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if folderStats.contains(where: { $0.bytes > 0 }) {
                        ForEach(folderStats, id: \.name) { stat in
                            HStack {
                                Text(stat.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(
                                    ByteCountFormatter.string(
                                        fromByteCount: stat.bytes,
                                        countStyle: .file
                                    )
                                )
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("Clear cache")
                    }
                    .confirmationDialog(
                        "Clear all cached videos?",
                        isPresented: $showClearConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Clear", role: .destructive) {
                            Task {
                                await CacheSweeper.shared.clearAll()
                                await refreshSize()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Removes all imported and processed videos from app storage. " +
                            "Files already saved to Photos are not affected."
                        )
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await refreshSize()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func refreshSize() async {
        let (total, stats) = await Task.detached(priority: .utility) {
            let total = await CacheSweeper.shared.totalCacheBytes()
            let stats = await CacheSweeper.shared.breakdown()
            return (total, stats)
        }.value
        formattedCacheSize = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        folderStats = stats
    }
}

#Preview {
    SettingsTabView()
}
