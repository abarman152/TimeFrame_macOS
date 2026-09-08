//
//  WidgetControlIntents.swift
//  Time Frame — shared widget control intents (Milestone 15)
//
//  The thin App Intents that back the widget's interactive `Button(intent:)` controls
//  (Pause / Resume / Skip / Restart / Stop / Start). They are compiled into BOTH the app and
//  the widget so the widget view can reference them; but they own NO timer logic, hold NO
//  session state, and never touch SwiftData, CloudKit, `TimerEngine`, or `SessionCoordinator`
//  — none of which this file can even see (ADR-069).
//
//  How they reach the one authoritative timer:
//
//      Button(intent:) → (system runs the intent in the APP process) → perform()
//          → @AppDependency WidgetControlActions   ← registered by the app at launch
//              → AppIntentSessionActions            ← the ONE place intents mutate the timer
//                  → SessionCoordinator → TimerEngine
//
//  `WidgetControlActions` is a pure, app-group-independent *router*: a value the app owns and
//  wires to `AppIntentSessionActions` (the existing Milestone-12 seam) plus a widget-projection
//  refresh. This file defines only the router's shape and the intents; the real routing lives
//  in the app target. When the router is not registered (e.g. an unexpected process), the
//  intent resolves the injected `.unavailable` default and fails *safely* with a friendly
//  message instead of trapping — a widget action can never crash or corrupt the timer.
//
//  These intents are deliberately NOT discoverable (`isDiscoverable == false`): they exist only
//  to drive the widget's buttons and must not clutter Shortcuts, which already exposes the
//  Milestone-12 command intents that share the exact same action seam.
//
//  Foundation + AppIntents only. No SwiftUI, no WidgetKit, no SwiftData, no CloudKit, no domain.
//

import Foundation
import AppIntents

// MARK: - Action vocabulary

/// The closed set of controls a widget button can request. A pure value; the mapping to a
/// real coordinator operation lives entirely in the app-registered `WidgetControlActions`.
public enum WidgetControlAction: String, Sendable, Codable, CaseIterable, Hashable {
    case pause
    case resume
    case skip
    case restart
    case stop
    case start
}

/// The pure decision of *which* controls a widget should offer for a given state — derived
/// solely from the read-only projection (state + phase) and how much room the family has. This
/// is the single source of truth the widget view renders from, so button availability can be
/// unit-tested without a WidgetKit host and can never drift from a second timer (ADR-070).
///
/// Layout note: `.idle`/`.completed`/`.interrupted` return `[.start]`; the widget realizes that
/// as a single inline primary button whose label varies by state ("Start Timer" vs "Start New
/// Session"). `.running`/`.paused` return the control row rendered by the view's control bar.
public enum WidgetControlSet {

    /// The ordered controls to present. Pure and deterministic.
    /// - Parameter compact: `true` for the small family, where fewer controls fit.
    public static func controls(
        for state: WidgetSessionState,
        phase: WidgetPhase,
        compact: Bool
    ) -> [WidgetControlAction] {
        switch state {
        case .running:
            if phase.isBreak {
                // A break can't be paused meaningfully; offer skip + stop.
                return [.skip, .stop]
            }
            // A focus interval: pause + skip always; stop where there is room.
            return compact ? [.pause, .skip] : [.pause, .skip, .stop]
        case .paused:
            return compact ? [.resume, .stop] : [.resume, .restart, .stop]
        case .idle, .completed, .interrupted:
            return [.start]
        case .unavailable:
            return []
        }
    }
}

/// The user-facing result of a successful widget control action — a single short confirmation
/// sentence the app produced (reusing the Milestone-12 dialog vocabulary). A pure value.
public struct WidgetControlResult: Sendable, Equatable {
    /// A short confirmation, e.g. "Time Frame is paused." Supplied by the app so all phrasing
    /// stays in one place; the widget intent only surfaces it.
    public let confirmation: String

    public init(confirmation: String) {
        self.confirmation = confirmation
    }
}

/// The only error this shared layer raises on its own: the app-side router was not available
/// in the process running the intent. Every *domain* failure (no active session, already
/// running, persistence error) is raised by the app's existing `TimeFrameIntentError` and
/// simply propagates through — this file never re-implements those messages.
public enum WidgetControlError: Error, CustomLocalizedStringResourceConvertible, LocalizedError, Sendable, Equatable {
    /// The app's control router was not registered in the current process, so the action could
    /// not be routed to the one coordinator. Surfaced as a calm, non-technical sentence.
    case unavailable

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable:
            return "Time Frame isn't available right now. Open the app and try again."
        }
    }

    public var errorDescription: String? { String(localized: localizedStringResource) }
}

