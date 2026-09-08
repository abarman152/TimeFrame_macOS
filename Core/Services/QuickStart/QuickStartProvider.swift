//
//  QuickStartProvider.swift
//  time_frame (Milestone 28)
//
//  Builds the Quick Start list from the AUTHORITATIVE repositories (ADR-104/105).
//
//  This is a read-only projection, exactly like `WidgetProjectionMapper` or
//  `MenuBarPresentationState`: it reads the pinned templates and plans, maps each to a pure
//  `QuickStartItem`, and orders them. It writes nothing, persists nothing, owns no timer, and
//  introduces no clock or cache — there is no second Quick Start store to keep in sync, so a
//  rename, an icon change, a pin, or a delete is reflected the next time this runs.
//
//  Every failure is swallowed into an empty/partial list: Quick Start is a convenience surface
//  and must never be able to disturb the app or the one timer.
//

import Foundation

/// Maps pinned templates and plans into the menu bar's Quick Start list.
@MainActor
enum QuickStartProvider {

    /// The pinned templates and plans, in Quick Start order (oldest pin first).
    static func items(
        templates: TaskTemplateRepository,
        plans: SessionPlanRepository
    ) -> [QuickStartItem] {
        let templateItems = ((try? templates.pinned()) ?? []).map(item(for:))
        let planItems = ((try? plans.pinned()) ?? []).map(item(for:))
        return QuickStartOrder.sorted(templateItems + planItems)
    }

    // MARK: Mapping

    /// One pinned template as a row. The subtitle mirrors the reference layout —
    /// "50 min focus · 10 min break" — read from the template's *live* configuration, so an
    /// edited configuration shows its new durations without any cached copy to invalidate.
    static func item(for template: TaskTemplate) -> QuickStartItem {
        QuickStartItem(
            id: template.id,
            kind: .template,
            name: template.name,
            subtitle: subtitle(for: template),
            icon: template.icon,
            isStartable: template.hasConfiguration,
            pinnedAt: template.pinnedAt
        )
    }

    /// One pinned plan as a row, summarised by focus count and total planned duration —
    /// pure arithmetic over the plan's own items, never the timer engine (ADR-028).
    static func item(for plan: SessionPlan) -> QuickStartItem {
        QuickStartItem(
            id: plan.id,
            kind: .plan,
            name: plan.name,
            subtitle: subtitle(for: plan),
            icon: plan.icon,
            isStartable: plan.isStartable,
            pinnedAt: plan.pinnedAt
        )
    }

    static func subtitle(for template: TaskTemplate) -> String {
        guard let configuration = template.configuration else {
            return "Needs a configuration"
        }
        let focus = TimeFormatting.minutesLabel(configuration.focusDuration)
        let brk = TimeFormatting.minutesLabel(configuration.shortBreakDuration)
        return "\(focus) focus · \(brk) break"
    }

    static func subtitle(for plan: SessionPlan) -> String {
        let count = plan.focusCount
        let focus = count == 1 ? "1 focus session" : "\(count) focus sessions"
        return "\(focus) · \(TimeFormatting.compactDuration(plan.totalDuration))"
    }
}
