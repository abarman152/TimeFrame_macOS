# 14 — Session Planner (Milestone 5)

The Session Planner is a **planning layer**: it lets a user design, preview, save,
edit, and start a multi-session Pomodoro plan before execution. It is **not** a
second timer. A plan is frozen into an immutable value snapshot at start, and that
snapshot runs through the existing `SessionCoordinator` → `TimerEngine` →
`FocusSession` path unchanged.

```
Template / Configuration
          │  (generate initial plan)
          ▼
      SessionPlan  ──edit──►  SessionPlan            (persisted, editable)
          │
          │  executionSnapshot   (freeze — ADR-028)
          ▼
 SessionPlanExecutionSnapshot     (immutable value, Sendable, no SwiftData)
          │
          ▼
   SessionCoordinator.startPlan
          │
   ┌──────┴───────┐
   ▼              ▼
TimerEngine    SessionRepository
   │              │
   └──────┬───────┘
          ▼
     FocusSession  →  SessionInterval  →  History
```

The key principle: **plan what to do → freeze what will execute → execute through
the existing engine → persist the actual session.**

> **Milestone 28.** A plan now carries a chosen **icon** (from the closed
> `TimeFrameIconIdentifier` catalog) and can be **pinned to Quick Start**, which shows it in the
> macOS menu bar popover ready to start in one click. Pin state lives on the plan itself, keyed by
> its stable `id`. Starting from Quick Start reuses the existing
> `SessionPlan.executionSnapshot → startPlan` chain — no new start path and no second timer. See
> `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md` (ADR-103/104).

---

## 1. What a Session Plan is

A `SessionPlan` is a named, ordered sequence of planned focus and break intervals —
what the user *intends* to run. It is distinct from a `FocusSession`, which is what
actually started/executed (ADR-026). A plan can be edited freely before starting;
once started, the resulting session is independent of the plan forever (ADR-029).

Example:

```
Research Deep Work            (name)
Research Quantum IDS          (task)

1  Focus       Research   50m
2  Short Break            10m
3  Focus       Research   50m
4  Short Break            10m
5  Focus       Writing    45m       ← a different configuration
6  Short Break            10m
7  Focus       Writing    45m
```

## 2. Model

Two SwiftData `@Model` types (schema V5), plus reused value types.

### `SessionPlan`
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `name` | `String` | the plan's own name |
| `taskName` | `String` | copied into the started `FocusSession` |
| `createdAt` / `updatedAt` | `Date` | `updatedAt` bumped on save |
| `items` | `[SessionPlanItem]` | inverse of `SessionPlanItem.plan`, **cascade** |

Derived: `orderedItems`, `focusCount`, `totalDuration`, `isStartable` (every focus
item still references a configuration), `draft` (value for editing), and
`executionSnapshot` (the frozen value to run — §6).

### `SessionPlanItem`
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `order` | `Int` | explicit 0-based position, normalized on save |
| `phase` | `TimerPhase` | focus / shortBreak / longBreak (the shared engine enum — ADR-027) |
| `duration` | `TimeInterval` | the item's **own** frozen length (seeded from, but independent of, the configuration) |
| `configuration` | `PomodoroConfiguration?` | focus items only; **nullify** inverse on the configuration |
| `configurationName` | `String` | frozen name, so a focus item still displays after its configuration is deleted |
| `plan` | `SessionPlan?` | inverse side (no macro here) |

`TimerPhase` is reused as the item "type" rather than inventing a parallel enum: it
is already the shared vocabulary of the engine, the generated plan, and the
persisted `SessionInterval`, so an item maps to an interval with no translation
(ADR-027).

### Multiple configurations (ADR-030)
Configuration lives **per focus item**, not per plan, so a plan may mix
configurations (Research focus + Writing focus). There is no `plan.configuration`.

## 3. Plan generation

`SessionPlanGenerator.generate(from:configurationID:configurationName:sessions:includeFinalBreak:)`
is a pure function producing `[PlanItemDraft]`. For N sessions and a long-break
interval L it emits `focus, break, focus, break, … , focus[, break]`, where the
break after focus *k* is long when `k % L == 0`. **The trailing break after the
final focus is optional and off by default** — the planner never forces a break
after the last focus (ADR-026, §22/§39 of the milestone). Generation is
deterministic: same input → identical plan.

## 4. Validation

`SessionPlanDraft.validate()` (pure) reports every violated rule
(`SessionPlanValidationError`), never silently modifying input:

- non-empty name and task;
- at least one focus interval;
- every focus interval has a configuration;
- every interval duration is `1 s … 8 h`;
- at most `PlanLimits.maxItems` (100) items;
- total duration `≤ 24 h`.

Limits live in `PlanLimits`; the per-interval maximum is shared with
`ConfigurationLimits.maxDuration`.

## 5. Configuration: snapshot vs reference (ADR-028)

- **While editing**, a focus item *references* a configuration (by id in the draft,
  as a to-one relationship in the model). Editing the configuration's durations does
  **not** change a saved plan item — the item's `duration` is its own frozen value.
- **At start**, the plan is frozen into a `SessionPlanExecutionSnapshot` (pure
  values). The running/historical `FocusSession` holds **no** live configuration
  reference; each interval freezes its `plannedDuration` and `configurationName`.
  Historical execution therefore never depends on mutable configuration state.
