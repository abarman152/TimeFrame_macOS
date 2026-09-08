//
//  MenuBarSessionSummaryView.swift
//  time_frame
//
//  The header of the popover for an active or just-finished session: the task name and
//  the session's *frozen* configuration name (§14). The configuration name comes from the
//  session's own snapshot, so editing or deleting the source configuration/template/plan
//  never changes what the menu bar shows for the running session (§53/§54).
//

import SwiftUI

struct MenuBarSessionSummaryView: View {
    let taskName: String?
    let configurationName: String?

    private var title: String {
        let name = taskName ?? ""
        return name.isEmpty ? "Focus session" : name
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let configurationName, !configurationName.isEmpty {
                Text(configurationName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
