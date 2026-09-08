//
//  MainWindowPresenter.swift
//  time_frame (Milestone 32)
//
//  The ONE pathway that brings Time Frame's main window forward (ADR-111).
//
//  Every entry point routes through `showMainWindow(_:)`: the menu bar's gear menu, the
//  popover's Start fallback, the Quick Start empty state, a Dock reopen, and a notification
//  the user opened. None of them decides anything itself — they supply the request, the
//  presenter supplies the policy, and a single-instance `Window` scene supplies the window.
//
//  The presenter owns no window and no timer. It holds a `MainWindowHosting` (AppKit in the
//  app, a fake in tests), asks it for the live window state on every request, and asks it to
//  perform the steps the pure `MainWindowPolicy` chose. It never restarts, resets, or
//  reconstructs anything: focusing a window is window behaviour, and the running session,
//  the engine, and the sidebar selection are none of its business (§17/§18).
//

import Foundation
import Observation

/// The AppKit-shaped capabilities the presenter needs, expressed as a protocol so the
/// decision logic is testable without a real `NSWindow` (§26).
@MainActor
protocol MainWindowHosting: AnyObject {
    /// Whether the whole application is hidden (⌘H).
    var applicationIsHidden: Bool { get }

    /// The live state of the one main window, or `nil` when there is none. Read fresh on
    /// every request — the host must never answer from a cached flag.
    func mainWindowSnapshot() -> MainWindowSnapshot?

    /// Unhides the application.
    func unhideApplication()

    /// Restores the main window from the Dock.
    func deminiaturizeMainWindow()

    /// Orders the existing main window front, makes it key, and activates the app, so the
    /// window takes on the ordinary macOS focused appearance. No custom highlight (§16).
    func focusMainWindow()

    /// Asks SwiftUI to present the single `Window` scene. Returns `false` when no opener has
    /// been registered yet, so the caller can fall back to the system's own reopen.
    @discardableResult
    func createMainWindow() -> Bool
}

/// The single main-window policy, shared by every surface that can ask for the window.
@MainActor
@Observable
final class MainWindowPresenter {

    /// The shared navigation seam. A request to open a particular section sets it here, and
    /// the existing window consumes it — the window is never rebuilt to show a section.
    let navigation: AppNavigation

    /// The AppKit host. Attached once at launch; `nil` only in tests that exercise the
    /// unattached fallback.
    @ObservationIgnored private var host: (any MainWindowHosting)?

    /// True between issuing a create and that window existing. Scoped to the current
    /// run-loop turn, so a burst of clicks collapses into one window while a later click
    /// still retries if the create never landed (§27/§28).
    @ObservationIgnored private var creationIsPending = false

    /// The most recent decision. Observable purely so the audit tests and diagnostics can
    /// see what happened; nothing in the UI branches on it.
    private(set) var lastAction: MainWindowAction?

    init(navigation: AppNavigation, host: (any MainWindowHosting)? = nil) {
        self.navigation = navigation
        self.host = host
    }

    /// Attaches the AppKit host. Called once, at launch.
    func attach(_ host: any MainWindowHosting) {
        self.host = host
    }

    /// Brings the main window forward, optionally switching it to a section first.
    ///
    /// This is the only method any surface calls. It is idempotent: calling it repeatedly
    /// focuses the same window every time and can never produce a second one.
    ///
    /// - Parameter section: the area the window should show, or `nil` to leave the user's
    ///   current screen exactly as it is.
    /// - Returns: the action taken, so a caller that must tell AppKit whether it handled a
    ///   reopen (the app delegate) can answer truthfully.
    @discardableResult
    func showMainWindow(_ section: AppSection? = nil) -> MainWindowAction {
        if let section { navigation.request(section) }

        guard let host else {
            // No host attached (only reachable before launch finishes, or in a test). Report
            // the honest answer so the caller can let the system handle it.
            let action = MainWindowAction.createWindow
            lastAction = action
            return action
        }

        let snapshot = host.mainWindowSnapshot()
        if snapshot != nil {
            // The window this presenter was waiting for exists. Nothing is pending any more.
            creationIsPending = false
        }

        let action = MainWindowPolicy.action(for: snapshot,
                                             applicationIsHidden: host.applicationIsHidden,
                                             creationIsPending: creationIsPending)
        switch action {
        case .coalesced:
            break

        case let .reuseExisting(unhideApplication, deminiaturize):
            if unhideApplication { host.unhideApplication() }
            if deminiaturize { host.deminiaturizeMainWindow() }
            host.focusMainWindow()

        case .createWindow:
            creationIsPending = true
            // Release the coalescing window at the end of this run-loop turn. A one-shot
            // main-actor continuation, not a timer and not a poll: if the create somehow
            // never lands, the next request retries rather than being ignored forever.
            Task { @MainActor [weak self] in self?.creationIsPending = false }
            host.createMainWindow()
        }

        lastAction = action
        return action
    }

    /// Called when a main window has registered itself with the host, so a create that has
    /// landed stops suppressing later requests.
    func mainWindowDidAppear() {
        creationIsPending = false
    }
}
