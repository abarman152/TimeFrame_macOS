# Developer Overview

An orientation for someone reading this codebase for the first time. It explains how Time Frame is
put together, which invariants matter, and where the detailed documents are. It deliberately does not
repeat those documents — each section links to the authority for its subject.

Start here, then read [`01-ARCHITECTURE.md`](01-ARCHITECTURE.md) for the full architecture and
[`DECISIONS.md`](DECISIONS.md) for the reasoning behind every structural choice.

---

## 1. The one-sentence version

Time Frame is a native macOS and iOS Pomodoro application built around a single, clock-injected timer
engine; every system surface Apple offers — widgets, Lock Screen accessories, Control Center, Live
Activities, App Intents, notifications — is either a read-only projection of that engine or a thin
command adapter back into it.

## 2. Layering

```text
  SwiftUI views  (time_frame/Views, TimeFrameiOS/Views)
        |
        v
  Coordinators and adapters  (SessionCoordinator, MenuBar, Calendar,
        |                     Notification, LiveActivity, WidgetProjectionWriter)
        v
  Domain  (TimerEngine, IntervalPlan, statistics value types)
        |
        v
  Persistence  (SwiftData repositories)
```

Dependencies point downward only. `TimerEngine` imports neither SwiftUI nor SwiftData.

## 3. Targets and directories

| Directory | Target membership | Contents |
|---|---|---|
| `Core/` | macOS app **and** iOS app | The platform-neutral domain: models, timer, statistics, persistence, notifications, cloud, Live Activity core, App Intents, widget projection writer, navigation |
| `Shared/` | All four app and extension targets | Pure, Foundation-only value types shared with widget extensions: widget projection, timeline builder, control intents, accessory and Control Center presentation |
| `time_frame/` | macOS app | macOS entry point, views, menu bar, calendar integration, the single-window layer, the login item |
| `TimeFrameWidgets/` | macOS widget extension | macOS widget bundle, provider, views |
| `TimeFrameiOS/` | iOS app | iOS entry point, tabbed root, screens, ActivityKit adapter |
| `TimeFrameiOSShared/` | Both iOS targets | The single ActivityKit attributes type |
| `TimeFrameiOSWidgets/` | iOS widget extension | Home Screen widget, Lock Screen accessories, Control Center controls, Live Activity UI |
| `time_frameTests/`, `TimeFrameiOSTests/` | Test bundles | Unit, integration, stability and boundary-audit suites |

`Core/`, `time_frame/`, `TimeFrameiOS/`, `TimeFrameWidgets/`, `TimeFrameiOSWidgets/` and
`TimeFrameiOSTests/` are **file-system-synchronized groups**: adding a `.swift` file there compiles it
automatically. `Shared/` and `TimeFrameiOSShared/` are **not** — a new file there needs explicit build
membership in every consuming target's Sources phase.

## 4. The timer engine

[`03-TIMER-ENGINE.md`](03-TIMER-ENGINE.md) is the specification. The essentials:

`TimerEngine` is a pure state machine. It owns no scheduling of any kind. It reads time only through
an injected `TimeProviding`, which makes the entire timing model deterministically testable without
launching a UI or waiting real seconds.

**Timing is timestamp-authoritative.** A running interval is anchored to a target end `Date`, and
remaining time is always derived as `targetEnd - now`. The engine never decrements a counter. This is
what makes sleep, backgrounding, and relaunch correct rather than special cases: `synchronize()`
recomputes the true state from timestamps and fast-forwards through every interval that elapsed while
the engine was not being driven.

Its whole surface is `start`, `pause`, `resume`, `stop`, `skip`, `restart`, `reset`, `load`,
`restore(from:)` and `synchronize()`.

## 5. The session coordinator

`SessionCoordinator` is the one control seam. It is `@MainActor` and `@Observable`, and it:

- drives the engine's heartbeat (the only scheduling primitive in `Core/`);
- mirrors meaningful transitions into SwiftData through the repositories;
- restores a live session on relaunch;
- emits `SessionLifecycleEvent`s that integrations subscribe to.

Every user-visible action — from the UI, an App Intent, a widget button, a notification action, a
Control Center control, or the menu bar — converges here. There is exactly one `TimerEngine` and one
`SessionCoordinator` in a running app.

See [`04-SESSION-LIFECYCLE.md`](04-SESSION-LIFECYCLE.md).

## 6. Concurrency model

The application is main-actor-centric by design. `SessionCoordinator`, the repositories and every
coordinator are `@MainActor`; model objects never cross an actor boundary.

Three rules make that safe, and they are enforced by tests:

1. **The heartbeat is the single scheduling primitive in `Core/`.** `Task.sleep` appears in exactly
   one file. The ticker is generation-stamped so a cancelled tick loop can never clear a newer one's
   handle — without that, tick loops multiply without bound.

2. **Nothing on the control path may do unbounded or persistence-heavy work.** Lifecycle events are
   emitted *synchronously*, so every observer runs inside the user's Pause. An observer may only do
   work derived from the engine's in-memory anchors; anything that reads the store, aggregates
   history, or grows with recorded data must be deferred onto a fresh main-actor task and coalesced.
   The Notification and Calendar coordinators use a `deferWork` helper for exactly this;
   `WidgetProjectionWriter` writes the session projection synchronously and the today summary on a
   coalesced follow-up.

