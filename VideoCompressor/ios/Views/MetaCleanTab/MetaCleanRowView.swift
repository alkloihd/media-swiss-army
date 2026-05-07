//
//  MetaCleanRowView.swift
//  VideoCompressor
//
//  Compact row in the MetaClean item list. Shows scan / clean state at a glance.
//

import SwiftUI

struct MetaCleanRowView: View {
    let item: MetaCleanItem
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            mediaIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle(tint: tint)
        .accessibilityElement(children: .combine)
    }

    private var mediaIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppShape.radiusS)
                .fill(tint.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: AppShape.radiusS)
                        .strokeBorder(tint.opacity(0.20), lineWidth: AppShape.strokeHairline)
                )

            Image(systemName: item.kind == .still ? "photo" : "film")
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusLine: some View {
        if item.cleanResult != nil {
            Label("Cleaned", systemImage: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: item.cleanResult != nil)
                .symbolEffectsRemoved(reduceMotion)
                .transition(.scale.combined(with: .opacity))
        } else if let err = item.scanError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        } else if item.tags.isEmpty {
            Label("Scanning…", systemImage: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .shimmer()
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
