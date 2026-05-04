//
//  SettingsTabView.swift
//  VideoCompressor
//
//  Settings tab — opt-in controls for power-user features.
//  Sections:
//    • What MetaClean does
//    • Background encoding toggle (Audio Background Mode)
//    • Performance
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
                // MARK: What MetaClean does
                Section("What MetaClean does") {
                    Text(
                        "MetaClean strips the hidden fingerprint that Meta AI glasses (Ray-Ban Meta, Oakley Meta) embed in every photo and video. The fingerprint is a binary marker in the file's metadata that tells anyone — Instagram, journalists, scrapers — \"this was shot on Meta hardware.\""
                    )
                    .font(.subheadline)

                    DisclosureGroup("What gets removed") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("The Meta fingerprint atom")
                            Text("XMP packets tagged with the same fingerprint")
                            Text("Optional GPS, dates, and camera info when you choose a full scrub")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("What stays") {
                        Text(
                            "Date taken. Location. Camera make and model. Live Photo identifiers. HDR gain map. Color profile. Orientation. Everything that makes your photos work properly in Photos."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("What MetaClean never does") {
                        Text(
                            "No accounts. No cloud. No analytics. No tracking. The only network calls this app makes are App Store updates handled by iOS itself."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settingsWhatMetaCleanDoesSection")

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

                // MARK: Performance (Phase 3 commit 8)
                Section {
                    HStack {
                        Text("Device class")
                        Spacer()
                        Text(
                            DeviceCapabilities.deviceClass == .pro
                                ? "Pro (2× encoder)"
                                : DeviceCapabilities.deviceClass == .standard
                                    ? "Standard (1× encoder)"
                                    : "Unknown"
                        )
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Parallel encodes")
                        Spacer()
                        Text("\(DeviceCapabilities.currentSafeConcurrency())")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    Text(
                        "Pro iPhones (13 Pro – 17 Pro) have 2 dedicated video encoder engines — " +
                        "both are used when batch-compressing. " +
                        "Concurrency drops to 1 if the device is thermally stressed."
                    )
                    .font(.caption)
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
