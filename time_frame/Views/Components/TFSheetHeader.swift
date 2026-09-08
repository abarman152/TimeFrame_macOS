//
//  TFSheetHeader.swift
//  time_frame (Milestone 29)
//
//  The title block every editor sheet opens with.
//
//  A macOS sheet has no navigation bar, so `navigationTitle` inside one renders nothing — the
//  Template and Plan editors previously opened with no title at all, leaving the user to infer
//  from the fields whether they were creating or editing. This gives the sheet a title, an
//  optional line of context, and a separator, in one shared place.
//

import SwiftUI

struct TFSheetHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TFSpacing.l)
            .padding(.top, TFSpacing.l)
            .padding(.bottom, TFSpacing.m)

            Divider()
        }
    }
}