// MARK: - Router (app-owned, app-group-independent)

/// A tiny indirection the **app** owns and registers as an App Intents dependency. It holds a
/// single main-actor closure that performs a `WidgetControlAction` by delegating to the app's
/// existing `AppIntentSessionActions` (the one mutation seam) and refreshing the widget
/// projection. This shared type deliberately knows nothing about how the action is performed —
/// only the app wires that in, keeping this file free of every domain type.
///
/// `@unchecked Sendable` is safe: the stored handler is immutable after construction and is
/// only ever invoked from `perform(_:)`, which is `@MainActor`. The default `.unavailable`
/// instance carries no handler and fails safely.
public final class WidgetControlActions: @unchecked Sendable {
    public typealias Handler = @MainActor (WidgetControlAction) throws -> WidgetControlResult
    /// Resolves and performs the *contextually correct* primary action for the current
    /// authoritative state, then returns the confirmation. Used by the Control Center adaptive
    /// control (Milestone 22): the app reads live coordinator state, maps it with the pure
    /// `ControlCenterControlSet.primaryAction(for:)`, and performs it through the SAME
    /// `AppIntentSessionActions` seam — so there is still exactly one mutation path (ADR-090).
    public typealias PrimaryHandler = @MainActor () throws -> WidgetControlResult
    /// Resolves and performs a *configured quick-start* for the current Control Center control
    /// (Milestone 23): starts a session from a user-selected saved configuration id (or the
    /// user's default when `nil`), through the SAME `AppIntentSessionActions.startSession`
    /// seam. A pure data-in command — the id is DATA, never a second timer authority (ADR-095).
    public typealias QuickStartHandler = @MainActor (UUID?) throws -> WidgetControlResult

    private let handler: Handler?
    private let primaryHandler: PrimaryHandler?
    private let quickStartHandler: QuickStartHandler?

    /// - Parameters:
    ///   - handler: the app-provided routing closure for an explicit `WidgetControlAction`, or
    ///     `nil` for the inert `.unavailable` router that fails safely.
    ///   - primaryHandler: the app-provided closure that resolves and performs the adaptive
    ///     primary action from live state (Control Center), or `nil` when unavailable.
    ///   - quickStartHandler: the app-provided closure that starts a session from a selected
    ///     configuration id (Milestone 23 configurable quick-start control), or `nil` when
    ///     unavailable.
    public init(
        handler: Handler? = nil,
        primaryHandler: PrimaryHandler? = nil,
        quickStartHandler: QuickStartHandler? = nil
    ) {
        self.handler = handler
        self.primaryHandler = primaryHandler
        self.quickStartHandler = quickStartHandler
    }

    /// Routes one action through the app-provided handler. Throws `WidgetControlError.unavailable`
    /// when no handler is wired (the intent then reports a calm, safe message).
    @MainActor
    public func perform(_ action: WidgetControlAction) throws -> WidgetControlResult {
        guard let handler else { throw WidgetControlError.unavailable }
        return try handler(action)
    }

    /// Performs the adaptive primary action for the current state (Control Center's one-tap
    /// control). Throws `WidgetControlError.unavailable` when no primary handler is wired.
    @MainActor
    public func performPrimary() throws -> WidgetControlResult {
        guard let primaryHandler else { throw WidgetControlError.unavailable }
        return try primaryHandler()
    }

    /// Starts a session from the selected configuration id (Milestone 23 configurable
    /// quick-start control). Passing `nil` starts from the user's default configuration — the
    /// app decides what "default" means; the widget never invents timer values. Throws
    /// `WidgetControlError.unavailable` when no quick-start handler is wired, and surfaces the
    /// app's existing `TimeFrameIntentError` (e.g. the selected configuration was deleted, or a
    /// session is already running) untouched.
    @MainActor
    public func performQuickStart(configurationID: UUID?) throws -> WidgetControlResult {
        guard let quickStartHandler else { throw WidgetControlError.unavailable }
        return try quickStartHandler(configurationID)
    }

    /// The inert router used as the `@AppDependency` default so an unregistered process never
    /// traps — the action simply reports that Time Frame isn't available.
    public static let unavailable = WidgetControlActions()
}

// MARK: - Intents

/// A common shape for the five session-control intents: resolve the app router, perform the
/// action, surface the app's confirmation. `openAppWhenRun == false` so the action runs quietly
/// in the background; `isDiscoverable == false` so it never appears as a separate Shortcut.
private protocol WidgetControlIntent: AppIntent {
    static var action: WidgetControlAction { get }
}

