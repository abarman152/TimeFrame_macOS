//
//  CloudSyncSettingsSection.swift
//  time_frame
//
//  The iCloud area of Settings: a master sync toggle plus a plain-language status
//  read-out projected from `CloudSyncCoordinator`. It observes a pure presentation
//  state — it is never a second persistence authority, and it never touches the
//  timer (Milestone 13 / ADR-060).
//

import SwiftUI

struct CloudSyncSettingsSection: View {
    @Bindable var cloudCoordinator: CloudSyncCoordinator

    private var state: CloudSyncPresentationState { cloudCoordinator.presentationState }

    var body: some View {
        Section("iCloud") {
            Toggle("iCloud Sync", isOn: Binding(
                get: { cloudCoordinator.syncEnabled },
                set: { cloudCoordinator.syncEnabled = $0 }
            ))
            .accessibilityIdentifier("cloud.settings.sync")

            // Status line — an icon paired with a word (never colour alone).
            LabeledContent("Status") {
                Label(state.statusText, systemImage: state.symbolName)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cloud.settings.status")
            }

            LabeledContent("iCloud Account", value: accountText)

            if let lastSyncedAt = state.lastSyncedAt {
                LabeledContent(
                    "Last Synced",
                    value: lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }

            Text(state.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            // SwiftData binds the CloudKit database when the store is created, so a
            // change to the toggle applies on the next launch. Say so plainly.
            Text("Changes to iCloud Sync take effect the next time you open Time Frame.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { cloudCoordinator.refresh() }
    }

    private var accountText: String {
        switch state.accountStatus {
        case .available:   return "Available"
        case .unavailable: return "Unavailable"
        case .unknown:     return "Checking…"
        }
    }
}
