//
//  TFDetailCard.swift
//  time_frame (Milestone 29)
//
//  The grouped "details" card shared by the Template and Plan detail screens: a titled card
//  whose rows are `label — value` pairs with a small leading symbol, divided by hairlines.
//
//  Rows are built from a value type rather than free-form views so every detail screen has the
//  same rhythm, the same divider inset, and the same VoiceOver phrasing ("Focus: 25 min") in
//  one place instead of being re-derived per screen.
//

import SwiftUI

/// One `label — value` line in a details card.
struct TFDetailRow: Identifiable {
    let id = UUID()
    /// An SF Symbol chosen by the *view* to signpost the field. Never stored data.
    let systemImage: String
    let label: String
    let value: String
    /// A caution treatment for a field whose value indicates a problem (e.g. a removed
    /// configuration). The words always say so too — colour is never the only signal.
    var isWarning: Bool = false

    init(_ label: String, _ value: String, systemImage: String, isWarning: Bool = false) {
        self.label = label
        self.value = value
        self.systemImage = systemImage
        self.isWarning = isWarning
    }
}

/// A titled card of detail rows.
struct TFDetailCard: View {
    var title: String?
    let rows: [TFDetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(TFTypography.groupTitle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TFSpacing.l)
                    .padding(.top, TFSpacing.m)
                    .padding(.bottom, TFSpacing.s)
                    .accessibilityAddTraits(.isHeader)
                TFRowDivider()
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                row(pair.element)
                if pair.offset < rows.count - 1 {
                    TFRowDivider(leadingInset: TFSpacing.l)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tfCard()
    }

    private func row(_ row: TFDetailRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.m) {
            Image(systemName: row.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(row.isWarning ? TFPalette.warning : Color.secondary)
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)

            Text(row.label)
                .font(TFTypography.rowLabel)
                .foregroundStyle(.secondary)

            Spacer(minLength: TFSpacing.l)

            Text(row.value)
                .font(TFTypography.rowValue)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(row.isWarning ? TFPalette.warning : Color.primary)
        }
        .padding(.horizontal, TFSpacing.l)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label): \(row.value)")
    }
}
