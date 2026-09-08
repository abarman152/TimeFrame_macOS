//
//  QuickStartItem.swift
//  time_frame (Milestone 28)
//
//  The pure value type behind the menu bar's Quick Start list: one pinned Task Template or
//  Session Plan, reduced to exactly what a row needs to draw and what a start needs to route
//  (ADR-104/105).
//
//  It carries **no** SwiftData model, no timer state, and no clock. It is rebuilt from the
//  authoritative repositories whenever they change, so it can never become a second source of
//  truth: it holds the item's stable `id`, and starting it re-resolves the live template/plan
//  by that id through the existing `AppIntentSessionActions` seam. A rename therefore takes
//  effect on the next refresh, and a deleted item simply stops appearing.
//
//  Foundation-only (no SwiftUI, no SwiftData) so the list, its ordering, and its accessibility
//  phrasing are unit-testable without rendering the menu bar.
//

import Foundation

/// One pinned item shown in Quick Start.
nonisolated struct QuickStartItem: Sendable, Equatable, Identifiable, Hashable {

    /// Which kind of saved definition this row represents. The menu bar shows the kind as a
    /// quiet secondary label so a Template and a Plan are distinguishable by *text*, not by
    /// icon alone — the icon is the user's own choice and carries no type meaning.
    enum Kind: String, Sendable, Equatable, Hashable {
        case template
        case plan

        /// The short, user-facing word for this kind.
        var displayName: String {
            switch self {
            case .template: "Template"
            case .plan: "Plan"
            }
        }
    }

    /// The stable identity of the underlying `TaskTemplate` / `SessionPlan`.
    let id: UUID
    let kind: Kind
    /// The item's own name, as the user last saved it.
    let name: String
    /// A compact secondary line, e.g. "50 min focus · 10 min break" or "4 focus sessions · 2h".
    let subtitle: String
    /// The user's chosen icon, already resolved through the one catalog (ADR-103).
    let icon: TimeFrameIconIdentifier
    /// Whether the item can currently start — false when its configuration was deleted. A
    /// non-startable item is still listed (so the pin is not silently lost) but its start
    /// control is disabled and explained.
    let isStartable: Bool
    /// When the user pinned it. Drives the stable Quick Start order.
    let pinnedAt: Date?

    init(
        id: UUID,
        kind: Kind,
        name: String,
        subtitle: String,
        icon: TimeFrameIconIdentifier,
        isStartable: Bool,
        pinnedAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.isStartable = isStartable
        self.pinnedAt = pinnedAt
    }

    /// The name shown in the row, never empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled \(kind.displayName)" : trimmed
    }

    /// The VoiceOver label for the row itself: what it is, plus its summary.
    var accessibilityLabel: String {
        "\(displayName), \(kind.displayName), \(subtitle)"
    }

    /// The VoiceOver label for the row's start control, e.g. "Start Deep Work".
    var startAccessibilityLabel: String { "Start \(displayName)" }

    /// The VoiceOver hint explaining why a start control is disabled, or `nil` when it is
    /// available. Essential state is carried by words, never by dimming alone.
    var unavailableReason: String? {
        isStartable ? nil : "Needs a configuration before it can start"
    }
}

/// The one comparator for Quick Start ordering, shared by the repositories and the provider so
/// every surface lists pinned items identically.
///
/// Oldest pin first — the order the user built by pinning, which never reshuffles when an item
/// is renamed or edited. Ties (a `nil` `pinnedAt` from an older row, or two pins in the same
/// instant) fall back to name and then id, so the order is fully deterministic.
nonisolated enum QuickStartOrder {

    /// Whether `lhs` sorts before `rhs`, given each item's pin date, name, and id.
    static func isOrderedBefore(
        _ lhs: (pinnedAt: Date?, name: String, id: UUID),
        _ rhs: (pinnedAt: Date?, name: String, id: UUID)
    ) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case let (l?, r?) where l != r:
            return l < r
        case (nil, _?):
            // An item with no recorded pin date sorts after one that has it.
            return false
        case (_?, nil):
            return true
        default:
            break
        }
        if lhs.name != rhs.name {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Sorts already-built items into Quick Start order.
    static func sorted(_ items: [QuickStartItem]) -> [QuickStartItem] {
        items.sorted { isOrderedBefore(($0.pinnedAt, $0.displayName, $0.id),
                                       ($1.pinnedAt, $1.displayName, $1.id)) }
    }
}
