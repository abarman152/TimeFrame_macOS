//
//  QuickStartPinPresentation.swift
//  time_frame (Milestone 28)
//
//  The exact words and symbols of the pin control, in one pure place (ADR-104).
//
//  Pin/unpin appears in several spots — a Template's detail page, a Plan's detail page, both
//  list context menus, and both list swipe actions — and each spot must say the same thing and
//  speak the same VoiceOver phrase. Keeping the phrasing here (Foundation-only) means the
//  strings are asserted by unit tests rather than duplicated across views.
//

import Foundation

/// The title, symbol, and spoken phrasing for the pin control in each state.
nonisolated enum QuickStartPinPresentation {

    /// The button's own title on a detail page: it states the *current* state, and the
    /// accessibility label states the *action*, which is the macOS convention for a toggle.
    static func title(isPinned: Bool) -> String {
        isPinned ? "Pinned to Quick Start" : "Pin to Quick Start"
    }

    /// The title inside a menu or swipe action, where a verb reads better than a state.
    static func menuTitle(isPinned: Bool) -> String {
        isPinned ? "Remove from Quick Start" : "Pin to Quick Start"
    }

    /// The SF Symbol for the current state. Filled when pinned; the state is always paired
    /// with a word, so the fill is never the only signal.
    static func symbolName(isPinned: Bool) -> String {
        isPinned ? "pin.fill" : "pin"
    }

    /// The VoiceOver label, naming both the item and what activating the control will do.
    static func accessibilityLabel(name: String, isPinned: Bool) -> String {
        let item = displayName(name)
        return isPinned
            ? "Remove \(item) from Quick Start"
            : "Pin \(item) to Quick Start"
    }

    /// The VoiceOver hint explaining where a pinned item shows up.
    static func accessibilityHint(isPinned: Bool) -> String {
        isPinned
            ? "Removes it from the menu bar's Quick Start list"
            : "Adds it to the menu bar's Quick Start list"
    }

    /// A never-empty display name, so the phrasing degrades gracefully for an unnamed item.
    private static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this item" : trimmed
    }
}
