//
//  TodayView.swift
//  time_frame
//
//  A light dashboard: today's focus totals and a shortcut into the Timer. It
//  reflects the shared coordinator's state — it never starts or drives a session
//  itself (that keeps a single active-session entry point and avoids duplicates).
//

import SwiftUI
import SwiftData

struct TodayView: View {
    let coordinator: SessionCoordinator
    /// Navigates to the Timer area.
    let openTimer: () -> Void

    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]

    private var engine: TimerEngine { coordinator.engine }

    /// Today's figures come from the **shared** statistics engine (Milestone 10), so
    /// Today and the Statistics screen can never disagree — there is one aggregation
    /// implementation, applied here to the `.today` period.
    ///
    /// Only sessions that can contribute to today are mapped: `SessionStatInput` faults in
    /// a session's intervals, so mapping all of history made every redraw cost grow with
    /// the lifetime of the app. The pure superset filter keeps the result identical while
    /// bounding the work to the day being shown (M26, ADR-100).
    private var todaySnapshot: StatisticsSnapshot {
        let range = StatisticsPeriod.today.range()
        let inputs = sessions
            .filter { range.mayContainActivity(startedAt: $0.startedAt, endedAt: $0.endedAt) }
            .map { SessionStatInput($0) }
        return StatisticsAggregator.aggregate(sessions: inputs, range: range)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                header

                if engine.state.isActive {
                    activeCard
                } else {
                    startCard
                }

                summaryCard
            }
            .padding(TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.contentColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Today")
    }

    /// A calm, time-of-day greeting over the date (§23).
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
            Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                .foregroundStyle(.secondary)
        }
    }

    // The current session is the one important, live contextual surface on Today, so
    // it — and only it — gets a floating Liquid Glass treatment (§7/§23).
    private var activeCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            Label("In progress", systemImage: "play.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TFPalette.running)
            Text(coordinator.activeSession?.taskName ?? "Focus session")
                .font(.title3.weight(.semibold))
            HStack(spacing: TFSpacing.s) {
                if let phase = engine.currentPhase {
                    Label(phase.displayLabel, systemImage: phase.symbol)
                        .font(.subheadline)
                        .foregroundStyle(phase.tint)
                }
                Group {
                    if engine.state == .running {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(TimeFormatting.clock(engine.remaining))
                        }
                    } else {
                        Text(TimeFormatting.clock(engine.remaining))
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                if engine.state == .paused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .foregroundStyle(TFPalette.paused)
                }
            }
            Button("Go to Timer", action: openTimer)
                .buttonStyle(.glassProminent)
                .padding(.top, TFSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.l)
        .tfGlassSurface(cornerRadius: TFRadius.large)
    }

    private var startCard: some View {
        quietCard {
            VStack(alignment: .leading, spacing: TFSpacing.s) {
                Text("Ready to Focus")
                    .font(.title3.weight(.semibold))
                Text("Choose a task and configuration to begin a session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start a Session", action: openTimer)
                    .buttonStyle(.glassProminent)
                    .padding(.top, TFSpacing.xs)
            }
        }
    }

    private var summaryCard: some View {
        // One aggregation per body pass — the figures below previously recomputed the
        // whole snapshot once each (M26).
        let snapshot = todaySnapshot
        let completedToday = snapshot.completedFocusIntervals
        return quietCard {
            VStack(alignment: .leading, spacing: TFSpacing.m) {
                Text("Today's Focus")
                    .font(.headline)
                HStack(spacing: TFSpacing.xxl) {
                    stat(value: "\(completedToday)", label: "Focus sessions")
                    stat(value: TimeFormatting.compactDuration(snapshot.focusDuration), label: "Focus time")
                }
                if completedToday == 0 {
                    Text("No completed focus sessions yet today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    /// A quiet (non-glass) grouped-content card for ordinary Today content (§8/§23).
    private func quietCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TFSpacing.l)
            .tfQuietSurface(cornerRadius: TFRadius.large)
    }
}
