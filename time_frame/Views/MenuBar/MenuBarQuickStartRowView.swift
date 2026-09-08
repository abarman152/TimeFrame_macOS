//
//  MenuBarQuickStartRowView.swift
//  time_frame (Milestone 28)
//
//  One pinned Template or Plan in the Quick Start list.
//
//  The whole row is a single control, so there is one focus stop and one VoiceOver element per
//  item ("Start Deep Work") rather than a row and a separate play button that read as two
//  things. The play glyph is decoration for the sighted layout only.
//
//  The leading icon is the user's own choice, resolved through the one catalog
//  (`item.icon.symbolName` — ADR-103); this view never spells out an SF Symbol for it.
//
//  ## Milestone 30 — the secondary line
//  The visible secondary line used to be prefixed with the item's kind ("Template · 25 min
//  focus · 5 min break"). In a 288 pt popover that prefix pushed the durations — the part the
//  user is actually choosing between — past the truncation point, so the row read
//  "Template · 25 min focus · 5 mi…". The kind is now carried by the row's **accessibility
//  value** instead, where it is spoken in full, and the visible line shows the summary alone.
//  Nothing is lost for VoiceOver, and the sighted row states the numbers it exists to state.
//

import SwiftUI

struct MenuBarQuickStartRowView: View {
    let item: QuickStartItem
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TFSpacing.m) {
                Image(systemName: item.icon.symbolName)
                    .font(.system(size: 15))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: TFSpacing.s)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, TFSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: TFRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .tfQuietSurface(cornerRadius: TFRadius.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.startAccessibilityLabel)
        .accessibilityValue(secondaryLine)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("timeFrame.menuBar.quickStart.\(item.kind.rawValue).\(item.id.uuidString)")
        .help(helpText)
    }

    /// "Template · 50 min focus · 10 min break" — the spoken value, kind first, so the type is
    /// still stated in words even though the visible line shows only the summary.
    private var secondaryLine: String {
        "\(item.kind.displayName) · \(item.subtitle)"
    }

    private var accessibilityHint: String {
        if let reason = item.unavailableReason { return reason }
        if !isEnabled { return "A session is already running" }
        return "Starts this \(item.kind.displayName.lowercased()) immediately"
    }

    private var helpText: String {
        item.unavailableReason ?? "Start \(item.displayName)"
    }
}
