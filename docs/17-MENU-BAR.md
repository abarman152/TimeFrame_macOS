# 17 — macOS Menu Bar Experience (Milestone 8)

Time Frame adds a native macOS **`MenuBarExtra`** that gives quick visibility and control
of the active session without opening the main window. This document describes its
architecture, why it can never become a second timer, and how it is tested.

> **One timer, many surfaces.** The menu bar is a *presentation and control surface* over
> the one authoritative `TimerEngine`/`SessionCoordinator`. It maintains no timer, owns no
> countdown, and persists no timer state.

> **Redesign (Milestone 28).** The popover's information hierarchy changed: the four navigation
> actions (Open Time Frame, Settings, History, Quit) moved behind a **gear menu** in the header's
> top-right corner, a **Quick Start** section of pinned Templates and Plans was added, and the
> running state gained a Restart control so running and paused offer the same four controls. The
> transport controls are laid out **outside any scroll view** so a long pinned list can never push
> them off screen. The actions, their identifiers, the routing, the projection semantics, and the
> preferences described below are **unchanged**. See
> `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md` (ADR-102/104/105).

> **Visual treatment (Milestone 9).** The popover adopts the same Liquid Glass design system
> as the rest of the app — glass transport buttons in a `GlassEffectContainer`, a phase-tinted
> uppercase phase label, the rounded countdown, and shared spacing/colour tokens — while the
> panel keeps its system `MenuBarExtra(.window)` background (no nested glass). This is a
> **visual-only** change: the architecture, projection semantics, control routing, and
> preferences below are unchanged. See `docs/18-LIQUID-GLASS-DESIGN.md`.

---

## 1. Architecture

```
                         TimerEngine            ← the single source of truth
                             │
                    SessionCoordinator          ← one instance, app-owned
                             │
                    SessionLifecycleEvent        ← the integration-agnostic seam
                             │
        ┌────────────┬───────┴────────┬─────────────┐
        ▼            ▼                ▼             ▼
     SwiftUI      Calendar       Notifications    Menu Bar
       Views      Coordinator      Coordinator   Coordinator
        │            │                │             │
        ▼            ▼                ▼             ▼
      App UI      EventKit        UserNotif.     MenuBarExtra
```

The `MenuBarCoordinator` is an **observer/adapter**, not a coordinator of its own. It holds
a reference to the one `SessionCoordinator` and exposes a pure projection of its state;
it never constructs an engine, a coordinator, or a `ModelContainer` (ADR-045/049).

### Files

- `Services/MenuBar/`
  - `MenuBarPresentationState.swift` — the pure projection value type (ADR-046).
  - `MenuBarCoordinator.swift` — the `@Observable` observer/control adapter (ADR-045/047).
  - `MenuBarPreferences.swift` — `MenuBarPreferences` + UserDefaults store (ADR-048).
- `Views/MenuBar/`
  - `TimeFrameMenuBarLabel.swift` — the status-item icon + title.
  - `TimeFrameMenuBarView.swift` — the `.window`-style popover root.
  - `MenuBarTimerView.swift` — countdown, phase, progress dots, next interval.
  - `MenuBarSessionSummaryView.swift` — task + frozen configuration header.
  - `MenuBarEmptyStateView.swift` — idle / completed / interrupted header.
  - `MenuBarControlsView.swift` — transport controls (navigation moved to the gear menu in
    Milestone 28).
  - `MenuBarGearMenu.swift` — the gear menu: the one place Open Time Frame / Settings / History /
    Quit appear (Milestone 28).
  - `MenuBarQuickStartView.swift` / `MenuBarQuickStartRowView.swift` — the pinned Templates and
    Plans, startable in one click (Milestone 28).
  - `MenuBarOpenSectionButton.swift` — the shared "open the main window on a section" link
    (Milestone 28).
  - `MenuBarStatusPresentation.swift` — pure title/icon/VoiceOver mapping.
  - `MenuBarSettingsSection.swift` — the Settings section.
- `Views/AppNavigation.swift` — the shared navigation seam + the `"main"` window id.
- `time_frameApp.swift` — owns the single `MenuBarCoordinator`; declares the `MenuBarExtra`
  scene alongside the main window scene. **Milestone 32** replaced that `WindowGroup` with a
  single-instance `Window`, so the menu bar's actions can no longer open a second window
  (ADR-111).

---

## 2. Why the menu bar cannot become a second timer

Four structural guarantees:

1. **Shared coordinator (ADR-045/049).** The app builds **one** `SessionCoordinator` in
   `time_frameApp.init` and hands the same instance to the window content and the menu bar.
   There is no per-surface engine.
2. **Pure projection (ADR-046).** `MenuBarPresentationState` is a `Sendable` value derived
   from the engine via `init(coordinator:)`. It carries a *snapshot* of remaining time; it
   holds no clock and cannot advance.
3. **Repaint-only refresh.** A `TimelineView(.periodic(by: 1))` re-derives the projection
   ~once a second **while running only**. It schedules a redraw; the remaining time still
   comes from `TimerEngine.remaining` (which is `targetEnd − now`). Paused/idle/finished
   states schedule no periodic redraw.
4. **No persisted menu-bar state.** Nothing like `menuBarRemaining`/`menuBarPhase` exists,
   and the projection never queries SwiftData — it is in-memory timestamp math (§87/§89).

A quick audit for forbidden patterns (`Timer.publish`, `DispatchSourceTimer`, a
`remainingSeconds -= 1` loop, a `Task.sleep` countdown) finds none in the menu-bar code —
`TimelineView` is the only refresh mechanism, and it repaints only.

---

## 3. State projection

