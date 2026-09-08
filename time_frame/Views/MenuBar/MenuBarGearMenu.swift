//
//  MenuBarGearMenu.swift
//  time_frame (Milestone 28)
//
//  The popover's secondary-action menu: the gear in the top-right corner (ADR-102).
//
//  Open Time Frame / Settings / History / Quit used to occupy four permanent rows at the
//  bottom of the popover, pushing the timer and Quick Start down. They are secondary actions,
//  so they now live behind one native `Menu` and the primary content gets the space back.
//
//  These are the *same* actions as before, but they no longer open a window themselves.
//  Milestone 32 moved that decision into the one `MainWindowPresenter` behind the
//  `showMainWindow` environment action (ADR-111): the gear asks for the window and the
//  section, and the presenter focuses the existing window — or creates the single one when
//  there is none. There is still no second Settings window and no duplicate History screen,
//  and now no duplicate main window either. Quit is the standard `NSApplication.terminate`,
//  never a manual process kill.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuBarGearMenu: View {
    @Environment(\.showMainWindow) private var showMainWindow

    var body: some View {
        Menu {
            Button { showMainWindow() } label: {
                Label("Open Time Frame", systemImage: "macwindow")
            }
            .accessibilityIdentifier("timeFrame.menuBar.openApp")

            Button { showMainWindow(.settings) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("timeFrame.menuBar.settings")

            Button { showMainWindow(.history) } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("timeFrame.menuBar.history")

            Divider()

            Button { quit() } label: {
                Label("Quit Time Frame", systemImage: "power")
            }
            .accessibilityIdentifier("timeFrame.menuBar.quit")
        } label: {
            // Subtle but discoverable: a secondary-tinted gear in its own tappable circle.
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings and more")
        .accessibilityLabel("Settings and More")
        .accessibilityHint("Open Time Frame, Settings, History, or quit the app")
        .accessibilityIdentifier("timeFrame.menuBar.gear")
    }

    // MARK: Actions (one window, one set of screens)

    /// Standard macOS termination — never a manual process kill.
    private func quit() {
        #if canImport(AppKit)
        NSApplication.shared.terminate(nil)
        #endif
    }
}
