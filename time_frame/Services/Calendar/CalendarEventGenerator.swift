//
//  CalendarEventGenerator.swift
//  time_frame
//
//  Pure conversion of a CalendarPlanContext into calendar event drafts. It knows
//  the task, plan, phases, durations, configuration names, and start/end times —
//  and nothing about how to save to Apple Calendar (that is the adapter's job).
//  Deterministic: same input → identical drafts.
//

import Foundation

/// Turns a plan/session (`CalendarPlanContext`) into `[CalendarEventDraft]`.
///
/// Two granularities (ADR-032, §12):
/// - `.singlePlan` — one event spanning the whole session.
/// - `.perInterval` — one event per interval, laid back to back from the start.
///
/// The generator is the single place that decides titles and notes, so both flows
/// (manual plan add and live session) render identically. Times are derived purely
/// from the anchor start and the interval durations — start + total = end (§66).
nonisolated enum CalendarEventGenerator {

    /// Builds the drafts for a context at a given style.
    ///
    /// - Parameters:
    ///   - context: the plan/session projection.
    ///   - style: single-event or per-interval.
    ///   - calendarIdentifier: the target calendar, or nil for the default.
    ///   - titleOverride: an optional user-customised title (single-event only; a
    ///     per-interval breakdown keeps its phase-specific titles).
    static func drafts(
        for context: CalendarPlanContext,
        style: CalendarEventStyle,
        calendarIdentifier: String?,
        titleOverride: String? = nil
    ) -> [CalendarEventDraft] {
        guard !context.intervals.isEmpty else { return [] }
        switch style {
        case .singlePlan:
            return [singleDraft(for: context, calendarIdentifier: calendarIdentifier, titleOverride: titleOverride)]
        case .perInterval:
            return intervalDrafts(for: context, calendarIdentifier: calendarIdentifier)
        }
    }

    // MARK: Single-event

    private static func singleDraft(
        for context: CalendarPlanContext,
        calendarIdentifier: String?,
        titleOverride: String?
    ) -> CalendarEventDraft {
        let title = titleOverride?.trimmedNonEmpty ?? context.defaultTitle
        return CalendarEventDraft(
            title: title,
            startDate: context.startDate,
            endDate: context.endDate,
            notes: planNotes(for: context),
            calendarIdentifier: calendarIdentifier
        )
    }

    // MARK: Per-interval

    private static func intervalDrafts(
        for context: CalendarPlanContext,
        calendarIdentifier: String?
    ) -> [CalendarEventDraft] {
        var drafts: [CalendarEventDraft] = []
        var cursor = context.startDate
        for interval in context.intervals {
            let end = cursor.addingTimeInterval(interval.duration)
            drafts.append(CalendarEventDraft(
                title: intervalTitle(interval, taskName: context.taskName),
                startDate: cursor,
                endDate: end,
                notes: intervalNotes(interval, taskName: context.taskName),
                calendarIdentifier: calendarIdentifier
            ))
            cursor = end
        }
        return drafts
    }

    private static func intervalTitle(_ interval: CalendarPlanContext.Interval, taskName: String) -> String {
        switch interval.phase {
        case .focus:
            return taskName.isEmpty ? "Focus" : "Focus — \(taskName)"
        case .shortBreak:
            return "Short Break"
        case .longBreak:
            return "Long Break"
        }
    }

    /// Phase names owned by the generator, so calendar text never depends on
    /// presentation-layer wording.
    private static func phaseLabel(_ phase: TimerPhase) -> String {
        switch phase {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    // MARK: Notes (§26)

    private static func planNotes(for context: CalendarPlanContext) -> String {
        var lines = ["Time Frame", ""]
        if !context.planName.isEmpty { lines.append("Plan: \(context.planName)") }
        if !context.taskName.isEmpty { lines.append("Task: \(context.taskName)") }
        if !context.planName.isEmpty || !context.taskName.isEmpty { lines.append("") }
        lines.append("Focus sessions: \(context.focusCount)")
        lines.append("Total planned duration: \(TimeFormatting.compactDuration(context.totalDuration))")
        let configs = context.focusConfigurationNames
        if configs.count == 1 {
            lines.append("Configuration: \(configs[0])")
        } else if configs.count > 1 {
            lines.append("Configurations: \(configs.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("Created by Time Frame")
        return lines.joined(separator: "\n")
    }

    private static func intervalNotes(_ interval: CalendarPlanContext.Interval, taskName: String) -> String {
        var lines = ["Time Frame", ""]
        if interval.phase == .focus && !taskName.isEmpty { lines.append("Task: \(taskName)") }
        lines.append("Phase: \(phaseLabel(interval.phase))")
        if interval.phase == .focus && !interval.configurationName.isEmpty {
            lines.append("Configuration: \(interval.configurationName)")
        }
        lines.append("Duration: \(TimeFormatting.minutesLabel(interval.duration))")
        lines.append("")
        lines.append("Created by Time Frame")
        return lines.joined(separator: "\n")
    }
}

private extension String {
    /// The trimmed string if it has visible content, else nil.
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
