# Architecture Decision Record

Chronological log of decisions that materially affect Time Frame's design or its
future milestones. Newest entries at the bottom of each section.

---

## ADR-001 — Timestamp-authoritative timer, not per-second decrement

**Context.** A Pomodoro timer must stay correct across app backgrounding, system
sleep, CPU scheduling jitter, and delayed callbacks, and must be restorable and
drivable from a future menu bar / notifications.

**Decision.** The engine anchors each running interval to a target end `Date` and
computes `remaining = targetEnd − now`. It never decrements a counter once per
second and owns no `Timer`. Automatic progression happens in `synchronize()`,
which fast-forwards through any intervals whose planned end has passed.

**Consequences.** Delayed/missed ticks are harmless; sleep is handled by
wall-clock `Date`; no drift accumulates (each interval anchors to the previous
interval's planned end). The UI/menu bar can update at any cadence.

---

## ADR-002 — Injected clock (`TimeProviding`)

**Decision.** Time is read only through an injected `TimeProviding`.
`SystemTimeSource` uses `Date()` in production; tests use a hand-advanced
`MockTimeSource`.

**Consequences.** The engine is fully deterministic under test — a 25-minute
interval is verified in microseconds. This is the primary testability seam.

---

## ADR-003 — Wall-clock (`Date`) rather than a monotonic clock

**Context.** `Date` can jump if the user changes the system clock; a monotonic
clock cannot. But a Pomodoro interval should keep elapsing *through system sleep*.

**Decision.** Use wall-clock `Date`. Elapsing through sleep is the desired
behaviour and outweighs the rare manual clock-change case.

**Revisit if.** We need to defend against deliberate clock manipulation, or we
want intervals to *pause* during sleep — then introduce a monotonic option behind
`TimeProviding`.

---

## ADR-004 — Engine performs no scheduling; a coordinator drives it

**Decision.** `TimerEngine` only reacts to `synchronize()`. The production
heartbeat lives in `SessionCoordinator` (a cancellable `Task`, ~250 ms). Tests
drive `synchronize()` directly.

**Consequences.** The engine is testable headlessly; scheduling policy is
swappable without touching domain logic.

---

## ADR-005 — Engine runs on a value snapshot, not the SwiftData model

**Decision.** The engine consumes `PomodoroConfigurationSnapshot` (an immutable,
validated `Sendable` value), never the `@Model` `PomodoroConfiguration`.

**Consequences.** The engine has no SwiftData dependency and cannot observe a
configuration mutating mid-session. Snapshot construction clamps invalid inputs
(durations → ≥ 1 s, counts → ≥ 1).

---

## ADR-006 — Domain vocabulary is `nonisolated`

**Context.** The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
which otherwise makes every type's members main-actor isolated.

**Decision.** Pure value types (`TimerPhase`, `TimerState`, `IntervalOutcome`,
`IntervalRecord`, `PlannedInterval`, `SessionPlan`,
`PomodoroConfigurationSnapshot`) and the `TimeProviding` protocol requirement are
declared `nonisolated`. `SystemTimeSource` is a `nonisolated` value type.

**Consequences.** Domain vocabulary is constructible from any isolation domain
(including the nonisolated test clock), which removed a class of actor-isolation
warnings at the source rather than patching call sites.

---

## ADR-007 — Delete rules: cascade for intervals, nullify for configuration

**Decision.** `FocusSession.intervals` uses `.cascade` (a session owns its
intervals). `PomodoroConfiguration.focusSessions` uses `.nullify` (historical
sessions survive deleting/editing a configuration). All optional-side endpoints
are optional so nullify cannot dangle. The `@Relationship` macro is placed on one
side of each relationship only.

---

## ADR-008 — Versioned schema from day one

**Decision.** Even with a single schema version, models are wrapped in
`TimeFrameSchemaV1: VersionedSchema` with a `TimeFrameMigrationPlan`.

**Consequences.** Future schema changes migrate explicitly instead of relying on
implicit lightweight migration.

---

## ADR-009 — Add a unit-test target by editing the project file

**Context.** The generated Xcode project had **no test target**, and it uses
file-system-synchronized groups (source files auto-included, but a *target* is
not).

**Decision.** Add a `time_frameTests` unit-test target (hosted by the app) via
targeted `project.pbxproj` edits, plus a **shared** `time_frame.xcscheme` whose
`TestAction` references it, so `xcodebuild … test` runs the suite. The test
target mirrors the app's Swift settings (`SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`, Swift 5 language mode, macOS 27 deployment target).

---

## ADR-010 — Trailing break after the final focus block

**Decision.** The generated plan appends a break after *every* focus block,
including the last (matching the Milestone 1 spec, e.g. `… Focus, Long`).

**Revisit if.** Users want the session to end on the final focus. Then add an
"omit trailing break" flag to `PomodoroConfiguration` and thread it through
`SessionPlan`.

---

## ADR-011 — Persistence is orchestrated by `SessionCoordinator`, through repositories

**Context (Milestone 2).** The session lifecycle must be durably persisted, but
the timer engine must stay free of persistence.

**Decision.** `SessionCoordinator` (already the engine's production driver)
becomes the single place that mirrors engine state into SwiftData. It does so
through two `@MainActor` repositories — `ConfigurationRepository` and
`SessionRepository` — so SwiftData calls never live in views or the engine, and
the coordinator itself holds no raw fetch/save logic. Model instances and
`ModelContext`s never cross an actor boundary.

**Consequences.** The layering `SwiftUI → SessionCoordinator → {TimerEngine,
Persistence} → SwiftData` holds. The coordinator reads the engine's pure state
and hands the repositories plain values to persist.

---

## ADR-012 — `TimerEngine` stays persistence-agnostic; recovery uses a value seam

**Decision.** `TimerEngine.swift` imports no SwiftData. Recovery is enabled by a
pure value type, `TimerEngineSnapshot`, plus `TimerEngine.restore(from:)` and two
read-only anchor accessors (`currentIntervalStart`, `currentIntervalEnd`). The
persistence layer reads the stored rows, assembles the snapshot, and hands it to
the engine. The engine remains the only writer of its timeline.

**Consequences.** The engine is still fully testable headlessly, and the hard
architectural constraint ("no `import SwiftData` in the engine") is preserved.
`SessionStatus`/`IntervalStatus` (the persisted lifecycle vocabulary) are
deliberately kept separate from the engine's `TimerState`/`IntervalOutcome`.

---

## ADR-013 — Persist timestamps, not countdown values

**Decision.** A running interval persists `startedAt` and `targetEndAt`; the
session persists `startedAt`/`endedAt`/`pausedAt`. No running countdown integer
is ever the source of truth — remaining is always `targetEnd − now`. The **one**
stored "remaining" value is `SessionInterval.remainingAtPause`, written only for
a *paused* interval, which by definition has no running target end to derive from
and whose remaining is genuinely frozen.

**Consequences.** Recovery and sleep/wake reconciliation are computed from the
authoritative timeline, so an arbitrary gap (sleep, crash, relaunch) advances
correctly instead of "subtracting seconds". Persisting `targetEndAt` (rather than
deriving it from `startedAt + plannedDuration`) is necessary because a
pause/resume re-anchors the end.

---

## ADR-014 — App-relaunch recovery: reconcile & resume

**Decision.** On launch the coordinator finds the single recoverable session
(status `running`/`paused`), rebuilds the plan **from its persisted intervals**
(so a changed/deleted configuration cannot corrupt recovery), restores the engine
via `TimerEngineSnapshot`, and — for a running session — calls `synchronize()` to
fast-forward through every interval whose planned end passed while the app was
away. A still-unfinished running session **resumes running**; a paused session is
restored **paused** (no time elapsed); a session whose anchors are inconsistent
(e.g. running with no `targetEndAt`) is marked **`interrupted`** and not
restored. If more than one session is recoverable, the newest wins and the rest
are marked interrupted, so at most one session is ever restored.

**Consequences.** Intervals are created once up front and only updated in place
(matched by `order`), so neither synchronization nor recovery can create
duplicate intervals or duplicate sessions. Sleep/wake uses the same path: an
`NSWorkspace.didWakeNotification` observer triggers an immediate reconcile, but
correctness does not depend on it — the next heartbeat would reconcile anyway.

---

## ADR-015 — Configuration validation rules, limits, and the default flag

**Decision.** Configuration create/update validate a `ConfigurationDraft` and
return **structured** `ConfigurationValidationError`s (via
`PersistenceError.invalidConfiguration`) — invalid input is never silently
clamped or modified at this layer. Rules: name non-empty; focus duration `> 0`;
break durations `≥ 0` (zero disables a break); counts `≥ 1`. Sensible maxima
reject typos: any single interval ≤ **8 hours**, total sessions ≤ **24**,
sessions-before-long-break ≤ **12**. Exactly one configuration may be the
default; `ConfigurationRepository.setDefault` clears the flag on all others.
Seeding creates the default configuration only when the store is empty, so it is
idempotent across relaunches and never overwrites a user's configurations.

**Note.** The engine's `PomodoroConfigurationSnapshot` still clamps values as a
last line of defence (ADR-005); that is independent of this user-facing
validation, which reports rather than mutates.

---

## ADR-016 — A legacy V1 on-disk store is rebuilt, not field-migrated

**Context.** Milestone 2 evolves the schema (V1 → V2): `FocusSession.status`
becomes `SessionStatus`, `SessionInterval` gains a status and recovery anchors
(and drops `isCompleted`/`outcome`), and `PomodoroConfiguration` gains
`isDefault`. Milestone 1, however, persisted **no** durable session/interval data
— its UI drove an in-memory engine — so the only stored row was an idempotently
re-seeded default configuration.

**Decision.** Because there is no user data contract to preserve, we do not carry
a faithful V1 model definition or a field-by-field migration stage (which would
mean duplicating the old `@Model` classes for zero real data). `TimeFrameSchemaV2`
is the current schema; `PersistenceController.makeContainer` opens the on-disk
store and, if a legacy store is incompatible, **rebuilds it once** and continues
with real on-disk persistence (rather than silently degrading to in-memory). The
only thing lost is the re-seedable default configuration.

**Revisit if.** Once real user data ships, future versions must append their
`VersionedSchema` and a concrete (lightweight or custom) `MigrationStage` to
`TimeFrameMigrationPlan` instead of rebuilding.

---

## ADR-017 — Native sidebar navigation; views observe the coordinator

**Context (Milestone 3).** The functional foundation needed a real, usable macOS
UI. The app has five areas (Today, Timer, Configurations, History, Settings) and
must feel native, not like a stretched iPhone app.

**Decision.** The root is a `NavigationSplitView` with a sidebar `List` bound to
an `AppSection` selection; the detail column renders the selected area. Every
screen is a thin SwiftUI layer that **observes the shared `@Observable
SessionCoordinator`/`TimerEngine`** and reads persisted data via `@Query` — there
is no second source of truth for the session, timer, phase, interval, or
remaining time. Domain actions are sent to the coordinator; persistence goes
through the existing repositories (views never touch `ModelContext` directly).

**Consequences.** The layering `SwiftUI → SessionCoordinator → {TimerEngine,
Repositories} → SwiftData` is preserved. The UI holds no timer state. The
countdown is refreshed for display by a `TimelineView(.periodic)` that re-reads
`engine.remaining` each second — a *display* cadence, never the authoritative
time (which stays timestamp-derived in the engine). No SwiftData write happens on
a timer tick; persistence remains event-driven through the coordinator.

---

## ADR-018 — Session setup is a per-run value, separate from the saved configuration

**Context.** A run needs a task name and a session count that may differ from the
configuration's default — without editing the saved configuration.

**Decision.** Setup input is modelled by a pure `SessionSetupDraft` (task name +
`totalSessions`). Starting a run calls `SessionCoordinator.startSession(
configuration:taskName:totalSessions:)`, where the count override is applied to a
**value snapshot** (`PomodoroConfigurationSnapshot.overriding(totalSessions:)`)
only. The relationship is strictly one-directional: `Saved Configuration →
Session Start Options → FocusSession`. A task name is required (trimmed,
non-empty) before Start is enabled; no persisted running session is created until
Start is confirmed.

**Consequences.** Changing the run's session count never mutates the stored
`PomodoroConfiguration`. The plan preview shown before starting is generated from
exactly the same snapshot the coordinator will run, so preview and reality match.

---

## ADR-019 — History preserves a configuration-name snapshot (schema V3)

**Context.** Historical *timing* is already frozen per interval
(`SessionInterval.plannedDuration`/`phase`), so edits to a configuration never
change a past session's durations. But the configuration **name** shown in
History came from the live relationship, which nullifies on delete and changes on
rename — so history could silently change or lose the name.

**Decision.** `FocusSession` gains `configurationName`, captured at session
creation (`SessionRepository.createSession`). History displays this frozen name
(`displayConfigurationName` falls back to the live relationship, then a neutral
label, for sessions created before the field existed). This is schema **V3**.
Consistent with ADR-016, the store references the *current* model types and does
not carry frozen per-version `@Model` copies, so V3 has **no field-level
migration stage**: an older incompatible on-disk store is rebuilt by
`PersistenceController` (the same throw-and-rebuild path that handled V1→V2),
losing only the re-seedable default configuration and dev-only prior sessions.

**Consequences.** History rows and detail remain historically accurate through
configuration renames and deletions. In-memory test stores are created fresh at
V3, so tests never migrate. **Revisit if** real user data must survive an upgrade
— then add a frozen `VersionedSchema` copy and a concrete `MigrationStage`.

---

## ADR-020 — Keyboard shortcuts are scoped to the active-run controls

**Context.** Standard macOS shortcuts must not interfere with text editing (the
task field) yet should make the timer fast to drive.

**Decision.** Shortcuts: **⌘↩** Start (setup) / Start New Session (completion);
**Space** Pause/Resume; **Esc** Stop (`.cancelAction`); **R** Restart; **→**
Skip. The bare-key shortcuts (Space, R, →) are attached **only** to
`TimerControls`, which is rendered solely while running/paused — never alongside
the task `TextField`. Start uses ⌘↩ (a modified combo) so it is safe to trigger
from a focused text field. Escape doubles as the standard sheet/dialog dismissal.

**Consequences.** No shortcut collides with text entry, because the screens that
show a text field do not mount the bare-key shortcuts. The set is documented in
Settings and in `docs/12-CORE-UI.md`.

---

## ADR-021 — `TaskTemplate` is a reusable session-start definition (schema V4)

**Context (Milestone 4).** Users repeat kinds of work ("Research", "Coding") and
want to configure a task once and start it repeatedly, without re-entering a task
name, configuration, and session count each time.

**Decision.** Add a `TaskTemplate` `@Model` (name, taskName, configuration
reference, defaultTotalSessions, isDefault, timestamps). A template is a *starting
point*, explicitly **not** a `FocusSession` and **not** a historical record. It
carries no interval/timeline data. This is schema **V4** (`TimeFrameSchemaV4`);
consistent with ADR-016/019 the store references current model types and an
incompatible older on-disk store is rebuilt rather than field-migrated (no
migration stage).

**Consequences.** The intended chain `TaskTemplate → PomodoroConfiguration →
SessionSetupDraft → FocusSession → SessionInterval` is realised without touching
the engine or the session system.

---

## ADR-022 — Template references a configuration; it does not copy its values

**Decision.** `TaskTemplate.configuration` is a to-one **reference** to
`PomodoroConfiguration` (mirroring `FocusSession.configuration`), never a copy of
its durations/counts. Only `defaultTotalSessions` — a per-run seed, not a rhythm
value — lives on the template.

**Consequences.** Editing a configuration (e.g. 50/10/30 → 60/15/30) changes what
**future** sessions started from the template use, with no template edit required.
Already-started sessions are unaffected (their plan is frozen per interval).
Configuration values are never duplicated or allowed to drift.

---

## ADR-023 — Template edits never mutate historical or running sessions

**Context.** A session started from a template must represent what the user
actually started, independent of later template changes.

**Decision.** Starting from a template **copies** the template's values into a
`SessionSetupPrefill` → the setup screen → the existing
`SessionCoordinator.startSession`, which builds the `FocusSession` from a value
snapshot. The session never holds a reference to the template and never reads it
again. A per-run session-count change edits only the run's snapshot, never
`TaskTemplate.defaultTotalSessions` (same principle as ADR-018).

**Consequences.** Editing a template's task name, configuration, or session count
after a run has started leaves that run — and its History entry — unchanged.
Verified by the Milestone 4 independence tests.

---

## ADR-024 — Deletion rules: template delete keeps sessions; config delete keeps templates

**Decision.** Deleting a `TaskTemplate` removes only the template — historical
sessions, their intervals, and the configuration are untouched (a template is only
a reusable definition). Deleting a `PomodoroConfiguration` **nullifies** the
reference on its templates (`PomodoroConfiguration.taskTemplates`, delete rule
`.nullify`): the template survives, is shown as "Configuration unavailable", and
cannot start until the user chooses a new configuration. Templates are never
auto-deleted and never silently reassigned. The configuration delete confirmation
reports how many templates (and past sessions) reference it.

**Consequences.** No historical data is ever lost by managing templates, and a
template can always recover from a deleted configuration.

---

## ADR-025 — Template start reuses the single session-start path; optional default template

**Decision.** A template does **not** create a `FocusSession` from the view. "Start"
queues a `SessionSetupPrefill` (task name, configuration id, session count) and
switches to the Timer setup screen, which fills its editable fields and then runs
the **existing** `startSession(configuration:taskName:totalSessions:)`. There is no
second session-start implementation. Start is blocked while a session is already
active, so no duplicate active session is created. A **default template** is
supported but optional: at most one (`TaskTemplateRepository.setDefault` clears the
flag on all others; `clearDefault` removes it), providing a quick-start affordance
without forcing the concept on the product.

**Consequences.** The whole timer/session lifecycle (pause/resume/skip/complete,
persistence, recovery, History) applies unchanged to template-started sessions. The
per-run override path (ADR-018) is reused verbatim.

---

## ADR-026 — SessionPlan is a planning entity, not an execution entity

**Context.** Milestone 5 introduces a way to design multi-session plans before
running them. This must not become a second timer.

**Decision.** `SessionPlan` (and its owned `SessionPlanItem`s) is a **planning**
model only: it carries no timer state, is never run directly, and is freely
editable. Executing a plan freezes it into an immutable value snapshot that runs
through the existing `SessionCoordinator` → `TimerEngine` → `FocusSession` path.
Generation of the initial timeline makes the **trailing break optional** (off by
default) — the planner never forces a break after the final focus, so a plan can
end on focus (important for future Calendar events).

**Consequences.** No `PlannerSession`/`PlannerTimerEngine`; the whole session
lifecycle (pause/resume/skip/complete, persistence, recovery, History) applies to
plan-started sessions unchanged. See `docs/14-SESSION-PLANNER.md`.

---

## ADR-027 — SessionPlanItem represents immutable execution intent; reuse TimerPhase

**Decision.** A `SessionPlanItem` stores its **own** `duration` (seeded from a
configuration, then independently editable) rather than deriving it live, and its
`order` is explicit and normalized on save (never inferred from array position
alone). The item "type" reuses the existing `TimerPhase` enum (focus / shortBreak /
longBreak) rather than a parallel enum, because `TimerPhase` is already the shared
vocabulary of the engine, the generated plan, and the persisted `SessionInterval`.

**Consequences.** Editing a configuration's durations never changes a saved plan
item; an item maps directly to a `PlannedInterval`/`SessionInterval` with no
translation. Reordering preserves item identity (matched by `id`) and creates no
duplicates.

---

## ADR-028 — Plan execution uses an immutable value snapshot; the engine plan is renamed

**Context.** A running session must not change when the saved plan or its
configurations are later edited or deleted, and a plan may span multiple
configurations that the single-configuration `FocusSession.configuration` cannot
represent.

**Decision.** Starting a plan builds a `SessionPlanExecutionSnapshot` — an
immutable, `Sendable`, SwiftData-free value carrying the task name and ordered
intervals (phase, duration, per-focus configuration **name**). `startPlan` runs the
engine from this snapshot and persists a `FocusSession` whose intervals each freeze
their `plannedDuration` and a new `SessionInterval.configurationName`; the session
holds **no** live configuration reference. To free the name `SessionPlan` for the
planning model, the engine's execution-plan value type is renamed `SessionPlan` →
`IntervalPlan` (a pure rename — ADR-031).

**Consequences.** Editing/deleting the plan or a configuration after start cannot
affect the running or historical session. Multi-configuration plans record which
configuration each focus used, keeping History accurate without a live reference.
The `FocusSession` model needed only one additive field (`SessionInterval.
configurationName`), not a parallel session type.

---

## ADR-029 — Plan deletion never deletes historical or running sessions

**Decision.** `SessionPlan.items` cascade-delete, so deleting a plan removes its
items — but a plan has **no** relationship to `FocusSession`, so deleting it never
touches a running session, a historical session, its intervals, or any
configuration. Deleting a configuration **nullifies** its plan-item references
(`PomodoroConfiguration.planItems`, delete rule `.nullify`): the plan survives, is
shown as incomplete, and cannot start until re-assigned.

**Consequences.** No historical data is ever lost by managing plans; a plan can
always recover from a deleted configuration. Verified by `SessionPlanRepositoryTests`
and `SessionPlanExecutionTests`.

---

## ADR-030 — Plans support multiple configurations (per focus item)

**Decision.** Configuration is stored **per focus item**, not per plan; there is no
`plan.configuration`. A plan can therefore mix configurations (e.g. Research focus
and Writing focus). "Create Plan" from a template or configuration seeds an initial
single-configuration plan but only *reads* the source — saving creates an
independent `SessionPlan` and never mutates the template or configuration.

**Consequences.** The planner is ready for advanced multi-configuration workflows;
the execution snapshot preserves each focus interval's configuration name, and the
session-level summary reports "Multiple configurations" when they differ.

---

## ADR-031 — Engine execution plan renamed `SessionPlan` → `IntervalPlan`

**Context.** The persisted planning model must be named `SessionPlan` (ADR-026),
but that name was already taken by the engine's ordered-intervals value type.

**Decision.** Rename the engine value type `SessionPlan` → `IntervalPlan`
(file `Timer/IntervalPlan.swift`), and the Timer setup preview view
`SessionPlanPreview` → `IntervalPlanPreview`. Purely mechanical; no behaviour
changes. The rename also clarifies the layering: the user designs a **session
plan**, the engine runs an **interval plan**.

**Consequences.** All existing engine/persistence code and tests updated; the 138
pre-existing tests continue to pass. The engine itself was not otherwise modified.

---

## ADR-032 — Calendar is an isolated, optional integration layer

**Context.** Milestone 6 adds Apple Calendar/EventKit support. EventKit must not
leak into the timer engine or the core domain, and the feature must be optional.

**Decision.** A dedicated `Services/Calendar/` layer sits beside the execution core.
`EventKitCalendarService` is the **only** file that imports EventKit; it hides
behind a `CalendarService` protocol that trades solely in pure value types
(`CalendarEventDraft`, `CalendarEventReference`, `CalendarDescriptor`,
`CalendarAuthorizationStatus`, `CalendarIntegrationError`). `CalendarCoordinator`
(`@MainActor @Observable`) orchestrates authorization and event lifecycle. No
`EKEvent`/`EKCalendar`/`EKEventStore` ever escapes the adapter. `TimerEngine` and the
timer/persistence domain import no EventKit.

**Consequences.** The whole integration is independently testable with a
`FakeCalendarService`; the timer builds and runs identically whether or not Calendar
is configured. See `docs/15-CALENDAR-INTEGRATION.md`.

---

## ADR-033 — `CalendarEventDraft` is framework-independent

**Decision.** The core event representation (`CalendarEventDraft`) and its inputs
(`CalendarPlanContext`) are pure `Sendable` values with no EventKit types. The
`CalendarEventGenerator` is a pure, deterministic function producing drafts; the
adapter is the sole translator into `EKEvent`.

**Consequences.** Event generation (titles, notes, times, styles) is unit-tested
without a real Calendar; the same drafts drive both the manual plan flow and the
live session flow.

---

## ADR-034 — Calendar event identity uses stable Time Frame ids

**Context.** Many events can share a title; identifying Time Frame events by title
would be unsafe and would cause duplicates.

**Decision.** Associations are keyed by a stable Time Frame id — the `FocusSession`
id for a live session, the `SessionPlan` id for a manually added plan — stored in a
`CalendarEventRecord` that pairs the owner id with the created
`CalendarEventReference`(s). Re-adding a plan replaces its prior events; a single run
never produces duplicates.

**Consequences.** Start → Stop → Start produces one event per (distinct) run, never
duplicates for one run; duplicate detection needs no title matching.

---

## ADR-035 — Calendar failure never blocks timer execution

**Context.** A permission error, an EventKit failure, or a missing calendar must
never stop or corrupt a running Pomodoro session.

**Decision.** The engine emits pure `SessionLifecycleEvent`s from `SessionCoordinator`
at meaningful transitions only (never on a tick). `CalendarCoordinator` subscribes,
reads the model on the main actor, and **defers** all calendar work onto a fresh
main-actor task that runs after the timer path has returned. Every calendar failure
is caught, logged, and surfaced as a non-blocking status — it is never rethrown
toward the engine. The engine imports no EventKit and has no calendar dependency.

**Consequences.** Verified by `CalendarTimerIndependenceTests`: the timer
starts/runs/pauses/stops when create/update fail or permission is denied. Calendar is
a representation derived from the engine's authoritative timestamps, never the source
of truth.

---

## ADR-036 — Live sessions use a single event; a minimal, documented ownership model

**Context.** Keeping *per-interval* events correct across mid-interval pause, resume,
and skip for a *live* timer is complex and error-prone.

**Decision.** A live session always creates **one whole-session event** anchored to
the **actual** start time (never a fabricated one — §31), and keeps it in sync by
adjusting **only its end date** at meaningful transitions. On stop the event is kept
(end = actual stop time), never deleted (§35). The user-chosen *event style* (single
vs per-interval) applies to the **manual plan add** flow, where the timeline is a
static projection. Ownership: Time Frame owns the association and the live event's
end time; the user owns the calendar, title, notes, and location — so live sync never
overwrites user-edited fields (§37/§38).

**Consequences.** Pause/resume/stop/completion stay correct and cheap; per-interval
live events are deferred. An externally deleted event is forgotten, not silently
recreated (§55/§79).

---

## ADR-037 — Calendar settings and associations persist outside SwiftData

**Context.** Milestone 6 needs to persist a few preferences and the plan/session ↔
event associations. Adding a SwiftData `@Model` would mean a schema bump (V6),
migration, and the store-rebuild risk noted below — for lightweight, non-relational
metadata.

**Decision.** Persist Calendar **settings** (`CalendarSettings`) and **associations**
(`CalendarEventRecord`, keyed by owner id) in `UserDefaults` via small observable
stores, not SwiftData. The milestone explicitly permits a simpler, documented
approach for lightweight data (§22/§46). No `EKEvent`/`EKCalendar` is persisted —
only identifiers. The schema stays **V5**; no migration is introduced.

**Consequences.** Core timer models stay free of any Calendar/EventKit state; there
is no schema migration to verify and no rebuild risk. The stores are fully testable
with a scratch `UserDefaults` suite.

---

## ADR-038 — Notifications are an isolated, optional integration layer

**Context.** Milestone 7 adds macOS local notifications. Like Calendar, they must be a
representation of the timer, never a dependency of it.

**Decision.** All UserNotifications code lives in `Services/Notifications/`, and
`import UserNotifications` appears in **exactly one file** — `UserNotificationService`,
the adapter and notification-center delegate. Everything else (coordinator, content
generator, scheduler, preferences, value types, tests) trades only pure Swift values;
no `UN*` type escapes the adapter. `NotificationCoordinator` subscribes to the existing
pure `SessionLifecycleEvent` seam via the app's fan-out closure, exactly as
`CalendarCoordinator` does, and imports neither UserNotifications nor SwiftData.

**Consequences.** The core timer and domain remain free of UserNotifications; the
adapter is swappable with `FakeNotificationService` for deterministic tests. Verified by
grep (only the adapter imports the framework) and the notification test suites.

---

## ADR-039 — The TimerEngine remains authoritative for notification timing

**Context.** A notification system could easily drift into a second source of timing
truth.

**Decision.** The engine owns phase, interval, target end, remaining time, and every
transition. `NotificationCoordinator` only *represents* those transitions; it never
reconstructs timer state from notifications and never re-derives Pomodoro rules (long
breaks come from the engine's plan — §73). The engine is unchanged; `SessionCoordinator`
gained only a read-only `currentLifecycleContext()` accessor (ADR-043).

**Consequences.** There is no parallel timer to keep in sync; correctness of *time* stays
in one place, and notifications are always derived from authoritative timestamps.

---

## ADR-040 — Schedule the whole remaining timeline of transitions, never per tick

**Context.** §21/§55/§72 lean toward "schedule the next transition," but §22 requires
notifications to fire when the app is backgrounded or fully closed, and the existing
lifecycle seam does **not** emit on an automatic focus→break advance (only on
start/pause/resume/skip/stop/complete). "Next-only" scheduling would therefore miss every
transition after the first once the app is suspended.

**Decision.** On each scheduling trigger (start/resume/skip/recover), schedule **one
notification per upcoming interval-start boundary** for the session at once — anchored to
the engine's authoritative timeline — and cancel + reschedule the whole set on the next
trigger. Never schedule on a timer tick. The count is bounded by the session's interval
count, so the queue stays small (§72). For a single-focus session this is exactly one
upcoming transition (§55); for a full 4-session plan it is seven.

**Consequences.** Transitions fire correctly even when the app is closed, without
per-tick churn. Verified by `NotificationScheduleBuilderTests` (one request per boundary,
cumulative fire dates) and `NotificationCoordinatorTests` (no per-tick scheduling).

---

## ADR-041 — Completion is delivered from the event, not pre-scheduled

**Context.** A pre-scheduled completion notification would race with the `.completed`
event (duplicate banners) and could fire stale after an early finish (skip-to-complete).

**Decision.** Do **not** pre-schedule completion. Deliver it immediately from the
`.completed` lifecycle event with a stable id and a coordinator guard, so it can never
duplicate (§30). Do not send a catch-up completion on relaunch for a session that finished
while the app was closed — recover state, cancel stale, and schedule only future
transitions (§32). The last *transition* notification (e.g. the final break starting)
still fires from its schedule when closed.

**Consequences.** No duplicate completion banners and no stale "finished" notifications;
completion is shown when the app is open at the finish (the common case).

---

## ADR-042 — A notification failure can never block the timer

**Context.** The milestone's central guarantee (mirrors ADR-035 for Calendar).

**Decision.** Every scheduler operation is deferred onto a fresh main-actor task (so the
timer path has returned) and wrapped so no failure escapes toward the engine. A
scheduling failure, denied permission, cancellation failure, or an action for a vanished
session becomes a logged, non-blocking status — never a throw into the timer.

**Consequences.** The session starts/runs/pauses/resumes/skips/stops/completes exactly as
if notifications did not exist. Verified by `NotificationTimerIndependenceTests`, which
also proves Calendar and Notifications never affect each other (§63).

---

## ADR-043 — Notification actions route through SessionCoordinator; a read-only context accessor

**Context.** A notification action must control the timer, and the notification layer must
be able to (re)synchronize with the live session on relaunch and on toggle-on — without
coupling to, or mutating, the engine.

**Decision.** A received action is parsed to a pure `ReceivedNotificationAction`, validated
by the pure `NotificationActionResolver` (§40), and routed back through
`SessionCoordinator` (`pause`/`resume`/`skip`/`stop`) — never applied to the engine
directly (§37). To reschedule outside of an event, `SessionCoordinator` exposes one
read-only `currentLifecycleContext()`; it imports nothing from any integration.

**Consequences.** All timer mutation stays behind the coordinator's guarded transitions;
an action for a missing/mismatched/finished session is ignored gracefully. The engine is
unchanged.

---

## ADR-044 — Notification preferences persist in UserDefaults, no schema change

**Context.** Notifications need a few lightweight preferences (mirrors ADR-037 for
Calendar).

**Decision.** Persist `NotificationPreferences` (a pure `Codable`/`Sendable` value) in
`UserDefaults` via a small observable store. No SwiftData `@Model`, no migration; the
schema stays **V5**. No UserNotifications object is ever persisted (§46/§78/§79).

**Consequences.** Core timer models stay free of any notification state; the store is
fully testable with a scratch `UserDefaults` suite.

---

## ADR-045 — The menu bar is a presentation/control surface over the one SessionCoordinator

**Context.** Milestone 8 adds a macOS `MenuBarExtra`. The overriding risk is that it
becomes a *second* timer — its own countdown loop, its own sequencing, its own state.

**Decision.** The menu bar observes the **same** `SessionCoordinator`/`TimerEngine` the
main window uses (ADR-049). A thin `MenuBarCoordinator` (`@MainActor @Observable`) holds a
reference to that one coordinator and its only owned state is the visibility preference; it
is an observer/adapter, never a coordinator of its own. The `MenuBarExtra` scene lives
alongside the existing `WindowGroup` and `Settings` usage in `time_frameApp`.

**Consequences.** There is exactly one authoritative timer with several presentation
surfaces (SwiftUI window, Calendar, Notifications, menu bar). Verified by
`MenuBarPresentationTests`/`MenuBarControlTests`, which drive the real engine.

---

## ADR-046 — The menu bar never owns timer state; it renders a pure projection

**Context.** The menu bar must show a live countdown without decrementing a counter of its
own (§10/§46/§47).

**Decision.** A pure, value-typed `MenuBarPresentationState` (`Sendable`, `Equatable`) is
*derived from* the authoritative engine on demand (`init(coordinator:)`). The status title
and popover read it; a `TimelineView` re-derives it ~1 Hz **only while running** so the
countdown ticks — the `TimelineView` merely schedules a repaint, it never holds time.
Nothing menu-bar-related is persisted (no `menuBarRemaining`/`menuBarPhase`), and the
projection never queries SwiftData (in-memory timestamp math only).

**Consequences.** The menu bar cannot drift from the engine, cannot become a second source
of truth, and stays lightweight (no per-second database work — §87/§89). Sleep/wake and
relaunch need no menu-bar-specific handling: it simply re-reads the engine (ADR-014).

---

## ADR-047 — Menu bar controls route through SessionCoordinator

**Context.** Pause/Resume/Skip/Stop/Restart and "start a new session" must be reachable
from the menu bar without touching engine internals (§20).

**Decision.** `MenuBarCoordinator.pause()/resume()/skip()/stop()/restart()` delegate
straight to the matching `SessionCoordinator` method (and `prepareForNewSession()` for a
fresh run). Each is a guarded no-op when it doesn't apply — the engine already ignores
out-of-state messages — so "pause with no session" or "resume when completed" are safe.
Starting from the menu bar never builds a second start flow: it opens the main window's
existing `SessionSetupView` (§13/§21).

**Consequences.** All timer mutation stays behind the coordinator's guarded transitions;
the menu bar can never corrupt a run. Verified by `MenuBarControlTests`.

---

## ADR-048 — Menu bar visibility/countdown persist in UserDefaults, no schema change

**Context.** The only durable menu-bar state is the "Show in Menu Bar" (and "Show
countdown") preference (§26/§46/§63/§64).

**Decision.** Persist `MenuBarPreferences` (a pure `Codable`/`Sendable` value) in
`UserDefaults` via a small observable store, mirroring ADR-037/044. No SwiftData `@Model`,
no migration; the schema stays **V5**. `MenuBarExtra(isInserted:)` is bound to the
preference, so turning the menu bar off removes the status item while the timer, Calendar,
and Notifications keep working untouched.

**Consequences.** Core models stay free of UI state; the store is fully testable with a
scratch `UserDefaults` suite (`MenuBarPreferencesTests`).

---

## ADR-049 — One application-level SessionCoordinator shared by the main window and menu bar

**Context.** With both a `WindowGroup` and a `MenuBarExtra`, the catastrophic failure mode
is two coordinators (one per surface) driving two engines (§69).

**Decision.** `time_frameApp` owns the single `SessionCoordinator` (and the Calendar,
Notification, and `MenuBarCoordinator` adapters) in `@State`, created once in `init`. Both
the `WindowGroup` content and the `MenuBarExtra` are handed that same instance. Reopening
the (id'd `"main"`) window creates a fresh `ContentView` but reuses the app-owned
coordinator, so closing the main window never stops the timer or spawns a new one
(§27/§28). The menu bar steers the existing window through a tiny `AppNavigation` seam
(request a section) plus `openWindow(id:)` — no second window implementation, no duplicate
Settings/History.

**Consequences.** Exactly one timer coordinator and one `ModelContainer` for the app's
lifetime; the menu bar remains alive and correct while the main window is closed. Verified
by `MenuBarRecoveryTests` and `MenuBarIndependenceTests`.

---

## ADR-050 — Liquid Glass is a presentation-layer concern and must not affect domain behavior

**Context.** Milestone 9 introduces the macOS 27 Liquid Glass visual identity across every
screen. The catastrophic failure mode for a *visual* milestone is a styling change that
reaches into timer, session-sequencing, persistence, Calendar, or Notification logic (§62/§97).

**Decision.** All Milestone 9 changes live strictly in the presentation layer: the new
`Support/DesignSystem/` tokens (`TimeFrameDesign.swift`, `TimeFrameGlass.swift`), the `Views/`
tree, and `time_frameApp`'s scene *chrome* only (a `.windowToolbarStyle(.unified)`). No file
under `Timer/`, `Services/`, or `Models/` was modified. The design system imports none of the
domain and contains no timing, sequencing, or persistence logic. The macOS 27 SDK's native
`glassEffect`/`GlassEffectContainer`/`.glass`/`.glassProminent` APIs (verified present in
`SwiftUICore`) are used directly with no availability fallback, per CLAUDE.md's "no
back-deployment abstractions" rule.

**Consequences.** The `TimerEngine` and `SessionCoordinator` are byte-for-byte unchanged; the
full 290-test suite passes unchanged. The same injected clock + configuration produce the same
engine behavior before and after the redesign (§95).

---

## ADR-051 — Glass surfaces are used selectively to establish hierarchy, not applied globally

**Context.** Liquid Glass is expensive and loses meaning if every surface is glass (§7/§8/§58).

**Decision.** Glass is reserved for floating/interactive/primary control regions: the timer
transport group (a `GlassEffectContainer` of `.glass`/`.glassProminent` buttons), the primary
launch/Save actions (`.glassProminent`), the Today "current session" card, the Completion
summary, and the menu-bar transport. Ordinary informational content uses a quiet, non-glass
surface (`tfQuietSurface`, a subtle system fill) — list rows, summary cards, and previews are
deliberately *not* glass. `GlassEffectContainer` groups sibling glass so they share a sampling
region (glass cannot sample glass); containers are never nested. The menu-bar popover keeps the
system `MenuBarExtra(.window)` background and adds no extra nested glass surface behind its
glass buttons (§30).

**Consequences.** Glass consistently signals "this is a control / this is important," giving the
app hierarchy without visual noise or large blur regions.

---

## ADR-052 — Visual state uses semantic design tokens instead of hard-coded values

**Context.** Ad-hoc colours, spacings, and radii scattered through views drift out of sync and
break Light/Dark adaptation (§10/§46/§79).

**Decision.** A single token system carries the visual language: `TFSpacing`, `TFRadius`,
`TFMotion`, and `TFPalette` (semantic colours — `focus`, `shortBreak`, `longBreak`, `running`,
`paused`, `completed`, `warning`, `destructive` — built only from system colours and the app
accent, never hard-coded RGB). `StatusPresentation`'s phase/status tints route through
`TFPalette`, so semantic colour has one source. Essential state is always paired with a label
and/or icon — colour is never the sole carrier of meaning (§48).

**Consequences.** Colours adapt automatically to Light/Dark and accessibility settings; the
"Focus/Break/Paused/Completed" language is consistent everywhere and legible to colour-blind
users.

---

## ADR-053 — Animations are presentation-only and never participate in timer correctness

**Context.** Animation must communicate state changes without becoming a source of timing or
regressing the "no second timer" invariant (§38/§39/§53/§96).

**Decision.** Motion is centralised in `TFMotion` and applied through a Reduce-Motion-aware
`tfAnimation(_:value:)` modifier that disables decorative animation under
`accessibilityReduceMotion` while the underlying state change still happens instantly.
Animations key on discrete state (phase, paused) — never on the per-second countdown. The
countdown remains a `contentTransition(.numericText())` over an engine-derived value inside a
repaint-only `TimelineView`; no new `Timer`, `Task.sleep`, `asyncAfter`, or counter decrement
was introduced (audited, §96). The timer number is never scale/opacity/layout-animated each
second.

**Consequences.** Transitions feel calm and native, respect Reduce Motion, and cannot affect
the authoritative remaining time. The four `TimelineView` usages remain exactly the pre-existing
repaint mechanisms.

---

## ADR-054 — Statistics are a read-only projection of history, not a persisted analytics store (Milestone 10)

**Context.** Milestone 10 adds productivity analytics (focus time, completion rate, daily and
configuration breakdowns, trends). This must answer rich questions without becoming a second
timer, a second source of session state, or a second database, and without regressing the "one
timer / one historical source of truth" invariant.

**Decision.** Statistics are a **read-only projection** of the existing persisted history
(`FocusSession`/`SessionInterval`). A `@MainActor` `StatisticsRepository` performs a single fetch
and maps rows into pure, `Sendable` `SessionStatInput` values; a `nonisolated`
`StatisticsAggregator` deterministically produces an immutable `StatisticsSnapshot` from those
values, the selected `StatisticsDateRange`, and the user's `Calendar`. Nothing is persisted:
snapshots are recomputed on demand and are reproducible from history alone. Attribution is
consistent and documented — session-level metrics by `startedAt`, interval-level metrics by a
**completed** interval's end instant — so a midnight-crossing session banks each interval on the
correct local day, and configuration grouping uses the **frozen** name so a rename/delete never
rewrites history (reuses ADR-019/028). No file under `Timer/`, `Services/` (except the new
`Services/Statistics/`), or `Models/` changed for statistics, and the SwiftData schema stays
**V5** (every metric derives from existing fields). `TodayView` was refactored to call the same
aggregator over the `.today` period, so there is exactly one aggregation implementation.

**Consequences.** The statistics engine is fully unit-testable without a store or UI and can never
affect timer correctness. There is no persisted derived data to keep in sync and no migration.
Historical attribution is limited to the frozen configuration name and the task name — sessions do
not persist a durable template/plan reference, so template/plan analytics are intentionally
deferred to a future data-model milestone rather than fabricated (see `docs/19-STATISTICS.md` §9).

---

## ADR-055 — WidgetKit surfaces are a read-only App Group projection, never a second timer (Milestone 11)

**Status.** Accepted (Milestone 11).

**Context.** Milestone 11 adds native macOS 27 WidgetKit surfaces. A widget runs in a
separate process and cannot observe the live `TimerEngine`. The risk is that a widget
becomes a second source of truth — running its own clock, decrementing seconds, or
reconstructing Pomodoro sequencing — diverging from the one authoritative timer.

**Decision.** The widget renders a **read-only projection** the app writes, and nothing more:

- `TimerEngine` → `SessionCoordinator` remain authoritative. A `WidgetProjectionWriter`
  observes the **same** `SessionLifecycleEvent` fan-out as Calendar/Notifications (plus a
  new additive `SessionCoordinator.onMeaningfulTransition` hook fired only where
  `reconcileIfChanged()` already writes — auto interval boundaries, never a per-tick),
  maps authoritative state to an immutable `WidgetProjection`, writes it to an **App Group**
  `UserDefaults` suite (`group.abirbarman.com.time-frame`), and reloads via `WidgetCenter`.
- The widget extension imports **no** SwiftData and no app model layer, never instantiates
  `TimerEngine`/`SessionCoordinator`, and creates **no** `Timer`, timer publisher,
  `DispatchSourceTimer`, or async countdown loop. Its `TimelineProvider` reads the last
  projection and asks a pure `WidgetTimelinePolicy` for entries + reload policy.
- The live countdown is SwiftUI's date-relative `Text(timerInterval:)` between the
  projection's frozen `intervalStartedAt`/`intervalPlannedEndAt` anchors — a repaint, not a
  clock (same shape as the Menu Bar's `TimelineView`, ADR-046). Paused shows the projection's
  **frozen** remaining and schedules **no** tick.
- The shared projection value types live in `Shared/`, compiled into **both** the app and
  the widget via explicit build membership (Foundation-only), so there is one source of
  truth for the DTO without sharing the app model layer. Deep links use a neutral
  `timeframe://…` scheme mapped to the **existing** `AppSection`s; unknown URLs are ignored.
- Configuration is a `StaticConfiguration` only — **no** App Intents command/control this
  milestone. **No SwiftData schema change (stays V5).** Preferences/state that the widget
  needs live in the App Group projection, never in SwiftData.

**Consequences.** A widget write can never stop, corrupt, or slow the timer (every path is a
best-effort no-op on failure); a missing App Group or corrupt payload degrades to a stable
`.unavailable` widget, never a crash. The projection is fully unit-testable (mapping,
timeline policy, serialization/fallback, store, deep links) plus a static source-scan
invariant test that fails if the widget target ever imports SwiftData or references the
engine/coordinator/a timer loop. The full suite grew **341 → 377 tests** (60 → 67 suites),
all passing, 0 warnings. See `docs/20-WIDGETKIT.md`.

---

## ADR-056 — App Intents are a thin integration layer routed exclusively through `SessionCoordinator` (Milestone 12)

**Context.** Milestone 12 exposes Time Frame to Shortcuts and Siri. The temptation with App
Intents is to let an intent "just start a timer" or mutate SwiftData directly. That would
create a second timer authority and a second start path.

**Decision.** Every intent is a **thin command/query** that resolves its inputs through the
existing repositories and then calls the **existing** coordinator operations —
`startSession` / `startPlan` / `pause` / `resume` / `skip` / `restart` / `stop` — via a single
`@MainActor AppIntentSessionActions` helper. No intent constructs a `FocusSession`, touches a
`ModelContext` write, or introduces any timer primitive (`Timer`, `Task.sleep`, `asyncAfter`,
a countdown, a decrement). Start-from-template reuses the exact UI chain
`TaskTemplate → SessionSetupPrefill → SessionCoordinator.startSession`; start-from-plan hands
the plan's frozen `executionSnapshot` to `SessionCoordinator.startPlan`. There remains exactly
**one** `TimerEngine` and **one** `SessionCoordinator`.

**Consequences.** The App Intents surface is another safe presentation/integration surface,
not a new engine. An intent failure is isolated (it throws before any coordinator call, or the
coordinator's own guards reject it), so it can never corrupt or partial-start the timer —
proven by `IntentFailureIsolationTests`. All intent logic is unit-testable by driving
`AppIntentSessionActions` against an in-memory coordinator with a mock clock, with no Siri or
Shortcuts dependency. **No schema change (stays V5).**

## ADR-057 — App Entities are resolved through the existing repositories with stable UUID identity

**Context.** Shortcuts needs to offer the user's real templates, plans, and configurations as
selectable parameters, and to re-resolve a previously chosen one on later runs.

**Decision.** `TaskTemplateEntity`, `SessionPlanEntity`, and `ConfigurationEntity` are
immutable value projections whose `id` is the model's **stable `UUID`** (never an array index).
Their `EntityStringQuery`s fetch through the **existing** repositories (a targeted
`template(with:)` / `plan(with:)` / `configuration(with:)` fetch added alongside the existing
`plan(with:)`), map to frozen display strings, and return `nil`/empty for deleted records —
never a throw or a leaked internal detail. A read-only `CurrentSessionEntity` (singleton id)
projects the live session for "get the remaining time"-style workflows and exposes **no**
control. Queries mutate nothing.

**Consequences.** A shortcut keeps working across relaunches (stable ids); a deleted
template/plan/configuration degrades gracefully. Entity queries are the only new SwiftData
readers, and they read exclusively through repositories over the app's existing container —
no arbitrary context access.

## ADR-058 — App Intent state is exposed through an immutable `AppIntentSessionState` projection

**Context.** Intents must answer "what's my status?" and phrase confirmations from the live
timer, without ever holding or re-deriving timer state.

**Decision.** A pure, Foundation-only `AppIntentSessionState` value is built from the
authoritative coordinator/engine with the **same** in-memory timestamp math as
`MenuBarPresentationState` and `WidgetProjectionMapper` — one source of truth, three read-only
projections. All user-facing phrasing lives in one pure `AppIntentDialogText` helper (the
single future-localization edit point). Intents read this snapshot and phrase it; they never
maintain a countdown.

**Consequences.** Status/dialog phrasing is fully unit-testable in isolation and stays
consistent with the menu bar and widget. The projection is additive (no consolidation rewrite
of the existing surfaces was undertaken — minimal change preferred).

## ADR-059 — Intents reach the one coordinator via `AppDependencyManager`; navigation reuses the existing deep link

**Context.** Intents run in the app process (there is no separate App Intents extension target),
but they need the app's single, already-owned `SessionCoordinator` and `ModelContainer` — not
a global singleton and not a fresh instance.

**Decision.** At launch (skipped under the unit-test host) the app registers its authoritative
`SessionCoordinator` and an `IntentDataProvider` (over the existing container) with
`AppDependencyManager`; intents and queries receive them via `@AppDependency`. The two
navigation intents (Open, Show Statistics) **reuse the existing `timeframe://` deep link** the
widgets already use — returning an `OpenURLIntent` that `ContentView.onOpenURL` maps to the
existing `AppSection` — so no second window or navigation system is created.

**Consequences.** There is one coordinator across the UI, menu bar, widgets, notifications,
calendar, and now App Intents. Registration is guarded so the test host never advertises the
live store; intent tests inject their own in-memory coordinators. **No new persistence store.**
The full suite grew **377 → 434 tests** (67 → 79 suites), all passing, 0 warnings. See
`docs/21-APP-INTENTS.md`.

## ADR-060 — CloudKit is a persistence transport, not timer authority

**Context.** Milestone 13 makes Time Frame's SwiftData store sync across a user's Apple devices
via CloudKit. The overriding risk is letting the network anywhere near the timer, which is and
must remain timestamp-authoritative (`remaining = targetEnd − authoritativeClock`, ADR-013).

**Decision.** CloudKit is a **transport below the repositories only**. `TimerEngine`,
`TimerState`, `TimerPhase`, `IntervalPlan`, and `SessionCoordinator` import no CloudKit and are
unchanged in substance (`SessionCoordinator` gains nothing CloudKit-aware). The sync itself is
**SwiftData's native mirroring** (`ModelConfiguration(cloudKitDatabase:)`) — so in fact **no
file in the project imports CloudKit at all**; there is no `CKRecord`/`CKContainer` code, no
custom sync engine, and no network call on any code path the timer touches. The iCloud UI reads
a pure `CloudSyncPresentationState` projection (like the menu-bar/widget/App-Intents
projections). No `Timer`/`Task.sleep`/`asyncAfter`/`DispatchSourceTimer`/polling was added.

**Consequences.** The timer is provably independent of sync: an import-boundary audit over
`Timer/` (and the whole tree) is clean. The widget keeps reading its **local App Group**
projection (never CloudKit), and App Intents keep routing through the one `SessionCoordinator`.
See `docs/22-ICLOUD-CLOUDKIT.md`.

## ADR-061 — Schema V6 drops `#Unique` for CloudKit; native SwiftData mirroring over manual CKRecord

**Context.** CloudKit mirroring imposes schema constraints: **no uniqueness constraints**, all
attributes optional-or-defaulted, all relationships optional. The V5 models already satisfied
optionality/defaults but declared `#Unique<Model>([\.id])` on all six models — which CloudKit
rejects, and which (once a CloudKit-backed configuration is used) breaks the **local** store too.

**Decision.** Introduce **schema V6**, whose only change is removing `#Unique` from every model
(plus the additive optional `FocusSession.originatingDeviceID`, ADR-063). Identity stays a
freshly-minted `UUID`; the repositories never reuse ids, so uniqueness holds in practice without
a database-level constraint. Prefer SwiftData's **native** CloudKit mirroring over hand-rolled
`CKRecord` mirroring — the milestone's stated preference and far less surface area. The
established **rebuild-on-incompatibility** store policy (ADR-016/019/021) carries an older local
store forward; only the re-seedable default configuration is lost.

**Consequences.** The schema is CloudKit-legal and the local store is unaffected in daily use. A
`CloudKitModelCompatibilityTests` suite asserts every V6 entity has **no** uniqueness constraint
and that all six models still round-trip. Schema bumped **V5 → V6**.

## ADR-062 — Local-first: a CloudKit failure falls back to the existing local store, never blocks the timer

**Context.** iCloud can be unavailable in many ways (signed out, no entitlement, CloudKit down,
first-launch delay). None may lose local data or stop the app — and a failure must never
silently swap in an empty in-memory store.

**Decision.** `PersistenceController.bootstrap(requestedMode:)` resolves an explicit
`PersistenceMode` (`local` / `cloudKit` / `fallback`). A `.cloudKit` request that throws is
caught and the **same on-disk store** is reopened **local-only**, reporting `.fallback`. The
CloudKit builder **never** removes store files (only the local builder rebuilds, and only on a
genuine schema incompatibility). CloudKit mirroring is requested at launch only when the user's
preference is on **and** an iCloud account is actually present, so a build that cannot sync (e.g.
a free developer team with no iCloud entitlement) cleanly runs local without attempting a
doomed cloud container. The unit-test host forces `.local` so the suite is deterministic and
never touches CloudKit. Changing the sync preference takes effect next launch (SwiftData binds
the CloudKit database at container creation) — the UI says so.

**Consequences.** A CloudKit problem degrades to offline operation with data intact and the timer
unaffected — proven by `SyncFailureIsolationTests` (injected CloudKit failure → fallback container
→ full pause/resume/stop still works) and `OfflinePersistenceTests`. Fallure isolation required
no timer change.

## ADR-063 — Running sessions are device-local; historical fields stay frozen across sync

**Context.** With sync, a running/paused `FocusSession` row appears on other devices. Naively,
Device B's launch-time `recover()` would restore Device A's live session into a **second timer**
— and worse, `fetchRecoverableSession` marks *other* recoverable sessions `interrupted`, which
would sync back and **stop the device that owns it**.

**Decision.** Timer execution is **device-local**. `FocusSession` gains an optional
`originatingDeviceID` (a random per-install UUID string — **never** an iCloud account id or any
PII), stamped at creation. `fetchRecoverableSession` only considers sessions belonging to **this
device** (`belongsToDevice`: nil origin ⇒ local, for back-compat); a session running on another
device is neither recovered nor mutated. Recovery otherwise follows the **existing** local rules
(ADR-014). Historical/frozen fields (`configurationName`, `startedAt`/`endedAt`/`targetEndAt`/
`remainingAtPause`) remain frozen — an edit elsewhere (e.g. a configuration rename) never
rewrites them, whether local or synced.

**Consequences.** A synced "running" row never triggers a second timer or a cross-device
takeover — proven by `RunningSessionSyncTests`. History stays honest under edits — proven by
`HistoricalIntegrityTests` (rename, plan delete, template delete). Additive optional field only;
schema stays V6.

**Milestone 13 verification.** Full suite grew **434 → 475 tests** (79 → 88 suites), all passing,
0 warnings. **CloudKit production sync was not manually verified** — the signing team is a
*personal* Apple Developer team, which cannot use the iCloud/CloudKit capability; enabling it
requires a paid membership + a created container (documented in `docs/22-ICLOUD-CLOUDKIT.md`).

## ADR-064 — Configurable widgets are presentation configuration, not timer state

**Context.** Milestone 14 makes the M11 widget user-configurable (what it shows, where a tap
goes, whether the countdown is visible). A naïve implementation could let configuration reach
into session state, run its own countdown per display mode, or add a second data path.

**Decision.** The widget configuration is a **pure presentation projection**. A Foundation-only
`TimeFrameWidgetConfiguration` (`displayMode`/`destination`/`showsCountdown`) selects *how* the
existing read-only `WidgetProjection` is rendered — nothing more. The pure `WidgetTimelineBuilder`
computes entries + reload policy from the **projection's state only** (via `WidgetTimelinePolicy`);
the configuration is carried onto each entry but **never** affects timing, so switching Timer /
Today / Statistics can never introduce a second clock. There is still exactly **one** `TimerEngine`
and **one** `SessionCoordinator`.

**Consequences.** Configuration is timing-invariant and provably isolated — `ConfiguredWidgetTimelineTests`
asserts all three display modes yield identical entry instants + reload for the same projection, and
`WidgetConfigurationIsolationTests` proves building configured timelines mutates no coordinator,
engine, session, interval, or `ModelContext`. No new timer primitive was introduced.

## ADR-065 — `AppIntentConfiguration` owns widget configuration; it is not persisted by the app

**Context.** WidgetKit needs a configuration surface in the standard widget editor. The app could
have stored widget preferences in `UserDefaults`/SwiftData, but that would duplicate ownership and
risk a second settings store.

**Decision.** The widget uses `AppIntentConfiguration` backed by a `WidgetConfigurationIntent`
(`TimeFrameWidgetConfigurationIntent`) with three `AppEnum` parameters carrying user-facing
`DisplayRepresentation`s ("Current Timer", "Today's Focus", "Open When Tapped", "Show/Hide
Countdown"). **WidgetKit owns and persists** the user's choice against the installed widget; the app
stores **nothing** for widget configuration — no `UserDefaults` suite, no SwiftData. Tap destinations
reuse the **existing** `timeframe://` deep links and `AppSection` mapping (no new navigation
mechanism). The intent has **no side effects** — it only maps its three choices to the pure
`TimeFrameWidgetConfiguration`.

**Consequences.** One owner of widget configuration (WidgetKit), no second settings database, and
the config UI reads without technical vocabulary. The intent + enums are discovered by the widget
extension's App Intents metadata extraction (verified in the built `.appex`'s `Metadata.appintents`),
and unit-tested deterministically (`WidgetConfigurationIntentTests`) without a Shortcuts/Siri host.

## ADR-066 — The widget configuration model is pure and defensively decoded

**Context.** A configuration value can arrive partial or forward-incompatible (a newer app writing
options an older reader doesn't know). Throwing on decode would risk an unusable or crashing widget.

**Decision.** `TimeFrameWidgetConfiguration` and its enums (`WidgetDisplayMode`/`WidgetDestination`)
are `Codable`/`Hashable`/`Sendable`, Foundation-only, and **decode defensively**: an unknown enum
raw value or a missing field degrades to the **safe default** (`Current Timer → Timer → countdown
on`) rather than throwing. The pure `AppEnum` layer (`WidgetContentOption`/`WidgetDestinationOption`/
`WidgetCountdownOption`) lives in `Shared/` and maps onto this model; `import AppIntents` appears in
**exactly one** shared file, guarded by a boundary test.

**Consequences.** A malformed or partial configuration always yields a usable widget, never a crash
— proven by `WidgetConfigurationTests`. The single sanctioned `AppIntents` import in `Shared/` is
enforced by `WidgetConfigurationBoundaryTests`.

## ADR-067 — Today/Statistics data is additive to the projection; no schema or kind change

**Context.** The Today and Statistics display modes need a little more data (completed focus
intervals today, a focus trend). A schema/store-format break would jeopardise M11 backward
compatibility.

**Decision.** Two **optional** fields (`completedFocusIntervalsToday`, `focusTrendToday`) are added
to `WidgetProjection` **without** bumping `currentSchemaVersion` (still `1`) or the storage key
(still `…v1`) — optional additive JSON fields are backward- and forward-compatible (an M11-shaped
payload simply reads them as `nil`; an incompatible `schemaVersion` is still rejected, never blindly
decoded). The app computes the trend from the **same** `StatisticsAggregator`/`StatisticsComparison`
the dashboard uses (today vs the prior day) and freezes a pure `WidgetFocusTrend` into the
projection — the widget **never aggregates**, it only renders. The widget `kind`
(`"TimeFrameTimerWidget"`), families (`.systemSmall`/`.systemMedium`), App Group
(`group.abirbarman.com.time-frame`), and SwiftData schema (**V6**) are all unchanged.

**Consequences.** Existing installed widgets migrate in place; the projection stays a single source
of truth with no duplicated statistics logic in the widget. Covered by
`WidgetProjectionConfigurationTests` (round-trip, backward-compat, malformed trend, version
rejection).

## ADR-068 — The configurable widget stays read-only and CloudKit-independent

**Context.** The widget must never become a write path or depend on iCloud, even as it gains
configuration and richer content.

**Decision.** The widget continues to read **only** the local App Group `WidgetProjectionStore`;
it imports no CloudKit, no SwiftData, and no app model layer, and it writes nothing. The M13 CloudKit
mirroring remains **below** the repositories and is never the widget's data source. A widget failure
can never stop the timer, and a CloudKit failure can never make the widget unusable (it renders the
local projection, or a stable `.unavailable` fallback when the App Group is missing).

**Consequences.** Proven by `WidgetCloudKitIndependenceTests` (local-only store path + App-Group-
unavailable fallback both build a valid timeline) and `WidgetConfigurationBoundaryTests` (widget
imports no CloudKit/SwiftData, references no `ModelContext`).

**Milestone 14 verification.** Full suite grew **475 → 517 tests** (88 → 96 suites), all passing,
0 warnings, clean build succeeds, widget App Intents metadata extracted and validated. **Manual
widget-gallery verification was not performed** — no GUI/widget-gallery automation is available in
this environment (the widget configuration UI is a macOS system surface); the configuration model,
intent, timeline, isolation, and boundary are instead pinned by deterministic tests and a built-
metadata check.

---

## ADR-069 — Interactive widget controls are command surfaces over the one coordinator

**Context.** Milestone 15 makes the widget interactive: users press Pause / Resume / Skip /
Restart / Stop / Start directly on the widget. The timer authority is a single in-memory
`TimerEngine`/`SessionCoordinator` owned by the app — it is **not** a shared store a separate
process could mutate. A widget button must therefore reach *that* coordinator, without the widget
gaining timer state, persistence, or a second start path.

**Decision.** Each control is a thin **App Intent** used with SwiftUI `Button(intent:)`. The intents
live in `Shared/WidgetControlIntents.swift` (compiled into both targets so the widget can reference
them) and own **no** domain: they resolve an `@AppDependency` **`WidgetControlActions`** router and
call it. WidgetKit runs a widget-button intent in the **app process**, where the app has registered a
router wired to the existing Milestone-12 **`AppIntentSessionActions`** — the one and only place an
intent mutates the timer. The chain is:

```
Button(intent:) → WidgetPause/Resume/Skip/Restart/Stop/StartIntent.perform()
    → @AppDependency WidgetControlActions   (registered by the app)
        → AppIntentSessionActions           (the ONE mutation seam)
            → SessionCoordinator → TimerEngine → SwiftData/history
```

No `WidgetTimerEngine`/`WidgetSessionCoordinator`, no widget-local session state, no widget-local
store, no second App Group. `Start` uses the app's existing default-configuration start path (the
widget invents no timer values). The control intents set `isDiscoverable == false` so they never
clutter Shortcuts, which already exposes the Milestone-12 command intents over the same seam.

**Consequences.** Exactly one timer and one mutation seam survive. If the router is ever resolved in a
process where the app did not register it, the injected `.unavailable` default fails **safely** with a
friendly message instead of trapping. Proven by `InteractiveWidgetActionTests`,
`InteractiveWidgetProjectionTests`, and `InteractiveWidgetBoundaryTests` (the app-side router
delegates to `AppIntentSessionActions`; the shared intents reference no `SessionCoordinator`/
`TimerEngine`/`ModelContext`).

---

## ADR-070 — Widget control availability is a pure projection of state

**Context.** Which buttons a widget shows must follow authoritative state — never a widget-owned
notion of "running" or a second clock.

**Decision.** A pure, Foundation-only `WidgetControlSet.controls(for:phase:compact:)` maps the
read-only `WidgetSessionState` + `WidgetPhase` (+ family width) to the ordered controls: running
focus → Pause/Skip(/Stop on medium); running break → Skip/Stop; paused → Resume/Restart(/… )/Stop;
idle/completed/interrupted → Start; unavailable → none. The widget view renders **only** from this
function and the projection; it holds no `@State` timer/session truth. Interactive controls appear in
**Timer** display mode only — Today and Statistics stay read-only (a view-level presentation choice);
the availability function is configuration-independent.

**Consequences.** Button state can be unit-tested without a WidgetKit host and can never drift from a
second timer. Pinned by `InteractiveWidgetStateTests` (every state/phase on small and medium) and
`InteractiveWidgetConfigurationTests` (availability ignores configuration; timing stays
config-invariant).

---

## ADR-071 — Widget actions refresh through the existing writer; stale/failed actions fail safely

**Context.** After an action the widget must show the new authoritative state, without per-second
reloads and without the widget writing its own projection. Some coordinator operations (notably
`restart`) apply without emitting a lifecycle event.

**Decision.** The projection is still produced **only** by the app-side `WidgetProjectionWriter` from
authoritative state; the widget never writes it. The router calls the writer's `update()` **after**
each action, so even `restart` (which emits no lifecycle event) yields fresh anchors, then WidgetKit
reloads — a **targeted** refresh on a meaningful transition, never a per-tick write or a global poll.
Failures are safe and non-destructive: a control on no active session surfaces the existing
`TimeFrameIntentError.noActiveSession`; `Start` while running surfaces `sessionAlreadyRunning`; an
invalid transition (e.g. Resume while running) is a coordinator-guarded no-op; a stale widget action
against a session that is no longer there **never resurrects** it. Repeated/rapid taps stay safe
because the coordinator remains the sole authority (the second Pause/Resume is a no-op; the second
Stop reports `noActiveSession`) — no widget-local lock is introduced.

**Consequences.** The "one timer, many surfaces" and "meaningful-transition writes only" invariants
hold under interactivity. Pinned by `InteractiveWidgetProjectionTests` (store equals the mapper's
view; restart refreshes anchors; no per-tick reload), `InteractiveWidgetFailureTests`,
`InteractiveWidgetConcurrencyTests`, and `InteractiveWidgetRecoveryTests`.

**Milestone 15 verification.** Full suite grew **517 → 557 tests** (96 → 105 suites), all passing,
**0 warnings**, clean build succeeds, the widget target builds, and App Intents metadata is extracted
and validated (`--validate-assistant-intents`) with all six widget-control intents discovered
(`isDiscoverable == false`) alongside the unchanged Milestone-12 intents and the configuration intent.
**Manual interactive-widget verification was not performed** — no GUI/widget-gallery automation is
available in this environment (the widget surface is a macOS system surface); the action routing,
state→controls mapping, failure/concurrency/recovery behavior, boundary, and CloudKit independence are
instead pinned by deterministic tests and a built-metadata check.

---

## Milestone 16 — Live Session Surface / ActivityKit

### ADR-072 — A Live Activity is a read-only projection of the one session; build the platform-neutral core

**Context.** Milestone 16 asks for a first-class *live session surface* via ActivityKit. Time Frame
already has one authoritative `TimerEngine`/`SessionCoordinator` and a fan-out of read-only surfaces
(Calendar, Notifications, Menu Bar, Widgets).

**Decision.** Model a Live Activity as **another read-only presentation projection** on the existing
`SessionLifecycleEvent` seam — never a second timer. Build the **platform-neutral core** now:
`Shared/LiveSessionProjection.swift` (`TimeFrameLiveActivityContent`, `LiveActivityIdentity`,
`LiveActivitySnapshot`, `LiveActivityRunState`), `Shared/LiveActivityPresentation.swift`,
`LiveActivityService` (Foundation-only protocol + `NoopLiveActivityService`),
`LiveActivityContentMapper` (authoritative state → snapshot, mirroring `WidgetProjectionMapper`), and
`LiveActivityCoordinator` (observer/adapter). The running countdown is a timestamp **repaint**
(`Text(timerInterval:)`); no `Timer`/`Timer.publish`/`scheduledTimer`/`DispatchSourceTimer`/
`Task.sleep`/`asyncAfter`/decrement is introduced. The layer imports only Foundation/Observation —
no SwiftData, WidgetKit, SwiftUI, CloudKit, or ActivityKit.

**Consequences.** The "one timer, many surfaces" invariant extends to the live surface. The core is
reusable by a future iOS/iPadOS target with no change. See ADR-076 for why the ActivityKit half is
not built on macOS.

### ADR-073 — Activity identity is the FocusSession id; explicit duplicate-prevention & reconciliation

**Context.** A Live Activity must not be duplicated across relaunch, crash, sleep/wake, or repeated
lifecycle callbacks, and must reconcile with the authoritative session on launch.

**Decision.** Activity identity is the **`FocusSession.id`** — never the task or configuration name.
`LiveActivityService.activeSessionIDs()` reports the live set (a real adapter reads ActivityKit's
`Activity.activities`, correct across relaunch). Starts are idempotent per id; starting for a session
first ends any stale activity for a *different* id. `reconcileOnLaunch()` converges to **exactly one**
activity for a recovered running/paused session and **none** when idle/terminal/disabled. The
Milestone-13 device-origin policy is preserved: reconcile acts only on this device's `activeSession`,
so a foreign session never gains a controllable activity.

**Consequences.** One session ⇒ at most one activity, always. Pinned by
`LiveActivityRecoveryTests` and `LiveActivityDuplicatePreventionTests`.

### ADR-074 — ActivityKit is isolated behind a service protocol; failures never reach the timer

**Context.** ActivityKit must never be able to stop or corrupt the timer, and unit tests must run
without an ActivityKit runtime.

**Decision.** All ActivityKit access is (would be) confined to a single `LiveActivityService` adapter
that the coordinator reaches only through the Foundation-only protocol in pure value types. Every
operation is best-effort: unsupported / unauthorized / throwing / system-terminated all resolve to
*no activity*, never a rethrow. A Live Activity control reuses the **existing Milestone-15 seam**
(`WidgetControlActions → AppIntentSessionActions → SessionCoordinator → TimerEngine`) — no
`LiveActivitySessionActions` is created.

**Consequences.** The whole lifecycle/recovery/failure/routing surface is testable with a fake; the
timer is provably unaffected. Pinned by `LiveActivityFailureIsolationTests` and
`LiveActivityAppIntentRoutingTests`.

### ADR-075 — Live Activity preferences would persist in UserDefaults; schema stays V6

**Context.** Presentation preferences (enable, show task, show configuration) may be needed by a
supported build.

**Decision.** Keep them in **UserDefaults** (`LiveActivityPreferencesStore`, mirroring
`MenuBarPreferencesStore`) — never SwiftData. Live Activity state is **ephemeral** and requires no
persistence and no migration; the schema stays **V6**. No Settings surface is shipped on macOS
(nothing to configure where the feature is unavailable — ADR-076); the store and
`preferencesDidChange()` exist ready for the companion target.

**Consequences.** No schema-version bump; no data-model risk from a presentation feature.

### ADR-076 — Platform limitation: Live Activities are unavailable on native macOS; deliver a feasibility milestone

**Context.** ActivityKit ships in the macOS SDK, but its Swift interface annotates every core symbol
`@available(macOS, unavailable)` (73 annotations; the framework is for **Mac Catalyst** only). The
compiler rejects `struct … : ActivityAttributes` in a native-macOS target with *"'ActivityAttributes'
is unavailable in macOS"*. Time Frame is a native macOS 27 app with no iOS target.

**Decision.** Do **not** fabricate a macOS Live Activity and do **not** add an iOS companion target as
part of this milestone (that is major product restructuring). Deliver M16 as a **platform-feasibility
milestone**: prove the limitation from the SDK, build the reusable platform-neutral core (ADR-072),
document the exact companion-target work (`docs/25-LIVE-ACTIVITIES.md` §11), keep the macOS app
completely unchanged and the build/tests green, and clearly state that **Live Activities are NOT
implemented on macOS**. `import ActivityKit` appears **nowhere** in the codebase.

**Consequences.** Accuracy and architectural integrity over a forced feature. A future iOS/iPadOS
target completes the feature by adding only the attributes conformance, the ActivityKit adapter, the
Live Activity UI, and thin wiring — reusing everything built here.

**Milestone 16 verification.** Full suite grew **557 → 602 tests** (**105 → 122 suites**), all
passing, **0 warnings**, clean build (app + widget) succeeds. Boundary audits pass (no second timer,
no persistence, no engine/coordinator construction, no CloudKit in the neutral layer; no
`import ActivityKit` anywhere). Schema unchanged (**V6**). **Manual acceptance is not applicable on
macOS** — there is no Live Activity to display — and is honestly not claimed; it is scoped for a
future iOS/iPadOS companion target.

---

### ADR-077 — Milestone 17 hardening adds no runtime architecture; hermeticity + a source-boundary audit become the release gate

**Status:** Accepted (Milestone 17).

**Context.** M16 left the app feature-complete. Before a release candidate we needed to *prove*
the architecture's load-bearing invariants stay true, guard against a real-store recovery hang in
the test host (which bit earlier milestones), and validate the Release configuration — without
adding features or rewriting anything.

**Decision.**
1. **No new runtime architecture.** M17 introduces no new coordinator, store, timer primitive, or
   schema change. The schema stays **V6**. `TimerEngine` remains the single timing authority and
   `SessionCoordinator` the single control/mutation seam. The only production edits are: extracting
   the existing test-host detection into a pure `Support/TestHostEnvironment.swift`
   (behaviour-identical); adding a URL-injectable
   `PersistenceController.openOnDiskContainer(schema:configuration:)` testability seam over the
   existing rebuild-on-incompatibility path (ADR-016); adding `.accessibilityAddTraits(.updatesFrequently)`
   to the two live countdowns; and binding a temporary at the Restart intent's call site to remove a
   spurious Release-only optimizer warning. None change timer, persistence, or integration behaviour.
2. **The production-readiness audit is a source-boundary release gate.** `ProductionReadinessTests`
   scans the source on disk (comments and string literals blanked; identifier-boundary aware) and
   fails the build if any invariant regresses: single scheduling authority, single engine/coordinator,
   persistence/widget/App-Intent boundaries, **no `import ActivityKit` anywhere**, no CloudKit import,
   V6 schema, and a hermetic test host. This complements — and generalises across the whole tree —
   the per-milestone boundary tests (`WidgetBoundaryInvariantTests`, `WidgetConfigurationBoundaryTests`,
   `InteractiveWidgetBoundaryTests`).
3. **Test-host hermeticity is a tested guarantee.** Under the XCTest host, launch skips live seeding,
   recovery, CloudKit, App-Group writes, and intent registration; the audit asserts the live process is
   detected and that launch guards those side effects, so the developer's real running session can
   never be recovered or mutated by the suite.

**Consequences.** A future change that crosses an architectural boundary, adds a second clock, imports
ActivityKit/CloudKit, or breaks test-host isolation fails an automated test rather than shipping.
CloudKit production sync remains **unverified** by design (needs a paid Apple Developer team + iCloud
container; ADR-060…062) — a documented release blocker, not an architectural gap. See
`docs/26-PRODUCTION-READINESS.md`.

---

## Milestone 18 — iOS/iPadOS Companion & Real Live Activities

### ADR-078 — Extract a platform-neutral `Core/` group shared by macOS and iOS; macOS content is unchanged

**Status:** Accepted (Milestone 18).

**Context.** Adding an iOS/iPadOS companion required the neutral domain (`TimerEngine`,
`SessionCoordinator`, models, persistence, statistics, projections, App-Intent seams, the M16 Live
Activity core) to compile into a second app target — **without** duplicating it and **without**
destabilizing the mature macOS build. The macOS app kept all of this inside a single
file-system-synchronized group (`time_frame/`), which also carries macOS-only UI and integrations that
cannot compile on iOS (`Views/`, `MenuBar`, `Calendar`, the `MenuBarExtra` app entry). Two shapes were
considered: (a) attach the existing `time_frame/` group to iOS with a large `membershipExceptions` list
excluding every macOS-only file; (b) move the neutral domain into a new shared group.

**Decision.** Extract the neutral domain into a new top-level **`Core/`** synchronized group attached to
**both** the macOS and iOS app targets. Moved: `Models/`, `Timer/`, `Statistics/`, `Support/`,
`Intents/`, `Widgets/`, a new `Navigation/` (the neutral `AppSection`/`AppNavigation`, and
`SessionSetupPrefill` which the App-Intent seam already depended on), and
`Services/{Persistence,Cloud,LiveActivity,Statistics}/`. The macOS module compiles the **identical set
of files** (now under `time_frame/` **and** `Core/`), so the `time_frame` module's contents,
`@testable import time_frame`, and the entire macOS test suite are unchanged. macOS-only code
(`Views/`, `Services/{Calendar,MenuBar,Notifications}/`, `ContentView`, `time_frameApp`) stays in
`time_frame/`. The `ProductionReadinessTests` source roots were updated to the new `Core/` locations
(the audited file set is unchanged).

**Consequences.** New neutral code is shared automatically; new macOS-only UI needs no exception
bookkeeping. `SessionCoordinator` already guarded AppKit with `#if canImport(AppKit)`, so the shared
core compiles cleanly on iOS. `Core/` imports no ActivityKit/UIKit-specific UI and remains the single
home of the one engine/coordinator. See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md` §4.

### ADR-079 — A native iOS/iPadOS companion with real ActivityKit Live Activities; ActivityKit confined to the two iOS targets

**Status:** Accepted (Milestone 18).

**Context.** ActivityKit is `@available(macOS, unavailable)` (ADR-076), so M16 built and tested a
platform-neutral live-session core and left the ActivityKit half unbuilt. M18 completes the feature on
iOS/iPadOS while keeping the macOS app native and ActivityKit-free, and while preserving every M1–M17
invariant.

**Decision.**
1. **Two new iOS targets, plus a tiny shared attributes group.** `TimeFrameiOS` (companion app) and
   `TimeFrameiOSWidgets` (Live Activity extension). The one ActivityKit attribute type,
   `TimeFrameLiveActivityAttributes`, lives in `TimeFrameiOSShared/`, compiled into both. `import
   ActivityKit` appears in exactly three files, all iOS: the attributes, the app-side adapter, and the
   Live Activity UI — **never** on the macOS side, in `Core/`, in `Shared/`, or in the tests. A
   `ProductionReadinessTests` assertion enforces this boundary (allowed only in the iOS roots).
2. **Reuse the M16 neutral projection verbatim as the ContentState.** `ContentState =
   TimeFrameLiveActivityContent` — no adapter type, no second state model, and crucially no
   independently ticking counter. The countdown is a `Text(timerInterval:)` repaint between the
   content's frozen anchors; the system advances it while the app is suspended.
3. **The Live Activity is presentation, never timer authority.** The app-side
   `ActivityKitLiveActivityService` is the concrete M16 `LiveActivityService` injected into the
   unchanged M16 `LiveActivityCoordinator`; it maps snapshots to `Activity.request/update/end`, is
   idempotent per `FocusSession.id` (duplicate prevention, ADR-073), reconciles on launch, derives a
   `staleDate` from frozen anchors (no loop), and swallows every failure so the timer runs on. Under
   the unit-test host a `NoopLiveActivityService` is used (hermeticity).
4. **Controls reuse the one seam.** Live Activity `Button(intent:)`s bind to the **shared** Milestone-15
   control intents; the system runs them in the app process, where the app's `WidgetControlActions`
   router delegates to the one `AppIntentSessionActions` → `SessionCoordinator` → `TimerEngine`. No
   second action architecture.
5. **One engine, one coordinator, one store.** The iOS app builds the same `SessionCoordinator` over the
   same `ModelContainer`, with the same lifecycle fan-out (widget projection writer + Live Activity
   coordinator, both read-only). Recovery is **device-local** (ADR-063) with **no new code**: a session
   running on another device is never recovered, mutated, or duplicated here.
6. **CloudKit-ready, not fabricated.** The iOS target uses the same SwiftData-native mirroring path, App
   Group, and V6 schema, so history/statistics sync naturally once enabled; the iCloud
   entitlement/container is intentionally **not** added (a personal team cannot enable it), so the store
   degrades safely to local and **cross-device sync stays unverified by design** — a documented release
   blocker, not an architectural gap.

**Consequences.** The macOS app is untouched and stays ActivityKit-free; the iOS app is a thin
presentation/control surface over the shared one-timer core. Schema stays **V6**. On-device Live
Activity visuals and cross-device CloudKit sync require, respectively, a Dynamic-Island device and a
paid Apple Developer team — both documented, neither faked. See
`docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md`.

---

### ADR-080 — Make CloudKit capability an explicit, testable seam; keep the free-team blocker honest

**Status:** Accepted (Milestone 19).

**Context.** Through M13–M18 the launch path decided whether to request a CloudKit-mirrored store from
two runtime facts only — the user's sync preference and iCloud account availability — and relied on
`PersistenceController.bootstrap` to *fall back* to local if the cloud container could not be created.
That works, but it makes the most fundamental fact — **is this build even entitled for CloudKit** —
implicit and only observable as a failed container build. The shipping build is signed by a **personal
(free) Apple Developer team**, which Apple never permits to use iCloud/CloudKit, so that entitlement is
permanently absent until a paid team is used. M19 needs that reality represented honestly and tested.

**Decision.**
1. Add `Core/Services/Cloud/CloudKitCapability.swift` (Foundation-only, CloudKit-free): a
   `CloudKitCapabilityProviding` protocol, a `BuildCloudKitCapabilityProvider`, and the pure resolver
   `CloudKitCapability.resolve(entitled:syncEnabled:account:) -> Decision{requestedMode,blocker}`.
   CloudKit is requested **only** when entitled **and** sync is on **and** an account is available;
   otherwise the decision is `.local` with a specific `CloudSyncError` reason.
2. The single honest switch is `CloudKitCapability.entitledInThisBuild` — `false` today because no
   `.entitlements` file declares an iCloud entitlement (a fabricated one would fail to sign). Flip to
   `true` only in a build actually signed with the iCloud capability + container.
3. Both the macOS app launch and the iOS app resolve the persistence mode through this seam, so they
   decide identically and testably. Behaviour is unchanged today (both resolve `.local`), but the
   decision is now explicit rather than discovered via a doomed container build.
4. `M19CloudKitHonestyTests` ties the constant to the provisioning reality: it **fails the build** if an
   iCloud entitlement appears while `entitledInThisBuild` is still `false`, or vice-versa.

**Consequences.** "This build cannot use CloudKit" is a first-class, unit-tested state across the full
entitled × preference × account matrix, with no real iCloud account required. The free-team blocker is
honest and self-enforcing; enabling real sync is a one-constant + entitlement change. No CloudKit
import, no timer primitive, no schema change (stays **V6**). See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.

---

### ADR-081 — Prove cross-device / merge / fallback behaviour deterministically, without a real iCloud account

**Status:** Accepted (Milestone 19).

**Context.** Real two-device CloudKit sync cannot be exercised here (paid-team blocker), but the
architecture's behaviour *under* sync is fully determined by pure, local logic: frozen historical
fields, device-local recovery, statistics as a re-derivation of history, and safe fallback. That
behaviour must be guaranteed by tests, not by a manual cross-device session that can't be run.

**Decision.** Add `CrossDeviceSyncValidationTests` (macOS): a single in-memory container models the
**merged, synced store**, and two `SessionRepository`/`SessionCoordinator` instances with distinct
device IDs act as Device A and Device B over it. The suite proves: (a) a completed session's frozen
`configurationName`/interval timing survive a live-config **rename** and **delete** (nullify, never
history loss); (b) completed history is visible to **both** devices; (c) a running session is
**device-local** — B never recovers or mutates A's session, and the fetch is non-destructive; (d)
statistics aggregate the **merged** history device-agnostically, grouping by the frozen name; (e) under
CloudKit `.fallback` every timer control works over the preserved local store. Real CloudKit
synchronization remains a documented, **unfaked** manual blocker.

**Consequences.** The sync-time invariants are guaranteed deterministically and offline. No second
timer/store/clock is introduced; the tests use only the existing repositories, coordinator, and
aggregator. Complements the existing `RunningSessionSyncTests`/`HistoricalIntegrityTests`/
`OfflinePersistenceTests` and the iOS `IOSCrossDeviceSessionPolicyTests`.

---

### ADR-082 — Extend the release-gate audit with CloudKit / App-Group / deep-link / secrets honesty checks

**Status:** Accepted (Milestone 19).

**Context.** M17's `ProductionReadinessTests` scans the source tree and fails the build on a boundary
regression. M19 introduces new invariants that deserve the same machine-checked enforcement: the App
Group must stay identical across every target, no fabricated iCloud entitlement may appear, the CloudKit
wiring must stay honest (native mirroring, V6, no wipe-on-failure), the deep-link scheme must stay
registered, and no secrets may be committed.

**Decision.** Add `ProductionReadinessM19Tests` with four suites: **App-Group consistency** (the same
`group.abirbarman.com.time-frame` in all four `.entitlements` files and `WidgetProjectionStore`);
**CloudKit honesty** (no iCloud entitlement declared; `entitledInThisBuild` equals that reality; a
non-entitled build never resolves to a cloud request); **CloudKit wiring** (`cloudKitDatabase` native
mirroring present, the CloudKit builder never calls `removeStoreFiles`, `Services/Cloud` stays
CloudKit-free, schema stays V6 with no uniqueness constraints); **deep-link scheme** (`timeframe://`
registered in both app Info.plists); and **no committed secrets** (no `.p12`/`.pem`/`.mobileprovision`/
`.provisionprofile`/… artifacts, no embedded `PRIVATE KEY`).

**Consequences.** The M19 honesty and boundary invariants are enforced on every build, so the free-team
blocker can never be silently faked and the App-Group/deep-link compatibility can never regress. Adds no
runtime code. See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.

### ADR-083 — Share the local-notification stack via `Core/`; UserNotifications stays the single isolated adapter

**Status:** Accepted (Milestone 20).

**Context.** The macOS notification integration (`Services/Notifications/`) was already platform-neutral
except two guarded AppKit calls; `UserNotificationService` imports only Foundation/UserNotifications/os,
and UNUserNotificationCenter is identical on iOS and macOS. iOS needs the same behaviour. Duplicating the
stack would create two sources of truth for identifiers, content, and lifecycle.

**Decision.** Move the entire notification stack into `Core/Services/Notifications/` so macOS and iOS
compile the **identical** code. Add a `#elseif canImport(UIKit)` branch to `NotificationCoordinator`'s
`openSystemSettings()` (iOS opens the app's Settings screen; macOS opens the Notifications pane).
`UserNotificationService` remains the **only** file importing UserNotifications — now shared by both
platforms, still the single isolation adapter; the neutral timer core/models import none of it. The macOS
app's wiring and its `Views/Notifications/NotificationSettingsSection` are unchanged; iOS gets its own
`NotificationSettingsView`. The M17 audit roots were updated (`app/Services/Notifications` →
`core/Services/Notifications`).

**Consequences.** One notification implementation, proven from both modules. The move is transparent to
the macOS suite (`@testable import time_frame` still sees the types via Core; 679/144 unchanged).
`ProductionReadinessM20Tests` enforces the UserNotifications-single-adapter and timer-core-free
invariants. See `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.

### ADR-084 — iOS Home Screen widgets reuse the existing projection / App Group / configuration architecture

**Status:** Accepted (Milestone 20).

**Context.** M18 deferred iOS home-screen widgets. The macOS configurable/interactive widget stack
(M11–M15) already defines a read-only projection, an App Group channel, a pure timeline builder, an
`AppIntentConfiguration`, and a control seam. A second data path or configuration system would violate
"one timer, many surfaces".

**Decision.** Add the Home Screen widget to the **existing** `TimeFrameiOSWidgets` extension (alongside
the Live Activity — no new extension). It reads the **same** `WidgetProjection` from the **same** App
Group (`group.abirbarman.com.time-frame`) written by the **same** `WidgetProjectionWriter`, resolves the
**same** `TimeFrameWidgetConfigurationIntent`, and derives its timeline from the **same** pure
`WidgetTimelineBuilder`. The iOS presentation files (view/provider/entry/preview/formatting) are adapted
from the macOS ones (separate target/module) so iOS can add `.systemLarge`; the shared pure logic stays
the single source of truth in `Shared/`. The widget imports no SwiftData, CloudKit, `TimerEngine`, or
`SessionCoordinator`, and constructs none of them.

**Consequences.** iOS gains small/medium/large Timer/Today/Statistics widgets with zero new data
plumbing and zero schema/App-Group change. Enforced by `ProductionReadinessM20Tests` (no persistence,
CloudKit, engine construction, or scheduling primitive in the iOS widget). See
`docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.

### ADR-085 — iOS widget configuration is presentation-only; interactive controls reuse the Milestone-15 seam

**Status:** Accepted (Milestone 20).

**Context.** The iOS widget must be configurable (Timer/Today/Statistics, tap destination, countdown
visibility) and offer the same interactive controls as macOS — without ever affecting timing or adding a
second action path.

**Decision.** Configuration is the **pure** `TimeFrameWidgetConfiguration`; the entry instants and reload
policy come **only** from `WidgetTimelinePolicy` (the projection's state), so a config change is purely
presentational and can never introduce a second clock. Timer-mode controls are `Button(intent:)`s bound
to the **shared** M15 intents, run by WidgetKit in the app process through the one
`WidgetControlActions → AppIntentSessionActions → SessionCoordinator` chain; Today/Statistics stay
read-only. Which controls appear is the pure `WidgetControlSet` projection of state/phase. The countdown
is a `Text(timerInterval:)` repaint between frozen anchors; the widget decrements nothing.

**Consequences.** One configuration system and one control seam across both platforms; the widget owns
no timer state and writes nothing. Covered by `IOSHomeScreenWidgetTests` (config isolation, countdown
anchors, control-set) and the boundary audit.

### ADR-086 — iOS local notifications are scheduled from authoritative timer anchors; failures never affect the timer

**Status:** Accepted (Milestone 20).

**Context.** Notifications must fire at interval/session transitions even when the app is backgrounded or
closed, without running a background countdown, polling, or a second clock — and a notification backend
failure must never disturb the one timer.

**Decision.** Schedule from the engine's **frozen** interval-end timestamps
(`UNTimeIntervalNotificationTrigger`): `NotificationScheduleBuilder` emits **one** notification per
upcoming interval-start boundary (never per tick); the completion notification is delivered immediately
from the `.completed` event (never pre-scheduled). Identifiers are deterministic
(`session id + interval index + purpose`), so reconciliation is idempotent (a reschedule replaces, never
duplicates) and cancellation only ever touches Time Frame's own namespaced notifications. Actions route
back through `SessionCoordinator`, never the engine. Every scheduling operation is deferred and every
failure caught and turned into a non-blocking status.

**Consequences.** Correct, background-safe transition notifications with no second clock, provably
isolated from the timer (`IOSNotificationLifecycleTests.failureIsolation`: the scheduler throws on every
call; the timer runs on). Permission is requested only in context; a denial never affects the timer. See
`docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.

### ADR-087 — Lock Screen & StandBy widgets reuse the one WidgetProjection pipeline; they are read-only projections, never a second clock

**Status:** Accepted (Milestone 21).

**Context.** iOS exposes system surfaces beyond the Home Screen — Lock Screen accessory widgets
(`.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`) and StandBy. We need Time Frame on
those surfaces without introducing a second timer, a second configuration system, a second projection, or
a new widget extension, and while keeping the Home Screen widget behaviour unchanged.

**Decision.** The Lock Screen widget (`TimeFrameLockScreenWidget`) lives in the **existing**
`TimeFrameiOSWidgets` extension and reuses the **entire** Home Screen pipeline: the same
`WidgetProjectionStore` (App Group `group.abirbarman.com.time-frame`), the same `WidgetProjectionWriter`
(no new write path), the same `AppIntentConfiguration` intent (`TimeFrameWidgetConfigurationIntent`), the
same `HomeScreenWidgetProvider`/`HomeScreenWidgetEntry`, and the same pure `WidgetTimelineBuilder` for
entries + reload. It differs only in its `kind` (its own gallery identity) and its accessory views. The
live countdown is a `Text(timerInterval:)` / `ProgressView(timerInterval:)` repaint between the
projection's frozen anchors; the paused reading is the frozen `pausedRemainingSeconds`. **StandBy is not a
separate API** — on iOS it re-presents the existing `.systemSmall`/`.systemMedium` Home Screen widgets, so
StandBy support is served by the (unchanged, background-agnostic) system-family views and verified for
glanceability, not by a new surface.

**Consequences.** One timer, more surfaces; no schema change (stays V6); the Home Screen widget is
untouched. The widget extension imports no SwiftData/CloudKit/`TimerEngine`/`SessionCoordinator` and owns
no clock (`ProductionReadinessM21Tests`). Freshness is meaningful-transition-only, re-proven by
`WidgetProjectionFreshnessTests`. See `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

### ADR-088 — A pure, WidgetKit-free family presentation mapper degrades information density per family

**Status:** Accepted (Milestone 21).

**Context.** Accessory families have wildly different space budgets (a circular gauge vs. a rectangular
block vs. a one-line inline). The per-family layout choices (which glyph, whether a live ring or a word,
what the VoiceOver sentence says) must be deterministic and unit-testable without a WidgetKit host, and
must never recompute timing.

**Decision.** `Shared/AccessoryWidgetPresentation.swift` maps `(WidgetProjection, TimeFrameWidgetConfiguration,
now) → {circular, rectangular, inline}` presentation values. It is **Foundation-only** — it imports no
WidgetKit, SwiftUI, AppIntents, ActivityKit, or SwiftData — using its own neutral `AccessoryWidgetFamily`
and `AccessoryCountdown` vocabulary so the view maps WidgetKit's `WidgetFamily` at the boundary. It reads
the projection's frozen anchors (never elapsed time), and each family **degrades information density**
(circular carries no task name; inline is one line) rather than inventing a second projection or state
system. Today/Statistics display modes render a compact daily glance from the same additive projection
fields the Home Screen widget uses.

**Consequences.** All accessory content is deterministic and tested from both the macOS and iOS suites
(`AccessoryWidgetPresentationTests`, `IOSLockScreenWidgetTests`), and the mapper's purity is a release-gate
audit (`M21AccessoryMapperPurityTests`). A malformed/stale projection degrades to a safe, non-negative
reading; `now` is used only for the snapshot spoken-remaining, never to advance a countdown.

### ADR-089 — Accessory widgets are read-only; interactive controls stay on surfaces with room

**Status:** Accepted (Milestone 21).

**Context.** WidgetKit permits `Button(intent:)` on Lock Screen accessory widgets, but their space is tiny
and the vibrant/monochrome rendering makes a row of controls easy to mis-tap and hard to label. Adding a
second mutation path would also risk the "one seam" invariant.

**Decision.** The accessory families are **read-only**: a tap opens the configured `timeframe://`
destination via `.widgetURL`, and no accessory view imports AppIntents or references a `Widget*Intent`. The
Milestone-15 interactive seam (`Button(intent:) → WidgetControlActions → AppIntentSessionActions →
SessionCoordinator`) stays on the Home Screen widget and the Live Activity, where controls can be presented
and labelled safely — so there remains exactly **one** mutation seam.

**Consequences.** No new mutation path; accessory surfaces cannot confuse the user or corrupt the timer. A
source audit (`M21AccessoryBoundaryTests.accessoryViewsAreReadOnly`) fails the build if an accessory view
ever gains an interactive intent. See `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

---

### ADR-090 — iOS Control Center controls are a command adapter over the ONE mutation seam

**Context.** Milestone 22 adds native iOS **Control Center** controls (WidgetKit `ControlWidget`,
iOS 18+) so the user can start/pause/resume/skip/stop the timer from Control Center, the Lock Screen
control tray, and the Action button. The risk is the same one every surface faces: becoming a second
timer, a second store, or a second mutation path.

**Decision.** A Control Center control is a **thin command adapter**. Its `ControlWidgetButton`
performs an App Intent that flows through the EXISTING Milestone-15 seam —
`ControlWidgetButton(action:) → Widget/App Intent → WidgetControlActions → AppIntentSessionActions →
SessionCoordinator → TimerEngine`. Two of the three controls reuse the M15 `WidgetStartIntent` /
`WidgetStopIntent` **verbatim**; the adaptive primary control adds ONE thin `TimeFramePrimaryControlIntent`
that resolves the *contextually correct* action from live state via the pure
`ControlCenterControlSet.primaryAction(for:)` and performs it through the SAME `perform(_:)` path the
explicit-action handler uses. `WidgetControlActions` gains a `performPrimary()` capability but remains
the **one** router; no second router, no second decision path. The SDK's `ControlWidgetTemplateBuilder`
has no `buildEither`/`buildOptional`, so state adaptation is done in the value provider + adapter intent,
not by branching intent types in the body.

**Consequences.** Exactly one `TimerEngine`/`SessionCoordinator` and one mutation seam remain. Every
control action refreshes the widget projection (including `restart`, which emits no lifecycle event and
relies on the router's explicit refresh). Actions fail safely (unavailable router / no session / invalid
transition) via the closed `TimeFrameIntentError`/`WidgetControlError`. `ProductionReadinessM22Tests`
fails the build if a second router/seam or a timer primitive appears in the control code. See
`docs/31-CONTROL-CENTER-CONTROLS.md`.

---

### ADR-091 — Control Center state is a pure, Foundation-only projection (never a clock)

**Context.** A Control Center control can reflect the current situation (idle / focus running / break
running / paused / …). It must do so without computing elapsed time or owning a clock.

**Decision.** The decision layer (`Shared/ControlCenterPresentation.swift`) is **pure and
Foundation-only**: `ControlCenterSessionState` is derived solely from the read-only `WidgetProjection`
(`state` × `phase`, splitting `running` into focus vs break so a break offers *skip*, not pause);
`ControlCenterControlSet` decides which controls are valid and which is primary; `ControlCenterActionCatalog`
supplies the title / SF Symbol / VoiceOver label. It imports no WidgetKit, SwiftUI, AppIntents, ActivityKit,
SwiftData, or CloudKit. The widget's value provider reads the frozen projection from the App Group; the
control introduces no `Timer`/`Timer.publish`/`DispatchSourceTimer`/`Task.sleep`/`asyncAfter`/`CADisplayLink`.

**Consequences.** The whole decision layer is unit-testable without a WidgetKit host and can never drift
into a second clock. `ProductionReadinessM22Tests` asserts the file is Foundation-only and clock-free.
See `docs/31-CONTROL-CENTER-CONTROLS.md`.

---

### ADR-092 — Control Center is iOS-only and CloudKit-independent; macOS stays ControlWidget-free

**Context.** `ControlWidgetButton` etc. are annotated available on macOS 26 as well as iOS 18, and
CloudKit remains intentionally disabled on the shipping personal (free) team build.

**Decision.** Time Frame keeps its Control Center surface **iOS-only**: the `ControlWidget`s live in the
existing `TimeFrameiOSWidgets` extension, and the macOS app, `Core/`, `Shared/`, and the macOS widget stay
`ControlWidget`-free. Control Center reads the **local** App Group projection and mutates the **local**
store through the seam — fully independent of CloudKit. `CloudKitCapability.entitledInThisBuild` stays
`false`; no entitlement, container, or sync claim is added.

**Consequences.** No new app-extension target, no new App Group, no schema change (stays **V6**).
`ProductionReadinessM22Tests.M22ControlWidgetPlatformTests` fails the build if any `ControlWidget` API
leaks into non-iOS production code, and the M19 CloudKit-honesty tests stay green. See
`docs/31-CONTROL-CENTER-CONTROLS.md`.

---

### ADR-093 — The configurable Control Center quick-start control uses `AppIntentControlConfiguration`

**Context.** Milestone 23 adds a **user-configurable** Control Center control: the user chooses *which*
saved timer it starts. Milestone 22 deliberately deferred this and shipped only fixed-behaviour
`StaticControlConfiguration` controls. The user-selectable variant needs WidgetKit's
`AppIntentControlConfiguration`, which is `@available(iOS 18.0, macOS 26.0)`.

**Decision.** The new `TimeFrameQuickStartControl` (in the **existing** `TimeFrameiOSWidgets` extension)
is an `AppIntentControlConfiguration` whose configuration is `QuickStartControlConfigurationIntent` — a
`ControlConfigurationIntent` with a single optional `timer` parameter. WidgetKit presents that parameter
in the standard Control Center configuration UI and persists the choice against the installed control; the
app persists **nothing** for it (no UserDefaults, no SwiftData). The control shows no countdown (a
quick-start is a command, not a live readout), so it needs no value provider and no clock. Its title and
VoiceOver phrasing come from the pure Foundation-only `QuickStartControlPresentation` (Shared/), reading
only the selected timer's frozen name — a deleted/blank selection reads as a safe "Start Timer".

**Consequences.** `AppIntentControlConfiguration` (and the rest of the ControlWidget API) stays **iOS-only**
— the macOS app, `Core/`, `Shared/`, and the macOS widget remain ControlWidget-free. No new extension, no
new App Group, no schema change (stays **V6**). `ProductionReadinessM23Tests` fails the build if the API
leaks into non-iOS code, and the M22 controls are unchanged. See
`docs/32-CONFIGURABLE-CONTROL-CENTER.md`.

---

### ADR-094 — The stable AppEntity id is the reference, not a cached timer configuration

**Context.** The configurable control must remember which saved configuration it starts, across renames
and edits, without the widget extension importing SwiftData and without the control becoming a second
source of truth for timer values.

**Decision.** The selectable entity is `QuickStartTimerEntity`, keyed by the configuration's **stable
`UUID`**. It is resolved from a lightweight, Foundation-only **App Group catalog snapshot**
(`QuickStartCatalog`/`QuickStartCatalogStore`) that the app writes (`QuickStartCatalogWriter` maps the
existing `ConfigurationRepository`) — so the picker works in any process and imports no SwiftData. The
catalog carries only frozen **display** values (id + name + a short subtitle); it is never authoritative
for timing. When the control is tapped, the app **re-resolves the authoritative live configuration by id**
through the existing `AppIntentSessionActions.startSession(configurationID:)`. Therefore a **rename** or a
**duration change** takes effect on the next tap, and a **deleted** configuration resolves to nothing —
the start fails safely with the existing `TimeFrameIntentError.configurationUnavailable` (never a phantom
session, never a silent fallback to a different timer). A `nil` selection starts the user's default
configuration.

**Consequences.** No cached duration ever becomes a second source of truth (Phase 9). The catalog reuses
the **existing** App Group (`group.abirbarman.com.time-frame`) under a distinct key — no new group. See
`docs/32-CONFIGURABLE-CONTROL-CENTER.md`.

---

### ADR-095 — Configured quick-start commands reuse the single existing mutation seam

**Context.** Tapping the configured control must start the chosen timer without introducing a second
start path, coordinator, or timer authority.

**Decision.** The chain is
`ControlWidgetButton(action:) → TimeFrameQuickStartIntent → WidgetControlActions.performQuickStart(configurationID:)
→ AppIntentSessionActions.startSession(configurationID:) → SessionCoordinator → TimerEngine`. The selected
entity is carried by the action intent as **data**; `WidgetControlActions` gains one `performQuickStart`
capability (the app wires it in `WidgetControlRouting`, alongside the M15 `handler` and the M22
`primaryHandler`) but remains the **one** router. WidgetKit runs the intent in the app process, so
`@AppDependency` resolves the app-registered router; an unregistered process fails safely with
`WidgetControlError.unavailable`. `startSession`'s existing `requireNoActiveSession()` guard means rapid
taps and an already-running session never duplicate a session.

**Consequences.** Exactly one `TimerEngine`/`SessionCoordinator` and one mutation seam remain.
`ProductionReadinessM23Tests` asserts `WidgetControlActions` is still declared only in
`Shared/WidgetControlIntents.swift` and that the configurable control constructs no engine, schedules no
clock, and defines no second seam. See `docs/32-CONFIGURABLE-CONTROL-CENTER.md`.

---

## ADR-096 — Time Frame has one product identity and one logo across all appearances

**Status.** Accepted (Milestone 24).

**Context.** The app needed a shipping user-facing name and an application icon. The user supplied a
**single** 1024×1024 logo (`tf_logo.png`, opaque, "TF") and required it be used unaltered for both Light
and Dark, on every platform.

**Decision.** The user-facing name is **"Time Frame"** everywhere the OS shows it — the macOS
`INFOPLIST_KEY_CFBundleDisplayName`, the iOS `CFBundleDisplayName`, widget `configurationDisplayName`s,
and Control Center display names — while every **internal** identifier (module/target names, bundle id
`abirbarman.com.time-frame`, App Group `group.abirbarman.com.time-frame`, URL scheme `timeframe://`,
SwiftData schema) is left unchanged. The one supplied logo is the single source artwork: the macOS
`AppIcon.appiconset` carries the classic mac raster ladder (16…1024 px) generated from it, and the iOS
`AppIcon.appiconset` (created in M24) carries a single 1024 "single-size" universal slot. Neither
`Contents.json` declares an `"appearances"` split — one image serves Light, Dark, and tinted contexts —
and no `*Dark*`/`*Light*`/tinted variant set exists. Only technically-necessary rasterization is
performed; the artwork's identity is never recolored, inverted, or redesigned.

**Consequences.** The macOS display name, which previously resolved to `PRODUCT_NAME` (`time_frame`), is
now "Time Frame" (verified in the built bundle). The iOS app gained its first asset catalog and app
icon. `ProductionReadinessM24Tests` fails the build if the display name regresses, an app icon is
missing/unreferenced, a second logo design (appearance-split or `*Dark*`/`*Light*` set) appears, or an
internal identifier changes. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md`.

## ADR-097 — The Control Center quick-start catalog refresh is event-driven and projection-based

**Status.** Accepted (Milestone 24).

**Context.** M23 published the quick-start picker catalog (`QuickStartCatalog`, App Group) **once** at
launch, so a configuration created/renamed/deleted after launch was not reflected until the next launch.
The refresh had to become live **without** polling, a second timer, or a second store, and **without**
the persistence layer depending on the widget/projection layer.

**Decision.** `ConfigurationRepository` gained a neutral, opaque `onChange: (@MainActor () -> Void)?`
hook fired after every successful mutation (create/update/delete/duplicate/setDefault/seed). The
repository knows nothing about *why* an observer cares — it just fires an event, so the downward-only
dependency rule holds. `SessionCoordinator.init` forwards the hook (new optional parameter, default
`nil`) to the repository without owning any widget knowledge. Each app wires the hook to
`QuickStartCatalogWriter.refresh(…)`, suppressed under the XCTest host (hermeticity, ADR-077) and
best-effort. The one-time launch publish is retained for the no-change launch.

**Consequences.** The picker stays current on every configuration change with no polling loop, no new
timer primitive, and no new persistence store — the App Group catalog remains a projection/cache over
the authoritative SwiftData model. `ProductionReadinessM24Tests` proves the hook fires on mutations,
does not fire on a rejected create, and is safe when nil. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md`.

## ADR-098 — M24 validates the presentation surfaces without adding a second timing authority

**Status.** Accepted (Milestone 24).

**Context.** M24 is identity + on-device UX validation + polish over the M11–M23 surfaces (Control
Center, widgets, Lock Screen, Live Activity, notifications, accessibility). Such a milestone can drift
into re-implementing surfaces or adding "helper" state.

**Decision.** M24 adds **no runtime architecture**. There remains exactly one `TimerEngine`, one
`SessionCoordinator`, one `AppIntentSessionActions` mutation seam, one App Group, and the schema stays
V6. The only behavioural edits are the identity work (ADR-096), the event-driven catalog refresh
(ADR-097), and a stale-string polish in the macOS About row (now the real bundle version). Accessibility
was reviewed, not churned: the existing mature coverage (VoiceOver countdown value +
`.updatesFrequently`, verb-labeled controls, menu-bar phrasing, pure presentation strings) had no
genuine gaps, so no unrelated changes were made. Widgets/Live Activity/notifications were validated via
the existing suites, not rewritten.

**Consequences.** The boundary is self-enforcing: `ProductionReadinessM24Tests` re-asserts the App
Group, URL scheme, bundle id, and V6 schema, and the M17…M23 audits continue to guarantee the single
engine/coordinator/seam, the persistence/widget/App-Intent boundaries, ActivityKit-only-on-iOS, and
CloudKit-disabled. CloudKit stays disabled (personal/free team; `entitledInThisBuild == false`). See
`docs/33-M24-ON-DEVICE-UX-VALIDATION.md`.

## ADR-099 — The heartbeat is generation-stamped, and presentation work is deferred off the control path

**Status.** Accepted (Milestone 26).

**Context.** Users reported the app intermittently freezing while a Pomodoro was running: Pause, Stop
and Skip would stop responding. Two independent defects were reproduced deterministically against the
shipping code (see `docs/34-M26-STABILITY-AND-RELIABILITY.md`), and both funnelled into the same
symptom — a saturated main actor.

1. **Heartbeat multiplication.** `startTickingIfNeeded()` created the tick loop as a `Task` that
   cleared `self.ticker` as it unwound. A cancelled heartbeat does not stop instantly: it resumes from
   its `Task.sleep` on a *later* main-actor turn. If a control had started a new heartbeat in the
   meantime, the old generation's late unwind cleared the handle to the **new** loop. That loop then
   became unreferenced — `stopTicking()` could no longer cancel it — while the now-`nil` `ticker`
   defeated the `ticker == nil` guard, so the next control started yet another. Live tick loops grew by
   one per pause→resume→control cycle (measured: 11 concurrent loops after ten cycles), each waking the
   main actor four times a second, without bound.

2. **Unbounded presentation work on the mutation path.** `WidgetProjectionWriter.handle(_:)` runs
   **synchronously inside** `pause()`/`resume()`/`stop()`/`skip()`/`startSession()` via the lifecycle
   fan-out. It called a `todayProvider` that fetched **every** `FocusSession` ever recorded, faulted in
   each one's intervals, and ran two full aggregations — all before the control returned. Pause latency
   was therefore O(lifetime history): measured at 5.6 ms per control with 10 recorded sessions versus
   **770 ms** with 2,000 — a 137× regression that grows forever as the user accumulates history.

**Decision.**

*Heartbeat lifetime.* The coordinator keeps a monotonic `tickerGeneration`. Each heartbeat captures the
generation it was born into and clears `ticker` **only if it is still the current one**; `stopTicking()`
retires the generation before cancelling. The handle therefore always describes reality, so a heartbeat
can neither be orphaned nor duplicated. `SessionCoordinator.activeTickerCount` exposes the `0...1`
invariant so the stability suite asserts it behaviourally rather than by inspection.

*Presentation deferral.* `WidgetProjectionWriter` splits its work by **cost, not importance**. The
session projection — derived entirely from the engine's in-memory anchors, and therefore free — is
still written synchronously, so no surface can show a stale running/paused state. The today summary is
refreshed on a **coalesced** follow-up main-actor task that runs after the control path has returned,
rewriting the projection only if the figures actually changed. A burst of transitions collapses into a
single statistics pass.

This adds no timer, no clock, no polling and no retry: the follow-up is scheduled by the same
transitions that already write, and it is a one-shot task, not a loop. The engine remains the one
timing authority and the coordinator the one mutation seam.

**Consequences.** A timer control now performs **zero** statistics reads and its latency is independent
of recorded history (measured 137× → 1.0×). Heartbeats settle at exactly one while running and zero
otherwise, across 100-cycle stress runs on both platforms. The widget's today figures arrive one
main-actor turn later than before — an intentional, tested trade, covered by
`ControlPathResponsivenessTests` and the updated `WidgetProjectionWriterTests`. The generation guard is
pinned structurally by `ProductionReadinessM26Tests` because its removal silently reintroduces unbounded
tick-loop multiplication. See `docs/34-M26-STABILITY-AND-RELIABILITY.md`.

## ADR-100 — Period statistics are fetched period-bounded, never over all history

**Status.** Accepted (Milestone 26).

**Context.** `StatisticsRepository.sessionInputs()` fetched every session ever recorded and mapped each
one — and mapping is the expensive part, because it faults in that session's `SessionInterval` rows.
Every period-scoped consumer paid the full lifetime cost to render a single day: the widget's today
summary (on the timer control path — ADR-099), the macOS `TodayView` and `StatisticsView` (which
`@Query` all sessions and re-aggregate on every body pass, i.e. after every store save a timer control
triggers), and the iOS `TodayScreen`/`StatisticsScreen` (which fetched all history *per body
evaluation*, with no query cache at all). `TodayView` additionally aggregated the whole snapshot twice
per body pass, once for each figure it displayed.

**Decision.** Introduce one pure definition of "relevant to a period" —
`StatisticsDateRange.mayContainActivity(startedAt:endedAt:)` — and route every period-scoped consumer
through it.

The aggregator attributes session-level metrics by `startedAt` and interval-level metrics by a completed
interval's end instant. Every interval end necessarily lies within `[session.startedAt, session.endedAt]`
(a session's `endedAt` is stamped from its last completed interval), and an open session has no end yet.
So a session can contribute to `[start, end)` only when `startedAt < end` **and**
`(endedAt ?? .distantFuture) >= start`. This is an exact **superset** test: it admits every session that
could contribute and excludes only sessions whose entire span lies outside the range.

`StatisticsRepository` gains `sessionInputs(in:)` and `sessionInputs(in:or:)` (the second for callers
that also need a comparison period from one pass), which apply the filter **before** mapping. The
unbounded `sessionInputs()` is retained for genuinely all-time questions. The SwiftUI screens keep their
`@Query` (it is what invalidates them on a store change) but apply the same filter before mapping.

**Consequences.** Aggregating the bounded subset is **byte-identical** to aggregating all of history for
the same range — asserted directly, on both platforms, over six ranges spanning the seeded window, its
edges, and regions entirely outside it (`BoundedStatisticsEquivalenceTests`). If that equivalence ever
breaks, the filter is wrong and statistics are silently losing data, so the test is the load-bearing
guarantee of this ADR. Cost becomes proportional to the period shown rather than to the lifetime of the
app, for the widget summary and all four screens. No schema change, no second store, no cache to
invalidate. See `docs/34-M26-STABILITY-AND-RELIABILITY.md`.

## ADR-101 — A `MenuBarExtra` label must not contain a `TimelineView`; its countdown repaints from the existing heartbeat

**Status.** Accepted (Milestone 26).

**Context.** After the ADR-099/100 work, the app still froze — this time *the moment a session was
started*, and then on every subsequent launch. Sampling the live process (`sample`) showed the main
thread pinned at 100% CPU with 199/199 samples inside a single SwiftUI cycle:

```
AppMenuBarExtrasController.makeMenuBarExtras
  → MenuBarExtraController.updateConfiguration
    → ViewGraphRootValueUpdater.invalidateProperties
      → MenuBarExtraHost.requestUpdate(after:)
        → UpdateGroup.dispatchActions
          → MenuBarExtraController.updateButton
            → -[NSStatusBarButton setImage:]   (re-rendering the SF Symbol, forever)
```

A `MenuBarExtra` **label** is not an ordinary view: SwiftUI renders it into an `NSStatusBarButton`
image, and `MenuBarExtraHost` re-renders it *synchronously* when its properties invalidate.
`TimeFrameMenuBarLabel` used `TimelineView(.periodic(by: 1))` while running, and the `TimelineView`
re-arms its schedule during that render — so the host requested the next update immediately rather
than a second later. The `after:` delay collapsed to zero and the loop never yielded.

The trigger is exactly `engine.state == .running`, which is why it presented as *"the app freezes when
I start a session"*. It was also self-perpetuating across launches: the frozen app could never stop the
session, so it stayed `running` in the store, and the next launch recovered it (ADR-014) and froze
again before the window was usable. The store recovered from the reporting machine contained exactly
one session, status `running`, with no `endedAt` — the signature of that trap.

Two hypotheses were tested against the real app, both falsified before the third succeeded:

1. *Removing the `TimelineView` fixes it* — confirmed the cause (100% → 0.6% CPU), but removes the
   ticking countdown, so it is not a fix.
2. *The loop is caused by rebuilding the projection (which reads the SwiftData `activeSession` model)
   **inside** the `TimelineView` closure* — **false.** Hoisting every observable read outside the
   schedule and leaving only pure arithmetic inside still span at 99% CPU. The `TimelineView` itself is
   the problem in this position, regardless of its contents.

**Decision.** No `TimelineView` (and no scheduling primitive of any kind) in a `MenuBarExtra` label.
The countdown still has to tick, so the repaint is driven from **outside** the render pass by the
heartbeat that already exists: `SessionCoordinator` publishes a display-only `displaySecond` — the
whole-second instant of the most recent tick, written at most once a second, only from `tick()`, and
only when the second actually changes. The label observes it and re-derives its title from
`presentation` as before.

This is **not** a second clock. It is the same single heartbeat that already reconciles the engine, and
`displaySecond` carries no authority: remaining time is still derived exclusively from `TimerEngine`'s
frozen anchors, nothing decrements, and no persistence, notification or projection work happens on that
path. Crucially, because the change originates *outside* rendering, it cannot re-trigger itself — which
is precisely the property the `TimelineView` lacked here.

`TimelineView` remains correct and unchanged everywhere else (`TimerDisplay`, `TodayView`, the menu-bar
*popover*), because those are ordinary hosted view hierarchies, not status-item image rendering.

**Consequences.** With the same recovered running session, the app went from 100% CPU / unresponsive to
1–2% CPU / idle. `MenuBarLabelRepaintTests` pins both halves: a source audit that no `TimelineView`,
`Timer(`, `scheduledTimer`, `asyncAfter` or `Task` returns to the label (the failure lives in SwiftUI's
status-item hosting, so no unit test can observe it directly — the rule that produced it is what gets
pinned), and behavioural tests that `displaySecond` advances at whole-second granularity and carries no
timing authority. See `docs/34-M26-STABILITY-AND-RELIABILITY.md`.

---

# Milestone 28 — Menu Bar Popover UX, Quick Start Pinning & Icons

## ADR-102 — The popover's secondary actions live behind a gear, not in its primary content

**Context.** Since Milestone 8 the menu bar popover ended in four permanent rows — Open Time
Frame, Settings, History, Quit. They are navigation, not timer control, yet they took roughly a
third of the popover's height in every state, including while a session was running. There was
also nowhere to put anything new: adding Quick Start would have made the popover a list of
links with a timer above it.

**Decision.** The four navigation actions move behind one native SwiftUI `Menu` with a
`gearshape` label in the header's top-trailing corner. The popover's primary content is then
ordered by importance: identity, then (when a session is live) the countdown and the transport
controls, then Quick Start, then the fallback Start action when nothing is running.

The actions themselves are **unchanged**: the same accessibility identifiers, the same
`openWindow(id: "main")` plus `AppNavigation` seam, the same `NSApplication.terminate`. There
is still one `WindowGroup`, one Settings screen, and one History screen.

Two layout rules are load-bearing and are enforced by tests rather than by review:

1. **The transport controls are laid out outside any scroll view.** Only the pinned list
   scrolls, inside a bounded height. However many items are pinned, the controls cannot be
   pushed off screen.
2. **The status-item label still contains no `TimelineView`** (ADR-101). Nothing in this
   redesign touches the label's repaint model; it still observes `displaySecond`.

Running and paused now offer the same four controls (Pause/Resume, Skip, Restart, Stop) so the
row does not re-flow mid-session. Restart became available while running; it routes through the
`SessionCoordinator.restart()` that already existed.

**Consequences.** The popover's height is roughly constant and its most-used content is at the
top. Secondary actions cost one extra click, which is the correct trade for a surface whose
whole purpose is speed on the primary path. `MenuBarPopoverStructureTests` fails the build if a
navigation identifier reappears outside `MenuBarGearMenu.swift`, if the controls view or the
popover root gains a `ScrollView`, if the pinned list loses its height bound, or if any menu
bar view introduces a scheduling primitive.

---

## ADR-103 — Template and Plan icons are a closed, typed catalog with one resolver

**Context.** Templates and Plans needed a visual identity that follows them from their list to
the menu bar. The obvious implementation — store an SF Symbol name on the model — has two real
failure modes: a stored string can name a symbol that does not exist (a missing glyph, on the
user's screen, with no build-time signal), and symbol names would end up spelled out across
many views.

**Decision.** A closed catalog, `TimeFrameIconIdentifier`, in `Core/Support/TimeFrameIcon.swift`.
Each member has a stable identifier, an SF Symbol name, a display name, and a category.

- **The persisted value is the identifier**, a plain dot-free token — never a symbol name,
  never free text. The editor's control is a typed `Picker` over the enum, so an arbitrary
  symbol string cannot be selected, typed, or pasted in.
- **`symbolName` is the one mapping.** Views ask an item for its `icon` and render
  `icon.symbolName`; `TimeFrameIconBadge` is the one renderer.
- **Stored data is always resolved, never trusted.** `resolve(_:fallback:)` maps an unknown,
  empty, or absent value to the type's default, so a corrupt row, a downgrade, or a value from
  a newer build still renders.
- The identifier is deliberately **decoupled** from the symbol name, so a symbol can be
  swapped for a better one in a future OS without rewriting stored rows.

The catalog is Foundation-only, so the models can reference it without the domain gaining a
presentation dependency, and it compiles into both platforms.

**Consequences.** A typo in the catalog fails the build:
`TimeFrameIconCatalogTests.everySymbolResolves` renders every entry through
`NSImage(systemSymbolName:)`. `ProductionReadinessM28Tests` asserts the enum is declared in
exactly one file, that the raw `iconIdentifier` string is read in exactly four (the two models
and their two repositories), and that no view passes it to `systemName:`.

A native `Picker` with a section per category was chosen over a symbol grid: keyboard
navigation, type-select, focus ring, and VoiceOver all come for free, and the control stays
compact inside a `Form`. Each option shows glyph plus name and carries a "<Name> icon" label,
so the choice is never conveyed by the glyph alone.

---

## ADR-104 — Pin state lives on the pinned item, keyed by its stable id

**Context.** Quick Start needs to know which Templates and Plans the user pinned. The tempting
implementations — a list of pinned ids in `UserDefaults`, or a pinned-items table — are both a
second place where the truth lives, and both have to be reconciled when an item is renamed,
edited, or deleted.

**Decision.** Pin state is two attributes on the item itself: `isPinned: Bool` and
`pinnedAt: Date?`, on `TaskTemplate` and `SessionPlan`, keyed by their existing stable `UUID`.
No side table, no preference key, no App Group key.

Four behaviours follow directly from that, rather than from reconciliation logic:

| Behaviour | Why |
| --- | --- |
| A **rename** keeps the pin | identity is the `id`; the name is not part of it |
| A **delete** removes it from Quick Start | the pin lived on the row that went away |
| An **edit** never changes the pin | `isPinned` is deliberately not part of the draft |
| A **duplicate** copies the icon, not the pin | pinning is an explicit choice about one item |

Pinning is idempotent: re-pinning keeps the original `pinnedAt`, so the order never jumps.

The **Quick Start list is a read-only projection** of those pinned rows, not a store:
`QuickStartProvider` maps them to pure `QuickStartItem` values ordered oldest-pin-first (ties
broken by name then id, so the comparator is total). Subtitles read the item's live data, so an
edited configuration shows new durations with nothing cached to invalidate.

**Starting routes through the seam that already exists**:
`QuickStartCoordinator.start` → `AppIntentSessionActions.startTemplate/startPlan` →
`SessionCoordinator` → `TimerEngine`. No new start path. The cached list is a display cache
only: a start re-resolves the authoritative item by id, so a stale row for a deleted item fails
safely through the closed `TimeFrameIntentError` set — a message, no phantom session, and a
timer left exactly as it was.

**Relationship to the Milestone 23 App Group catalog.** `QuickStartCatalog` is unchanged and is
*not* a competing store. It exists because the iOS Control Center picker runs in a
widget-extension process that cannot import SwiftData, so it needs a cross-process snapshot of
the user's **configurations**. The macOS popover runs in the app process and reads the
repositories directly, which is strictly better there. Both derive from the same authoritative
models; pin state is persisted in exactly one place.

**Schema.** This is what moves the schema **V6 → V7**: three attributes on each of two models,
the same six model types, every attribute defaulted or optional (so CloudKit-legal per ADR-061
and lightweight-migratable). Nine earlier suites that asserted "still V6" as shorthand for "this
milestone added no model" were retargeted to assert the current version **and** the six-entity
set — the invariant they actually own.

---

## ADR-105 — Quick Start refreshes on the repositories' change hook, never by polling

**Context.** The `MenuBarExtra` scene has no SwiftData environment — only the `WindowGroup`
carries the model container — so the popover cannot use `@Query`. It needs its pinned list to be
current the moment the user pins something, without a restart and without polling.

**Decision.** Reuse the pattern ADR-097 established for the Control Center catalog.
`TaskTemplateRepository` and `SessionPlanRepository` gained the same neutral, opaque `onChange`
hook `ConfigurationRepository` already carries, fired after every successful mutation.
`SessionCoordinator.init` forwards it as one new optional parameter, `onLibraryChanged`, exactly
as it already forwards `onConfigurationsChanged`. The app wires it to
`QuickStartCoordinator.refresh()`.

```
repository mutation → onChange (opaque) → SessionCoordinator forwards → refresh() → Observation redraw
```

The persistence layer stays ignorant of who observes it: the repositories mention no
`QuickStartCoordinator`, no menu bar, and no WidgetKit — dependencies still point downward only.

**Consequences.** No polling, no timer, no second clock. `ProductionReadinessM28Tests` fails the
build if the Quick Start layer contains `Timer(`, `Task.sleep`, `asyncAfter`, `scheduledTimer`,
`DispatchSourceTimer`, `TimelineView`, or `publish(every`, and re-asserts that
`SessionCoordinator.swift` remains the only file in `Core/` containing `Task.sleep` (ADR-099).
A refresh reads only pinned rows and swallows any failure, so a Quick Start problem can never
disturb the app or the one timer.

See `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md`.

---

---

## ADR-106 — A pushed detail page presents its own editor sheet

**Status.** Accepted (Milestone 29).

**Context.** `TemplateDetailView` and `PlanDetailView` are pushed by a
`navigationDestination` inside their list's `NavigationStack`. Both delegated editing upward: the
detail page called an `onEdit` closure that set `@State` on the list, and the list's
`.sheet(item:)` — attached to the `NavigationStack` — was supposed to present the editor.

It did not. On macOS a sheet requested from the stack's **root** while a destination is pushed is
not presented; the request is held until the stack pops back, at which point the editor appears
over the list, apparently unprompted. So "Edit" on either detail page looked dead. Every other
action on those pages worked, because every other action was local to the page.

This was reproduced by driving the running app: pressing Edit produced nothing, and navigating back
produced the correctly-populated editor.

**Decision.** A view presents the sheets it owns. Each detail page holds its own
`@State private var editing…` and its own `.sheet(item:)`, and neither page takes an `onEdit`
closure any more. The lists keep their own `.sheet` for Create and for their own row actions, where
the root view is on screen and presentation works.

```
TemplateDetailView  --(local @State)-->  .sheet -> TemplateEditorView -> TaskTemplateRepository.update
PlanDetailView      --(local @State)-->  .sheet -> PlanEditorView     -> SessionPlanRepository.update
```

**Consequences.** Nothing below the view layer changed: the same editor, the same repository, the
same identity, pin, icon, timeline and history. Because a behaviour test cannot see a presentation
bug, `EditorPresentationStructureTests` audits the source — each detail page must contain its own
editor sheet, neither may contain `onEdit`, and neither list may pass `onEdit:` into a pushed
destination. `TemplateEditFlowTests` and `PlanEditFlowTests` cover identity preservation, the
absence of duplicates, pin and icon persistence, cancellation, rejection of invalid edits, the
Quick Start refresh, and the fact that editing never disturbs a running timer.

See `docs/38-M29-MACOS-UI-REDESIGN.md`.

---

## ADR-107 — The menu bar popover does not scroll

**Status.** Accepted (Milestone 29). Supersedes the height-bounded scrolling list introduced with
ADR-102.

**Context.** Milestone 28 put the Quick Start list inside a height-bounded `ScrollView` so a long
list of pins could not push the transport controls off screen. That protected the controls, but it
made the popover partly hide its own contents and turned a glance-and-go surface into something the
user had to scroll and hunt in.

**Decision.** No part of the popover scrolls. `MenuBarQuickStartView.visibleLimit` (3) rows are
drawn and are always fully visible; any pins beyond that are offered by a compact "N more…" native
menu that starts them directly. Nothing is dropped and nothing is clipped.

**Consequences.** The transport controls are still structurally safe — the list is capped, not
bounded by height — and the popover stays a glance surface rather than a miniature of the app.
`MenuBarPopoverLayoutTests` now fails the build if **any** menu-bar view contains a `ScrollView`,
and additionally asserts that the cap is explicit, that the overflow is reachable rather than
discarded, and that the limit stays small. The start seam is unchanged
(`QuickStartCoordinator → AppIntentSessionActions → SessionCoordinator → TimerEngine`), and the
status-item label still contains no `TimelineView` (ADR-101).

See `docs/38-M29-MACOS-UI-REDESIGN.md`.

## ADR-108 — The type scale and the control-size rule live in the design system

**Status.** Accepted (Milestone 30). Extends ADR-050 (the design system is presentation-only).

**Context.** Milestone 9 centralised spacing, radii, motion and semantic colour; Milestone 29
centralised the components every screen composes. Two values were never centralised: how large a
control is, and how large a word is.

The consequences were visible. The Timer screen's Start action spanned the content column at
`.controlSize(.large)` while every other action in the app was sized to its content — a full-width
filled button at the foot of a column of labelled fields reads as a web form's submit button, not
as a macOS action. And the type hierarchy was a convention repeated in sixty files rather than a
decision recorded once: each screen named `.largeTitle.weight(.bold)`, `.headline`,
`.subheadline` and `.caption` itself, so it looked consistent only for as long as everyone kept
choosing the same four values.

**Decision.** `TFTypography` names the type roles the product uses (`pageTitle`, `subjectTitle`,
`sectionTitle`, `rowTitle`, `body`, `secondary`, `metadata`, `numericValue`, `groupTitle`,
`rowLabel`, `rowValue`) in native system fonts, and the shared components read from it.
`TFControl` plus `tfPrimaryAction()` / `tfSecondaryAction()` state the control rule: a screen has
exactly one prominent action, it is sized to its content at the native `.regular` height with a
108 pt floor width, and supporting actions match that height. `tfPrimaryAction` offers no
full-width variant — a control that spans its container says so at the call site.

One call site does: the menu-bar popover's single fallback action, whose 288 pt container genuinely
is the width of the control. That exception is recorded by a test rather than left to memory.

**Consequences.** Changing what a section title or a primary action looks like is one edit. The
Timer screen, Template detail and Plan detail now share one action height instead of three similar
ones. A disabled Start states why in words rather than relying on being dim (§48).

This changes no runtime architecture: the design system still imports none of the domain, no file
under `Timer/`, `Services/` or `Models/` changed, the schema stays **V7**, and there is still one
`TimerEngine`, one `SessionCoordinator` and one Quick Start projection. `ProductionReadinessM30Tests`
fails the build if a redesigned page reaches for `.large`, if the Timer's Start becomes full-width
again, if a type role disappears, or if a redesigned screen introduces a scheduling primitive.

The audits are source scans and assert no pixel geometry — they prove the rule is applied, not that
a screenshot was matched.

See `docs/39-M30-DESIGN-SYSTEM-CONSOLIDATION.md`.

## ADR-109 — A store that cannot be opened is preserved, never deleted

**Status.** Accepted (Milestone 31). **Supersedes ADR-016** (rebuild-on-incompatibility).

**Context.** From Milestone 2 the store had one answer for a failed open: delete the store
files and build a fresh one in their place. ADR-016 justified it while the only thing at risk
was "the re-seedable default configuration and any dev-only prior sessions". That justification
stopped being true the moment the app persisted templates, plans and history — but the code did
not change, and two tests were written that asserted the deletion happened.

The `catch` was not narrow. It caught *every* error `ModelContainer(for:migrationPlan:configurations:)`
could throw: a schema mismatch, yes, but equally a locked file, a denied permission, a truncated
WAL, or a transient I/O failure. Any of those was answered by erasing the only copy of the user's
history, with no backup, no prompt, and a single log line as the trace.

This is not hypothetical. During Milestone 31's own investigation a locally built copy of the app
opened a developer's real store (see ADR-110) and this path destroyed it: templates, plans,
configurations and all recorded sessions, unrecoverably.

**Decision.** The app never removes a store because opening it failed.

- `PersistenceController.openOnDiskContainer` classifies the failure (`StoreOpenFailure`) and
  throws `StoreOpenError`. It touches no files.
- `removeStoreFiles(at:)` was **deleted**, not left unused. While it existed, the safest-looking
  `catch` in the file was one line from erasing a user's history.
- Failure classification is explicit and closed (`schemaMismatch`, `migrationFailed`,
  `storeCorrupt`, `malformedStore`, `fileAccessFailed`, `permissionDenied`, `fileLocked`,
  `unknown`). An unrecognised failure is `unknown` — never a default of "corrupt", because that
  default is what licensed the deletion.
- `bootstrap` returns `PersistenceState.needsRecovery(failure)` with a **scratch in-memory**
  container, so the app can launch far enough to explain itself without writing anything to disk.
- The user decides. `PersistenceRecoveryView` says the data was not opened, says plainly that
  **nothing has been deleted**, and offers Try Again / Show in Finder / Continue Without Existing
  Data. Only the last changes anything, and it confirms first.
- "Continue Without Existing Data" *moves* the store — with its `-wal` and `-shm` sidecars, which
  can hold committed transactions the main file does not — into
  `TimeFrame Recovery/<UTC timestamp>/`. Collisions are impossible by construction, so an earlier
  recovery copy is never overwritten. If the move fails, the operation fails and the app stays in
  recovery: it never trades the user's data for a clean launch.

**Rejected: keep "delete and rebuild" behind a narrower error check.** A narrower `catch` would
still be a guess about someone's only copy of their data, and the guess only has to be wrong once.
Preserving costs a folder.

**Consequences.** An unopenable store now blocks the library behind an explanation instead of
presenting an empty one — which is the specific failure mode that made the data loss invisible.
`ProductionReadinessM31Tests` fails the build if any production source calls
`FileManager.removeItem`, if `removeStoreFiles` returns, if the opener stops classifying, or if
the app stops branching on `needsRecovery`. The two tests that asserted the old behaviour were
inverted rather than deleted, so the policy they encoded cannot quietly return.

See `docs/40-M31-DATA-SAFETY-AND-RECOVERY.md`.

## ADR-110 — The store's location is an explicit decision, and tests cannot reach production

**Status.** Accepted (Milestone 31).

**Context.** The macOS app is not sandboxed and passed no URL to `ModelConfiguration`, so it used
SwiftData's default store: `~/Library/Application Support/default.store`. Every build on a machine
— the installed copy, an Xcode Debug build, a build launched by tooling — resolved to that one
file, and to the one `abirbarman.com.time-frame` defaults domain. Nothing said so anywhere, and
nothing warned.

That is how a locally built copy of the app came to open a developer's real library and, via
ADR-016's rebuild path, destroy it.

**Decision.** `StoreLocation` resolves the store URL explicitly, with production as the case a
process has to *fall through to* rather than get by default:

1. `TIMEFRAME_STORE_DIRECTORY` redirects any build to a scratch store — an explicit developer
   choice always wins.
2. An XCTest host resolves to an isolated store under the temporary directory, so a test that
   forgets to pass a URL still cannot reach production data.
3. Otherwise, production — at exactly the path the app has always used, so no existing user's
   data is orphaned by this change.

`productionStoreURL()` is named separately so every call site wanting real user data is greppable,
and `assertNotProductionStore(_:)` traps for destructive tests that must never touch it.

**Consequences.** The production path is unchanged for real users. Running the test suite cannot
touch a developer's library, and this is asserted against the *live* environment rather than a
synthetic one. `ProductionReadinessM31Tests` fails the build if the store URL stops being
explicit, or if any test source names the production path.

The bundle identifier is deliberately **not** changed: doing so would orphan existing users' data
and their notification and calendar permissions. A Debug build still shares the identifier — and
therefore `UserDefaults` — with an installed copy; only the SwiftData store is isolated. That
remains a known limitation.

See `docs/40-M31-DATA-SAFETY-AND-RECOVERY.md`.

## ADR-111 — Time Frame has one main window, and one pathway to it

**Status:** accepted (Milestone 32)

**Context.** The main scene was a `WindowGroup`, a scene type whose purpose is to allow more than
one window: `openWindow(id:)` creates a new window on every call, and the system offers File ▸ New
Window. Four surfaces each held that capability and each wrote its own copy of
`navigation.request(…)` + `NSApplication.shared.activate(…)` + `openWindow(id:)`. There was no
policy — there were four copies of an action, and a fifth would have arrived the same way.

A Dock reopen was worse. Nothing implemented `applicationShouldHandleReopen`, so the default
machinery answered it, and that machinery reads `hasVisibleWindows` — which is false for a
*minimized* window and false for a *hidden* application. Clicking the Dock icon while the window sat
in the Dock produced a second window beside the first.

**Decision.**

1. The main scene is a single-instance **`Window`**. SwiftUI cannot present a second one, so the
   guarantee is architectural rather than defensive.
2. One **`MainWindowPresenter`** decides what "show the main window" means, for every surface —
   the gear menu, the popover's Start fallback, the Quick Start empty state, and the Dock.
3. The decision itself is a pure function, `MainWindowPolicy.action(for:applicationIsHidden:
   creationIsPending:)`, over a snapshot read **fresh from the live window on every request**.
   There is no `windowIsOpen` boolean: a boolean is wrong the moment the window is closed,
   minimized, hidden, or rebuilt by SwiftUI, and being wrong is what produced the duplicate.
4. The AppKit steps live behind `MainWindowHosting`, so the policy is testable without `NSWindow`.
   The host holds its window **weakly** and deregisters on `NSWindow.willCloseNotification`, so a
   closed window leaves nothing stale behind.
5. SwiftUI's `openWindow` is captured **once per scene** and republished as the
   `\.showMainWindow` environment action. It appears in exactly one file.
6. `applicationShouldHandleReopen` never consults `hasVisibleWindows`; it asks the presenter.
7. Two requests in one run-loop turn coalesce: the first creates, the rest are ignored. The mark is
   released by a one-shot main-actor continuation and by the window registering itself — never by a
   timer and never by a poll.
8. `applicationShouldTerminateAfterLastWindowClosed` returns **`false`**. This is not incidental:
   `WindowGroup` kept the process alive when the last window closed, and a single-instance `Window`
   does not. Both builds were launched and their windows closed to establish this. Without the
   override, ⌘W would end a running Pomodoro.

**Consequences.** No code path can create a duplicate main window, and there is no File ▸ New
Window. Focusing a window is window behaviour only: it never resets navigation, scroll position or
setup fields, and never touches the engine, the session, or history — asserted against a real
`SessionCoordinator`. Users can no longer open two windows of Time Frame, which was never a
supported workflow. Saved window frames move from the `main-AppWindow-1` key to `main`, so the
remembered size and position reset once. The layer is macOS-only; `Core/` and the iOS companion are
untouched. `ProductionReadinessM32Tests` fails the build if a `WindowGroup` returns, if `openWindow`
or window ordering escapes the window service, if the reopen handler branches on
`hasVisibleWindows`, if closing the window is allowed to quit the app, or if a boolean starts
standing in for the window's state.

See `docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md`.

## ADR-112 — The login item is registered with SMAppService, and the system is the source of truth

**Status:** accepted (Milestone 32)

**Context.** "Open at Login" is a setting whose value lives outside the app: macOS owns the login
item, the user can change it in System Settings, a registration can fail, and a registration can be
*pending the user's approval*. The tempting implementation — a `UserDefaults` boolean the toggle
binds to, with a registration attempt as a side effect — produces a switch that reads "on" while
nothing is registered. The user finds out at the next login.

**Decision.**

1. Use **`SMAppService.mainApp`** — the app registers itself. No helper bundle, no
   `SMLoginItemSetEnabled`, no `LSSharedFileList`.
2. `LoginItemService.swift` is the **only** file importing ServiceManagement, isolated exactly like
   `EventKitCalendarService` and `UserNotificationService`, behind a `LoginItemManaging` protocol so
   the coordinator and the tests never touch the real login-item database.
3. **Nothing is persisted.** No `UserDefaults` key, no `@AppStorage`. `isEnabled` is derived from
   the status `SMAppService` reports, re-read on launch, whenever Settings appears, and after every
   change — including a failed one.
4. `.requiresApproval` reads as **off**, with the reason stated and System Settings offered. It will
   not launch until approved, so it must not claim success.
5. Failures are the closed `LoginItemError` set, each with a description and a remedy; a raw
   ServiceManagement error is never shown. One attempt per user action, with no scheduling
   primitive in the coordinator, so a failure can never become a retry loop.
6. `register()`/`unregister()` are `nonisolated async`, so ServiceManagement runs off the main
   actor. Under the XCTest host the app injects `UnavailableLoginItemService`, so the suite can
   never register a developer build as a login item (ADR-077).

**Consequences.** The toggle cannot show a state the system does not hold. A refused registration
leaves it off; a refused removal leaves it on; an approval-pending registration says so. The app
adds no persistence and no schema change. `ProductionReadinessM32Tests` fails the build if
ServiceManagement leaks past the seam, if a deprecated login-item API appears, if the state is
persisted, if a change stops re-reading the system, or if the coordinator gains a retry loop.

Launching at login has **not** been verified by logging out and back in, and `SMAppService`
registration has not been exercised against the real login-item database — doing either would
register a development build on the developer's Mac.

See `docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md`.

## ADR-113 — The product name lives in `PRODUCT_NAME`; the Swift module is pinned separately

**Status.** Accepted (Milestone 33). Completes ADR-096 (product identity).

**Context.** Milestone 24 branded the app by setting `INFOPLIST_KEY_CFBundleDisplayName` to
"Time Frame", and `ProductionReadinessM24Tests` asserted it. The macOS **application menu** —
the bold title immediately right of the Apple menu — still read `time_frame`.

That title comes from `CFBundleName`, not `CFBundleDisplayName`. Nothing set it, so it fell
back to the generated default, which is `PRODUCT_NAME`, which was `$(TARGET_NAME)`. The menu
*items* were already correct ("About Time Frame", "Quit Time Frame") because those use the
display name — so every string a test might reasonably have inspected was right, and the one
that was wrong was the one nobody had named.

Two attempted fixes did not work and are worth recording so they are not retried:

- `INFOPLIST_KEY_CFBundleName` is **not honoured** by the build.
- Writing `CFBundleName` into the physical `Info.plist` is a **no-op**: with
  `GENERATE_INFOPLIST_FILE = YES` the generated value wins.

**Decision.** Set `PRODUCT_NAME = "Time Frame"` on the macOS app target, and pin
`PRODUCT_MODULE_NAME = time_frame` beside it.

`PRODUCT_NAME` is the only lever that moves `CFBundleName`. It also renames the bundle to
`Time Frame.app` and the executable to `Time Frame`, so the Dock, Finder, Force Quit and
Activity Monitor all show the product name. Because the Swift module name defaults to
`PRODUCT_NAME`, the pin is what keeps this safe: without it the module would be renamed and
every `@testable import time_frame` in the suite would stop compiling. `TEST_HOST` follows the
product and was updated in both configurations.

On iOS the target generates no `Info.plist`, so `CFBundleName` is stated in the file directly,
alongside `CFBundleIconName = AppIcon` — without which the icon compiles into `Assets.car` but
is never declared, and App Store validation rejects the build.

**Rejected: renaming the target, project, module or bundle identifier.** None of those is
user-facing, and each would break signing, the App Group, deep links, persistence or the test
suite. The product name is a *product* setting; the internal identifiers stay as they are.

**Consequences.** `Time Frame.app` replaces `time_frame.app` as the built product, so an
existing installed copy is not overwritten by a new build — the old bundle must be removed by
hand once. `ProductionReadinessM33Tests` asserts the keys M24's suite did not: `PRODUCT_NAME`,
the module pin, `TEST_HOST`, iOS `CFBundleName` and iOS `CFBundleIconName`, plus that the
bundle identifier, App Group and URL scheme did not move.

See `docs/42-M33-PRODUCT-NAME-AND-ICON.md`.

## Known constraints / notes for future work

- **SwiftData lifetime:** a `ModelContext` does not keep its `ModelContainer`
  alive. Always retain the container for as long as the context is used (this bit
  us once in tests). Reflected in `CLAUDE.md` and `docs/10-TESTING-PLAN.md`.
- **Live session recording** to SwiftData is implemented (Milestone 2+).
  **Statistics** are now implemented as a read-only projection of that history
  (Milestone 10; ADR-054) with **no** schema change — confirming the earlier
  expectation that the models and the engine's `IntervalRecord` history were shaped
  to support analytics without a redesign.
