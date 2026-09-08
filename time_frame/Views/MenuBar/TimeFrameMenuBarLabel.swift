//
//  TimeFrameMenuBarLabel.swift
//  time_frame
//
//  The status-bar item itself: a compact icon + title (§8/§44). The title is derived
//  from the authoritative projection by `MenuBarStatusPresentation` — the remaining time
//  always comes from the engine's timeline, never from a counter owned here
//  (§10/§11/§47).
//
//  ## Why there is no TimelineView here (M26, ADR-101)
//  A `MenuBarExtra` label is not an ordinary view: SwiftUI renders it into an
//  `NSStatusBarButton`, and `MenuBarExtraHost` re-renders it *synchronously* when its
//  properties invalidate. A `TimelineView` re-arms its schedule during that render, so
//  the host immediately requested another update instead of one a second later — an
//  unbounded `updateButton → setImage: → invalidate → update` loop that pinned the main
//  thread at 100% CPU and froze the entire app for as long as a session was running.
//  Because the label switches to the live branch exactly when the engine starts running,
//  the app froze the moment a session was started — and, since the frozen app could
//  never stop that session, every later launch recovered it and froze again.
//
//  Removing the `TimelineView` is not enough on its own: the countdown still has to tick.
//  So the repaint is driven from *outside* the render pass, by the coordinator's existing
//  heartbeat (`displaySecond`, bumped at most once a second). Observation invalidates
//  this label when that value changes; because the change originates outside rendering it
//  cannot re-trigger itself, so there is no loop. No second timer is introduced — it is
//  the same single heartbeat that already drives the engine's reconciliation.
//

import SwiftUI

struct TimeFrameMenuBarLabel: View {
    let menuBar: MenuBarCoordinator

    var body: some View {
        // Reading `presentation` registers Observation on the engine, so the label
        // refreshes immediately on any state change (start/pause/skip/complete — §33).
        let state = menuBar.presentation

        // Reading the display heartbeat registers Observation on it too, so the label
        // also repaints ~1 Hz while running — the countdown ticks without a TimelineView.
        // Only needed when a countdown is actually shown for a live interval.
        if state.state == .running && menuBar.preferences.showCountdownInLabel {
            _ = menuBar.displaySecond
        }

        return content(state)
    }

    private func content(_ state: MenuBarPresentationState) -> some View {
        let title = MenuBarStatusPresentation.title(
            for: state, showCountdown: menuBar.preferences.showCountdownInLabel)
        return Label(title, systemImage: MenuBarStatusPresentation.symbolName(for: state))
            .accessibilityLabel(MenuBarStatusPresentation.accessibilityLabel(for: state))
    }
}
