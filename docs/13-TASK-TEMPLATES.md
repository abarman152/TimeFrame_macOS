# 13 — Task Templates

Milestone 4. Task Templates make a recurring kind of work a first-class, reusable
starting point: configure a task once (its name, a Pomodoro configuration, a
default session count) and start sessions from it repeatedly. A template is **not**
a `FocusSession` and **not** a historical record — it is a reusable *definition*.

> **Milestone 28.** A template now carries a chosen **icon** (from the closed
> `TimeFrameIconIdentifier` catalog) and can be **pinned to Quick Start**, which shows it in the
> macOS menu bar popover ready to start in one click. Pin state lives on the template itself, keyed
> by its stable `id`, so renaming keeps the pin and deleting removes it from Quick Start. Starting
> from Quick Start reuses the existing `TaskTemplate → SessionSetupPrefill → startSession` chain —
> no new start path. See `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md` (ADR-103/104).

---

## 1. What a Task Template is

```
TaskTemplate
      │  used as a starting point
      ▼
SessionSetupDraft (per-run values)
      │  copied into
      ▼
FocusSession  ──<  SessionInterval
```

A template combines:

- a **template name** — how the reusable template is identified (e.g. "Research");
- a **task name** — what the started session focuses on (e.g. "Research Quantum
  IDS"). Deliberately distinct from the template name;
- a **referenced `PomodoroConfiguration`** — never a copy of its values (ADR-022);
- a **default focus-session count** — the per-run count the setup screen seeds.

Once a session starts, it is **independent** of the template: editing or deleting
the template never touches the running or historical session (ADR-023/024).

## 2. Data model — `TaskTemplate`

`Models/TaskTemplate.swift`, a SwiftData `@Model`.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique`, stable identity |
| `name` | `String` | the template's own name |
| `taskName` | `String` | copied into the `FocusSession` |
| `configuration` | `PomodoroConfiguration?` | to-one reference, optional (survives config deletion) |
| `defaultTotalSessions` | `Int` | per-run seed count (1…24) |
| `isDefault` | `Bool` | at most one default template (ADR-025) |
| `createdAt` / `updatedAt` | `Date` | `updatedAt` bumped on Save |

Derived: `hasConfiguration` (still references a configuration) and
`displayConfigurationName` (the configuration's name, or "Configuration
unavailable").

The inverse of the configuration reference lives on
`PomodoroConfiguration.taskTemplates` with delete rule **nullify** (one side only,
mirroring `focusSessions`). Schema is **V4** (`TimeFrameSchemaV4`); an incompatible
older on-disk store is rebuilt, consistent with ADR-016/019 (ADR-021).

## 3. Lifecycle

```
Create ─► Save ─► (View / Edit / Duplicate / Set Default) ─► Delete
```

- **Create / Edit** happen in a sheet (`TemplateEditorView`). The persisted model
  is mutated **only on Save**; Cancel discards the in-memory form state. Save
  validates first; `updatedAt` advances on a successful edit.
- **Duplicate** produces an independent copy ("… Copy") with a new identity and
  fresh timestamps, never the default; it preserves the task name, configuration
  reference, and session count.
- **Delete** removes only the template (confirmation dialog). Historical sessions,
  their intervals, and the configuration are untouched.
- **Default** is optional and at most one (`setDefault` clears the flag on all
  others; `clearDefault` removes it).

All operations go through `TaskTemplateRepository`
(`Services/Persistence/TaskTemplateRepository.swift`) — views never touch the
`ModelContext`. Persistence happens only on Save / Delete / Duplicate / Set
Default, never per keystroke.

## 4. Validation

`Services/Persistence/TaskTemplateValidation.swift` — a dedicated, pure layer
(`TaskTemplateDraft.validate()`), used identically by create and update. Invalid
input is reported, never silently modified.

| Rule | Requirement |
|---|---|
| Template name | non-empty (trimmed) |
| Task name | non-empty (trimmed) |
| Configuration | required (a configuration must be chosen) |
| Session count | 1 … `ConfigurationLimits.maxTotalSessions` (24) |

Failures surface as `PersistenceError.invalidTemplate([TaskTemplateValidationError])`
with friendly messages.

## 5. Template → session start

The most important flow. It reuses the **single** existing session-start path — no
second implementation (ADR-025):

```
Template
   │  Start
   ▼
SessionSetupPrefill (task name, configuration id, session count)
   │  fills
   ▼
SessionSetupView  ── user may adjust per-run values ──►  Start
   │
   ▼
SessionCoordinator.startSession(configuration:taskName:totalSessions:)
   │
   ▼
FocusSession ──< SessionInterval   (driven by the existing TimerEngine)
```

- Pressing **Start** on a template (list row, detail, or context menu) queues a
  `SessionSetupPrefill` and switches to the Timer area. The setup screen copies the
  prefill into its editable fields, then clears it.
- The user may change the per-run session count (e.g. 4 → 6). The template's
  `defaultTotalSessions` is **never** mutated — the override rides along the
  per-run value snapshot exactly as in Milestone 3 (ADR-018).
- Start is blocked (with a clear message) if a session is already active, so no
  duplicate active session is created.
- A template whose configuration was deleted cannot start; it shows "Configuration
  unavailable" and offers **Choose Configuration** instead.

## 6. Configuration relationship & deletion behaviour

- A template **references** a configuration (ADR-022). Editing the configuration
  (e.g. 50/10/30 → 60/15/30) changes what **future** sessions started from the
  template use; already-started sessions keep their frozen plan.
- Deleting a configuration **nullifies** the reference on its templates (ADR-024):
  the template is kept, marked unavailable, and the user can choose a new
  configuration. Templates are never auto-deleted and never silently reassigned.
- The configuration delete confirmation reports how many templates (and past
  sessions) a configuration is used by, so the consequence is clear before
  deleting.

## 7. Independence from historical sessions

Guaranteed and tested:

- **Edit template** (e.g. change the task name) → existing sessions unchanged
  (a session copies the task name at start; it does not read the template).
- **Edit configuration** → existing sessions unchanged (each interval froze its
  own `plannedDuration`/`phase`; ADR-019).
- **Delete template** → sessions and their History entries remain intact.
- **Delete configuration** → templates remain (reference nullified).

History never depends on the continued existence of a template. Template
attribution is intentionally **not** stored on the session (there is no product
requirement for it in V1); the historical session remains the source of truth for
its own display, exactly as before.

## 8. UI

`Views/Templates/`:

- `TemplateListView` — sidebar area, native list, New button, empty state,
  per-row navigation to detail, context menu and swipe actions (Start / Edit /
  Duplicate / Set Default / Delete), delete confirmation.
- `TemplateRowView` — template name, task name, "configuration · N sessions", or a
  text+icon "Configuration unavailable" state (never colour alone).
- `TemplateDetailView` — task, configuration, the configuration's focus/break/long
  durations, session count, and the Start / Edit / Duplicate / Delete actions.
- `TemplateEditorView` — the create/edit sheet (name, task, configuration picker,
  session stepper, inline validation).

Accessibility: rows carry combined labels, the unavailable state is announced as
text, and important controls carry stable accessibility identifiers
(`template.new`, `template.save`, `template.detail.start`, …).

## 9. Future compatibility (do not build yet)

The chain is deliberately preserved for later milestones:

```
TaskTemplate ─► PomodoroConfiguration ─► SessionSetupDraft ─► FocusSession ─► SessionInterval
```

which later extends to:

```
TaskTemplate ─► SessionPlanner ─► Calendar Event
```

The Session Planner, Calendar/EventKit, notifications, and menu bar remain
explicitly deferred; nothing here blocks them.

**App Intents (Milestone 12).** `StartTemplateIntent` starts a session from a template by
reusing this exact chain: it resolves the `TaskTemplateEntity` through
`TaskTemplateRepository`, builds the existing `SessionSetupPrefill`, and calls
`SessionCoordinator.startSession` — there is no second template-execution path. A
`TaskTemplateEntity` (stable UUID) exposes templates to Shortcuts. See `docs/21-APP-INTENTS.md`.
