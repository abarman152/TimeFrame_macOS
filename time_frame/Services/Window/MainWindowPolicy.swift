//
//  MainWindowPolicy.swift
//  time_frame (Milestone 32)
//
//  The decision half of "show the main window", with no AppKit in it.
//
//  Time Frame has exactly one main window (ADR-111). Everything that can ask for it —
//  the menu bar's gear menu, the popover's Start fallback, the Quick Start empty state,
//  a Dock reopen, a notification the user opened — asks the same question: *given the
//  window that exists right now, what has to happen for it to be the focused window?*
//
//  That question is answered here, as a pure function over a snapshot. It is deliberately
//  not answered with a stored `windowIsOpen` boolean: a window can be closed, minimized,
//  hidden with the application, or recreated by SwiftUI at any moment, and a boolean is
//  wrong the instant any of those happens. The snapshot is read from the live window each
//  time, so the decision can never be based on a stale belief.
//

import Foundation

/// What the one main window is doing right now. Read fresh from the live window on every
/// request — never cached, never inferred (ADR-111).
struct MainWindowSnapshot: Equatable, Sendable {
    /// The window is minimized into the Dock.
    var isMiniaturized: Bool
    /// The window is on screen (AppKit's `isVisible`, which is false while minimized
    /// and false while the application is hidden).
    var isVisible: Bool

    init(isMiniaturized: Bool = false, isVisible: Bool = true) {
        self.isMiniaturized = isMiniaturized
        self.isVisible = isVisible
    }

    /// An ordinary, on-screen window.
    static let onScreen = MainWindowSnapshot(isMiniaturized: false, isVisible: true)
    /// A window minimized into the Dock.
    static let miniaturized = MainWindowSnapshot(isMiniaturized: true, isVisible: false)
    /// A window that exists but is off screen — typically because the application is hidden.
    static let offScreen = MainWindowSnapshot(isMiniaturized: false, isVisible: false)
}

/// The one decision the window layer makes.
enum MainWindowAction: Equatable, Sendable {
    /// No main window exists, so one must be created. This is the *only* branch that can
    /// bring a window into being, and the scene it opens is a single-instance `Window`,
    /// so it cannot produce a second one.
    case createWindow

    /// A main window already exists: reuse it. The associated values say what has to be
    /// undone first — the application being hidden, and the window being minimized.
    /// Reuse never rebuilds the view tree, so navigation, scroll position, and the running
    /// session are untouched (§17/§18).
    case reuseExisting(unhideApplication: Bool, deminiaturize: Bool)

    /// A creation is already in flight from an earlier request in this same run-loop turn.
    /// Doing nothing is the correct answer: the window being created *is* the window this
    /// request wants (§28).
    case coalesced

    /// Whether this action results in a window being brought forward rather than created.
    var reusesExistingWindow: Bool {
        if case .reuseExisting = self { return true }
        return false
    }
}

/// The pure policy. No AppKit, no SwiftUI, no stored state.
enum MainWindowPolicy {

    /// Decides what must happen for the main window to end up focused.
    ///
    /// - Parameters:
    ///   - existing: the live state of the main window, or `nil` when the app has none
    ///     (the user closed it, or it has not been created yet).
    ///   - applicationIsHidden: whether the whole application is hidden (⌘H).
    ///   - creationIsPending: whether a create was already issued in this run-loop turn.
    static func action(for existing: MainWindowSnapshot?,
                       applicationIsHidden: Bool,
                       creationIsPending: Bool) -> MainWindowAction {
        guard let existing else {
            // A window that does not exist cannot be focused. Create one — unless a
            // create from a moment ago has not landed yet, in which case a second create
            // is exactly the duplicate this milestone exists to prevent.
            return creationIsPending ? .coalesced : .createWindow
        }
        // A window exists in every other case, including minimized and hidden. It is
        // always reused: an existing window is never replaced by a new one.
        return .reuseExisting(
            unhideApplication: applicationIsHidden || (!existing.isVisible && !existing.isMiniaturized),
            deminiaturize: existing.isMiniaturized
        )
    }
}
