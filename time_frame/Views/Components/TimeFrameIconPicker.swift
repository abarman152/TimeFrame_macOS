//
//  TimeFrameIconPicker.swift
//  time_frame (Milestone 28)
//
//  The one icon-selection control, shared by the Template editor and the Plan editor
//  (ADR-103).
//
//  It is a native `Picker` over the closed `TimeFrameIconIdentifier` catalog, grouped into
//  labelled sections. That choice is deliberate:
//
//    • it is a standard macOS pop-up button, so keyboard navigation, type-select, focus ring,
//      and VoiceOver all work without reimplementation;
//    • it stays compact in a Form rather than becoming a large scrolling grid;
//    • the selection type is the catalog enum, so an arbitrary SF Symbol string cannot be
//      selected, typed, or pasted in — the picker can only ever produce a catalog member.
//
//  Each option shows the glyph *and* its human-readable name, and carries an explicit
//  accessibility label ("Laptop icon"), so the choice is never conveyed by the glyph alone.
//

import SwiftUI

struct TimeFrameIconPicker: View {
    @Binding var selection: TimeFrameIconIdentifier
    /// The field label. Defaults to "Icon"; callers rarely change it.
    var title: String = "Icon"

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(TimeFrameIconCategory.allCases) { category in
                Section(category.displayName) {
                    ForEach(TimeFrameIconIdentifier.icons(in: category)) { icon in
                        Label(icon.displayName, systemImage: icon.symbolName)
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel(icon.accessibilityLabel)
                            .tag(icon)
                    }
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection.accessibilityLabel)
        .accessibilityHint("Choose the icon shown for this item in lists and Quick Start")
    }
}

/// A small, consistent way to render a chosen icon anywhere in the app. Every caller goes
/// through the catalog's `symbolName`, so no view spells out a template or plan symbol itself.
struct TimeFrameIconBadge: View {
    let icon: TimeFrameIconIdentifier
    var size: CGFloat = 15
    /// Whether the badge is tinted with the accent colour (used where the item is actionable).
    var isProminent: Bool = true

    var body: some View {
        Image(systemName: icon.symbolName)
            .font(.system(size: size))
            .foregroundStyle(isProminent ? Color.accentColor : Color.secondary)
            .frame(width: size + 7, height: size + 7)
            // The icon is a personal marker, never the sole carrier of meaning: the name it
            // sits beside always states what the item is.
            .accessibilityHidden(true)
    }
}