3. **Period statistics are never fetched over all history.** Period-scoped reads go through
   `StatisticsDateRange.mayContainActivity` / `StatisticsRepository.sessionInputs(in:)`.

A fourth rule is presentation-specific but load-bearing: **a `MenuBarExtra` label must never contain a
`TimelineView`** or any scheduling primitive. SwiftUI renders a status-item label into an
`NSStatusBarButton` and re-renders it synchronously; a `TimelineView` re-arms during that render and
produces an unbounded update loop that pins the main thread. A status-item countdown repaints from
`SessionCoordinator.displaySecond` instead — a display-only whole-second signal published by the
existing heartbeat, carrying no timing authority.

See [`34-M26-STABILITY-AND-RELIABILITY.md`](34-M26-STABILITY-AND-RELIABILITY.md) and ADR-099 to
ADR-101.

## 7. Persistence

SwiftData, schema **V6**, with a versioned migration plan. Six models: `PomodoroConfiguration`,
`FocusSession`, `SessionInterval`, `TaskTemplate`, `SessionPlan`, `SessionPlanItem`.

Repositories (`Configuration`, `Session`, `TaskTemplate`, `SessionPlan`, `Statistics`) are the only
things that touch a `ModelContext`. `PersistenceController` resolves an explicit `PersistenceMode` and
degrades safely to the preserved local store on any CloudKit failure — never to an empty in-memory
store, and never in a way that blocks the timer.

**Frozen historical identity** is the rule that shapes the data model: when a session starts it copies
the values it needs, including the configuration's name. Renaming or deleting a configuration later
cannot rewrite history.

See [`02-DATA-MODEL.md`](02-DATA-MODEL.md).

## 8. Projection architecture

Widgets and Control Center run in a separate process and cannot read the app's database. The bridge is
a single small value:

```text
SessionCoordinator ──emits──> SessionLifecycleEvent
                                    |
                          WidgetProjectionWriter
                                    |
                     WidgetProjection (Codable, App Group)
                                    |
              ┌─────────────────────┼─────────────────────┐
        Home Screen widget   Lock Screen accessory   Control Center
```

The App Group is `group.abirbarman.com.time-frame`. The projection carries the session's *frozen
anchors* — interval start and planned end — so every surface renders its countdown with
`Text(timerInterval:)` between those anchors. That is a repaint, not a clock: no widget creates a
`Timer`, a timer publisher, or an async countdown loop.

The projection is written only on meaningful transitions, never per tick.

See [`20-WIDGETKIT.md`](20-WIDGETKIT.md), [`23-CONFIGURABLE-WIDGETS.md`](23-CONFIGURABLE-WIDGETS.md),
[`30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`](30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md).

## 9. The command seam

Interactive surfaces send commands back through exactly one path:

```text
Button(intent:) / ControlWidgetButton / App Shortcut / notification action
        |
        v
WidgetControlActions          (router, app-owned)
        |
        v
AppIntentSessionActions       (the one place an intent mutates the timer)
        |
        v
SessionCoordinator ──> TimerEngine
```

WidgetKit runs a widget-button intent in the *app* process, which is where the router is registered.
Failures surface as the closed `TimeFrameIntentError` set — never a leaked Swift or SwiftData error.

See [`21-APP-INTENTS.md`](21-APP-INTENTS.md), [`24-INTERACTIVE-WIDGETS.md`](24-INTERACTIVE-WIDGETS.md),
[`31-CONTROL-CENTER-CONTROLS.md`](31-CONTROL-CENTER-CONTROLS.md),
[`32-CONFIGURABLE-CONTROL-CENTER.md`](32-CONFIGURABLE-CONTROL-CENTER.md).

## 10. Integration isolation

Calendar, notifications, the menu bar, the widget projection and the Live Activity all subscribe to
the *same* `SessionLifecycleEvent` seam, independently. They never call each other, and none of them
can stop or corrupt the timer.

Each is isolated behind a protocol with exactly one framework importer:

| Integration | Sole importer | Notes |
|---|---|---|
| Calendar | `EventKitCalendarService` | macOS only |
| Notifications | `UserNotificationService` | Shared by macOS and iOS |
| Live Activity | `ActivityKitLiveActivityService` | iOS only |
| Open at Login | `SMAppServiceLoginItem` | macOS only; persists nothing |

`import ActivityKit` appears in exactly three iOS files and nowhere in `Core/`, `Shared/`, or the
macOS side. `import CloudKit` appears nowhere at all. Both facts are enforced by tests.

See [`15-CALENDAR-INTEGRATION.md`](15-CALENDAR-INTEGRATION.md), [`16-NOTIFICATIONS.md`](16-NOTIFICATIONS.md),
[`25-LIVE-ACTIVITIES.md`](25-LIVE-ACTIVITIES.md),
[`27-IOS-COMPANION-LIVE-ACTIVITIES.md`](27-IOS-COMPANION-LIVE-ACTIVITIES.md).

