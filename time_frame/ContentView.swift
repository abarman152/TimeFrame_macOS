//
//  ContentView.swift
//  time_frame
//
//  The app's root: a native macOS sidebar split view. The sidebar lists the
//  primary areas (Today / Timer / Configurations / History / Settings); the
//  detail column shows the selected area. Every area observes the shared
//  `SessionCoordinator` (and the SwiftData store via `@Query`) — there is no
//  second source of truth for the session or the timer.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    /// The shared coordinator (engine + persistence), created by the app.
    let coordinator: SessionCoordinator

    /// The shared Calendar integration, created by the app. Observed by the
    /// Settings, Plans, and Timer areas; the timer itself never depends on it.
    let calendarCoordinator: CalendarCoordinator

    /// The shared Notifications integration, created by the app. Observed by the
    /// Settings area; the timer itself never depends on it.
    let notificationCoordinator: NotificationCoordinator

    /// The shared Menu Bar adapter, created by the app. Observed by the Settings area
    /// so the "Show in Menu Bar" preference lives with the other integrations; it wraps
    /// the *same* coordinator, so there is no second timer (ADR-045/049).
    let menuBarCoordinator: MenuBarCoordinator

    /// The shared iCloud sync adapter, created by the app. Observed by the Settings
    /// area to show sync status; it is a read-only projection over the persistence
    /// mode and never touches the timer (ADR-060).
    let cloudCoordinator: CloudSyncCoordinator

    /// The shared Quick Start adapter, created by the app and already used by the menu bar.
    /// The Timer screen's Quick Start control reads the *same* projection and routes through
    /// the *same* `AppIntentSessionActions` seam — there is no second Quick Start source
    /// (ADR-104/105).
    let quickStartCoordinator: QuickStartCoordinator

    /// The shared "Open at Login" adapter, created by the app. Observed by the Settings area;
    /// its state is read back from macOS, never stored (Milestone 32, ADR-112).
    let loginItemCoordinator: LoginItemCoordinator

    /// The shared navigation seam. The menu bar sets a requested section here; this
    /// window applies it to `selection` and clears it, reusing the existing screens
    /// rather than opening parallel ones (§22/§23/§24).
    let navigation: AppNavigation

    /// The selected sidebar area. Timer is the primary screen, so it opens there.
    @State private var selection: AppSection = .timer

    /// Setup values queued by "Start" on a Task Template. Consumed by the Timer
    /// setup screen, which copies them into its editable fields; the running
    /// session goes through the one existing `startSession` path (ADR-025).
    @State private var pendingSetup: SessionSetupPrefill?

    /// A plan draft queued by "Create Plan" on a template or configuration. Consumed
    /// by the Plans screen, which opens its editor pre-filled; the plan becomes an
    /// independent `SessionPlan` on save, leaving the source unchanged (ADR-030).
    @State private var pendingPlanDraft: SessionPlanDraft?

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    // One weight and one rendering mode for every sidebar glyph, so the
                    // column reads as a single icon set rather than eight styles (§4).
                    Image(systemName: section.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.vertical, 1)
                .tag(section)
                .accessibilityIdentifier("sidebar.\(section.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 300)
            .navigationTitle("Time Frame")
        } detail: {
            detail(for: selection)
                .frame(minWidth: 460, minHeight: 420)
        }
        // Apply a menu-bar navigation request whether this window was already open
        // (onChange) or freshly reopened with a request pending (task).
        .onChange(of: navigation.requestedSection) { _, _ in applyPendingNavigation() }
        .task { applyPendingNavigation() }
        // A widget tap (`timeframe://…`) brings the app forward and selects the matching
        // existing screen. Unknown URLs are ignored safely — no new navigation surface.
        .onOpenURL { url in
            guard let section = WidgetDeepLink.section(for: url) else { return }
            selection = section
        }
    }

    /// Consumes a pending section request from the menu bar, switching the sidebar and
    /// clearing the request so it fires once.
    private func applyPendingNavigation() {
        guard let section = navigation.requestedSection else { return }
        selection = section
        navigation.requestedSection = nil
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .today:
            TodayView(coordinator: coordinator, openTimer: { selection = .timer })
        case .timer:
            TimerView(coordinator: coordinator,
                      calendarCoordinator: calendarCoordinator,
                      quickStart: quickStartCoordinator,
                      pendingSetup: $pendingSetup,
                      openConfigurations: { selection = .configurations })
        case .templates:
            TemplateListView(coordinator: coordinator,
                             startFromTemplate: startFromTemplate,
                             createPlanFromTemplate: createPlan(from:))
        case .plans:
            PlanListView(coordinator: coordinator,
                         calendarCoordinator: calendarCoordinator,
                         pendingDraft: $pendingPlanDraft,
                         openTimer: { selection = .timer })
        case .configurations:
            ConfigurationListView(coordinator: coordinator,
                                  createPlanFromConfiguration: createPlan(from:))
        case .history:
            HistoryListView()
        case .statistics:
            StatisticsView(openTimer: { selection = .timer })
        case .settings:
            SettingsView(coordinator: coordinator,
                         calendarCoordinator: calendarCoordinator,
                         notificationCoordinator: notificationCoordinator,
                         menuBarCoordinator: menuBarCoordinator,
                         cloudCoordinator: cloudCoordinator,
                         loginItemCoordinator: loginItemCoordinator)
        }
    }

    /// Queues the template's values for the setup screen and switches to the Timer
    /// area. The template view has already ensured no session is active, so the
    /// setup screen (shown only when idle) consumes the prefill on appear.
    private func startFromTemplate(_ template: TaskTemplate) {
        pendingSetup = SessionSetupPrefill(template: template)
        selection = .timer
    }

    /// Generates an initial plan from a template (task name, configuration, default
    /// session count) and opens the Plans editor pre-filled. The template is only
    /// read — creating and editing the plan never mutates it (ADR-030).
    private func createPlan(from template: TaskTemplate) {
        guard let config = template.configuration else { return }
        let items = SessionPlanGenerator.generate(
            from: config.snapshot,
            configurationID: config.id,
            configurationName: config.name,
            sessions: template.defaultTotalSessions
        )
        pendingPlanDraft = SessionPlanDraft(name: template.name, taskName: template.taskName, items: items)
        selection = .plans
    }

    /// Generates an initial plan from a configuration's defaults and opens the Plans
    /// editor pre-filled. The configuration is only read — it is never modified.
    private func createPlan(from configuration: PomodoroConfiguration) {
        let items = SessionPlanGenerator.generate(
            from: configuration.snapshot,
            configurationID: configuration.id,
            configurationName: configuration.name,
            sessions: configuration.defaultTotalSessions
        )
        pendingPlanDraft = SessionPlanDraft(name: configuration.name, taskName: "", items: items)
        selection = .plans
    }
}
