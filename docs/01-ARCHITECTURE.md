# 01 — Architecture

> **Milestone 22 note.** iOS Control Center controls are a command/presentation adapter over the one
> timer: they route through the existing `WidgetControlActions → AppIntentSessionActions →
> SessionCoordinator → TimerEngine` seam and derive state from a pure, Foundation-only projection. No
> second timer/clock/store/router; Control Center is iOS-only and CloudKit-independent. See
> `docs/31-CONTROL-CENTER-CONTROLS.md` and ADR-090/091/092.

Time Frame follows a layered architecture with a strict one-way dependency flow.
The defining constraint is that **domain logic (the timer engine) depends on
neither SwiftUI nor SwiftData** and is fully testable headlessly.

> **Milestone 19 — CloudKit capability seam.** CloudKit remains a **persistence transport below the
> repositories** (SwiftData native mirroring), never timer authority. M19 adds the pure, CloudKit-free
> `Core/Services/Cloud/CloudKitCapability.swift`, which separates the **build/provisioning** fact (is
> this build entitled for iCloud) from the **runtime** account fact and resolves the launch-time
> `PersistenceMode` (`CloudKitCapability.resolve`). Both the macOS app and the iOS companion decide
> through this one seam. It adds no second timer/store/clock/control seam and no schema change (stays
> **V6**). See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md` and ADR-080/081/082.

> **Milestone 18 — multi-platform.** The platform-neutral domain now lives in a shared **`Core/`** group
> compiled into **both** the macOS app (`time_frame`) and the native iOS/iPadOS companion
> (`TimeFrameiOS`): the same `TimerEngine`, `SessionCoordinator`, models, persistence, statistics,
> projections, and App-Intent seams — there is still exactly **one** timer and **one** control seam
> across platforms. Platform UI stays platform-specific (macOS `Views/`/`MenuBar`; iOS `TimeFrameiOS/`).
> The iOS Live Activity (`TimeFrameiOSWidgets`) is a read-only presentation surface; ActivityKit is
> confined to the iOS targets and the macOS app stays ActivityKit-free (ADR-078/079). See
> `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md`.

---

## 1. Layers

```
┌─────────────────────────────────────────────┐
│ SwiftUI Views (sidebar app: Today / Timer /  │  presentation only
│  Configurations / History / Settings)        │
└───────────────┬─────────────────────────────┘
                │ observes / sends intents
┌───────────────▼─────────────────────────────┐
│ Application State / Coordinators             │  SessionCoordinator
│  (SessionCoordinator, @MainActor)            │  heartbeat + persistence + recovery
└───────┬──────────────────────────┬──────────┘
        │ drives                    │ persists (via repositories)
┌───────▼─────────────────────┐   ┌▼──────────────────────────┐
│ Domain Logic — Timer Engine │   │ Persistence (SwiftData)   │  Config/Session
│  (pure, no SwiftUI/SwiftData)│   │  repositories, @Model     │  repositories,
│  TimerEngine, IntervalPlan, │   │  types, schema            │  PersistenceController
│  PomodoroConfigurationSnapshot│  └───────────┬───────────────┘
└───────┬─────────────────────┘               │
        │ (injected clock)                     ▼
┌───────▼─────────┐                    ┌───────────────┐
│ Time Source     │                    │ SwiftData     │
│ (TimeProviding) │                    │ store         │
└─────────────────┘                    └───────────────┘
        ▲                                      ▲
        └──── recovery seam (TimerEngineSnapshot, pure values) ────┘
