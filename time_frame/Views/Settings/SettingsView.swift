//
//  SettingsView.swift
//  time_frame
//
//  A small settings area: choose the default configuration and review the
//  keyboard shortcuts. Deliberately minimal for this milestone.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    let coordinator: SessionCoordinator
    let calendarCoordinator: CalendarCoordinator
    let notificationCoordinator: NotificationCoordinator
    let menuBarCoordinator: MenuBarCoordinator
    let cloudCoordinator: CloudSyncCoordinator

    /// The "Open at Login" adapter, created by the app. Its state is read back from macOS,
    /// so this screen never shows a login-item setting the system does not actually hold
    /// (Milestone 32, ADR-112).
    let loginItemCoordinator: LoginItemCoordinator

    @Query(sort: \PomodoroConfiguration.createdAt, order: .reverse)
    private var configurations: [PomodoroConfiguration]

    @State private var errorMessage: String?

    /// The user-facing version string for the About section, read from the bundle so it always
    /// tracks the real `CFBundleShortVersionString` (never a stale hard-coded milestone).
    private static var appVersionText: String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return "Version \(version)"
    }

    private var defaultConfigurationID: UUID? {
        configurations.first { $0.isDefault }?.id
    }

    var body: some View {
        Form {
            LoginItemSettingsSection(loginItem: loginItemCoordinator)

            Section("Default Configuration") {
                if configurations.isEmpty {
                    Text("No configurations yet. Create one in the Configurations tab.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Default", selection: Binding(
                        get: { defaultConfigurationID },
                        set: { newID in
                            if let config = configurations.first(where: { $0.id == newID }) {
                                setDefault(config)
                            }
                        }
                    )) {
                        ForEach(configurations) { config in
                            Text(config.name).tag(config.id as UUID?)
                        }
                    }
                    Text("New sessions start from this configuration by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CalendarSettingsSection(calendarCoordinator: calendarCoordinator)

            NotificationSettingsSection(notificationCoordinator: notificationCoordinator,
                                        coordinator: coordinator)

            MenuBarSettingsSection(menuBarCoordinator: menuBarCoordinator)

            CloudSyncSettingsSection(cloudCoordinator: cloudCoordinator)

            Section("Keyboard Shortcuts") {
                shortcut("Start session", "⌘↩")
                shortcut("Pause / Resume", "Space")
                shortcut("Stop session", "Esc")
                shortcut("Restart interval", "R")
                shortcut("Skip interval", "→")
                shortcut("New item on this screen", "⌘N")
                shortcut("Edit the open template or plan", "⌘E")
            }

            Section("About") {
                LabeledContent("Time Frame", value: Self.appVersionText)
                Text("A native macOS Pomodoro timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task {
            calendarCoordinator.refreshAuthorization()
            if calendarCoordinator.authorizationStatus.isSufficient {
                await calendarCoordinator.loadCalendars()
            }
            await notificationCoordinator.refreshAuthorization()
            // The system is the source of truth for the login item, so re-read it whenever
            // this screen appears — the user may have changed it in System Settings.
            loginItemCoordinator.refresh()
        }
        .alert("Settings Error",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func shortcut(_ label: String, _ keys: String) -> some View {
        LabeledContent(label) {
            Text(keys)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func setDefault(_ config: PomodoroConfiguration) {
        do {
            try coordinator.configurations.setDefault(config)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't set the default."
        }
    }
}
