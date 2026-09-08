//
//  TimeFrameAppDelegate.swift
//  time_frame (Milestone 32)
//
//  The application delegate exists for one reason: a Dock-icon click is an AppKit event, and
//  AppKit is the only place it can be answered (ADR-111).
//
//  Without `applicationShouldHandleReopen`, a reopen while the window is minimized or hidden
//  is handled by the default machinery, which treats "no *visible* window" as "no window" —
//  the case that produced a second window while the first sat in the Dock. The delegate
//  answers it through the same presenter every other surface uses, so the Dock behaves
//  exactly like the menu bar.
//
//  It also answers `applicationShouldTerminateAfterLastWindowClosed`, and that answer is not
//  cosmetic. Under the old `WindowGroup` scene, SwiftUI kept the process alive when the last
//  window closed, which is what let the menu bar — and a running Pomodoro — survive a Cmd-W.
//  A single-instance `Window` does not: closing it quits the app, even with a `MenuBarExtra`
//  inserted. That was measured, not assumed, by launching both builds and closing the window.
//  Returning `false` restores the documented behaviour exactly (§19/§30).
//
//  The delegate also owns the presenter and the navigation seam, because AppKit creates the
//  delegate before any scene exists and a reopen can arrive before the first window does.
//

import AppKit
import SwiftUI

@MainActor
final class TimeFrameAppDelegate: NSObject, NSApplicationDelegate {

    /// The AppKit half of the window policy. Owned here so it outlives every scene.
    let windowHost = AppKitMainWindowHost()

    /// The one main-window policy, shared by the app's scenes and by this delegate.
    private(set) lazy var windowPresenter: MainWindowPresenter = {
        let presenter = MainWindowPresenter(navigation: AppNavigation(), host: windowHost)
        windowHost.onMainWindowRegistered = { [weak presenter] in presenter?.mainWindowDidAppear() }
        return presenter
    }()

    /// The shared navigation seam the menu bar and the window both read.
    var navigation: AppNavigation { windowPresenter.navigation }

    /// Answers a Dock-icon click (and any other reopen).
    ///
    /// `hasVisibleWindows` is not consulted: it is false for a minimized window and false
    /// for a hidden application, and treating either as "there is no window" is what created
    /// duplicates. The presenter reads the real window state instead.
    ///
    /// Returning `false` says the reopen is fully handled — no window is created. `true` is
    /// returned only when there is genuinely no window and the presenter could not open one
    /// itself, letting AppKit run the default reopen for the single `Window` scene.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let action = windowPresenter.showMainWindow()
        switch action {
        case .reuseExisting, .coalesced:
            return false
        case .createWindow:
            // The presenter asked its host to open the window. If the host had an opener,
            // that has already happened and AppKit must not open another.
            return !windowHost.hasOpener
        }
    }

    /// Closing the main window must not quit Time Frame.
    ///
    /// The menu bar is a full control surface and a session can be running with no window on
    /// screen at all, so "last window closed" is not "the user is finished". This restores the
    /// behaviour the `WindowGroup` scene had implicitly; the single-instance `Window` scene
    /// terminates on close unless it is answered here. Quitting stays where it always was:
    /// Cmd-Q and the popover's Quit item, both `NSApplication.terminate`.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