- Deleting a configuration **nullifies** the reference on plan items
  (`PomodoroConfiguration.planItems`, delete rule `.nullify`): the plan survives,
  the focus item shows its frozen name, `isStartable` becomes false, and the user
  must re-choose a configuration before starting (mirrors a template — ADR-024/029).

## 6. Execution snapshot & conversion

`SessionPlanExecutionSnapshot` is an immutable `Sendable` value independent of
SwiftData. It carries the task name and the ordered intervals (index, phase,
duration, per-focus `configurationName`), and derives `enginePlan` (an
`IntervalPlan`), `totalDuration`, `focusCount`, and `summaryConfigurationName`
(one name, or "Multiple configurations").

`SessionCoordinator.startPlan(_:)`:
1. guards no active session and a non-empty snapshot;
2. `engine.load(plan: snapshot.enginePlan)` + `engine.start()`;
3. `SessionRepository.createPlannedSession(...)` builds the `FocusSession` and its
   `SessionInterval`s (freezing each focus interval's `configurationName`);
4. `reconcile()` + start the heartbeat.

No second timer, no `PlannerSession`, no `PlannerTimerEngine`.

### `IntervalPlan` rename (ADR-031)
The engine's execution-plan value type, formerly `SessionPlan`, is now
`IntervalPlan`. The name `SessionPlan` is the user-designed planning **model**; the
engine runs an **interval plan**. Purely a rename — no behavioural change.

## 7. Independence guarantees (tested)

Once a plan is started, the running session is independent of everything that made
it. Verified by `SessionPlanExecutionTests`:

| After start… | Running session |
|---|---|
| edit the saved plan (e.g. 50 m → 60 m) | unchanged |
| delete the saved plan | keeps running; History intact |
| edit the referenced configuration | unchanged |
| delete the referenced configuration | still valid; frozen names intact |

Deleting a plan cascades only to its items — never to configurations, historical
sessions, or a session started from it (ADR-029).

## 8. Persistence

`SessionPlanRepository` (`@MainActor`, main context, `PersistenceError`) provides
`all` / `count` / `plan(with:)` / `create` / `update` / `delete` / `duplicate`.
Ordering is normalized on save; `update` reconciles items by id (updated in place,
added, or removed) so identities are stable and no duplicate rows are created.
Duplication yields a new identity, fresh timestamps, a "… Copy" name, and
independent items. The planner **never** saves during timer ticks; the active run is
handled by the existing session lifecycle.

Schema V5 (`TimeFrameSchemaV5`) adds `SessionPlan`, `SessionPlanItem`, and
`SessionInterval.configurationName`. Consistent with ADR-016, an incompatible older
on-disk store is rebuilt; purely additive changes migrate in place. In-memory test
stores are created fresh at V5.

## 9. UI

`Views/Plans/`: `PlanListView` (list + empty state + New Plan ⌘N), `PlanRowView`,
`PlanDetailView` (summary, timeline preview, Start ⌘↩ / Edit / Duplicate / Delete),
`PlanEditorView` (name, task, add/remove/reorder/edit timeline, live summary),
`PlanItemRowView`, `PlanItemEditorView` (type, configuration, duration),
`PlanPreviewView` (totals + relative `H:MM` timeline). "Plans" sits between
Templates and Configurations in the sidebar. "Create Plan" is offered from a Task
Template and from a Configuration; both only *read* the source and open the editor
pre-filled — saving creates an independent plan without modifying the source.

The preview uses a **relative** timeline (`0:00`, `0:50`, `1:00`, …); no fake
calendar date is persisted. A scheduled start time is intentionally deferred to the
Calendar milestone.

## 10. Recovery

A plan-started `FocusSession` is an ordinary session, so the existing Milestone 2
recovery (`SessionCoordinator.recover`) and sleep/wake reconciliation apply
unchanged — no second recovery mechanism. Verified by
`SessionPlanExecutionTests.recoveryAfterRelaunch`.

## 11. Calendar integration & future compatibility

The planner's exposed values (start/end, duration, task, per-interval phase and
configuration) now feed the **Calendar integration (Milestone 6)**: a plan can be
added to Apple Calendar (single-event or per-interval) from Plan Detail, and starting
a session can create a calendar event, via `CalendarEventGenerator` →
`CalendarEventDraft` → `CalendarCoordinator` → `EventKitCalendarService`. This is an
**isolated, optional** layer — starting a plan runs through the existing
`SessionCoordinator`/`TimerEngine` path unchanged, and a Calendar failure never
affects the timer. Deleting a plan never deletes its calendar events; duplicating a
plan does not copy its association. See `docs/15-CALENDAR-INTEGRATION.md`.

Notifications, menu bar, Liquid Glass, widgets, and advanced statistics are implemented in
later milestones; iCloud/CloudKit remains deferred. Nothing in this model blocks them.

**App Intents (Milestone 12).** `StartPlanIntent` starts a plan by reusing this layer exactly:
it resolves the `SessionPlanEntity` through `SessionPlanRepository`, takes the plan's frozen
`executionSnapshot`, and hands it to the existing `SessionCoordinator.startPlan` — all plan
validation, snapshotting, interval generation, persistence, and the timer start remain here. A
running session stays independent of the saved plan (deleting the plan afterwards cannot stop
it). See `docs/21-APP-INTENTS.md`.
