//
//  MetadataInspectorView.swift
//  VideoCompressor
//
//  Sheet that shows all metadata tags for one MetaCleanItem, grouped by
//  category. Includes a segmented mode picker (Auto / Strip All / Keep All)
//  and a Clean toolbar button that opens MetaCleanExportSheet.
//
//  See `.agents/work-sessions/2026-05-03/plans/PLAN-stitch-metaclean.md` task M3.
//

import SwiftUI

struct MetadataInspectorView: View {
    @ObservedObject var queue: MetaCleanQueue
    let itemID: MetaCleanItem.ID
    @Environment(\.dismiss) private var dismiss
    @State private var showExportSheet = false

    private var item: MetaCleanItem? {
        queue.items.first(where: { $0.id == itemID })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    listView(item)
                } else {
                    Text("Item not found.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item?.displayName ?? "Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clean") { showExportSheet = true }
                        .disabled(item?.tags.isEmpty ?? true)
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let item {
                    MetaCleanExportSheet(queue: queue, item: item) { dismiss() }
                }
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private func listView(_ item: MetaCleanItem) -> some View {
        List {
            modePickerSection
            if item.tags.isEmpty {
                Section {
                    if item.scanError != nil {
                        Label(item.scanError ?? "Scan failed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        Text("Scanning metadata…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(MetadataCategory.allCases, id: \.self) { cat in
                    let group = item.tags.filter { $0.category == cat }
                    if !group.isEmpty {
                        Section(cat.displayName) {
                            ForEach(group) { tag in
                                MetadataTagCardView(
                                    tag: tag,
                                    willStrip: queue.rules.willStrip(tag)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mode picker

    @ViewBuilder
    private var modePickerSection: some View {
        Section("Strip mode") {
            Picker("Mode", selection: $queue.rules) {
                Text("Auto (Meta glasses)").tag(StripRules.autoMetaGlasses)
                Text("Strip All").tag(StripRules.stripAll)
                Text("Keep All").tag(StripRules.identity)
            }
            .pickerStyle(.segmented)
        }
    }
}
