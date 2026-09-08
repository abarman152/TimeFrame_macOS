//
//  MenuBarOpenSectionButton.swift
//  time_frame (Milestone 28)
//
//  A small link-style button that brings the one main window forward on a given section.
//  Shared by the Quick Start empty state (which points at Templates and Plans) so those
//  destinations use the exact same seam the gear menu uses — one window, one set of screens,
//  no parallel navigation.
//
//  Milestone 32: it asks the one `MainWindowPresenter` through `showMainWindow`, so it can
//  never be the path that opens a second window (ADR-111).
//

import SwiftUI

struct MenuBarOpenSectionButton: View {
    let title: String
    let section: AppSection

    @Environment(\.showMainWindow) private var showMainWindow

    var body: some View {
        Button(title) {
            showMainWindow(section)
        }
        .buttonStyle(.link)
        .font(.caption)
        .accessibilityLabel("Open \(title)")
        .accessibilityIdentifier("timeFrame.menuBar.open.\(section.rawValue)")
    }
}
