//
//  SettingsTabView.swift
//  VideoCompressor
//
//  Settings tab — opt-in controls for power-user features.
//  Sections:
//    • What MetaClean does
//    • Help & how to use
//    • Background encoding toggle (Audio Background Mode)
//    • Advanced performance
//    • Storage (cache management — Phase 3 commit 4)
//    • About
//

import SwiftUI

private let privacyPolicyURL = URL(
    string: "https://alkloihd.github.io/media-swiss-army/privacy/"
)!

struct SettingsTabView: View {
    @AppStorage("allowBackgroundEncoding") private var allowBackgroundEncoding = false
    @Environment(\.colorScheme) private var colorScheme

    // Storage section state
    @State private var formattedCacheSize: String = "—"
    @State private var folderStats: [CacheSweeper.FolderStat] = []
    @State private var showClearConfirm = false

    private var settingsTint: Color {
        AppTint.settings(colorScheme)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: What MetaClean does
                Section {
                    Text(
                        "MetaClean strips the hidden fingerprint that Meta AI glasses (Ray-Ban Meta, Oakley Meta) embed in every photo and video. The fingerprint is a binary marker in the file's metadata that tells anyone — Instagram, journalists, scrapers — \"this was shot on Meta hardware.\""
                    )
                    .font(.subheadline)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("The Meta fingerprint atom")
                            Text("XMP packets tagged with the same fingerprint")
                            Text("Optional GPS, dates, and camera info when you choose a full scrub")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } label: {
                        settingsLabel("What gets removed", systemImage: "eye.trianglebadge.exclamationmark")
                    }

                    DisclosureGroup {
                        Text(
                            "Date taken. Location. Camera make and model. Live Photo identifiers. HDR gain map. Color profile. Orientation. Everything that makes your photos work properly in Photos."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } label: {
                        settingsLabel("What stays", systemImage: "checkmark.shield")
                    }

                    DisclosureGroup {
                        Text(
                            "No accounts. No cloud. No analytics. No tracking. The only network calls this app makes are App Store updates handled by iOS itself."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } label: {
                        settingsLabel("What MetaClean never does", systemImage: "network.slash")
                    }
                } header: {
                    settingsHeader("What MetaClean does", systemImage: "eye.slash")
                }
                .accessibilityIdentifier("settingsWhatMetaCleanDoesSection")

                SettingsHelpSection(tint: settingsTint)
                    .accessibilityIdentifier("settingsHelpSection")

                // MARK: Background encoding
                Section {
                    Toggle(isOn: $allowBackgroundEncoding) {
                        settingsLabel("Allow encoding in background", systemImage: "waveform")
                    }
                } footer: {
                    Text(
                        "When on, compression and stitch jobs continue while the screen is locked or you switch apps. " +
                        "The app uses iOS's audio background mode (silently — no sound is played) to stay alive. " +
                        "When active, you may see Media Swiss Army on the lock screen's Now Playing widget."
                    )
                }

                // MARK: Advanced performance
                Section {
                    DisclosureGroup {
                        HStack {
                            settingsLabel("Device class", systemImage: "iphone")
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
                            settingsLabel("Parallel encodes", systemImage: "rectangle.3.group")
                            Spacer()
                            Text("\(DeviceCapabilities.currentSafeConcurrency())")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text(
                            "Pro iPhones (13 Pro – 17 Pro) have 2 dedicated video encoder engines — " +
                            "both are used when batch-compressing. " +
                            "Concurrency drops to 1 if the device is thermally stressed."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } label: {
                        settingsLabel("Advanced", systemImage: "speedometer")
                    }
                } header: {
                    settingsHeader("Performance", systemImage: "bolt")
                }

                // MARK: Storage
                Section {
                    HStack {
                        settingsLabel("App cache", systemImage: "externaldrive")
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
                        Label("Clear cache", systemImage: "trash")
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
                } header: {
                    settingsHeader("Storage", systemImage: "internaldrive")
                }

                // MARK: About
                Section {
                    Link(destination: privacyPolicyURL) {
                        HStack {
                            settingsLabel("Privacy Policy", systemImage: "hand.raised")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text(
                        "Opens the latest privacy policy in Safari. " +
                        "Media Swiss Army does not collect, transmit, or store any of your data."
                    )
                    .font(.caption)
                }
            }
            .tint(settingsTint)
            .scrollContentBackground(.hidden)
            .background(AppMesh.backdrop(colorScheme))
            .navigationTitle("Settings")
            .toolbarBackground(.thinMaterial, for: .navigationBar)
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

    private func settingsHeader(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(settingsTint)
            .textCase(.uppercase)
    }

    private func settingsLabel(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(settingsTint)
        }
    }
}

struct SettingsHelpTopic: Identifiable, Equatable {
    let title: String
    let systemImage: String
    let details: String

    var id: String { title }

    static let all: [SettingsHelpTopic] = [
        SettingsHelpTopic(
            title: "Compress",
            systemImage: "wand.and.stars",
            details: "Import videos or photos from Photos, choose a preset, then tap Compress All. Video presets include Max Quality, Balanced, Small, and Streaming; photo presets appear when your selection is photos-only. Finished items show size savings and can be saved back to Photos. If an output is not meaningfully smaller, the app keeps the original."
        ),
        SettingsHelpTopic(
            title: "Stitch",
            systemImage: "square.stack.3d.up",
            details: "Import two or more clips or stills, then arrange them on the timeline. Drag to reorder, long-press for timeline actions, or sort by Date Taken when available. Choose an aspect ratio and transition, tap a clip to trim, crop, split, or set photo duration, then export and save to Photos."
        ),
        SettingsHelpTopic(
            title: "MetaClean",
            systemImage: "eye.slash",
            details: "Import videos or photos to inspect metadata before sharing. Tags are grouped by type. Auto strips only detected Meta/Ray-Ban glasses fingerprint metadata, Strip All removes broader non-technical metadata, and Keep All preserves metadata. Cleaned files save with a _CLEAN suffix."
        ),
        SettingsHelpTopic(
            title: "Settings",
            systemImage: "gearshape",
            details: "Background encoding is off by default. When enabled, long jobs can continue while the app is locked or backgrounded; iOS may show Media Swiss Army in Now Playing, but no sound is played. Clear cache removes staged imports and processed app copies, not files already saved to Photos."
        ),
    ]
}

struct SettingsHelpSection: View {
    let tint: Color

    var body: some View {
        Section {
            ForEach(SettingsHelpTopic.all) { topic in
                DisclosureGroup {
                    Text(topic.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Label {
                        Text(topic.title)
                    } icon: {
                        Image(systemName: topic.systemImage)
                            .foregroundStyle(tint)
                    }
                }
            }
        } header: {
            Label("Help & how to use", systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
        } footer: {
            Text("Each tool works locally on this device. Import from Photos, export when the job finishes, then save only the results you want to keep.")
                .font(.caption)
        }
    }
}

#Preview {
    SettingsTabView()
}
