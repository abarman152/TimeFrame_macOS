//
//  time_frameApp.swift
//  time_frame
//
//  Created by Abir on 13/08/26.
//

import SwiftUI
import SwiftData
import os

@main
struct time_frameApp: App {
    /// The app-wide SwiftData container. Built from the versioned schema, with
    /// an in-memory fallback so the app still launches if the on-disk store
    /// cannot be opened at all.
    let modelContainer: ModelContainer

    /// What the store is actually doing (Milestone 31, ADR-109).
    ///
    /// `.needsRecovery` means `modelContainer` above is a scratch in-memory store and the
    /// user's real store is untouched on disk. The window shows the recovery surface in
    /// that case rather than an empty library, because an empty library is exactly what a
    /// destroyed store used to look like.
    @State private var persistenceState: PersistenceState

    /// The single coordinator that drives the engine and persistence for the
    /// app's lifetime. Created once and shared with the view tree.
    @State private var coordinator: SessionCoordinator

    /// The optional Calendar integration, created once and shared with the view
    /// tree. It subscribes to the session coordinator's pure lifecycle events; the
    /// timer never depends on it (ADR-035).
    @State private var calendarCoordinator: CalendarCoordinator

    /// The optional Notifications integration, created once and shared with the view
    /// tree. It subscribes to the same pure lifecycle events; the timer never depends
    /// on it, and it is entirely independent of the Calendar integration (ADR-042).
    @State private var notificationCoordinator: NotificationCoordinator

    /// The Menu Bar adapter, created once and shared with the view tree and the
    /// `MenuBarExtra` scene. It wraps the *same* `SessionCoordinator` — it is a
    /// presentation/control surface, not a second timer (ADR-045/046/049).
    @State private var menuBarCoordinator: MenuBarCoordinator

    /// The menu bar's Quick Start adapter, created once and shared with the `MenuBarExtra`
    /// scene. Like `MenuBarCoordinator` it wraps the *same* `SessionCoordinator`: it projects
    /// the user's pinned Templates and Plans and routes a start through the existing
    /// `AppIntentSessionActions` seam — it is not a second timer or a second store (ADR-104).
    @State private var quickStartCoordinator: QuickStartCoordinator

    /// The WidgetKit projection writer. It observes the same lifecycle seam as Calendar and
    /// Notifications and mirrors authoritative state into the shared App Group store the
    /// widget extension reads — a read-only projection, never a second timer (ADR-055).
    @State private var widgetWriter: WidgetProjectionWriter

    /// The iCloud sync adapter. A read-only projection over the resolved persistence
    /// mode and iCloud account status; it observes, it never drives the store or the
    /// timer (ADR-060). The actual sync is SwiftData's native CloudKit mirroring below
    /// the repositories.
    @State private var cloudCoordinator: CloudSyncCoordinator

    /// The application delegate. It exists so a Dock-icon reopen can be answered in AppKit,
    /// where that event actually arrives, and it owns the one `MainWindowPresenter` and the
    /// shared `AppNavigation` seam — both have to outlive every scene, because a reopen can
    /// be delivered before the first window exists (Milestone 32, ADR-111).
    @NSApplicationDelegateAdaptor(TimeFrameAppDelegate.self) private var appDelegate

    /// The "Open at Login" adapter. Its state is read back from `SMAppService`, never from a
    /// stored preference, so the Settings toggle always reflects the real registration
    /// (Milestone 32, ADR-112).
    @State private var loginItemCoordinator: LoginItemCoordinator

