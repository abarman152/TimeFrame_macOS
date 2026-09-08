//
//  TimeFrameMenuBarView.swift
//  time_frame
//
//  The popover shown from the status item (`MenuBarExtra` `.window` style). A compact,
//  native quick-control surface — not a second window (§12/§45). It reads the one
//  authoritative projection and lays out the matching header + controls; it holds no
//  timer state and drives no countdown of its own (§10/§30/§46).
//
//  ## Milestone 28 layout (ADR-102)
//  Top to bottom, the popover is now ordered by importance:
//
//    • a header: the status identity, with the gear in the top-right corner. Open Time Frame,
//      Settings, History and Quit live behind that gear instead of taking four permanent rows.
//    • when a session is live: the countdown block, then the transport controls.
//    • Quick Start: the user's pinned Templates and Plans.
//    • when nothing is running: the fallback "Start Timer" action, which opens the existing
//      setup screen — it never becomes a second start path.
//
//  ## Layout rule (Milestone 29, ADR-107)
//  **No part of the popover scrolls.** Milestone 28 bounded the pinned list inside a scroll
//  view; ADR-107 removed scrolling entirely, because a glance-and-go surface that hides its
//  own contents behind a scroll gesture is slower than the app it is shortcutting. The pinned
//  list is capped at `MenuBarQuickStartView.visibleLimit` rows and any remainder is offered by
//  a compact "More" menu, so however many items are pinned, the countdown and the transport
//  controls can never be pushed out of the popover.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct TimeFrameMenuBarView: View {
    let menuBar: MenuBarCoordinator
    let quickStart: QuickStartCoordinator

    var body: some View {
        // One read of the projection drives the situation switch; the countdown block
        // re-derives its own value via a TimelineView while running.
        let state = menuBar.presentation
        VStack(spacing: TFSpacing.m) {
            header(for: state)

            if state.hasActiveSession {
                MenuBarTimerView(menuBar: menuBar)
                MenuBarControlsView(menuBar: menuBar)
                Divider()
                MenuBarQuickStartView(quickStart: quickStart)
            } else {
                Divider()
                MenuBarQuickStartView(quickStart: quickStart)
                startButton(for: state)
            }
        }
        .padding(TFSpacing.l)
        .frame(width: 288)
        .accessibilityIdentifier("timeFrame.menuBar")
    }

    // MARK: Header (identity + gear)

    /// The identity block, with the gear pinned to the top-right corner. The gear is drawn in
    /// an overlay so it never shifts the centred identity content.
    private func header(for state: MenuBarPresentationState) -> some View {
        identity(for: state)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                MenuBarGearMenu()
            }
    }

    @ViewBuilder
    private func identity(for state: MenuBarPresentationState) -> some View {
        switch state.situation {
        case .running, .paused:
            MenuBarSessionSummaryView(taskName: state.taskName,
                                      configurationName: state.configurationName)
                // Keep the summary clear of the gear's corner.
                .padding(.trailing, TFSpacing.xl)
        case .completed, .empty, .interrupted:
            MenuBarEmptyStateView(state: state)
        }
    }

    // MARK: Fallback start

    /// The default action when nothing is pinned or the user wants different values: it
    /// clears any finished run and brings the main window's existing `SessionSetupView`
    /// forward (§13/§21). It is not a second start flow.
    private func startButton(for state: MenuBarPresentationState) -> some View {
        MenuBarStartButton(
            title: state.situation == .completed ? "Start New Session" : "Start Timer",
            menuBar: menuBar
        )
    }
}

/// The popover's fallback primary action. It clears any finished run and asks the one
/// presenter for the main window on the Timer screen — it opens nothing itself (ADR-111).
private struct MenuBarStartButton: View {
    let title: String
    let menuBar: MenuBarCoordinator

    @Environment(\.showMainWindow) private var showMainWindow

    var body: some View {
        Button {
            menuBar.prepareForNewSession()
            showMainWindow(.timer)
        } label: {
            Label(title, systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .accessibilityLabel(title)
        .accessibilityHint("Opens Time Frame to choose what to focus on")
        .accessibilityIdentifier("timeFrame.menuBar.start")
    }
}
