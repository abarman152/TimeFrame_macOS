//
//  AppNavigation.swift
//  time_frame
//
//  A tiny shared navigation seam so the menu bar can steer the existing main window
//  instead of building parallel screens (§22/§23/§24). The menu bar sets a requested
//  section; `ContentView` observes it, applies it to its sidebar selection, and clears
//  it. This reuses the one WindowGroup and the one set of screens — there is no second
//  Settings window and no duplicate History view.
//

import Foundation
import Observation

/// Identifiers for the app's scenes, so the menu bar can bring the *existing* main
/// window forward via `openWindow(id:)` rather than spawning a parallel one (§22/§67).
enum MainWindow {
    static let id = "main"
}

/// A one-shot navigation request from the menu bar (or anywhere) to the main window.
@MainActor
@Observable
final class AppNavigation {
    /// The section the main window should switch to, consumed and cleared by the window.
    var requestedSection: AppSection?

    /// Requests that the main window show the given section.
    func request(_ section: AppSection) {
        requestedSection = section
    }
}