    init() {
        // The app target is also the **unit-test host**. Under XCTest, skip live
        // store seeding/recovery so the developer's real persisted state can never
        // affect — or hang — the test runner (the tests build their own in-memory
        // containers; this keeps the suite hermetic). This changes launch behaviour
        // only while hosting tests; a normal run is unaffected, and no domain type
        // (TimerEngine/SessionCoordinator) changes.
        let isHostingUnitTests = TestHostEnvironment.isHostingUnitTests()

        // Resolve how the store is backed. CloudKit mirroring is requested only when
        // the user wants sync **and** an iCloud account is actually available — we
        // never construct a cloud-backed container that plainly cannot sync (no
        // account / no iCloud entitlement), and we never prompt for iCloud on launch.
        // Under the unit-test host it is forced local so the suite is deterministic
        // and never touches CloudKit. `bootstrap` still degrades safely to the
        // *existing local store* if CloudKit can't initialise — a CloudKit problem
        // can never lose data or block the timer (ADR-062). The timer imports none of
        // this (ADR-060).
        let cloudPreferences = CloudSyncPreferencesStore()
        let accountProvider = SystemCloudAccountStatusProvider()
        // CloudKit is requested only when the build is actually entitled for it
        // (a paid-team capability — false on this personal-team build; ADR-080),
        // the user wants sync, and an iCloud account is available. The capability
        // seam makes the "not entitled" case an explicit, tested decision rather
        // than something only discovered when a doomed cloud container fails to
        // build. Under the unit-test host it is forced local for determinism.
        let cloudDecision = CloudKitCapability.resolve(
            accountProvider: accountProvider,
            syncEnabled: cloudPreferences.syncEnabled
        )
        let requestedMode: PersistenceMode = isHostingUnitTests ? .local : cloudDecision.requestedMode
        let persistence = PersistenceController.bootstrap(requestedMode: requestedMode)
        let container = persistence.container
        self.modelContainer = container
        _persistenceState = State(initialValue: persistence.state)
        if let failure = persistence.state.pendingFailure {
            AppLog.persistence.error(
                "Launching into recovery: \(failure.logSummary, privacy: .public). The existing store is preserved."
            )
        }

        // Republish the Control Center quick-start catalog whenever the user's configurations
        // change (create/rename/delete/duplicate/default), so the picker stays current without any
        // polling (Milestone 24, ADR-097). Event-driven off the existing repository lifecycle; a
        // throwaway repository over the same context reads the fresh state, and the write is
        // best-effort (a failure never disturbs the app or the timer). Suppressed under the unit
        // -test host so the suite never writes to the App Group (hermeticity — ADR-077).
        var quickStartRefresh: (@MainActor () -> Void)? = nil
        if !isHostingUnitTests {
            let refreshContext = container.mainContext
            quickStartRefresh = {
                QuickStartCatalogWriter.refresh(configurations: ConfigurationRepository(context: refreshContext))
            }
        }
        // Refresh the menu bar's Quick Start list whenever a template or plan changes
        // (pin/unpin, rename, icon change, create, duplicate, delete), so the popover is
        // current without polling and without an app restart (Milestone 28, ADR-105). The
        // closure is installed just below, once the coordinator it reads from exists.
        var libraryRefresh: (@MainActor () -> Void)? = nil
        let coordinator = SessionCoordinator(
            context: container.mainContext,
            onConfigurationsChanged: quickStartRefresh,
            onLibraryChanged: { libraryRefresh?() }
        )
        if !isHostingUnitTests {
            // Ensure a default configuration exists (idempotent), then restore any
            // session that was live when the app last stopped.
            _ = try? coordinator.configurations.seedDefaultIfNeeded()
            _ = try? coordinator.recover()
        }

        // Build the Calendar integration and subscribe it to the coordinator's
        // lifecycle events. The subscription is the *only* link between the two;
        // the coordinator imports no EventKit and is unaffected by any calendar
        // failure (ADR-032/035).
        let calendar = CalendarCoordinator(
            service: EventKitCalendarService(),
            preferences: CalendarPreferencesStore(),
            records: CalendarEventRecordStore()
        )

        // Build the Notifications integration and subscribe it to the same lifecycle
        // events. It is independent of Calendar (they never call each other — §8/§63),
        // imports no UserNotifications, and can never affect the timer (ADR-042).
        let notifications = NotificationCoordinator(
            scheduler: UserNotificationService(),
            preferences: NotificationPreferencesStore()
        )
        // Route notification actions back through the coordinator (§37) and give the
        // coordinator a read-only view of the live timer state for action safety (§40).
        notifications.performAction = { [weak coordinator] action in
            guard let coordinator else { return }
            switch action {
            case .pause: try? coordinator.pause()
            case .resume: try? coordinator.resume()
            case .skip: try? coordinator.skip()
            case .stop: try? coordinator.stop()
            case .open: break
            }
        }
        notifications.timerStateProvider = { [weak coordinator] in
            (coordinator?.activeSession?.id, coordinator?.engine.state ?? .idle)
        }

        // Build the WidgetKit projection writer over the same coordinator. Its today
        // summary is computed from the same statistics aggregator the dashboard uses, on
        // the shared main context, and is fully defensive (never throws toward the timer).
        let widgetStore = WidgetProjectionStore()
        let mainContext = container.mainContext
        let widgetWriter = WidgetProjectionWriter(
            coordinator: coordinator,
            store: widgetStore,
            todayProvider: { time_frameApp.todaySummary(context: mainContext) }
        )

        // A single fan-out closure delivers every lifecycle event to every integration.
        // They observe independently; none can influence another or the timer.
        coordinator.onLifecycleEvent = { [weak calendar, weak notifications, weak widgetWriter] event in
            calendar?.handle(event)
            notifications?.handle(event)
            widgetWriter?.handle(event)
        }

        // Auto interval boundaries (focus→break→focus) advance the engine without a
        // lifecycle event; refresh the widget projection there too (read-only, §ADR-055).
        coordinator.onMeaningfulTransition = { [weak widgetWriter] in
            widgetWriter?.update()
        }

        // After relaunch recovery, reconcile the notification queue with the restored
        // authoritative state: cancel stale notifications and schedule the next future
        // transitions for a still-running session (§31). Deferred so it runs once the
        // notification coordinator has read its authorization status.
        if !isHostingUnitTests {
            let recoveredContext = coordinator.currentLifecycleContext()
            let isRunning = coordinator.engine.state == .running
            Task { @MainActor in
                await notifications.refreshAuthorization()
                notifications.reconcileActiveSession(recoveredContext, isRunning: isRunning)
            }

            // Publish an initial projection so the widget reflects the restored (or idle)
            // state immediately on launch, before any further transition.
            widgetWriter.update()
        }

        // The menu bar observes the *same* coordinator and routes controls back through
        // it (ADR-045/047). Its only owned state is the show/countdown preference.
        let menuBar = MenuBarCoordinator(session: coordinator, preferences: MenuBarPreferencesStore())

        // The Quick Start adapter observes the SAME coordinator and reads the SAME
        // repositories; its list is a projection of pinned templates/plans (ADR-104). The
        // repository change hook installed above now points at it, so every mutation
        // republishes the list — event-driven, never polled (ADR-105).
        let quickStart = QuickStartCoordinator(session: coordinator)
        libraryRefresh = { [weak quickStart] in quickStart?.refresh() }
        if !isHostingUnitTests {
            quickStart.refresh()
        }

        // The iCloud sync adapter projects the resolved persistence mode + account
        // status for Settings. It observes only — no store or timer authority (ADR-060).
        let cloud = CloudSyncCoordinator(
            activeMode: persistence.activeMode,
            preferences: cloudPreferences,
            accountProvider: accountProvider
        )

        // Advertise the app's authoritative instances to the App Intents layer, so intents
        // (`@AppDependency var coordinator`) and entity queries (`@AppDependency var data`)
        // receive the SAME coordinator and container the rest of the app uses — never a second
        // timer or a second store (ADR-056/059). Skipped while hosting unit tests: the intent
        // tests inject their own in-memory coordinators, so the live store is never advertised.
        if !isHostingUnitTests {
            TimeFrameAppIntents.registerDependencies(coordinator: coordinator, container: container)

            // Wire the widget's interactive controls (Milestone 15) to the SAME coordinator via
            // the existing `AppIntentSessionActions` seam, refreshing the widget projection after
            // each action so the surface reflects the new authoritative state. The system runs a
            // widget-button intent in this (app) process, where this router is registered — the
            // widget itself owns no timer and never mutates state (ADR-069/071).
            let widgetControl = WidgetControlRouting.makeActions(
                coordinator: coordinator,
                refreshProjection: { [weak widgetWriter] in widgetWriter?.update() }
            )
            TimeFrameAppIntents.registerWidgetControl(widgetControl)

            // Publish the saved configurations to the App Group so the configurable Control
            // Center quick-start control can offer them in its picker (Milestone 23). Read-only
            // display data; the actual start re-resolves the authoritative configuration by id
            // (ADR-093/094). Best-effort — a failed write never disturbs the app or the timer.
            QuickStartCatalogWriter.refresh(configurations: coordinator.configurations)
        }

        // "Open at Login" reads the system's registration. Under the unit-test host the
        // unavailable service is injected instead, so the suite can never register the
        // developer's build as a login item (the hermeticity rule of ADR-077).
        let loginService: any LoginItemManaging =
            isHostingUnitTests ? UnavailableLoginItemService() : SMAppServiceLoginItem()
        _loginItemCoordinator = State(initialValue: LoginItemCoordinator(service: loginService))

        _coordinator = State(initialValue: coordinator)
        _calendarCoordinator = State(initialValue: calendar)
        _notificationCoordinator = State(initialValue: notifications)
        _menuBarCoordinator = State(initialValue: menuBar)
        _quickStartCoordinator = State(initialValue: quickStart)
        _widgetWriter = State(initialValue: widgetWriter)
        _cloudCoordinator = State(initialValue: cloud)
    }

