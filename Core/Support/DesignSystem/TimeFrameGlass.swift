//
//  TimeFrameGlass.swift
//  time_frame
//
//  The Liquid Glass surface vocabulary for Time Frame (Milestone 9; ADR-051). Glass
//  is used *strategically* to establish hierarchy — for floating, interactive, or
//  primary control regions — never applied to every element (§7/§8). Ordinary
//  content uses the quiet (non-glass) surface so glass keeps its meaning.
//
//  These helpers are presentation-only wrappers over the native macOS 27
//  `glassEffect` API; the app targets macOS 27, so no availability fallback is
//  needed (per CLAUDE.md: no back-deployment abstractions).
//

import SwiftUI

extension View {
    /// A prominent floating **Liquid Glass** surface for a control/action region or a
    /// primary contextual card — the timer transport group, the menu-bar popover, the
    /// Today "current session" card (§7/§15/§34). Apply *after* layout modifiers so the
    /// glass wraps the finished shape (glass-effect modifier order rule).
    ///
    /// - Parameters:
    ///   - cornerRadius: the surface's corner radius, from `TFRadius`.
    ///   - tint: an optional semantic tint (from `TFPalette`) to raise prominence
    ///     without reaching for a non-existent `.prominent` glass style.
    ///   - interactive: set only when the surface itself responds to interaction
    ///     (§37) — informational surfaces stay non-interactive.
    func tfGlassSurface(cornerRadius: CGFloat = TFRadius.large,
                        tint: Color? = nil,
                        interactive: Bool = false) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A **quiet**, non-glass grouped-content surface for ordinary cards, rows, and
    /// summaries (§8/§57). Uses a subtle system fill plus a hairline border that read
    /// calmly under content and adapt to Light/Dark automatically. Reach for this — not
    /// glass — whenever a surface is informational rather than a floating control.
    ///
    /// Milestone 29 made this and `tfCard` the *same* surface, so every grouped card in the
    /// app (Statistics, Today, the library lists, the detail pages, the menu bar rows) has
    /// one fill, one border and one corner language instead of two near-identical ones.
    func tfQuietSurface(cornerRadius: CGFloat = TFRadius.medium) -> some View {
        tfCard(cornerRadius: cornerRadius)
    }

    /// The standard content card: a very subtle fill plus a hairline border. Used for the
    /// grouped detail cards, list rows that behave as cards, and the session-plan previews.
    ///
    /// - Parameters:
    ///   - cornerRadius: from `TFRadius`; defaults to the large card radius.
    ///   - isSelected: raises the fill slightly for a hovered/selected row.
    func tfCard(cornerRadius: CGFloat = TFRadius.large, isSelected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 1))
    }
}

/// The hairline divider used *inside* a card, inset so it never touches the card's border.
struct TFRowDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}
