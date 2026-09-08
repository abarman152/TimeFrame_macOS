//
//  AppKitMainWindowHost.swift
//  time_frame (Milestone 32)
//
//  The AppKit half of the single-main-window policy (ADR-111): it finds the one main
//  `NSWindow`, reports its live state, and performs the steps `MainWindowPresenter` asks
//  for. It contains no decision of its own.
//
//  Finding the window is deliberately *not* done by remembering that one was opened. The
//  window registers itself when its content view is installed and deregisters when it
//  actually closes, and the reference to it is weak — so a closed window leaves nothing
//  behind and the next request creates a fresh one (§13). A defensive scan of
//  `NSApplication.shared.windows` covers the window that exists before registration runs
//  (state restoration, or a create that has just landed); the menu bar's popover is an
//  `NSPanel` and can never be mistaken for it.
//

import AppKit
import SwiftUI

/// Locates and manipulates the app's one main `NSWindow`.
@MainActor
final class AppKitMainWindowHost: MainWindowHosting {

    /// The registered main window. Weak on purpose: the host must never keep a closed
    /// window alive, and a stale strong reference is exactly how "focus the window" turns
    /// into "focus a window the user closed".
    private weak var registeredWindow: NSWindow?

    /// SwiftUI's `openWindow(id:)`, captured from the view tree the first time the main
    /// window exists. `OpenWindowAction` stays valid for the app's lifetime, so this keeps
    /// working after the user closes the window — which is precisely when it is needed.
    private var opener: (() -> Void)?

    /// Called when a window has registered itself, so the presenter can stop coalescing.
    var onMainWindowRegistered: (() -> Void)?

    // MARK: Registration (from the window's own view tree)

    /// Registers the window hosting the app's root view, and arranges for it to be forgotten
    /// when it closes.
    func register(_ window: NSWindow) {
        guard registeredWindow !== window else { return }
        registeredWindow = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.registeredWindow === window else { return }
                self.registeredWindow = nil
            }
        }
        onMainWindowRegistered?()
    }

    /// Whether SwiftUI's window-opening capability has been captured yet. The app delegate
    /// reads it to decide whether AppKit still has to run its own reopen.
    var hasOpener: Bool { opener != nil }

    /// Records SwiftUI's window-opening capability. Idempotent; the first registration wins,
    /// so there is one opener rather than one per view that happens to mount.
    func registerOpener(_ opener: @escaping () -> Void) {
        guard self.opener == nil else { return }
        self.opener = opener
    }

    // MARK: MainWindowHosting

    var applicationIsHidden: Bool { NSApplication.shared.isHidden }

    func mainWindowSnapshot() -> MainWindowSnapshot? {
        guard let window = locateMainWindow() else { return nil }
        return MainWindowSnapshot(isMiniaturized: window.isMiniaturized, isVisible: window.isVisible)
    }

    func unhideApplication() {
        NSApplication.shared.unhide(nil)
    }

    func deminiaturizeMainWindow() {
        locateMainWindow()?.deminiaturize(nil)
    }

    func focusMainWindow() {
        // Native activation only — no artificial flash, no custom highlight (§16). The
        // window takes on the ordinary macOS key-window appearance, and VoiceOver announces
        // the focus change itself (§23).
        NSApplication.shared.activate(ignoringOtherApps: true)
        locateMainWindow()?.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func createMainWindow() -> Bool {
        guard let opener else { return false }
        opener()
        return true
    }

    // MARK: Locating

    /// The one main window, or `nil` when the app currently has none.
    private func locateMainWindow() -> NSWindow? {
        if let registeredWindow, isUsable(registeredWindow) { return registeredWindow }
        // Not registered (yet). Fall back to the live window list rather than to a
        // remembered answer, so the state is always the real one.
        if let scanned = scanForMainWindow() {
            registeredWindow = scanned
            return scanned
        }
        return nil
    }

    /// A window counts only while it is genuinely part of the UI. A window SwiftUI has torn
    /// down is neither visible nor minimized, and must not be "focused".
    private func isUsable(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized
    }

    /// Finds the app's main document-style window among AppKit's live windows. The
    /// `MenuBarExtra` popover is an `NSPanel`, and SwiftUI's off-screen helper windows are
    /// neither visible nor minimized, so neither can match.
    private func scanForMainWindow() -> NSWindow? {
        let candidates = NSApplication.shared.windows.filter { window in
            guard !(window is NSPanel), window.canBecomeMain else { return false }
            return isUsable(window)
        }
        // Prefer the window SwiftUI identified with the main scene's id; otherwise the first
        // ordinary main-capable window is the only thing this app can have.
        if let identified = candidates.first(where: { window in
            guard let raw = window.identifier?.rawValue else { return false }
            return raw == MainWindow.id || raw.hasPrefix("\(MainWindow.id)-")
        }) {
            return identified
        }
        return candidates.first
    }
}
