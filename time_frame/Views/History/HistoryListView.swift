//
//  HistoryListView.swift
//  time_frame
//
//  A read-only history of focus sessions, grouped by day and backed directly by
//  SwiftData. Every figure is derived from the session's own persisted intervals
//  and its frozen configuration name, so history never changes when a
//  configuration is later edited or deleted (ADR-019).
//
//  Milestone 29: the screen adopted the shared page header, day headings, and card rows, so
//  History reads like the rest of the library. It stays read-only — no action mutates a
//  recorded session.
//

import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]

    /// Only sessions that actually started, grouped by their start day (newest
    /// day first).
    private var groupedByDay: [(day: Date, sessions: [FocusSession])] {
        let started = sessions.filter { $0.startedAt != nil }
        let groups = Dictionary(grouping: started) { $0.startDay() }
        return groups
            .map { (day: $0.key, sessions: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                .navigationDestination(for: UUID.self) { id in
                    if let session = sessions.first(where: { $0.id == id }) {
                        HistoryDetailView(session: session)
                    } else {
                        ContentUnavailableView("Session Unavailable", systemImage: "questionmark.folder")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if groupedByDay.isEmpty {
            EmptyStateView(
                title: "No Focus History",
                systemImage: "clock.arrow.circlepath",
                message: "Sessions you start will be recorded here, with what you focused on and for how long."
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.l, pinnedViews: []) {
                TFPageHeader(title: "History",
                             subtitle: "Every session you've run, newest first.")

                ForEach(groupedByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: TFSpacing.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayLabel(group.day))
                                .font(.subheadline.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text(dayTotal(group.sessions))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: TFSpacing.s) {
                            ForEach(group.sessions) { session in
                                NavigationLink(value: session.id) {
                                    HistoryRowView(session: session)
                                }
                                .buttonStyle(.plain)
                                .tfCard()
                                .accessibilityLabel(HistoryRowPresentation.accessibilityLabel(for: session))
                                .accessibilityHint("Opens the session's intervals")
                                .accessibilityIdentifier("history.row.\(session.id.uuidString)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func dayLabel(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day().year())
    }

    /// The day's completed focus time, so a heading answers "how much did I do?" without
    /// opening a row. Pure arithmetic over the sessions already fetched for that day.
    private func dayTotal(_ sessions: [FocusSession]) -> String {
        let total = sessions.reduce(0) { $0 + $1.completedFocusDuration }
        return "\(TimeFormatting.compactDuration(total)) focus"
    }
}

/// One session row in the history list.
private struct HistoryRowView: View {
    let session: FocusSession

    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.m) {
            TFSymbolTile(systemImage: session.status.symbol,
                         size: .medium,
                         tint: session.status.tint == .secondary ? .secondary : session.status.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.taskName.isEmpty ? "Focus session" : session.taskName)
                    .font(.headline)
                    .lineLimit(1)
                Text(session.displayConfigurationName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(HistoryRowPresentation.metrics(for: session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: TFSpacing.s)

            VStack(alignment: .trailing, spacing: 3) {
                Label(session.status.displayLabel, systemImage: session.status.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(session.status.tint)
                if let started = session.startedAt {
                    Text(started.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, TFSpacing.m)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// The History list's words in one place, so the row and VoiceOver agree.
enum HistoryRowPresentation {

    /// "3 of 4 focus sessions · 1h 20m".
    static func metrics(for session: FocusSession) -> String {
        let completed = session.completedFocusCount
        let planned = session.plannedFocusCount
        let duration = TimeFormatting.compactDuration(session.completedFocusDuration)
        return "\(completed) of \(planned) focus sessions · \(duration)"
    }

    static func accessibilityLabel(for session: FocusSession) -> String {
        let task = session.taskName.isEmpty ? "Focus session" : session.taskName
        let time = session.startedAt.map { ", started \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "\(task), \(session.displayConfigurationName), \(session.status.displayLabel), \(metrics(for: session))\(time)"
    }
}
