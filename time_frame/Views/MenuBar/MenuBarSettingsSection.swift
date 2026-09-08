//
//  MenuBarSettingsSection.swift
//  time_frame
//
//  The Menu Bar area of Settings: a master toggle and, when shown, a countdown-in-title
//  toggle (§65/§66). Integrated into the existing `SettingsView` — no separate settings
//  window (§66). The preference only affects whether/what the menu bar shows; it can
//  never change timer, calendar, or notification behaviour (§26/§37/§38).
//

import SwiftUI

struct MenuBarSettingsSection: View {
    @Bindable var menuBarCoordinator: MenuBarCoordinator

    private var preferences: MenuBarPreferencesStore { menuBarCoordinator.preferences }

    var body: some View {
        Section("Menu Bar") {
            Toggle("Show in Menu Bar", isOn: Binding(
                get: { preferences.showInMenuBar },
                set: { preferences.showInMenuBar = $0 }
            ))
            .accessibilityIdentifier("menubar.settings.show")

            if preferences.showInMenuBar {
                Toggle("Show countdown in menu bar", isOn: Binding(
                    get: { preferences.showCountdownInLabel },
                    set: { preferences.showCountdownInLabel = $0 }
                ))
                .accessibilityIdentifier("menubar.settings.countdown")
            }

            Text("Control your timer from the menu bar, even when the main window is closed. Your timer always works whether the menu bar is shown or not.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