    /// Computes today's focus/completed summary (and a focus trend versus yesterday) for the
    /// widget from the SAME statistics aggregator the dashboard uses. Fully defensive: any
    /// fetch failure yields `nil` so a widget refresh can never disturb the app. A single
    /// fetch, mutating nothing — the widget never aggregates anything itself (Milestone 14).
    private static func todaySummary(context: ModelContext) -> TodaySummary? {
        let todayRange = StatisticsPeriod.today.range()
        let yesterdayRange = StatisticsPeriod.today.previousRange()
        // Bounded to the two days actually shown, so an accumulated history can never
        // make this read grow without limit (M26, ADR-100).
        guard let inputs = try? StatisticsRepository(context: context)
            .sessionInputs(in: todayRange, or: yesterdayRange) else {
            return nil
        }
        let today = StatisticsAggregator.aggregate(sessions: inputs, range: todayRange)
        let yesterday = StatisticsAggregator.aggregate(sessions: inputs, range: yesterdayRange)
        let trend: WidgetFocusTrend
        switch StatisticsComparison(current: today.focusDuration, previous: yesterday.focusDuration).direction {
        case .up: trend = .up
        case .down: trend = .down
        case .flat: trend = .steady
        }
        return TodaySummary(
            focusSeconds: today.focusDuration,
            completedSessions: today.completedSessions,
            completedFocusIntervals: today.completedFocusIntervals,
            focusTrend: trend
        )
    }

