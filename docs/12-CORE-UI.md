# 12 — Core UI (Milestone 3)

The first usable Time Frame application: a native macOS sidebar app built on the
existing timer engine, coordinator, and persistence. Milestone 3 delivered a
**functional UI only** (no Liquid Glass, animations beyond system defaults,
Calendar, notifications, menu bar, templates, planner, widgets, App Intents, or
statistics). The **visual identity — Liquid Glass, design tokens, typography,
animation — was added in Milestone 9**; see `docs/18-LIQUID-GLASS-DESIGN.md`. The
guiding rule is unchanged across both: **the UI observes the domain; it never owns
timer truth.**

---

## 1. Navigation structure

```
ContentView  (NavigationSplitView)
├── Sidebar: AppSection  ─ Today · Timer · Configurations · History · Settings
└── Detail:  the selected area
```

- `AppSection` (`Views/AppSection.swift`) enumerates the areas with a title and an
  SF Symbol. The sidebar is a `List(selection:)`; the detail column switches on
  the selection.
- The app opens on **Timer** (the primary screen).
- The detail column has minimum dimensions, and the window uses
  `windowResizability(.contentMinSize)` with a sensible `defaultSize`, so the
  layout stays usable at small sizes and there is no hardcoded positioning.

## 2. UI architecture & state flow

```
View  ──user intent──▶  SessionCoordinator  ──▶  TimerEngine / Repositories  ──▶  SwiftData
  ▲                            │
  └────────── observes ────────┘   (@Observable coordinator+engine, @Query for lists)
```

- **One source of truth.** Views read `coordinator.engine.state`,
  `.currentPhase`, `.remaining`, `.currentFocusNumber`, etc., and
  `coordinator.activeSession`. There is no `@State var remainingTime` or UI-side
  session counter.
- **Countdown display.** `TimerDisplay` wraps the readout in a
  `TimelineView(.periodic(by: 1))` **only while running**, re-reading
  `engine.remaining` each redraw. This is a *display* cadence; the authoritative
  time is always `targetEnd − now` inside the engine (ADR-001/013). Phase/interval
  transitions re-render via `@Observable` observation, driven by the coordinator's
  existing heartbeat — **no SwiftData write happens on a tick** (persistence stays
  event-driven in the coordinator).
- **Persistence boundary.** Views never touch `ModelContext`. Writes go through
  the coordinator and the `ConfigurationRepository`/`SessionRepository`; reads for
  lists use `@Query` over the shared container.
- **No business logic in views.** Setup validation is the pure `SessionSetupDraft`;
  configuration validation is the existing `ConfigurationValidation`; history
  figures are derived on `FocusSession`.

### View inventory (`Views/`)

| Area | Views |
|---|---|
| Root | `ContentView` (split view), `AppSection` |
| Timer | `TimerView`, `TimerDisplay`, `TimerControls`, `SessionProgressView`, `SessionSetupView`, `IntervalPlanPreview`, `CompletionView` |
| Configurations | `ConfigurationListView`, `ConfigurationRowView`, `ConfigurationEditorView` |
| History | `HistoryListView`, `HistoryDetailView` |
| Today | `TodayView` |
| Settings | `SettingsView` |
| Components | `EmptyStateView`, `StatusPresentation`, `ConfigurationSummaryView` |
| Support | `TimeFormatting`, `SessionSetupDraft` |

## 3. Timer screen — states

`TimerView` renders exactly what the engine/coordinator report:

| Engine state | Screen |
|---|---|
| `idle` / `cancelled` | **Setup** (`SessionSetupView`) |
| `running` / `paused` | **Active run** (task, configuration, `TimerDisplay`, `Paused` label when paused, `SessionProgressView`, `TimerControls`, next-up) |
| `completed` | **Completion** (`CompletionView`) |