extension WidgetControlIntent {
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }
}

/// Pause the running session from the widget.
struct WidgetPauseIntent: WidgetControlIntent {
    static let title: LocalizedStringResource = "Pause Time Frame"
    static let description = IntentDescription("Pause the current Time Frame session from the widget.")
    static let action: WidgetControlAction = .pause

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.perform(Self.action)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

/// Resume the paused session from the widget.
struct WidgetResumeIntent: WidgetControlIntent {
    static let title: LocalizedStringResource = "Resume Time Frame"
    static let description = IntentDescription("Resume the paused Time Frame session from the widget.")
    static let action: WidgetControlAction = .resume

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.perform(Self.action)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

/// Skip the current interval from the widget.
struct WidgetSkipIntent: WidgetControlIntent {
    static let title: LocalizedStringResource = "Skip Time Frame Interval"
    static let description = IntentDescription("Skip the current focus or break interval from the widget.")
    static let action: WidgetControlAction = .skip

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.perform(Self.action)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

/// Restart the current interval from the widget.
struct WidgetRestartIntent: WidgetControlIntent {
    static let title: LocalizedStringResource = "Restart Time Frame Interval"
    static let description = IntentDescription("Restart the current interval from the beginning, from the widget.")
    static let action: WidgetControlAction = .restart

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.perform(Self.action)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

/// Stop the session from the widget (preserves history — never a delete).
struct WidgetStopIntent: WidgetControlIntent {
    static let title: LocalizedStringResource = "Stop Time Frame"
    static let description = IntentDescription("Stop the current Time Frame session from the widget.")
    static let action: WidgetControlAction = .stop

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.perform(Self.action)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

/// The adaptive primary action behind the iOS Control Center control (Milestone 22). Unlike the
/// five fixed-action intents above, this one has no compile-time action: at run time the app
/// resolves the *contextually correct* primary action from live authoritative state (start when
/// idle, pause a running focus interval, resume when paused, skip a running break) and performs it
/// through the SAME `AppIntentSessionActions` seam via `performPrimary()`. Reused by
/// `ControlWidgetButton` so a single Control Center control behaves like the timer's primary button;
/// still not discoverable as a Shortcut (ADR-090).
struct TimeFramePrimaryControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Time Frame Timer"
    static let description = IntentDescription("Start, pause, resume, or advance your Time Frame timer from Control Center.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.performPrimary()
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

/// Start a new session from the widget, using the app's existing default-configuration start
/// path (the app decides what "default" means — the widget never invents timer values).
struct WidgetStartIntent: WidgetControlIntent {
    static let title: LocalizedStringResource = "Start Time Frame"
    static let description = IntentDescription("Start a Time Frame session from the widget using your default configuration.")
    static let action: WidgetControlAction = .start

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.perform(Self.action)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}

// MARK: - Configurable quick-start (Milestone 23)
//
// A USER-CONFIGURABLE Control Center control that starts a *chosen* saved timer configuration.
// The pieces below are all Foundation/AppIntents-only so they compile into BOTH the app and the
// iOS widget extension, and they own NO timer:
//
//   • `QuickStartTimerDescriptor` / `QuickStartCatalog` / `QuickStartCatalogStore` — a tiny,
//     App-Group-backed snapshot of the user's saved configurations used ONLY to populate the
//     picker. The app writes it; the picker reads it. It is never a source of truth for timing.
//   • `QuickStartTimerEntity` (+ its query) — the App Intents entity the control's configuration
//     parameter selects, resolved from that catalog WITHOUT SwiftData (so it resolves in any
//     process and drops deleted configurations gracefully).
//   • `QuickStartControlConfigurationIntent` — the `ControlConfigurationIntent` WidgetKit persists
//     against the installed control (a configuration holder, no side effects).
//   • `TimeFrameQuickStartIntent` — the action the control's `ControlWidgetButton` runs. It carries
//     the selected entity as DATA and routes through the ONE existing seam:
//       performQuickStart(configurationID:) → AppIntentSessionActions.startSession(configurationID:)
//     resolving the AUTHORITATIVE live configuration in the app, so a rename/duration change takes
//     effect on the next tap and a deleted configuration fails safely (ADR-093/094/095).

/// A lightweight, Foundation-only snapshot of one saved timer configuration, used ONLY to
/// populate the Control Center quick-start picker. It carries frozen display values; it is NOT
/// an authoritative timer. The actual start always re-resolves the live configuration in the app
/// by `id`, so a rename or a duration change takes effect on the next tap (ADR-094).
public struct QuickStartTimerDescriptor: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity — the configuration's `UUID`.
    public let id: UUID
    /// The configuration's name, e.g. "Deep Work".
    public let name: String
    /// Focus-interval length in seconds (for a meaningful subtitle).
    public let focusDuration: TimeInterval
    /// Default number of focus sessions.
    public let defaultTotalSessions: Int

    public init(id: UUID, name: String, focusDuration: TimeInterval, defaultTotalSessions: Int) {
        self.id = id
        self.name = name
        self.focusDuration = focusDuration
        self.defaultTotalSessions = defaultTotalSessions
    }

    /// A short subtitle, e.g. "25 min focus · 4 sessions". Pure string math — no formatter
    /// dependency, so this value type stays usable in the widget extension.
    public var subtitle: String {
        let minutes = max(1, Int((focusDuration / 60).rounded()))
        let sessionWord = defaultTotalSessions == 1 ? "session" : "sessions"
        return "\(minutes) min focus · \(defaultTotalSessions) \(sessionWord)"
    }
}

/// The full catalog snapshot the app writes to the App Group for the quick-start picker.
/// Versioned so a forward-incompatible payload is ignored rather than mis-decoded.
public struct QuickStartCatalog: Sendable, Codable, Equatable {
    /// The schema version this build writes/understands.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let timers: [QuickStartTimerDescriptor]