```

**Dependencies point downward only.** Views know about the coordinator; the
coordinator knows about both the engine and persistence; the engine knows only
about value types and the injected clock. The engine does **not** import SwiftUI
or SwiftData — recovery crosses the boundary as plain values
(`TimerEngineSnapshot`), assembled by the persistence side and applied via
`TimerEngine.restore(from:)`.

## 2. Components (as implemented)

### Presentation — `Views/` (Milestone 3)
`ContentView` is now the app root: a native `NavigationSplitView` with a sidebar
(`AppSection`: Today / Timer / Templates / Plans / Configurations / History /
Statistics / Settings) and
a detail column. Each area is a thin SwiftUI layer that **observes the shared
`SessionCoordinator`/`TimerEngine`** and reads persisted data via `@Query`; it
sends user intents to the coordinator and never holds timer state or touches
`ModelContext` directly. The primary Timer screen renders setup / running /
paused / completed and the restored/interrupted recovery states; the countdown is
refreshed for display by a `TimelineView(.periodic)` that re-reads
`engine.remaining` (a display cadence only — the authoritative time stays in the
engine). Full breakdown: `docs/12-CORE-UI.md`.

### Visual design system — `Support/DesignSystem/` (Milestone 9)
A **presentation-only** leaf that carries the macOS 27 Liquid Glass visual identity:
`TimeFrameDesign.swift` (semantic tokens — `TFSpacing`/`TFRadius`/`TFMotion`/`TFPalette` —
and the Reduce-Motion-aware `tfAnimation`) and `TimeFrameGlass.swift` (`tfGlassSurface` for
selective glass, `tfQuietSurface` for quiet content). The `Views/` tree composes these with
the native glass APIs. The design system **imports no domain** and no `Timer/`/`Services/`/
`Models/` file changed for the redesign, so styling can never affect timer behaviour
(ADR-050). Full breakdown: `docs/18-LIQUID-GLASS-DESIGN.md`.

### Coordinator — `SessionCoordinator` (`Timer/SessionCoordinator.swift`)
`@MainActor`, `@Observable`. The junction between the pure engine and durable
persistence (Milestone 2). It owns a `TimerEngine`, drives the production
**heartbeat** (a cancellable `Task` loop, default every 250 ms, that calls
`engine.synchronize()`), and **mirrors every meaningful lifecycle transition into
SwiftData** through the repositories. It also performs **app-relaunch recovery**
(`recover()`) and **sleep/wake reconciliation**. It reads only the engine's pure
state and hands the repositories plain values — it holds no raw fetch/save logic
itself. See `docs/04-SESSION-LIFECYCLE.md`. Its persistence behaviour *is*
unit-tested (deterministically, via a mock clock and in-memory store, with the
heartbeat disabled).

### Domain — `TimerEngine` (`Timer/TimerEngine.swift`)
`@Observable`, but pure domain logic. An explicit finite state machine over
`TimerState` × `TimerPhase` running an `IntervalPlan`. It reads time **only**
through an injected `TimeProviding`. See `docs/03-TIMER-ENGINE.md`.

Supporting domain types:
- `IntervalPlan` / `PlannedInterval` — the generated interval sequence the engine
  runs (renamed from `SessionPlan` in Milestone 5 to free that name for the planner
  model — ADR-031).
- `PomodoroConfigurationSnapshot` — an immutable, validated value copy of a
  configuration that the engine runs from (decouples the engine from SwiftData).
- `TimerState`, `TimerPhase`, `IntervalRecord`, `IntervalOutcome` — domain
  vocabulary, marked `nonisolated` so they are usable from any isolation.
- `SessionStatus`, `IntervalStatus` — the **persisted** lifecycle vocabulary,
  kept separate from the engine's `TimerState`/`IntervalOutcome` (they add
  `planned`/`interrupted` and the pending/running/paused interval states).
- `TimerEngineSnapshot` — a pure value describing engine state, the SwiftData-free
  seam used by `TimerEngine.restore(from:)` for recovery.

### Time source — `TimeProviding` (`Timer/TimeSource.swift`)
The injectable clock seam. `SystemTimeSource` returns `Date()` in production; a
`MockTimeSource` in the test target advances by hand. This is what makes the
engine deterministic under test.

### Persistence — `Services/Persistence/`
- `TimeFrameSchemaV5` (`VersionedSchema`, current) + `TimeFrameMigrationPlan`
  (`SchemaMigrationPlan`). `V1`–`V4` are retained as historical anchors;
  incompatible older on-disk stores are rebuilt (ADR-016/019/021).
- `PersistenceController` — builds the `ModelContainer` (on-disk or in-memory);
  an incompatible legacy on-disk store is rebuilt once rather than degrading to
  in-memory (ADR-016).
- `ConfigurationRepository` — configuration CRUD, duplicate, set-default, and
  idempotent seeding.
- `SessionRepository` — session/interval creation, recoverable-session fetch, and
  single-save reconciliation (`applySync`).
- `TaskTemplateRepository` — task-template CRUD, duplicate, set/clear-default, and
  by-id configuration resolution (Milestone 4; ADR-021…025).
- `SessionPlanRepository` — session-plan CRUD, duplicate, item reconciliation, and
  by-id configuration resolution (Milestone 5; ADR-026…030). Contains no timer
  logic — executing a plan is the coordinator's job.
- `SessionPlanValidation` — `SessionPlanDraft`/`PlanItemDraft` + structured
  `SessionPlanValidationError` + `PlanLimits` (Milestone 5).
- The planner value types `SessionPlanGenerator` (deterministic generation) and
  `SessionPlanExecutionSnapshot` (the immutable freeze the engine runs from) live in
  `Timer/`; `SessionCoordinator.startPlan(_:)` runs a snapshot through the existing
  engine. See `docs/14-SESSION-PLANNER.md`.
- `TaskTemplateValidation` — `TaskTemplateDraft` + structured
  `TaskTemplateValidationError` (name/task required, configuration required, count
  1…24).
- `ConfigurationValidation` — `ConfigurationDraft` + structured
  `ConfigurationValidationError` + limits (ADR-015).
- `PersistenceError` — structured, observable failures (never swallowed).
- `AppLog` — `os.Logger` channels (log identifiers/counts, never user content).
- `@Model` types in `Models/`.

### App — `time_frameApp.swift`
Builds the `ModelContainer` at launch (with an in-memory fallback), creates the
shared `SessionCoordinator`, seeds the default configuration (idempotent),
**recovers any previously live session**, and injects the container into the
SwiftUI environment. Sets a sensible default window size and
`windowResizability(.contentMinSize)`; the split view enforces minimum column and
detail widths so the layout stays usable when resized.

### Calendar integration — `Services/Calendar/` (Milestone 6)
An **optional, isolated** layer that projects plans/sessions onto Apple Calendar.
`CalendarCoordinator` (`@MainActor`, `@Observable`) orchestrates authorization and
event lifecycle; `EventKitCalendarService` (behind the `CalendarService` protocol) is
the only EventKit importer; `CalendarEventGenerator` is a pure
`CalendarPlanContext → [CalendarEventDraft]` function. Settings and event
associations persist in `UserDefaults` (no schema change; ADR-037). The link to the
core is one closure — `SessionCoordinator.onLifecycleEvent` — carrying pure
`SessionLifecycleEvent`s; all calendar work is deferred and never throws toward the
engine (ADR-035). `time_frameApp` builds the `CalendarCoordinator` and wires the
subscription. Full detail: `docs/15-CALENDAR-INTEGRATION.md`.

### Notification integration — `Services/Notifications/` (Milestone 7)
A second **optional, isolated** layer that delivers macOS local notifications for
interval transitions and completion. `NotificationCoordinator` (`@MainActor`,
`@Observable`) orchestrates authorization and scheduling; `UserNotificationService`
(behind the `NotificationScheduling` protocol) is the **only** UserNotifications
importer and the notification-center delegate; `NotificationContentGenerator` and
`NotificationScheduleBuilder` are pure functions. Preferences persist in `UserDefaults`
(no schema change; ADR-044). It subscribes to the **same** `SessionLifecycleEvent` seam
as Calendar — the app fans one event out to both — and is fully independent of Calendar
(they never call each other; §63). All notification work is deferred and never throws
toward the engine (ADR-042); actions route back through `SessionCoordinator` (ADR-043).
Full detail: `docs/16-NOTIFICATIONS.md`.

### Menu Bar — `Services/MenuBar/` + `Views/MenuBar/` (Milestone 8)
A native `MenuBarExtra` presentation/control surface — **not a second timer**. The app owns
**one** `SessionCoordinator`/`TimerEngine` and shares it with both the main window scene and
the menu bar (ADR-045/049). `MenuBarCoordinator` (`@MainActor`, `@Observable`) is an
observer/adapter: it exposes a pure `MenuBarPresentationState` projection of the
authoritative engine (ADR-046) and routes every control back through `SessionCoordinator`
(ADR-047). The live countdown is a `TimelineView` **repaint** of `TimerEngine.remaining`;
no menu-bar timer state is owned or persisted. Visibility persists in `UserDefaults` (no
schema change; ADR-048), and the menu bar steers the existing window through the one
`MainWindowPresenter` (`\.showMainWindow`) plus the `AppNavigation` seam — since Milestone 32
it holds no `openWindow` of its own (ADR-111). It observes the same authoritative state as Calendar and
Notifications and is independent of both. Full detail: `docs/17-MENU-BAR.md`.

### Statistics — `Statistics/` + `Services/Statistics/` + `Views/Statistics/` (Milestone 10)
A **read-only projection** of persisted history — **not** a second timer or a second store.
A `@MainActor` `StatisticsRepository` performs a single fetch and maps `FocusSession` into pure,
`Sendable` `SessionStatInput` values; the `nonisolated` `StatisticsAggregator` deterministically
derives an immutable `StatisticsSnapshot` from those values, a `StatisticsDateRange`, and the
user's `Calendar`. The engine imports no SwiftData/SwiftUI and has no clock. Nothing derived is
persisted (snapshots are reproducible from history), the schema is unchanged (**V5**), and
`TodayView` uses the same aggregator over `.today`. Dependencies point downward only
(history → repository/inputs → aggregator → snapshot → SwiftUI/Charts). Full detail:
`docs/19-STATISTICS.md` (ADR-054).

### WidgetKit — `Shared/` + `time_frame/Widgets/` + `TimeFrameWidgets/` (Milestone 11)
**Read-only projection surfaces** over the one authoritative timer — **not** a second timer.
The chain is `TimerEngine → SessionCoordinator → WidgetProjectionWriter → App Group store →
TimelineProvider → widgets`. A `@MainActor` `WidgetProjectionMapper` turns authoritative state
into an immutable `WidgetProjection`; a `WidgetProjectionWriter` observes the same
`SessionLifecycleEvent` fan-out as Calendar/Notifications (plus the additive
`onMeaningfulTransition` hook) and writes it to `group.abirbarman.com.time-frame`, then reloads
`WidgetCenter`. The `TimeFrameWidgets` app-extension reads that projection and renders it; it
imports no SwiftData, never instantiates `TimerEngine`/`SessionCoordinator`, and runs no clock
(the countdown is `Text(timerInterval:)` between frozen anchors). The pure projection types in
`Shared/` compile into both the app and the widget. The schema is unchanged (**V5**).
Dependencies point downward only. Full detail: `docs/20-WIDGETKIT.md` (ADR-055).

**Milestone 14 — configurable widget.** The widget becomes user-configurable via
`AppIntentConfiguration` (the `StaticConfiguration` is replaced; the provider becomes an
`AppIntentTimelineProvider`), keeping the same `kind`, families, and App Group. A pure
`TimeFrameWidgetConfiguration` (display mode / tap destination / countdown) selects **presentation
only**: the pure `WidgetTimelineBuilder` derives entries + reload from the **projection's state
alone**, so configuration never affects timing. The `WidgetConfigurationIntent` is owned/persisted by
**WidgetKit** (the app persists nothing for widget config). Two additive optional `WidgetProjection`
fields feed the Today/Statistics modes with no schema-version bump; the trend is computed by the app
from the same `StatisticsAggregator` the dashboard uses. The widget stays read-only and
CloudKit-independent. Full detail: `docs/23-CONFIGURABLE-WIDGETS.md` (ADR-064…068).

**Milestone 15 — interactive widget.** The configurable widget gains per-state `Button(intent:)`
controls (Pause/Resume/Skip/Restart/Stop/Start). The controls are thin App Intents in
`Shared/WidgetControlIntents.swift` that WidgetKit runs in the **app process**, where an app-registered
`@AppDependency WidgetControlActions` router delegates to the existing `AppIntentSessionActions` seam —
the one place an intent mutates the timer. Dependencies point the same direction as every other
surface: `Widget button → App Intent → SessionCoordinator → TimerEngine → SwiftData`. The widget still
owns no timer state; which controls appear is a pure `WidgetControlSet` projection, the countdown stays
a `Text(timerInterval:)` repaint, and the projection is produced only by `WidgetProjectionWriter`
(refreshed after each action, reloaded on the meaningful transition — never per tick). Exactly one
`TimerEngine`/`SessionCoordinator` and one App Group remain. Full detail:
`docs/24-INTERACTIVE-WIDGETS.md` (ADR-069/070/071).

## 3. Key architectural decisions

1. **Timestamp-authoritative time, not per-second decrement.** The engine
   anchors each interval to a target end `Date` and computes
   `remaining = targetEnd − now`. It never relies on receiving exactly one tick
   per second. This is what makes it correct across sleep, backgrounding, CPU
   scheduling jitter, and delayed callbacks, and what will make menu-bar and
   notification support straightforward. See `docs/03-TIMER-ENGINE.md` §"Accuracy".

2. **Engine performs no scheduling.** All periodic driving lives in
   `SessionCoordinator` (production) or the test (deterministic). The engine
   only reacts to `synchronize()`. This is the seam that keeps it testable
   without the UI and without waiting real time.

3. **Engine runs on a value snapshot, not the SwiftData model.** `TimerEngine`
   consumes `PomodoroConfigurationSnapshot`, never `PomodoroConfiguration`. The
   engine therefore has no persistence dependency and cannot observe a
   configuration mutating mid-session.

4. **Domain vocabulary is `nonisolated`.** The project builds with
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure value types
   (`TimerPhase`, `TimerState`, `IntervalPlan`, …) are explicitly `nonisolated`
   so they can be constructed from any isolation domain. See `docs/DECISIONS.md`.

5. **Services isolate integrations.** The **Calendar/EventKit integration is now
   implemented** (Milestone 6) as an isolated service layer behind a
   `CalendarService` protocol — `EventKitCalendarService` is the only file importing
   EventKit, and the engine/domain import none of it. `SessionCoordinator` emits pure
   `SessionLifecycleEvent`s that `CalendarCoordinator` subscribes to; a Calendar
   failure can never stop the timer (ADR-032/035). The **Notification integration**
   (Milestone 7) follows the identical pattern behind a `NotificationScheduling`
   protocol — `UserNotificationService` is the only UserNotifications importer, and a
   notification failure can never stop the timer (ADR-038/042). The two integrations are
   independent. Menu-bar support will follow the same pattern. See
   `docs/15-CALENDAR-INTEGRATION.md` and `docs/16-NOTIFICATIONS.md`.

6. **Persistence is orchestrated by the coordinator, through repositories**
   (ADR-011), and the **engine stays SwiftData-free** — recovery uses the
   `TimerEngineSnapshot` value seam (ADR-012). **Timestamps, not countdowns,**
   are persisted (ADR-013), which is what makes **relaunch and sleep/wake
   recovery** correct (ADR-014).

7. **The UI observes the coordinator; it holds no timer truth** (ADR-017). Session
   setup is a per-run value that never mutates the saved configuration (ADR-018).
   History freezes a configuration-name snapshot so it stays accurate through
   edits/deletes (ADR-019, schema V3). Keyboard shortcuts are scoped to the
   active-run controls so they never clash with text entry (ADR-020).

8. **Task Templates are reusable session-start definitions** (ADR-021, schema V4).
   A template references a configuration rather than copying it (ADR-022), and
   starting from a template **copies** its values into the existing setup/start
   path so the running session is independent of later template edits or deletes
   (ADR-023/025). Deleting a template never deletes sessions; deleting a
   configuration nullifies its templates rather than removing them (ADR-024).

## 4. Concurrency model

- The app uses Swift's approachable concurrency with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- `TimerEngine` and `SessionCoordinator` are effectively main-actor bound
  (UI-facing observable state); this is correct because their observable state
  drives the UI.
- The injected clock (`TimeProviding.now()`) is `nonisolated` and `Sendable`, so
  time can be read from any context.
- `SessionCoordinator`'s heartbeat is a structured, cancellable `Task`; pausing/
  stopping cancels it, and `deinit` cancels it.

## 5. Testability

- The engine is exercised entirely through the injected clock; the coordinator's
  persistence and recovery logic is exercised deterministically (mock clock,
  in-memory store, heartbeat disabled) — **138 tests** run in ~0.5 s with no real
  waiting. Milestone 3 adds application-logic coverage (setup draft, count
  override, name snapshot, edit-while-running, recovery outcomes); Milestone 4
  adds template validation, repository CRUD/duplicate/default, the template →
  session workflow, and template/history independence.
- Persistence is exercised against in-memory `ModelContainer`s, plus one real
  on-disk close/reopen test for relaunch.
- See `docs/10-TESTING-PLAN.md`.

## Milestone 13 — iCloud/CloudKit as a transport below the repositories

CloudKit sits **below** the SwiftData repositories, provided by SwiftData's native mirroring
(`ModelConfiguration(cloudKitDatabase: .automatic)`). Dependencies still point downward only:
Views → Coordinators → `TimerEngine` → repositories → `ModelContainer` → CloudKit. **No file
imports CloudKit** — the timer and coordinator are unchanged and CloudKit-free (ADR-060). The
iCloud Settings surface reads a pure `CloudSyncPresentationState` projection, and
`PersistenceController.bootstrap` resolves an explicit `PersistenceMode` with a safe fallback to
the local store (ADR-062). See `docs/22-ICLOUD-CLOUDKIT.md`.

**Milestone 16 — Live Session Surface (platform-neutral core; ActivityKit unavailable on macOS).**
A Live Activity would be one more read-only surface on the same `SessionLifecycleEvent` fan-out as
Calendar/Notifications/Menu Bar/Widgets: `SessionCoordinator → LiveActivityCoordinator →
LiveActivityService → [ActivityKit adapter] → Live Activity`, never `Live Activity → TimerEngine`.
The platform-neutral core (projection value types, presentation, service protocol, mapper,
coordinator) is built and tested, but ActivityKit is **`@available(macOS, unavailable)`** (Mac
Catalyst-only in the macOS SDK), so the adapter/UI are **not** built and the core is **inert in the
shipping macOS app**. There is still exactly one `TimerEngine`/`SessionCoordinator`; the core imports
no ActivityKit/WidgetKit/SwiftData/CloudKit and introduces no clock (`Text(timerInterval:)` repaint).
See `docs/25-LIVE-ACTIVITIES.md`.

## Milestone 17 — production hardening adds no runtime architecture

M17 is a **hardening** milestone: it introduces no new coordinator, store, timer primitive, or schema
change (**V6** unchanged). `TimerEngine` stays the single timing authority and `SessionCoordinator` the
single control seam. The only production edits are behaviour-preserving: the XCTest-host detection is
extracted into the pure `Support/TestHostEnvironment.swift` (launch still skips live
seeding/recovery/CloudKit/App-Group writes/intent registration under the test host);
`PersistenceController.openOnDiskContainer(schema:configuration:)` exposes the existing
rebuild-on-incompatibility path for hermetic migration tests; the two live countdowns gain the
`.updatesFrequently` accessibility trait; and the Restart intent binds a local to clear a spurious
Release-only optimizer warning. A whole-tree `ProductionReadinessTests` source-boundary audit becomes the
**release gate**, failing the build if any of these invariants regress (single scheduling authority; single
engine/coordinator; persistence/widget/App-Intent boundaries; no ActivityKit/CloudKit import; V6 schema;
hermetic test host). See `docs/26-PRODUCTION-READINESS.md` (ADR-077).

> **Milestone 20 note.** iOS gains two presentation surfaces over the one timer — a configurable Home
> Screen widget (in the existing `TimeFrameiOSWidgets` extension, reusing the shared
> `WidgetProjection`/App Group/`AppIntentConfiguration`/`WidgetTimelineBuilder` and the M15 control
> seam) and local notifications (the neutral notification stack moved to `Core/Services/Notifications/`
> and is shared by macOS + iOS; `UserNotificationService` stays the single UserNotifications importer).
> Neither is a second timer/clock/store; the schema stays **V6** and no CloudKit is added. See
> `docs/29-IOS-WIDGETS-NOTIFICATIONS.md` (ADR-083/084/085/086).

> **Milestone 21 note.** A third iOS presentation surface — **Lock Screen accessory widgets**
> (circular / rectangular / inline) and **StandBy** — was added in the same extension, reusing the same
> projection pipeline and configuration intent. Per-family content comes from the pure, Foundation-only
> `Shared/AccessoryWidgetPresentation.swift`; accessory families are read-only (the M15 control seam
> stays the one mutation path). No second timer/clock/store/seam; schema stays **V6**; no CloudKit. See
> `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md` (ADR-087/088/089).

## Milestone 24 — Identity & event-driven catalog refresh (2026-08-17)

M24 adds no runtime architecture. Product identity (name + one logo) is a presentation/build concern
(ADR-096). The Control Center quick-start catalog refresh became event-driven via a neutral
`ConfigurationRepository.onChange` hook forwarded through `SessionCoordinator.init` and wired by each
app to `QuickStartCatalogWriter.refresh` — no polling, no new timer/store, the App Group catalog stays
a projection over the authoritative model (ADR-097). One `TimerEngine`/`SessionCoordinator`/mutation
seam; schema stays V6. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md`.

