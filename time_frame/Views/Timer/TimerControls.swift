//
//  TimerControls.swift
//  time_frame
//
//  The transport controls for an active run. Only the controls valid for the
//  current engine state are shown, and each carries a scoped keyboard shortcut.
//  These controls are only rendered while running/paused (never alongside the
//  task text field), so the bare-key shortcuts can't interfere with typing.
//

import SwiftUI

struct TimerControls: View {
    let coordinator: SessionCoordinator
    /// Surfaces a user-facing message if a control fails.
    let reportError: (String) -> Void

    private var engine: TimerEngine { coordinator.engine }

    var body: some View {
        // The transport is the timer's floating Liquid Glass control region (§15/§34).
        // Grouping the glass buttons in a single container gives them a shared sampling
        // region so the glass renders consistently (glass cannot sample other glass).
        GlassEffectContainer(spacing: TFSpacing.m) {
            VStack(spacing: TFSpacing.m) {
                // Primary row: one dominant action (Pause/Resume) plus Stop (§36).
                HStack(spacing: TFSpacing.m) {
                    switch engine.state {
                    case .running:
                        Button {
                            run { try coordinator.pause() }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.space, modifiers: [])
                        .help("Pause (Space)")
                        .accessibilityIdentifier("timeFrame.timer.pause")

                    case .paused:
                        Button {
                            run { try coordinator.resume() }
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.space, modifiers: [])
                        .help("Resume (Space)")
                        .accessibilityIdentifier("timeFrame.timer.resume")

                    default:
                        EmptyView()
                    }

                    Button {
                        run { try coordinator.stop() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction) // Escape
                    .help("Stop (Escape)")
                    .accessibilityIdentifier("timeFrame.timer.stop")
                }
                .controlSize(.large)

                // Secondary row: quieter glass actions.
                HStack(spacing: TFSpacing.m) {
                    Button {
                        run { try coordinator.restart() }
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                    .keyboardShortcut("r", modifiers: [])
                    .help("Restart the current interval (R)")
                    .accessibilityIdentifier("timeFrame.timer.restart")

                    Button {
                        run { try coordinator.skip() }
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Skip to the next interval (→)")
                    .accessibilityIdentifier("timeFrame.timer.skip")
                }
                .controlSize(.regular)
                .buttonStyle(.glass)
            }
        }
    }

    /// Runs a throwing control action and reports any failure to the parent.
    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            reportError((error as? LocalizedError)?.errorDescription ?? "Something went wrong.")
        }
    }
}