    public init(timers: [QuickStartTimerDescriptor], schemaVersion: Int = QuickStartCatalog.currentSchemaVersion) {
        self.timers = timers
        self.schemaVersion = schemaVersion
    }

    /// The empty catalog (no saved timers, or the App Group was unavailable).
    public static let empty = QuickStartCatalog(timers: [])
}

/// Reads/writes the quick-start catalog in the SAME App Group suite as the widget projection
/// (a separate key — no new App Group). Mirrors `WidgetProjectionStore`: JSON in/out, every
/// failure isolated and non-fatal. Foundation-only; usable from any process (app or extension).
// `@unchecked Sendable`: the only stored member is a `UserDefaults` (documented thread-safe),
// read/written atomically; the compiler can't prove its Sendability, so we vouch for it here.
public struct QuickStartCatalogStore: @unchecked Sendable {

    /// The key the catalog is stored under in the shared suite (distinct from the widget
    /// projection's key — the two never collide).
    public static let storageKey = "com.time-frame.quickStartCatalog.v1"

    private let defaults: UserDefaults?

    /// Injects a specific suite (or `nil`, modelling "App Group unavailable"). Used by tests.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// Opens the shared App Group suite (the same one the widget projection uses). Falls back
    /// to an inert store if the suite cannot be created — never crashes.
    public init(appGroupIdentifier: String = WidgetProjectionStore.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Whether a shared suite is actually available.
    public var isAvailable: Bool { defaults != nil }

    /// Persists the catalog as JSON. Returns `false` when the suite is unavailable or encoding
    /// failed — a failed catalog write is never fatal to the app.
    @discardableResult
    public func write(_ catalog: QuickStartCatalog) -> Bool {
        guard let defaults else { return false }
        do {
            let data = try JSONEncoder().encode(catalog)
            defaults.set(data, forKey: QuickStartCatalogStore.storageKey)
            return true
        } catch {
            return false
        }
    }

    /// Reads the last-written catalog, or `nil` when the suite is unavailable, nothing has been
    /// written, the payload is corrupt, or its schema version is not understood. Corruption is
    /// swallowed, never thrown.
    public func read() -> QuickStartCatalog? {
        guard let defaults else { return nil }
        guard let data = defaults.data(forKey: QuickStartCatalogStore.storageKey) else { return nil }
        guard let catalog = try? JSONDecoder().decode(QuickStartCatalog.self, from: data) else { return nil }
        guard catalog.schemaVersion == QuickStartCatalog.currentSchemaVersion else { return nil }
        return catalog
    }

    /// Removes any stored catalog.
    public func clear() {
        defaults?.removeObject(forKey: QuickStartCatalogStore.storageKey)
    }
}

/// The App Intents representation of a saved timer configuration, so the Control Center
/// quick-start control can take one as its configuration parameter. Immutable value, stable
/// UUID id, frozen display strings. Resolved WITHOUT SwiftData — from the App Group catalog —
/// so it compiles into the widget extension and resolves in any process (ADR-093/094).
public struct QuickStartTimerEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer")
    public static let defaultQuery = QuickStartTimerEntityQuery()

