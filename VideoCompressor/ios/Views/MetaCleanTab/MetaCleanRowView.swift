//
//  MetaCleanRowView.swift
//  VideoCompressor
//
//  Compact row in the MetaClean item list. Shows scan / clean state at a glance.
//

import SwiftUI

struct MetaCleanRowView: View {
    let item: MetaCleanItem

    var body: some View {
        HStack {
            Image(systemName: "film")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if item.cleanResult != nil {
            Label("Cleaned", systemImage: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        } else if let err = item.scanError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        } else if item.tags.isEmpty {
            Label("Scanning…", systemImage: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            let n = item.tags.count
            let f = item.tags.filter(\.isMetaFingerprint).count
            Text(
                f > 0
                    ? "\(n) tags · \(f) Meta fingerprint\(f == 1 ? "" : "s")"
                    : "\(n) tags"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
