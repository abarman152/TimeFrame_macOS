//
//  QuickStartPinButton.swift
//  time_frame (Milestone 28; restyled in Milestone 29)
//
//  The pin/unpin control used on the Template and Plan detail pages, and the matching
//  menu/swipe label used in their lists.
//
//  Pinning is an ordinary, reversible preference, so on a detail page it is a native `Toggle`
//  in a quiet card — not a full-width prominent button. A preference that reads as loudly as
//  "Start" is a hierarchy error, and it was one of the reasons the detail pages looked like a
//  stack of identical call-to-action bars (§18). All wording still comes from the pure
//  `QuickStartPinPresentation`, so every surface says and speaks the same thing (ADR-104).
//

import SwiftUI

/// The detail page's pin control: a labelled switch inside a quiet card.
struct QuickStartPinButton: View {
    let name: String
    let isPinned: Bool
    let action: () -> Void
    var identifier: String

    var body: some View {
        Toggle(isOn: Binding(get: { isPinned }, set: { _ in action() })) {
            Label {
                Text(QuickStartPinPresentation.title(isPinned: isPinned))
                    .font(.subheadline)
            } icon: {
                Image(systemName: QuickStartPinPresentation.symbolName(isPinned: isPinned))
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, TFSpacing.m)
        .padding(.vertical, 9)
        .tfCard(cornerRadius: TFRadius.medium)
        .tfAnimation(TFMotion.control, value: isPinned)
        .accessibilityLabel(QuickStartPinPresentation.accessibilityLabel(name: name, isPinned: isPinned))
        .accessibilityHint(QuickStartPinPresentation.accessibilityHint(isPinned: isPinned))
        .accessibilityIdentifier(identifier)
        .help(QuickStartPinPresentation.menuTitle(isPinned: isPinned))
    }
}

/// The pin entry for a context menu or a swipe action.
struct QuickStartPinMenuButton: View {
    let name: String
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(QuickStartPinPresentation.menuTitle(isPinned: isPinned),
                  systemImage: QuickStartPinPresentation.symbolName(isPinned: isPinned))
        }
        .accessibilityLabel(QuickStartPinPresentation.accessibilityLabel(name: name, isPinned: isPinned))
    }
}

/// The small "Pinned" marker shown in a list row or beside a detail title. Always states the
/// word, so the pin is never conveyed by a glyph alone.
struct QuickStartPinnedMarker: View {
    var body: some View {
        Label("Pinned", systemImage: "pin.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(.tint)
            .accessibilityLabel("Pinned to Quick Start")
    }
}