    // MARK: Store recovery actions (Milestone 31, ADR-109)
    //
    // These are the only places the app acts on a store that failed to open, and two of the
    // three change nothing on disk. None of them deletes anything: "Continue Without
    // Existing Data" *moves* the store into a dated recovery folder, and if that move fails
    // the app stays in recovery rather than trading the user's history for a clean launch.

    /// Re-attempts the same open, for a failure that may have cleared (a lock, a volume
    /// that came back). Purely a retry — it modifies nothing either way.
    private func retryOpeningStore() {
        guard let failure = persistenceState.pendingFailure else { return }
        let bootstrap = PersistenceController.retryOpening(storeURL: failure.storeURL)
        persistenceState = bootstrap.state
        if bootstrap.state.pendingFailure == nil {
            AppLog.persistence.notice("Store opened on retry; relaunch to use it.")
        }
    }

    /// Reveals the store's folder so the user can copy it somewhere safe before deciding.
    private func revealStoreInFinder(_ storeURL: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([storeURL])
        #endif
    }

    /// Moves the existing store into a timestamped recovery folder and opens a fresh one.
    /// Invoked only from the recovery surface's confirmed action.
    private func startFreshPreservingStore(_ storeURL: URL) {
        do {
            let result = try PersistenceController.startFreshPreservingExistingStore(storeURL: storeURL)
            persistenceState = result.state
            AppLog.persistence.notice("Fresh store created; the previous one is preserved. Relaunch to use it.")
        } catch {
            // Preserving failed, so nothing was moved and nothing was removed. Staying in
            // recovery is the correct outcome: the alternative would be to proceed by
            // destroying the very data this screen exists to protect.
            AppLog.persistence.error(
                "Could not preserve the existing store; leaving it untouched and staying in recovery."
            )
        }
    }

