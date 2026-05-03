//
//  MetadataTagCardView.swift
//  VideoCompressor
//
//  One tag row in the MetadataInspectorView list. Red + strikethrough when
//  the tag will be stripped; green when it will be kept.
//

import SwiftUI

struct MetadataTagCardView: View {
    let tag: MetadataTag
    let willStrip: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tag.category.systemImage)
                .foregroundStyle(willStrip ? .red : .green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.displayName)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(willStrip)
                    .foregroundStyle(willStrip ? .secondary : .primary)
                Text(tag.value)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                if tag.isMetaFingerprint {
                    Label("Meta glasses fingerprint", systemImage: "exclamationmark.shield")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
    }
}

#Preview {
    List {
        MetadataTagCardView(
            tag: MetadataTag(
                id: UUID(),
                key: "com.apple.quicktime.comment",
                displayName: "Comment",
                value: "<binary, 32 bytes>",
                category: .custom,
                isMetaFingerprint: true
            ),
            willStrip: true
        )
        MetadataTagCardView(
            tag: MetadataTag(
                id: UUID(),
                key: "com.apple.quicktime.location.ISO6709",
                displayName: "Location Iso6709",
                value: "+37.3320-122.0312+030.000/",
                category: .location,
                isMetaFingerprint: false
            ),
            willStrip: false
        )
    }
}