## Milestone 32 — One main window, and a login item that tells the truth (2026-09-08)

Two application-level concerns, both macOS-only, both additive to the layering above.

**Windows.** The main scene is a single-instance **`Window`**, not a `WindowGroup`. That is the
whole guarantee: a `WindowGroup` is a scene type designed to present more than one window, and
`openWindow(id:)` over it creates a new one on every call — which four surfaces were doing, each
with its own copy of activate-then-open. Every request now goes through one
`MainWindowPresenter`, published to views as the `\.showMainWindow` environment action, so
`openWindow` exists in exactly one file and window ordering in exactly one other
(`AppKitMainWindowHost`).

The decision is pure (`MainWindowPolicy`) and reads the live window's state on every request —
never a cached `windowIsOpen` boolean, which is wrong the moment the window is closed, minimized,
hidden, or rebuilt by SwiftUI. A Dock reopen is answered by `applicationShouldHandleReopen`
without consulting `hasVisibleWindows` (false for a minimized window *and* for a hidden app —
exactly the case that produced a duplicate). Concurrent requests coalesce for one run-loop turn.

The layer sits beside the presentation layer, above nothing: it owns no domain type, no store,
and no clock, and `Core/` is untouched by it. Focusing a window never resets navigation state and
never reaches `TimerEngine` or `SessionCoordinator`. `applicationShouldTerminateAfterLastWindowClosed`
returns `false`, restoring the survive-on-close behaviour `WindowGroup` had implicitly — without
it, ⌘W would end a running session (ADR-111).

**Open at Login.** Isolated behind `LoginItemManaging` exactly like Calendar and Notifications;
`LoginItemService.swift` is the only file importing ServiceManagement. The state is **not**
persisted — `SMAppService`'s reported status is re-read on launch, when Settings appears, and
after every change, so the toggle can never claim a registration the system does not hold
(ADR-112).

Schema stays **V7**; no model, repository, engine, coordinator, widget, intent, notification or
CloudKit behaviour changed. Full detail: `docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md`.
