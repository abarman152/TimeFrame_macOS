# 29 — iOS Home Screen Widgets & Local Notifications (Milestone 20)

> **Milestone 22 note.** iOS **Control Center** controls were added (Milestone 22), routing through the
> same App-Intent mutation seam as the interactive Home Screen widget controls. See
> `docs/31-CONTROL-CENTER-CONTROLS.md`.

> **Milestone 21 note.** The iOS WidgetKit experience was extended to the **Lock Screen** accessory
> families (circular / rectangular / inline) and **StandBy** — all read-only projections reusing the
> pipeline described here. See `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

> Status: implemented. Native iOS/iPadOS **Home Screen widgets** and **local notifications**, plus
> companion UI polish and a Live Activity regression pass. Reuses every existing architectural seam —
> one `TimerEngine`, one `SessionCoordinator`, the shared `WidgetProjection`/App Group, the shared
> `AppIntentConfiguration`, the Milestone-15 interactive-control seam, and the neutral notification
> stack. **No second timer, no second clock, no schema change (stays V6), no CloudKit.** See
> ADR-083/084/085/086.

## 1. Objective

Milestone 20 completes the iOS productivity layer M18 deliberately deferred: a configurable **Home
Screen widget** (Timer / Today / Statistics) and **local notifications** for interval and session
transitions. It is fully useful and testable on a **personal (free) Apple Developer team** — no
iCloud entitlement, no CloudKit container, no paid-team dependency.

The load-bearing invariants are unchanged and non-negotiable:

1. **One timer.** Exactly one `TimerEngine`, still the only timing authority.
2. **One control seam.** Every mutation routes through `SessionCoordinator`.
3. **Widgets and notifications are read-only projections / presentation surfaces**, never a second
   clock. The widget countdown is `Text(timerInterval:)`; notifications fire from the engine's frozen
   interval-end anchors — neither owns or decrements a counter.
4. **A notification failure can never stop or corrupt the timer.**
5. **ActivityKit stays iOS-only; macOS/Core/Shared stay ActivityKit-free.**
6. **CloudKit stays honestly disabled** (personal team), and the SwiftData schema stays **V6**.

## 2. iOS Home Screen widgets

### Architecture (ADR-084)

The Home Screen widget is a **second presentation surface over the same projection** the macOS widget
reads — not a new data path:

```
TimerEngine → SessionCoordinator → WidgetProjectionWriter → App Group store → HomeScreenWidgetProvider → widget
```

The iOS widget lives in the **existing** `TimeFrameiOSWidgets` extension (alongside the M18 Live
Activity — no new extension target). It imports WidgetKit + SwiftUI + the shared `Shared/` value
types; it never imports SwiftData, CloudKit, the app model layer, `TimerEngine`, or
`SessionCoordinator`.

New files (`TimeFrameiOSWidgets/`):

| File | Role |
| --- | --- |
| `HomeScreenWidget.swift` | The `TimeFrameHomeScreenWidget` (`AppIntentConfiguration`, kind `"TimeFrameHomeScreenWidget"`), families `.systemSmall` / `.systemMedium` / `.systemLarge`, + deterministic previews. |
| `HomeScreenWidgetProvider.swift` | `AppIntentTimelineProvider`: reads the App Group store, resolves the shared config intent, asks the pure `WidgetTimelineBuilder` for entries + reload. |
| `HomeScreenWidgetEntry.swift` | `TimelineEntry` carrying the render instant, the projection, and the configuration. |
| `HomeScreenWidgetView.swift` | Per-mode / per-state SwiftUI (Timer / Today / Statistics), accessibility, interactive controls. |
| `HomeScreenWidgetPreviewData.swift` | Fixed sample projections (no `Date.now` / store / engine). |
| `HomeScreenWidgetFormatting.swift` | Small pure display formatters (clock, focus duration, spoken). |
| `TimeFrameiOSWidgetsBundle.swift` (edited) | Now vends `TimeFrameHomeScreenWidget()` **and** `TimeFrameLiveActivity()`. |

The macOS widget stack (`TimeFrameWidgets/`) is **unchanged**. The two extensions are separate
targets/modules; the iOS presentation files are adapted from the macOS ones so iOS can diverge (e.g.
`.systemLarge`) without disturbing macOS. The *shared* pure logic — `WidgetProjection`,
`WidgetTimelineBuilder`, `WidgetTimelinePolicy`, `TimeFrameWidgetConfiguration`,
`TimeFrameWidgetConfigurationIntent`, `WidgetControlSet` — is the single source of truth in `Shared/`.

### Modes & configuration (ADR-085)

The widget reuses the **same** `TimeFrameWidgetConfigurationIntent` (`AppIntentConfiguration`) as the
macOS configurable widget — one configuration system across platforms. Configuration is
**presentation-only**: `displayMode` (Timer / Today / Statistics), `destination` (a `timeframe://`
deep link), `showsCountdown`. Because the entry instants and reload policy come **only** from
`WidgetTimelinePolicy` (the projection's state), a configuration change can never alter timing or
introduce a second clock.

- **Timer** — idle (Ready to focus), focus/break countdown + progress, paused (frozen remaining),
  completed / interrupted summaries; interactive controls (below).
- **Today** — focus time today, completed sessions, focus intervals; a clean empty state.
- **Statistics** — focus time today, completed sessions, a trend badge vs. the prior day; empty state.

Today/Statistics numbers come from the app, computed by the **same** `StatisticsAggregator` the
dashboard uses (via the two additive optional projection fields `completedFocusIntervalsToday` /
`focusTrendToday`, unchanged since M14). The widget never aggregates.

### Countdown rule

The live countdown is always `Text(timerInterval: start...end, countsDown: true)` between the
projection's **frozen** anchors. The paused reading is the projection's frozen
`pausedRemainingSeconds`, rendered statically. The widget contains **no** `Timer` /`Timer.publish` /
`DispatchSourceTimer` / `Task.sleep` / `asyncAfter` / `scheduledTimer` and **decrements nothing**.

### Interactive controls (reuse the M15 seam)

Timer-mode controls are `Button(intent:)`s bound to the **shared** Milestone-15 intents
(`WidgetPauseIntent` … `WidgetStartIntent`). WidgetKit runs them in the **app process**, where the app
registered a `WidgetControlActions` router wired to the one `AppIntentSessionActions` seam. Chain:

```
Button(intent:) → WidgetControlActions → AppIntentSessionActions → SessionCoordinator → TimerEngine
```

Which controls appear is a **pure** function of the projection (`WidgetControlSet.controls(for:phase:compact:)`):
focus → Pause/Skip(/Stop); break → Skip/Stop; paused → Resume/Restart/Stop; idle/completed/interrupted
→ Start. Today/Statistics modes stay **read-only**. The widget owns no timer state and writes nothing.

## 3. iOS local notifications

### Shared stack in `Core/` (ADR-083)

The entire notification integration moved from the macOS app target into
**`Core/Services/Notifications/`**, so macOS and iOS compile the **identical** code — one source of
truth. It was already platform-neutral (the only platform-specific calls, `activateApp()` /
`openSystemSettings()`, are guarded `#if canImport(AppKit)` / `#elseif canImport(UIKit)`).

`UserNotificationService` (UNUserNotificationCenter adapter) remains the **single** file that imports
`UserNotifications` — now shared by both platforms. The neutral timer core (`Core/Timer`,
`Core/Models`) imports none of it. This is enforced by `ProductionReadinessM20Tests`.

Files: `NotificationScheduling` (protocol + `NotificationCategoryDescriptor`), the pure value types
(`NotificationDescriptor`/`NotificationContent`/`NotificationIdentifier`, `NotificationCategory`,
`NotificationAction`, `NotificationSound`, `NotificationAuthorizationStatus`,
`NotificationIntegrationError`, `NotificationSessionSnapshot`), the pure planners
(`NotificationContentGenerator`, `NotificationScheduleBuilder`, `NotificationActionResolver`), the
`@Observable` `NotificationCoordinator`, the UserDefaults-backed `NotificationPreferences`, and the
`UserNotificationService` adapter.

### Scheduling from authoritative anchors (ADR-086)

Notifications are scheduled from the engine's **frozen interval-end timestamps**, never a countdown:
`NotificationScheduleBuilder.upcomingDescriptors` lays out **one** notification per upcoming
interval-start boundary (`UNTimeIntervalNotificationTrigger`), so transitions still fire when the app
is backgrounded or closed. It is **never** a per-tick scheduler. The completion notification is
delivered immediately from the `.completed` lifecycle event (never pre-scheduled), so it can't
duplicate or fire stale.

Supported events: focus-interval start, short/long-break start, and session completion (each
per-category-toggleable). Defaults: integration **off** until the user opts in; every category on once
enabled.

### Lifecycle & idempotent reconciliation

The `NotificationCoordinator` subscribes to the **same** `SessionLifecycleEvent` seam as Calendar,
Notifications, the widget writer, and the Live Activity:

| Event | Action |
| --- | --- |
| Start / Resume / Skip | cancel the session's pending set, reschedule the remaining timeline |
| Pause / Stop | cancel the session's pending transitions |
| Completion | cancel pending transitions, deliver one completion notification |
| Launch / recovery | `reconcileActiveSession(...)` — cancel stale, schedule the running session's future transitions; nothing for a non-running session |

Identifiers are **deterministic** (`session id + interval index + purpose`), so a re-schedule
**replaces** rather than duplicates — reconciling twice is idempotent. Time Frame only ever cancels
its own namespaced identifiers, never another app's.

### Permission & failure isolation

Permission is requested **only in context** (when the user enables notifications), never on launch.
The Settings section surfaces the current authorization (`notDetermined` / `authorized` /
`provisional` / `denied`) and makes the app *preference* vs. the iOS *permission* explicit; a denial
routes the user to iOS Settings. Every scheduling operation is deferred onto a fresh main-actor task
and every failure is caught and turned into a non-blocking status — **a notification failure never
reaches the engine.** Proven by `IOSNotificationLifecycleTests.failureIsolation` (the scheduler throws
on every call; the timer runs on).

### iOS Settings

`TimeFrameiOS/Views/NotificationSettingsView.swift` presents the neutral coordinator: master toggle,
in-context permission button, per-category toggles, sound + action-button toggles, and a "Manage
Notification Permissions" / "Open Settings" affordance. Preferences persist in **UserDefaults** (no
SwiftData, no schema change).

