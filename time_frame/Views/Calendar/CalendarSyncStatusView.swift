//
//  CalendarSyncStatusView.swift
//  time_frame
//
//  A small, reusable status chip for the Calendar integration. Deliberately quiet:
//  it never interrupts the timer, and state is always carried by the *label*, not
//  by colour alone (a11y — §76). Used on the Timer screen and anywhere a compact
//  sync indicator helps (§52).
//

import SwiftUI

struct CalendarSyncStatusView: View {
    let status: CalendarSyncStatus

    var body: some View {
        if let presentation {
            Label {
                Text(presentation.label)
            } icon: {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Calendar: \(presentation.label)")
            .accessibilityIdentifier("calendar.syncStatus")
        }
    }

    /// The presentation for a status, or nil when nothing should be shown (the
    /// integration is off).
    private var presentation: (label: String, symbol: String, tint: Color)? {
        switch status {
        case .notConfigured:
            return nil
        case .idle:
            return ("Calendar on", "calendar", .secondary)
        case .syncing:
            return ("Syncing…", "arrow.triangle.2.circlepath", .secondary)
        case .synced:
            return ("Added to Calendar", "calendar.badge.checkmark", .green)
        case .permissionDenied:
            return ("Calendar access needed", "calendar.badge.exclamationmark", .orange)
        case let .unavailable(message):
            return (message, "calendar.badge.exclamationmark", .orange)
        case let .error(message):
            return (message, "exclamationmark.triangle.fill", .yellow)
        }
    }
}