`MenuBarPresentationState.Situation` maps the engine's authoritative state onto the coarse
layout the popover switches on:

| Engine state              | Recovery       | Situation      |
|---------------------------|----------------|----------------|
| `.running`                | —              | `.running`     |
| `.paused`                 | —              | `.paused`      |
| `.completed`              | —              | `.completed`   |
| `.idle` / `.cancelled`    | `.interrupted` | `.interrupted` |
| `.idle` / `.cancelled`    | else           | `.empty`       |

The projection also carries: `taskName`, `configurationName` (the session's **frozen**
snapshot, not the live configuration — §53), `phase`, `remaining`, `currentFocusNumber`,
`totalFocusSessions`, `completedFocusCount`, `nextPhase`/`nextDuration`, and `recovery`.
`MenuBarStatusPresentation` turns it into the compact title:

- Running focus → `Focus 24:37` · running break → `Break 04:12` · paused → `Paused 24:37`
- Completed → `Done` · idle/interrupted → `Time Frame` (never a bare `00:00`, §50)
- With "Show countdown in menu bar" off, only the phase word (or `Paused`) is shown.

---

## 4. Controls

All routed through `SessionCoordinator` (ADR-047); the menu bar never calls the engine.

| Situation  | Transport controls           | Navigation (footer)                         |
|------------|------------------------------|---------------------------------------------|
| Running    | Pause · Skip · Stop          | Open Time Frame · Settings · History · Quit |
| Paused     | Resume · Restart · Stop      | Open Time Frame · Settings · History · Quit |
| Empty      | Start Timer                  | Open Time Frame · Settings · History · Quit |
| Completed  | Start New Session            | Open Time Frame · Settings · History · Quit |
| Interrupted| Start Timer                  | Open Time Frame · Settings · History · Quit |

- **Start Timer / Start New Session** clear any finished run (`prepareForNewSession`, a
  safe no-op mid-run) and open the main window's existing `SessionSetupView` — never a
  second start flow (§13/§21).
- **Open Time Frame / Settings / History** ask the one `MainWindowPresenter` for the window,
  through the `\.showMainWindow` environment action (**Milestone 32**, ADR-111). The presenter
  brings the existing `"main"` window forward — unhiding the app and restoring it from the Dock
  if needed — and requests the section through `AppNavigation`, reusing the one window and its
  screens (§22/§23/§24). The menu bar views no longer hold `openWindow`, no longer call
  `NSApplication.activate`, and no longer take an `AppNavigation`: they ask, and decide nothing.
- **Quit Time Frame** uses `NSApplication.terminate` (standard mechanism, §25).

Accessibility identifiers: `timeFrame.menuBar`, `…pause`, `…resume`, `…skip`, `…stop`,
`…restart`, `…start`, `…openApp`, `…settings`, `…history`, `…quit`.

---

## 5. Recovery, sleep/wake, window independence

- **Relaunch.** `SessionCoordinator.recover()` restores authoritative state on launch; the
  menu bar simply projects it. A recovered running session shows the fast-forwarded
  remaining; a recovered paused session shows the frozen remaining; a session that finished
  while away shows **completed**, never a stale running countdown (§35/§76).
- **Sleep/wake.** No menu-bar wake timer exists. The engine reconciles on wake (existing
  behavior); the menu bar re-reads it on its next repaint (§36/§77).
- **Window independence.** The `MenuBarExtra` keeps the process alive when the main window
  is closed. Closing the window does not stop the engine, Calendar, Notifications, or the
  menu bar; reopening reuses the app-owned coordinator (§27/§28, ADR-049).

---

## 6. Settings

`Settings → Menu Bar` (in the existing `SettingsView`, no separate window):

- **Show in Menu Bar** — default **on**. Bound to `MenuBarExtra(isInserted:)`, so turning
  it off removes the status item; the timer, Calendar, and Notifications keep working.
- **Show countdown in menu bar** — default **on**; controls whether the live time appears
  in the compact title.

Both persist in `UserDefaults` (`MenuBarPreferencesStore`); **no SwiftData schema change**
(schema stays V5, ADR-048).

---

## 7. Failure isolation

The menu bar shares only the one `SessionCoordinator`; it does **not** call, and is not
called by, the Calendar or Notification coordinators (they merely observe the same
lifecycle seam). Therefore:

- A Notification scheduling failure or a Calendar write failure can never break the menu
  bar (`MenuBarIndependenceTests`).
- A menu-bar action cannot affect Calendar or Notification state beyond the normal shared
  lifecycle event.
- Disabling the menu bar preference never affects timer, Calendar, or Notification behavior.

The menu bar is also robust to awkward sessions: an empty task name, a deleted
configuration (the frozen snapshot survives), and inapplicable controls are all handled
safely (§60/§93).

---

## 8. Testing

Deterministic, engine-level tests (no fragile menu-bar rendering tests) via the mock clock:

- `MenuBarPresentationTests` — every situation projection + frozen-configuration independence.
- `MenuBarControlTests` — control routing, countdown derivation, safe no-ops.
- `MenuBarPreferencesTests` — defaults, persistence, countdown title, timer untouched.
- `MenuBarRecoveryTests` — recovered running/paused and completed-while-away.
- `MenuBarIndependenceTests` — failing integrations never break the menu bar; robustness.

See `docs/10-TESTING-PLAN.md`. Total suite after Milestone 8: **290 tests, 0 warnings**.

---

## 9. Future improvements (deferred)

- A dynamic/animated status icon per phase (a stable icon + text is intentionally used now).
- "Start from Template" / "Start a saved Plan" directly from the menu bar (currently the
  menu bar opens the existing setup flow — §39/§40).
- Liquid Glass visual identity (a separate milestone; §43).
