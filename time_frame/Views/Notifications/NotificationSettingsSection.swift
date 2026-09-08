//
//  NotificationSettingsSection.swift
//  time_frame
//
//  The Notifications area of Settings: a master toggle, the permission flow, and — once
//  authorized — per-category toggles plus sound and actions. Native and compact (§66).
//  Permission is requested only in context, never on launch (§67/§70).
//

import SwiftUI

struct NotificationSettingsSection: View {
    @Bindable var notificationCoordinator: NotificationCoordinator
    /// The session coordinator, read only to (re)schedule the active session when the
    /// user turns notifications on mid-run. The timer never depends on this view.
    let coordinator: SessionCoordinator

    private var preferences: NotificationPreferencesStore { notificationCoordinator.preferences }
    private var status: NotificationAuthorizationStatus { notificationCoordinator.authorizationStatus }

    var body: some View {
        Section("Notifications") {
            Toggle("Notifications", isOn: enabledBinding)
                .accessibilityIdentifier("notifications.settings.toggle")
            Text("Get a heads-up when a focus session or break begins. Your timer always works, even if notifications are off or unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if preferences.isEnabled {
            switch status {
            case .authorized, .provisional:
                authorizedSections
            case .notDetermined:
                permissionRequestSection
            case .denied:
                deniedSection
            }
        }
    }

    // MARK: Authorized

    @ViewBuilder
    private var authorizedSections: some View {
        Section("Notify Me When") {
            Toggle("Focus sessions start", isOn: boolBinding(\.focusStarted, set: { preferences.focusStarted = $0 }))
                .accessibilityIdentifier("notifications.settings.focus")
            Toggle("Short breaks start", isOn: boolBinding(\.shortBreakStarted, set: { preferences.shortBreakStarted = $0 }))
                .accessibilityIdentifier("notifications.settings.shortBreak")
            Toggle("Long breaks start", isOn: boolBinding(\.longBreakStarted, set: { preferences.longBreakStarted = $0 }))
                .accessibilityIdentifier("notifications.settings.longBreak")
            Toggle("Session completes", isOn: boolBinding(\.sessionCompleted, set: { preferences.sessionCompleted = $0 }))
                .accessibilityIdentifier("notifications.settings.completed")
        }

        Section("Style") {
            Toggle("Sound", isOn: boolBinding(\.soundEnabled, set: { preferences.soundEnabled = $0 }))
                .accessibilityIdentifier("notifications.settings.sound")
            Toggle("Action buttons", isOn: boolBinding(\.actionsEnabled, set: { preferences.actionsEnabled = $0 }))
                .accessibilityIdentifier("notifications.settings.actions")
            Text("Action buttons let you pause or skip from the notification itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Button("Manage Notification Permissions") { notificationCoordinator.openSystemSettings() }
                .accessibilityIdentifier("notifications.settings.manageAccess")
        }
    }

    // MARK: Permission states

    private var permissionRequestSection: some View {
        Section {
            Text("Allow Time Frame to notify you when your focus sessions and breaks change.")
                .font(.callout)
            Button("Enable Notifications") {
                Task {
                    await notificationCoordinator.requestAuthorization()
                    notificationCoordinator.reconcileActiveSession(
                        coordinator.currentLifecycleContext(),
                        isRunning: coordinator.engine.state == .running)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("notifications.settings.enable")
        }
    }

    private var deniedSection: some View {
        Section {
            Label {
                Text("Notifications are turned off for Time Frame in macOS.")
            } icon: {
                Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            Button("Open System Settings") { notificationCoordinator.openSystemSettings() }
                .accessibilityIdentifier("notifications.settings.openSystemSettings")
        }
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.isEnabled },
            set: { turnOn in
                notificationCoordinator.setEnabled(
                    turnOn,
                    activeSession: coordinator.currentLifecycleContext(),
                    isRunning: coordinator.engine.state == .running)
            }
        )
    }

    /// A binding over a preference flag that persists through the store.
    private func boolBinding(_ get: KeyPath<NotificationPreferences, Bool>, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { preferences.settings[keyPath: get] }, set: { set($0) })
    }
}