    /// Stable identity — the configuration's `UUID`.
    public let id: UUID
    /// The configuration's name, e.g. "Deep Work".
    public let name: String
    /// A short, frozen subtitle, e.g. "25 min focus · 4 sessions".
    public let subtitle: String

    public init(id: UUID, name: String, subtitle: String) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
    }

    public init(descriptor: QuickStartTimerDescriptor) {
        self.init(id: descriptor.id, name: descriptor.name, subtitle: descriptor.subtitle)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

/// Resolves `QuickStartTimerEntity` values from the App Group catalog the app writes. It touches
/// NO SwiftData and needs no `@AppDependency`, so the picker works in the Control Center
/// configuration UI regardless of process, and a deleted configuration simply drops out of the
/// results (its id no longer resolves). `EntityStringQuery` so typing filters by name.
public struct QuickStartTimerEntityQuery: EntityStringQuery {
    public init() {}

    /// The catalog currently published by the app (or empty when unavailable/first-launch).
    private func currentCatalog() -> QuickStartCatalog { QuickStartCatalogStore().read() ?? .empty }

    public func entities(for identifiers: [UUID]) async throws -> [QuickStartTimerEntity] {
        Self.resolve(identifiers, in: currentCatalog())
    }

    public func suggestedEntities() async throws -> [QuickStartTimerEntity] {
        Self.suggested(in: currentCatalog())
    }

    public func entities(matching string: String) async throws -> [QuickStartTimerEntity] {
        Self.matching(string, in: currentCatalog())
    }

    // MARK: Pure, testable resolution cores (no I/O, no process assumptions)

    /// Resolves the given ids against a catalog, preserving request order and dropping unknown
    /// ids (a deleted configuration). Pure.
    public static func resolve(_ identifiers: [UUID], in catalog: QuickStartCatalog) -> [QuickStartTimerEntity] {
        let byID = Dictionary(catalog.timers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0].map(QuickStartTimerEntity.init(descriptor:)) }
    }

    /// Every saved timer, in catalog order. Pure.
    public static func suggested(in catalog: QuickStartCatalog) -> [QuickStartTimerEntity] {
        catalog.timers.map(QuickStartTimerEntity.init(descriptor:))
    }

    /// Case-insensitive name filter. Pure.
    public static func matching(_ string: String, in catalog: QuickStartCatalog) -> [QuickStartTimerEntity] {
        let needle = string.lowercased()
        return catalog.timers
            .filter { $0.name.lowercased().contains(needle) }
            .map(QuickStartTimerEntity.init(descriptor:))
    }
}

/// The `ControlConfigurationIntent` that backs the configurable quick-start Control Center
/// control (Milestone 23). It owns NO command — WidgetKit presents its one parameter (the
/// selected timer) in the Control Center configuration UI and persists the choice against the
/// installed control. Its `perform()` returns `Never` (a configuration holder, not an action).
public struct QuickStartControlConfigurationIntent: ControlConfigurationIntent {
    public static var title: LocalizedStringResource { "Quick-Start Timer" }
    public static var description: IntentDescription {
        IntentDescription("Choose which saved timer this Control Center control starts.")
    }

    /// The saved timer to start. Optional: when unset, the control starts the user's default
    /// configuration, so a freshly added control is useful before a choice is made.
    @Parameter(title: "Timer")
    public var timer: QuickStartTimerEntity?

    public init() {}
    public init(timer: QuickStartTimerEntity?) { self.timer = timer }

    public static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$timer)")
    }
}

/// Starts a session from the configured quick-start timer (Milestone 23). It carries the selected
/// entity so `ControlWidgetButton` can serialize the choice; on run (in the app process) it
/// resolves the app-registered `WidgetControlActions` router and starts through the SAME
/// `AppIntentSessionActions.startSession` seam via `performQuickStart(configurationID:)`. Owns no
/// timer state, decrements nothing, and is not discoverable as a Shortcut (ADR-093/095).
struct TimeFrameQuickStartIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick-Start Time Frame"
    static let description = IntentDescription("Start the selected Time Frame timer.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Timer")
    var timer: QuickStartTimerEntity?

    @AppDependency(default: WidgetControlActions.unavailable) private var actions: WidgetControlActions

    init() {}
    init(timer: QuickStartTimerEntity?) { self.timer = timer }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try actions.performQuickStart(configurationID: timer?.id)
        return .result(dialog: IntentDialog("\(result.confirmation)"))
    }
}