## 4. iOS companion UI polish

Targeted, architecture-preserving improvements (no second presentation architecture; reuses
`TimeFormatting`, the shared aggregator, `AppSection`/`IOSNavigation`):

- **TimerScreen** — content wrapped in a `ScrollView` with a `maxWidth: 640` constraint so the timer
  and configuration cards stay centred and readable on iPad / landscape and don't clip at the largest
  Dynamic Type sizes; a proper `ContentUnavailableView` empty state when no configuration exists.
- **TodayScreen** / **StatisticsScreen** — a clean `ContentUnavailableView` empty state when the
  period has no recorded activity (Statistics keeps its period picker visible so the user can switch).
- Accessibility identifiers added for the notification settings and statistics period picker; existing
  VoiceOver labels, combined elements, and `.updatesFrequently` on the live countdown are retained.

## 5. Live Activity regression (Milestone 18, re-verified)

No Live Activity code changed. Verified: `import ActivityKit` appears in **exactly three** iOS files
(`TimeFrameLiveActivity.swift`, `TimeFrameLiveActivityAttributes.swift`,
`ActivityKitLiveActivityService.swift`) and nowhere on macOS/Core/Shared; the coordinator wiring
(`handle` fan-out, `onMeaningfulTransition`, `reconcileOnLaunch()`) is intact; controls still route
through the M15 seam; duplicate prevention and stale-date behaviour are unchanged. Enforced by
`ProductionReadinessTests` / `ProductionReadinessM20Tests`.