Recovery (from `coordinator.recoveryOutcome`, ADR-014):
- `.restored` → the active run shows a dismissible "Welcome back" banner.
- `.interrupted` → a calm banner above Setup ("Previous session couldn't be
  safely restored … saved to History"), dismissed via `acknowledgeRecovery()`.

**Controls shown per state** (invalid controls are never shown): running →
Pause / Stop / Restart / Skip; paused → Resume / Stop / Restart / Skip; completed
→ Start New Session; idle → Start (in Setup).

## 4. Session setup workflow

```
Task (required) ─▶ Configuration ─▶ Session count ─▶ Plan preview ─▶ Start
```

- Task name is required (trimmed, non-empty) before Start is enabled; the
  persisted name is the trimmed value.
- Configuration is chosen from stored configurations (default preselected), with a
  live `ConfigurationSummaryView`.
- **Session count** is a per-run override seeded from the configuration's default.
  It is applied to a value snapshot only — the saved configuration is **never**
  mutated (ADR-018). Relationship: `Saved Configuration → Session Start Options →
  FocusSession`.
- The **plan preview** (`IntervalPlanPreview`) is generated from the selected
  configuration and count (never hardcoded) and matches exactly what will run.
- Start calls `SessionCoordinator.startSession(configuration:taskName:
  totalSessions:)`, which persists the `FocusSession` and begins the timer. No
  persisted running session is created before Start.
- **No accidental double sessions:** Setup is only reachable when no session is
  active, and Today's quick action *navigates* to the Timer rather than starting a
  run, so at most one active session can exist. Start is additionally guarded
  against an active engine.

## 5. Configuration management

`ConfigurationListView` + `ConfigurationEditorView` (sheet) provide full CRUD via
the repository:

- **Create / Edit** — a `Form` in a sheet; durations in whole minutes. Validation
  uses `ConfigurationValidation` (the view does **not** re-implement rules) and
  shows friendly messages (e.g. "Focus duration must be greater than zero."),
  never raw Swift errors; invalid values are never silently changed.
- **Duplicate** — creates an independent "Copy of …" configuration (own id,
  editable values, never default).
- **Set Default** — the repository enforces exactly one default; a "Default" badge
  (text, not colour alone) marks it; Settings also exposes the default picker.
- **Delete** — a confirmation dialog. Deletion nullifies the reference on
  historical sessions (ADR-007) and explains that those sessions are preserved and
  stay accurate; history never cascade-deletes.
- **Editing while a session runs** does not affect the run — the engine holds a
  value snapshot of the plan, so the active session keeps its established timings;
  the edited configuration applies to future runs only (ADR-018).
- Empty state offers "Create Configuration".

## 6. History workflow

- `HistoryListView` is read-only, backed by `@Query`, **grouped by day**
  (Today / Yesterday / date). Each row shows task, configuration name, status
  (label + symbol), completed focus count, and total focus time.
- `HistoryDetailView` shows task, configuration, started/ended, status, and the
  per-interval breakdown (phase, planned duration, status).
- **Historical accuracy (ADR-019).** Every figure is derived from the session's
  **own persisted intervals** and its **frozen `configurationName`** — never from
  the current configuration. Renaming or deleting a configuration does not change
  past sessions. Cancelled and interrupted sessions display their true status.

## 6b. Statistics workflow (Milestone 10)

- A dedicated **Statistics** sidebar section (between History and Settings) presents a
  productivity dashboard: primary metric cards (Focus Time, Sessions, Completion Rate,
  Average Focus), a focus **trend** vs the previous equivalent period, the **most
  productive day**, native **Swift Charts** (Focus by Day, Sessions Completed, Focus by
  Configuration), and a secondary metric grid (Break Time, Longest Session, Stopped,
  Interrupted).
- A period picker supports **Today / Yesterday / This & Last Week / This & Last Month /
  Custom** (the custom date fields enforce start ≤ end).
- Statistics is **read-only** and shares the persisted history History browses; it never
  starts, stops, or mutates a session/configuration/plan or the timer. `TodayView` draws
  its two figures from the **same** aggregator (`.today`), so the two screens agree.
- Polished empty states: a new-user "No Focus Sessions Yet" with a **Start Timer** action,
  and a quiet "No Focus in This Period" note when a selected range has no activity.
- See `docs/19-STATISTICS.md` for the architecture, metric definitions, and accessibility.

## 7. Keyboard shortcuts (ADR-020)

| Shortcut | Action | Scope |
|---|---|---|
| ⌘↩ | Start / Start New Session | Setup, Completion |
| Space | Pause / Resume | Active run only |
| Esc | Stop (`.cancelAction`) | Active run (also dismisses sheets/dialogs) |
| R | Restart current interval | Active run only |
| → | Skip to next interval | Active run only |

The bare-key shortcuts (Space, R, →) are attached **only** to `TimerControls`,
which is shown solely while running/paused — never alongside the task text field —
so they cannot interfere with text editing. Start uses a modified combo (⌘↩) that
is safe from a focused field. The set is also listed in Settings.

## 8. Accessibility

- The timer readout is one accessibility element with a label (phase + "time
  remaining") and a spoken value ("42 minutes 18 seconds", via
  `TimeFormatting.accessibleClock`).
- Progress dots expose "Focus sessions" / "N of M completed" rather than relying
  on the dots visually.
- **No essential state is conveyed by colour alone**: Paused, Default, and every
  status/phase carry a text label alongside any tint/symbol
  (`StatusPresentation`).
- Buttons use `Label`s (title + symbol); history rows and plan steps combine into
  meaningful spoken summaries.
- Standard controls (`Form`, `Stepper`, `Picker`, `List`, `TextField`) provide
  native keyboard navigation and Dynamic Type support.

## 9. Empty & error states

- Empty states via `EmptyStateView` (built on `ContentUnavailableView`): no
  configurations (with a Create action), no history, and the Setup "Ready to
  Focus" state.
- Errors from save/delete/start/recovery surface as user-facing alerts; technical
  detail is logged via `AppLog`, never shown. Nothing crashes or silently
  swallows a failure.

## 10. Explicitly not in this milestone

Liquid Glass / advanced visuals, Calendar/EventKit, notifications, menu bar /
`MenuBarExtra`, Task Templates, the full Session Planner, widgets, App Intents,
Siri/Shortcuts, iCloud/CloudKit, statistics/analytics. The architecture leaves
room for each (e.g. the `TaskTemplate → PomodoroConfiguration → FocusSession →
SessionInterval` chain is unblocked), but none is implemented.