## 11. Statistics

A pure, read-only projection of persisted history. The value types and `StatisticsAggregator` import
only Foundation; a `@MainActor` `StatisticsRepository` performs a single fetch and maps rows into
immutable inputs.

Nothing derived is persisted — snapshots are recomputed and reproducible. Session-level metrics are
attributed by `startedAt`; interval-level metrics by a completed interval's end instant. Only
intervals with status `.completed` count toward focus and break totals.

See [`19-STATISTICS.md`](19-STATISTICS.md).

## 12. CloudKit status

Sync is SwiftData's native mirroring, sitting below the repositories. No file imports CloudKit; there
is no custom sync engine and no polling.

`CloudKitCapability.entitledInThisBuild` is **`false`** on the shipping personal-team build, so both
apps launch local-first and never attempt a cloud container that cannot work. The iCloud entitlement
is deliberately absent — fabricating one would fail to sign — and a test fails the build if the
entitlement and the constant ever disagree.

**Real CloudKit sync has never been verified.** It requires a paid Apple Developer team.

See [`22-ICLOUD-CLOUDKIT.md`](22-ICLOUD-CLOUDKIT.md),
[`28-CLOUDKIT-DEVICE-VALIDATION.md`](28-CLOUDKIT-DEVICE-VALIDATION.md).

## 13. Testing strategy

Swift Testing (`@Test`, `@Suite`, `#expect`) is the default; the suites fall into four kinds:

1. **Deterministic domain tests.** The engine is driven through a `MockTimeSource`. No test ever waits
   a real second.
2. **Persistence and integration tests.** In-memory `ModelContainer`s. A container must be kept alive
   for the whole test — a `ModelContext` does not retain its container.
3. **Isolation tests.** Prove that a failing calendar, notification, widget or intent layer cannot
   stop or corrupt a session.
4. **Source-boundary audits.** `ProductionReadiness*Tests` scan the source tree and fail the build if
   an architectural invariant regresses: more than one engine or coordinator, a second scheduling
   primitive, SwiftData in a widget extension, ActivityKit outside iOS, a CloudKit import, a fabricated
   entitlement, a schema-version change, or a `TimelineView` back in the menu-bar label.

The audits are the reason the architecture has held across many milestones: they turn prose rules into
build failures.

See [`10-TESTING-PLAN.md`](10-TESTING-PLAN.md).

### Running the tests

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame \
  -destination 'platform=macOS' test
```

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme TimeFrameiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

On a machine without a provisioning profile for this bundle identifier, append
`CODE_SIGNING_ALLOWED=NO`. Note that doing so also strips entitlements, so the App Group is
unavailable and widget surfaces will not show live data.

Run `xcodebuild` invocations serially; concurrent runs contend on the shared DerivedData build
database.

## 14. Invariants worth knowing before you change anything

- Exactly one `TimerEngine` and one `SessionCoordinator` per running app.
- Timing is derived from timestamps. Never introduce a counter, and never let a UI callback become the
  source of elapsed time.
- No second clock anywhere: no `Timer`, `Task.sleep`, `asyncAfter`, or timer publisher in a view,
  widget, control, Live Activity, or intent.
- Nothing unbounded or persistence-heavy on the control path; defer and coalesce instead.
- No `TimelineView` in a `MenuBarExtra` label.
- Exactly one main window. The macOS main scene is a single-instance `Window`, never a
  `WindowGroup`; `openWindow` lives in one file and window ordering in one other, and every surface
  (including a Dock reopen) goes through `MainWindowPresenter`. Never cache the window's state in a
  boolean — read the live window.
- Focusing the window is window behaviour only. It never resets navigation or setup state, and never
  touches the engine, the session, or history.
- The login item's state is `SMAppService`'s, not ours. Never persist it, and never show a
  registration the system has not confirmed.
- Widget extensions import no SwiftData, no CloudKit, and no app model layer.
- ActivityKit is iOS-only; `ControlWidget` is iOS-only; macOS stays free of both.
- The schema is V7. Changing it requires a migration stage and updating the audits.
- The App Group identifier and the `timeframe://` URL scheme are fixed.
- Historical fields are frozen. Never make a past session depend on a live configuration.

## 15. Where to read next

| If you want to understand | Read |
|---|---|
| The product's scope and boundaries | [`00-PRODUCT-REQUIREMENTS.md`](00-PRODUCT-REQUIREMENTS.md) |
| The full architecture | [`01-ARCHITECTURE.md`](01-ARCHITECTURE.md) |
| The data model | [`02-DATA-MODEL.md`](02-DATA-MODEL.md) |
| The timer specification | [`03-TIMER-ENGINE.md`](03-TIMER-ENGINE.md) |
| Session states and recovery | [`04-SESSION-LIFECYCLE.md`](04-SESSION-LIFECYCLE.md) |
| Why anything is the way it is | [`DECISIONS.md`](DECISIONS.md) |
| What changed and when | [`CHANGELOG.md`](CHANGELOG.md) |
| The user-facing behaviour | [`35-USER-GUIDE.md`](35-USER-GUIDE.md) |
