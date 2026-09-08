//
//  TimeFrameIcon.swift
//  time_frame (Milestone 28)
//
//  The app's single, controlled icon catalog: the closed set of SF Symbols a user may
//  choose for a Task Template or a Session Plan (ADR-103).
//
//  Two rules make this a *catalog* rather than a loose convention:
//
//  1. **Only a catalog member can be stored.** The persisted value is a stable, opaque
//     identifier (`TimeFrameIconIdentifier.rawValue`) — never an SF Symbol name and never
//     free text. An unknown or empty stored value resolves to the type's default instead
//     of reaching `Image(systemName:)`, so a corrupt row, a downgrade, or a synced value
//     from a newer build can never render a missing glyph.
//  2. **Only this file maps an identifier to a symbol.** `symbolName` is the one resolver;
//     views ask a template/plan for its `icon` and render `icon.symbolName`. No view spells
//     out an SF Symbol string for a template or plan icon.
//
//  Pure Foundation: no SwiftUI, no SwiftData, no timer. It is a naming/identity concern, so
//  it lives in `Core/Support/` (compiled into both the macOS app and the iOS companion) and
//  can be referenced from the models without the domain gaining a presentation dependency.
//

import Foundation

/// The logical grouping an icon belongs to. Drives the section headers of the icon picker
/// and keeps the catalog browsable as it grows.
nonisolated enum TimeFrameIconCategory: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case focus
    case study
    case work
    case wellbeing
    case general

    var id: String { rawValue }

    /// The section title shown in the picker.
    var displayName: String {
        switch self {
        case .focus: "Focus"
        case .study: "Study"
        case .work: "Work"
        case .wellbeing: "Wellbeing"
        case .general: "General"
        }
    }
}

/// The closed set of icons a template or plan may carry.
///
/// The `rawValue` is the **stable persisted identifier**. It is deliberately independent of
/// the SF Symbol name so a symbol can be swapped for a better one in a later OS without
/// rewriting stored rows — and so no SF Symbol string ever originates from stored data.
nonisolated enum TimeFrameIconIdentifier: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {

    // Focus / work surfaces
    case brain
    case laptop
    case desktop
    case keyboard
    case pencil
    case target
    case scope

    // Study
    case book
    case bookClosed
    case textbook
    case graduationCap
    case studentDesk
    case notebook

    // Work / business
    case briefcase
    case chart
    case calendar
    case people
    case list

    // Wellbeing / breaks
    case walk
    case run
    case leaf
    case coffee
    case moon
    case bed

    // General
    case star
    case bolt
    case flag
    case checkmark
    case timer
    case clock
    case grid

    var id: String { rawValue }

    /// The SF Symbol this identifier renders as. **The one mapping in the app** — a view
    /// never writes one of these strings itself for a template/plan icon.
    var symbolName: String {
        switch self {
        case .brain: "brain"
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .keyboard: "keyboard"
        case .pencil: "pencil"
        case .target: "target"
        case .scope: "scope"

        case .book: "book"
        case .bookClosed: "book.closed"
        case .textbook: "text.book.closed"
        case .graduationCap: "graduationcap"
        case .studentDesk: "studentdesk"
        case .notebook: "note.text"

        case .briefcase: "briefcase"
        case .chart: "chart.bar"
        case .calendar: "calendar"
        case .people: "person.2"
        case .list: "list.bullet.rectangle"

        case .walk: "figure.walk"
        case .run: "figure.run"
        case .leaf: "leaf"
        case .coffee: "cup.and.saucer"
        case .moon: "moon"
        case .bed: "bed.double"

        case .star: "star"
        case .bolt: "bolt"
        case .flag: "flag"
        case .checkmark: "checkmark.circle"
        case .timer: "timer"
        case .clock: "clock"
        case .grid: "square.grid.2x2"
        }
    }

    /// The human-readable name shown beside the icon in the picker and spoken by VoiceOver.
    var displayName: String {
        switch self {
        case .brain: "Brain"
        case .laptop: "Laptop"
        case .desktop: "Desktop"
        case .keyboard: "Keyboard"
        case .pencil: "Pencil"
        case .target: "Target"
        case .scope: "Scope"

        case .book: "Book"
        case .bookClosed: "Closed Book"
        case .textbook: "Textbook"
        case .graduationCap: "Graduation Cap"
        case .studentDesk: "Desk"
        case .notebook: "Notebook"

        case .briefcase: "Briefcase"
        case .chart: "Chart"
        case .calendar: "Calendar"
        case .people: "People"
        case .list: "Checklist"

        case .walk: "Walk"
        case .run: "Run"
        case .leaf: "Leaf"
        case .coffee: "Coffee"
        case .moon: "Moon"
        case .bed: "Rest"

        case .star: "Star"
        case .bolt: "Bolt"
        case .flag: "Flag"
        case .checkmark: "Checkmark"
        case .timer: "Timer"
        case .clock: "Clock"
        case .grid: "Grid"
        }
    }

    /// The category this icon is listed under.
    var category: TimeFrameIconCategory {
        switch self {
        case .brain, .laptop, .desktop, .keyboard, .pencil, .target, .scope:
            .focus
        case .book, .bookClosed, .textbook, .graduationCap, .studentDesk, .notebook:
            .study
        case .briefcase, .chart, .calendar, .people, .list:
            .work
        case .walk, .run, .leaf, .coffee, .moon, .bed:
            .wellbeing
        case .star, .bolt, .flag, .checkmark, .timer, .clock, .grid:
            .general
        }
    }

    /// The VoiceOver phrasing for one picker option, e.g. "Laptop icon".
    var accessibilityLabel: String { "\(displayName) icon" }

    // MARK: Defaults and resolution

    /// The icon a template carries when the user has not chosen one.
    static let templateDefault: TimeFrameIconIdentifier = .target

    /// The icon a plan carries when the user has not chosen one.
    static let planDefault: TimeFrameIconIdentifier = .list

    /// Resolves a **stored** identifier, falling back to `fallback` for an unknown, empty,
    /// or absent value. This is the only entry point stored data uses; it guarantees a
    /// renderable symbol without ever trusting the stored string as a symbol name.
    static func resolve(_ rawValue: String?, fallback: TimeFrameIconIdentifier) -> TimeFrameIconIdentifier {
        guard let rawValue, let icon = TimeFrameIconIdentifier(rawValue: rawValue) else {
            return fallback
        }
        return icon
    }

    /// Every icon in a category, in catalog order.
    static func icons(in category: TimeFrameIconCategory) -> [TimeFrameIconIdentifier] {
        allCases.filter { $0.category == category }
    }
}
