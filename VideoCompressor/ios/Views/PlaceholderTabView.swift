//
//  PlaceholderTabView.swift
//  VideoCompressor
//
//  Generic "Coming soon" view used by the Stitch and MetaClean tabs while
//  those features are still in plan/build. Polished enough to not feel like
//  a stub: large SF Symbol, headline, subtitle, and a single-line hint of
//  what the feature will do.
//

import SwiftUI

struct PlaceholderTabView: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                Image(systemName: tab.symbolName)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.tint)
                VStack(spacing: 6) {
                    Text(tab.title)
                        .font(.title2.weight(.semibold))
                    Text("Coming soon")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(tab.title)
        }
    }

    private var blurb: String {
        switch tab {
        case .compress:
            return ""
        case .stitch:
            return "Reorder, trim, and concatenate clips with all processing held until the final export."
        case .metaClean:
            return "Strip GPS, timestamps, and device fingerprints from videos without re-encoding."
        }
    }
}

#Preview {
    PlaceholderTabView(tab: .stitch)
}