## 6. Tests

- **iOS suite** (`TimeFrameiOSTests`, added): `IOSHomeScreenWidgetTests` (projection decode /
  backward-compat / defensive enums / corrupt-store / timeline anchors / config isolation /
  control-set), `IOSNotificationTests` (preferences, deterministic identifiers, schedule builder,
  full lifecycle, idempotent reconcile, failure isolation, action routing), `IOSCompanionUIStateTests`
  (empty vs. active snapshots, formatting, coordinator state), `IOSPerformanceTests` (large history /
  long plan, generous machine-dependent thresholds), plus `IOSTestSupport` (mock clock, in-memory
  notification scheduler, wired rig).
- **macOS suite**: `ProductionReadinessM20Tests` adds the iOS-widget / notification / UserNotifications
  / ActivityKit / CloudKit / schema-V6 boundary audits; the M17 audit roots were updated for the
  notification move into `Core/`. The full macOS suite stays green and unchanged in count.

## 7. What this milestone intentionally does **not** do

- No CloudKit activation (personal team; `CloudKitCapability.entitledInThisBuild` stays `false`).
- No SwiftData schema change (stays **V6**); no new model for widgets, notifications, or preferences.
- No ActivityKit **push** updates; no new second timer/clock/store/control seam.

## 8. Manual verification status

| Item | Status |
| --- | --- |
| macOS Debug/Release build, full macOS suite | see the Milestone 20 report |
| iOS Debug/Release build (simulator SDK) | see the report |
| iOS unit suite (iPhone + iPad simulators) | see the report |
| Home Screen widget on a running simulator (add/configure via the widget gallery; live render) | **NOT visually verified in this environment** — requires an interactive simulator session |
| Local-notification delivery / permission prompt on a simulator | **NOT visually verified** — deterministic behaviour is unit-tested via a fake scheduler; a real banner needs an interactive session |
| Live Activity Lock Screen / Dynamic Island visuals | **NOT verified** — requires hardware with a Dynamic Island |
| Cross-device CloudKit sync | **BLOCKED** — requires a paid Apple Developer team + iCloud container |

## 9. Remaining blockers / deferred

- **Paid Apple Developer team** for real CloudKit sync, device install, TestFlight, App Store.
- On-device Live Activity / Dynamic Island / VoiceOver verification (hardware).
- ActivityKit push updates; a widget "add to Home Screen" scripted UI test (WidgetKit gallery is
  system UI, not app-drivable in unit tests).

## Milestone 24 validation (2026-08-17)

The iOS Home Screen widget and iOS local notifications were validated against the existing suites — no
change. Notifications stay anchored to frozen interval-end timestamps (no second clock, no polling). See
`docs/33-M24-ON-DEVICE-UX-VALIDATION.md` §9, §13.