    /// The one main window's content: the recovery surface when the store did not open, and
    /// the app otherwise. Extracted so the window's own wiring reads in one place.
    @ViewBuilder
    private var mainWindowContent: some View {
        if let failure = persistenceState.pendingFailure {
            // The store did not open. Never present this as an empty library.
            PersistenceRecoveryView(
                failure: failure,
                retry: retryOpeningStore,
                revealInFinder: { revealStoreInFinder(failure.storeURL) },
                startFresh: { startFreshPreservingStore(failure.storeURL) }
            )
        } else {
            ContentView(coordinator: coordinator,
                        calendarCoordinator: calendarCoordinator,
                        notificationCoordinator: notificationCoordinator,
                        menuBarCoordinator: menuBarCoordinator,
                        cloudCoordinator: cloudCoordinator,
                        quickStartCoordinator: quickStartCoordinator,
                        loginItemCoordinator: loginItemCoordinator,
                        navigation: appDelegate.navigation)
        }
    }

    var body: some Scene {
        Window("Time Frame", id: MainWindow.id) {
            mainWindowContent
                // The window tells the host which `NSWindow` it is, and lends the presenter
                // SwiftUI's `openWindow` so it can recreate the window after a close (ADR-111).
                .registersAsMainWindow(appDelegate.windowHost)
                .mainWindowPresentation(appDelegate.windowPresenter, host: appDelegate.windowHost)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 940, height: 640)
        .windowResizability(.contentMinSize)
        // A unified title bar integrates the sidebar and content into one calm window
        // surface, matching the macOS 27 design language (§31/§32).
        .windowToolbarStyle(.unified)

        // The menu-bar surface. Inserted only while the "Show in Menu Bar" preference is
        // on (§26); toggling it never touches the timer, which keeps running regardless.
        // Closing the main window does not stop the process: the MenuBarExtra keeps the
        // app — and its one running session — alive (§27/§28).
        MenuBarExtra(isInserted: showInMenuBar) {
            TimeFrameMenuBarView(menuBar: menuBarCoordinator,
                                 quickStart: quickStartCoordinator)
                .mainWindowPresentation(appDelegate.windowPresenter, host: appDelegate.windowHost)
        } label: {
            TimeFrameMenuBarLabel(menuBar: menuBarCoordinator)
        }
        .menuBarExtraStyle(.window)
    }

    /// A binding over the menu-bar visibility preference, driving `MenuBarExtra`'s
    /// insertion. Reads/writes the shared preferences store (§26/§65).
    private var showInMenuBar: Binding<Bool> {
        Binding(
            get: { menuBarCoordinator.preferences.showInMenuBar },
            set: { menuBarCoordinator.preferences.showInMenuBar = $0 }
        )
    }
}
