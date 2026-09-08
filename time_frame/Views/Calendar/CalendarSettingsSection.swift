//
//  CalendarSettingsSection.swift
//  time_frame
//
//  The Calendar area of Settings: a master toggle, the permission flow, and — once
//  authorized — the calendar, event style, and creation-trigger choices. Native and
//  minimal (§48). Permission is requested only in context, never on launch (§47).
//

import SwiftUI

struct CalendarSettingsSection: View {
    @Bindable var calendarCoordinator: CalendarCoordinator

    private var preferences: CalendarPreferencesStore { calendarCoordinator.preferences }
    private var status: CalendarAuthorizationStatus { calendarCoordinator.authorizationStatus }

    var body: some View {
        Section("Calendar") {
            Toggle("Calendar Integration", isOn: enabledBinding)
                .accessibilityIdentifier("calendar.settings.toggle")
            Text("Turn your focus plans and sessions into events in Apple Calendar. Your timer always works, even if Calendar is off or unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if preferences.isEnabled {
            switch status {
            case .fullAccess:
                authorizedSections
            case .notDetermined:
                permissionRequestSection
            case .denied, .writeOnly:
                deniedSection
            case .restricted:
                restrictedSection
            }
        }
    }

    // MARK: Authorized

    @ViewBuilder
    private var authorizedSections: some View {
        Section("Default Calendar") {
            if calendarCoordinator.availableCalendars.isEmpty {
                Text("No writable calendars were found.")
                    .foregroundStyle(.secondary)
            } else {
                CalendarPickerView(
                    calendars: calendarCoordinator.availableCalendars,
                    selection: calendarBinding
                )
            }
            Text("New events are added to this calendar. Time Frame only ever writes to the calendar you choose.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Events") {
            Picker("Event Style", selection: styleBinding) {
                ForEach(CalendarEventStyle.allCases) { style in
                    Text(style.displayLabel).tag(style)
                }
            }
            .accessibilityIdentifier("calendar.settings.eventStyle")

            Picker("Create Events When", selection: triggerBinding) {
                ForEach(CalendarCreationTrigger.allCases) { trigger in
                    Text(trigger.displayLabel).tag(trigger)
                }
            }
            .accessibilityIdentifier("calendar.settings.trigger")

            Text("A live session always uses one event so pause and stop stay accurate; the per-interval style applies when you add a plan to your calendar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Button("Manage Calendar Access") { calendarCoordinator.openSystemSettings() }
                .accessibilityIdentifier("calendar.settings.manageAccess")
        }
    }

    // MARK: Permission states

    private var permissionRequestSection: some View {
        Section {
            Text("Calendar access is required to create and update Time Frame events.")
                .font(.callout)
            Button("Allow Calendar Access") {
                Task { await calendarCoordinator.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("calendar.settings.allowAccess")
        }
    }

    private var deniedSection: some View {
        Section {
            Label {
                Text(status == .writeOnly
                     ? "Time Frame has write-only calendar access. Full access is needed to update and manage events."
                     : "Calendar access is turned off for Time Frame.")
            } icon: {
                Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
            }
            .font(.callout)
            Button("Open System Settings") { calendarCoordinator.openSystemSettings() }
                .accessibilityIdentifier("calendar.settings.openSystemSettings")
        }
    }

    private var restrictedSection: some View {
        Section {
            Label {
                Text("Calendar access is restricted on this Mac and can't be enabled here.")
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.isEnabled },
            set: { turnOn in
                preferences.isEnabled = turnOn
                if turnOn {
                    calendarCoordinator.refreshAuthorization()
                    Task {
                        if calendarCoordinator.authorizationStatus.canRequest {
                            await calendarCoordinator.requestAccess()
                        } else if calendarCoordinator.authorizationStatus.isSufficient {
                            await calendarCoordinator.loadCalendars()
                        }
                    }
                }
            }
        )
    }

    private var calendarBinding: Binding<String?> {
        Binding(
            get: { preferences.defaultCalendarIdentifier },
            set: { preferences.defaultCalendarIdentifier = $0 }
        )
    }

    private var styleBinding: Binding<CalendarEventStyle> {
        Binding(get: { preferences.eventStyle }, set: { preferences.eventStyle = $0 })
    }

    private var triggerBinding: Binding<CalendarCreationTrigger> {
        Binding(get: { preferences.creationTrigger }, set: { preferences.creationTrigger = $0 })
    }
}
