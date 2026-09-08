//
//  PlanRowView.swift
//  time_frame
//
//  One row in the Plans list: the chosen icon, the plan's name (with its Pinned marker), a
//  compact summary line, and the facts that decide whether it is the right plan to run —
//  session count, total duration, and which configuration it uses.
//
//  Milestone 29: the row became a card with a leading icon tile. It renders *content only* —
//  the trailing Start and overflow controls are composed by the list beside the navigation
//  link, so a click on them is never swallowed by the link.
//

import SwiftUI

struct PlanRowView: View {
    let plan: SessionPlan

    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.m) {
            TimeFrameIconTile(icon: plan.icon, size: .medium)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: TFSpacing.s) {
                    Text(plan.name.isEmpty ? "Untitled Plan" : plan.name)
                        .font(.headline)
                        .lineLimit(1)
                    if plan.isPinned { QuickStartPinnedMarker() }
                    if !plan.isStartable {
                        Label("Needs a configuration", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(TFPalette.warning)
                            .accessibilityLabel("Needs a configuration")
                    }
                }

                Text(PlanRowPresentation.summary(for: plan))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: TFSpacing.xs) {
                    TFChip(PlanRowPresentation.sessionsChip(for: plan))
                    TFChip("\(TimeFormatting.compactDuration(plan.totalDuration)) total")
                    TFChip(PlanRowPresentation.configurationChip(for: plan))
                }
                .accessibilityHidden(true)
            }

            Spacer(minLength: TFSpacing.s)
        }
        .padding(.leading, TFSpacing.m)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A small, quiet metadata chip. Deliberately understated: it groups a fact, it is not a
/// badge and never carries state on its own.
struct TFChip: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// The Plans list's words in one place, so the row and its VoiceOver label agree.
enum PlanRowPresentation {

    /// "3 focus sessions · 1h 40m · Updated yesterday".
    static func summary(for plan: SessionPlan) -> String {
        // Pluralise in Swift: automatic inflection markdown only renders when the string
        // literal is passed straight to `Text`, not via a computed String.
        let focus = plan.focusCount == 1 ? "1 focus session" : "\(plan.focusCount) focus sessions"
        let duration = TimeFormatting.compactDuration(plan.totalDuration)
        let updated = plan.updatedAt.formatted(.relative(presentation: .named))
        return "\(focus) · \(duration) · Updated \(updated)"
    }

    static func sessionsChip(for plan: SessionPlan) -> String {
        plan.focusCount == 1 ? "1 session" : "\(plan.focusCount) sessions"
    }

    /// The configuration a plan runs on: its name when every focus interval agrees, and
    /// "Custom" when the plan deliberately mixes configurations (ADR-030).
    static func configurationChip(for plan: SessionPlan) -> String {
        let names = Set(plan.orderedItems.filter(\.isFocus).map(\.displayConfigurationName))
            .filter { !$0.isEmpty }
        if names.count == 1, let only = names.first { return only }
        if names.isEmpty { return "No configuration" }
        return "Custom"
    }

    static func accessibilityLabel(for plan: SessionPlan) -> String {
        let name = plan.name.isEmpty ? "Untitled Plan" : plan.name
        let pin = plan.isPinned ? ", pinned to Quick Start" : ""
        return "\(name)\(pin), \(summary(for: plan)), \(configurationChip(for: plan))"
    }
}
