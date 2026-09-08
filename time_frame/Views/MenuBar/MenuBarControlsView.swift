//
//  MenuBarControlsView.swift
//  time_frame
//
//  The popover's transport controls. Every control routes through the shared
//  `MenuBarCoordinator` → `SessionCoordinator` — never the engine directly (§20/§47).
//
//  ## Milestone 28
//  This view is now transport-only. The four secondary navigation rows (Open Time Frame /
//  Settings / History / Quit) moved behind the header's gear menu (`MenuBarGearMenu`), so the
//  popover's primary content is the timer, its controls, and Quick Start (ADR-102). No action
//  was removed and no routing changed — only where the secondary actions live.
//
//  The running and paused states now offer the same four controls (Pause/Resume, Skip,
//  Restart, Stop), so the control row never re-flows into a different shape as a session moves
//  between running and paused: only the first button's verb and glyph change.
//

import SwiftUI

struct MenuBarControlsView: View {
    let menuBar: MenuBarCoordinator

    var body: some View {
        transport(for: menuBar.presentation)
    }

    // MARK: Transport controls (situation-specific)

    // The transport buttons share one GlassEffectContainer so their Liquid Glass samples
    // consistently within the popover (§30/§66). The panel itself keeps the system
    // MenuBarExtra `.window` background — no extra nested glass surface.
    @ViewBuilder
    private func transport(for state: MenuBarPresentationState) -> some View {
        switch state.situation {
        case .running:
            GlassEffectContainer(spacing: TFSpacing.xs) {
                HStack(spacing: TFSpacing.xs) {
                    control("Pause", "pause.fill", label: "Pause Timer",
                            id: "timeFrame.menuBar.pause", prominent: true) { menuBar.pause() }
                    skipControl
                    restartControl
                    stopControl
                }
            }
        case .paused:
            GlassEffectContainer(spacing: TFSpacing.xs) {
                HStack(spacing: TFSpacing.xs) {
                    control("Resume", "play.fill", label: "Resume Timer",
                            id: "timeFrame.menuBar.resume", prominent: true) { menuBar.resume() }
                    skipControl
                    restartControl
                    stopControl
                }
            }
        case .empty, .interrupted, .completed:
            EmptyView()
        }
    }

    private var skipControl: some View {
        control("Skip", "forward.end.fill", label: "Skip Interval",
                id: "timeFrame.menuBar.skip", prominent: false) { menuBar.skip() }
    }

    private var restartControl: some View {
        control("Restart", "arrow.counterclockwise", label: "Restart Timer",
                id: "timeFrame.menuBar.restart", prominent: false) { menuBar.restart() }
    }

    private var stopControl: some View {
        control("Stop", "stop.fill", label: "Stop Timer",
                id: "timeFrame.menuBar.stop", prominent: false) { menuBar.stop() }
    }

    /// One compact transport button: glyph above a word. The word is always present, so the
    /// action is never carried by an icon alone (a11y §48), and the explicit accessibility
    /// label spells out what the verb applies to ("Skip Interval", not just "Skip").
    @ViewBuilder
    private func control(
        _ title: String,
        _ symbol: String,
        label: String,
        id: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) { controlLabel(title, symbol) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
                .help(label)
        } else {
            Button(action: action) { controlLabel(title, symbol) }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
                .help(label)
        }
    }

    private func controlLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }
}
