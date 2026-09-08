//
//  TFDetailActions.swift
//  time_frame (Milestone 29)
//
//  The action hierarchy shared by the Template and Plan detail pages.
//
//  Before this, every action on those pages was a full-width control and three of them were
//  filled blue, so "Start", "Create Plan", "Pin", "Duplicate" and "Delete" all shouted equally
//  (§18). The rule the app now follows is the macOS one:
//
//    • exactly ONE prominent action per page (Start);
//    • supporting actions are bordered and sized to their content;
//    • a preference (pinning) is a switch, not a button;
//    • destructive actions live in a separate, quieter "Manage" group and are red only there.
//
//  Presentation-only: these views take closures and render them. They own no state and never
//  touch the engine.
//

import SwiftUI

/// The quiet "Manage" group at the foot of a detail page: reversible maintenance actions,
/// separated from the page's real actions so Delete never sits beside Start.
struct TFManageSection: View {
    let duplicate: () -> Void
    let delete: () -> Void
    var duplicateIdentifier: String
    var deleteIdentifier: String
    /// What is being deleted, for the destructive control's VoiceOver label.
    let itemDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            Text("Manage")
                .font(TFTypography.groupTitle)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: TFSpacing.s) {
                Button(action: duplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Duplicate \(itemDescription)")
                .accessibilityIdentifier(duplicateIdentifier)
                .help("Create an independent copy")

                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(TFPalette.destructive)
                .accessibilityLabel("Delete \(itemDescription)")
                .accessibilityHint("Asks for confirmation first")
                .accessibilityIdentifier(deleteIdentifier)

                Spacer(minLength: 0)
            }
        }
    }
}

/// A caution note shown inside a detail page when the item cannot start. The message carries
/// the meaning; the colour and glyph only reinforce it (§48).
struct TFNoticeBanner: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = TFPalette.warning

    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(TFTypography.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(TFSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: TFRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
