//
//  MainWindowPresentation.swift
//  time_frame (Milestone 32)
//
//  The SwiftUI glue between a view that wants Time Frame's window and the one presenter
//  that decides what that means (ADR-111).
//
//  A view cannot open a scene without SwiftUI's `openWindow`, and `openWindow` is only
//  reachable from a view's environment. Rather than let every surface hold that capability
//  — which is how four separate call sites each grew their own `NSApp.activate(...)` +
//  `openWindow(id:)` pair, and how duplicates appeared — the capability is captured *once*
//  per scene here, handed to the presenter, and re-published as a single environment action.
//
//  A call site therefore reads `showMainWindow(.settings)` and knows nothing about windows.
//  There is one policy, in one place, and no view can bypass it.
//

import AppKit
import SwiftUI

/// The one action a view calls to bring Time Frame's window forward.
struct ShowMainWindowAction {
    fileprivate let handler: (@MainActor (AppSection?) -> Void)?

    /// Brings the main window forward, optionally switching it to `section` first. Passing
    /// `nil` leaves the user's current screen exactly as it is (§17).
    @MainActor
    func callAsFunction(_ section: AppSection? = nil) {
        handler?(section)
    }
}

extension EnvironmentValues {
    /// Brings the app's one main window forward. Defaults to a no-op so a preview or an
    /// isolated view never has to know about window management.
    @Entry var showMainWindow = ShowMainWindowAction(handler: nil)
}

extension View {
    /// Wires a scene's view tree to the one main-window presenter: publishes
    /// `\.showMainWindow` and lends the presenter SwiftUI's window-opening capability.
    ///
    /// Applied to both scenes, so the menu bar can open the window even when it is closed —
    /// `OpenWindowAction` stays valid for the app's lifetime once captured.
    func mainWindowPresentation(_ presenter: MainWindowPresenter,
                                host: AppKitMainWindowHost) -> some View {
        modifier(MainWindowPresentationModifier(presenter: presenter, host: host))
    }

    /// Registers the window hosting this view as the app's main window. Applied once, to
    /// the root of the main scene.
    func registersAsMainWindow(_ host: AppKitMainWindowHost) -> some View {
        background(MainWindowAccessor(host: host).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Publishes the `showMainWindow` action and captures `openWindow` for the presenter.
private struct MainWindowPresentationModifier: ViewModifier {
    let presenter: MainWindowPresenter
    let host: AppKitMainWindowHost

    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .environment(\.showMainWindow, ShowMainWindowAction { section in
                presenter.showMainWindow(section)
            })
            .onAppear {
                host.registerOpener { openWindow(id: MainWindow.id) }
            }
    }
}

/// A zero-sized bridge that tells the host which `NSWindow` is the main one. Registration
/// comes from the window itself rather than from a flag set when one was opened, so it is
/// correct after a close, a reopen, or a scene SwiftUI rebuilt (§6/§13).
private struct MainWindowAccessor: NSViewRepresentable {
    let host: AppKitMainWindowHost

    func makeNSView(context: Context) -> NSView {
        let view = MainWindowRegisteringView()
        view.host = host
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MainWindowRegisteringView)?.host = host
    }
}

/// Registers its window with the host as soon as it has one.
private final class MainWindowRegisteringView: NSView {
    var host: AppKitMainWindowHost?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        host?.register(window)
    }
}
