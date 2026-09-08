//
//  TimerView.swift
//  time_frame
//
//  The primary screen. It renders whatever the shared engine/coordinator say is
//  true — setup when idle, the live run when running/paused, completion when
//  finished — and surfaces relaunch recovery (restored or interrupted). It owns
//  no timer state of its own.
//

import SwiftUI

struct TimerView: View {
    let coordinator: SessionCoordinator
    let calendarCoordinator: CalendarCoordinator
    /// The shared Quick Start projection, forwarded to the setup screen's Quick Start
    /// control. The same adapter the menu bar uses — never a second list (ADR-104).
    let quickStart: QuickStartCoordinator
    /// Setup values queued by a Task Template's "Start", consumed by the setup
    /// screen. A binding so the setup screen can clear it once applied.
    @Binding var pendingSetup: SessionSetupPrefill?
    let openConfigurations: () -> Void

    @State private var controlError: String?

    private var engine: TimerEngine { coordinator.engine }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Timer Error",
                   isPresented: Binding(get: { controlError != nil },
                                        set: { if !$0 { controlError = nil } })) {
                Button("OK", role: .cancel) { controlError = nil }
            } message: {
                Text(controlError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch engine.state {
        case .running, .paused:
            activeSession
        case .completed:
            CompletionView(coordinator: coordinator)
        case .idle, .cancelled:
            idleContent
        }
    }

    // MARK: Idle / setup (with interrupted recovery notice)

    @ViewBuilder
    private var idleContent: some View {
        if coordinator.recoveryOutcome == .interrupted {
            VStack(spacing: 0) {
                interruptedBanner
                SessionSetupView(coordinator: coordinator,
                                 quickStart: quickStart,
                                 pendingSetup: $pendingSetup,
                                 openConfigurations: openConfigurations)
            }
        } else {
            SessionSetupView(coordinator: coordinator,
                             quickStart: quickStart,
                             pendingSetup: $pendingSetup,
                             openConfigurations: openConfigurations)
        }
    }

    private var interruptedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TFPalette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Previous session couldn't be safely restored")
                    .font(.callout.weight(.semibold))
                if let name = coordinator.interruptedSession?.taskName, !name.isEmpty {
                    Text(name).font(.callout).foregroundStyle(.secondary)
                }
                Text("It's been saved to History. You can start a new session below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { coordinator.acknowledgeRecovery() }
                .buttonStyle(.link)
        }
        .padding(TFSpacing.m)
        .background(TFPalette.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: TFRadius.medium, style: .continuous))
        .padding([.horizontal, .top], TFSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: Active run

    private var activeSession: some View {
        ScrollView {
            VStack(spacing: TFSpacing.xl) {
                if coordinator.recoveryOutcome == .restored {
                    restoredBanner
                }

                // Task (prominent, secondary to the countdown) + frozen configuration
                // name (§16 visual priority).
                VStack(spacing: TFSpacing.xs) {
                    Text(taskTitle)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if let config = coordinator.activeSession?.displayConfigurationName {
                        Text(config)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                TimerDisplay(engine: engine)
                    // The countdown dims slightly while paused, reinforcing the frozen
                    // state beyond colour alone (§17); reduced motion still applies the
                    // state, just without the fade.
                    .opacity(engine.state == .paused ? 0.55 : 1)
                    .tfAnimation(TFMotion.state, value: engine.state)

                // Paused is conveyed by an explicit label + icon, never colour alone (§17/§48).
                if engine.state == .paused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TFPalette.paused)
                        .transition(.opacity)
                        .accessibilityIdentifier("timeFrame.timer.pausedIndicator")
                }

                SessionProgressView(engine: engine)

                TimerControls(coordinator: coordinator) { controlError = $0 }
                    .padding(.top, TFSpacing.xs)

                // A quiet, non-blocking calendar status — never interrupts the run.
                if calendarCoordinator.preferences.isEnabled {
                    CalendarSyncStatusView(status: calendarCoordinator.syncStatus)
                }

                nextUp
            }
            .tfAnimation(TFMotion.state, value: engine.state == .paused)
            .padding(TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.contentColumn)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Timer")
    }

    private var restoredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Welcome back — your session was restored.")
                .font(.callout)
            Spacer()
            Button("Dismiss") { coordinator.acknowledgeRecovery() }
                .buttonStyle(.link)
        }
        .padding(TFSpacing.m)
        .background(.tint.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: TFRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = engine.plan.interval(at: engine.currentIndex + 1) {
            VStack(spacing: 6) {
                Divider()
                HStack(spacing: 8) {
                    Text("Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label(next.phase.displayLabel, systemImage: next.phase.symbol)
                        .font(.subheadline)
                    Text("· \(TimeFormatting.minutesLabel(next.duration))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next: \(next.phase.displayLabel), \(TimeFormatting.minutesLabel(next.duration))")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var taskTitle: String {
        let name = coordinator.activeSession?.taskName ?? ""
        return name.isEmpty ? "Focus session" : name
    }
}
