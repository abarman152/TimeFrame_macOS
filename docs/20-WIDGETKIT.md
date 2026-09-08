# 20 — WidgetKit Surfaces (Milestone 11)

Native macOS 27 WidgetKit surfaces for Time Frame. The widgets are **projection
surfaces only**: they render a read-only snapshot the app writes, and they can never
become a second timer. See ADR-055.

> **Milestone 18 note.** The macOS widget stack (M11–M15) is **unchanged**. The iOS companion adds a
> separate `TimeFrameiOSWidgets` extension whose sole widget this milestone is the **Live Activity**
> (Lock Screen + Dynamic Island) — it reuses the same `Shared/` projection value types and control
> intents. iOS **home-screen** widgets are deliberately deferred (the smallest architecture-consistent
> iOS surface for M18 is the Live Activity). The shared `WidgetProjection`/App Group format is
> unchanged. See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md` §22/§8.

> **Milestone 20/21 note.** The iOS **Home Screen** widget (M20) and the iOS **Lock Screen accessory**
> widgets + StandBy (M21) live in the **same** `TimeFrameiOSWidgets` extension and reuse this exact
> pipeline (`WidgetProjection`/App Group/`WidgetProjectionWriter`/`TimeFrameWidgetConfigurationIntent`/
> `WidgetTimelineBuilder`). The M21 accessory content is produced by the pure
> `Shared/AccessoryWidgetPresentation.swift`; accessory families are read-only. See
> `docs/29-IOS-WIDGETS-NOTIFICATIONS.md` and `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

## 1. Principle — one timer, many surfaces

There is still exactly **one** source of truth:

```
TimerEngine  →  SessionCoordinator  →  WidgetProjectionWriter  →  App Group store  →  TimelineProvider  →  widgets
```

`TimerEngine` and `SessionCoordinator` remain authoritative. Everything downstream of
the writer is a read-only *projection*. The widget extension:

- creates **no** `Timer`, Combine timer publisher, `DispatchSourceTimer`, or async
  countdown loop;
- decrements **no** seconds and reconstructs **no** Pomodoro sequencing;
- never instantiates `TimerEngine` or `SessionCoordinator`, never imports the SwiftData
  model layer, and never writes app model state;
- reads only the JSON projection the app last wrote.

The live countdown "ticks" because SwiftUI's date-relative `Text(timerInterval:)` animates
between the projection's frozen `intervalStartedAt`/`intervalPlannedEndAt` anchors — the
truth still lives in the engine. This mirrors the Menu Bar's `TimelineView` repaint
approach (Milestone 8, ADR-046).

## 2. Layers and files

### Shared, pure projection (`Shared/` — compiled into BOTH app and widget)

Foundation-only value types; import no SwiftData, WidgetKit, SwiftUI, or domain engine.

- `WidgetProjection.swift` — the `Codable`/`Sendable`/`Equatable` snapshot the app writes
  and the widget reads (schema version, generated instant, state, phase, task/config,
  interval index/total, completed count, interval start/planned-end anchors, paused
  remaining, today's focus/sessions, optional failure reason). `currentSchemaVersion = 1`.
- `WidgetProjectionState.swift` — `WidgetSessionState` (idle / running / paused / completed
  / interrupted / **unavailable**) and `WidgetPhase` (focus / shortBreak / longBreak /
  none). Both **decode defensively**: an unknown raw value degrades to `.unavailable` /
  `.none` instead of throwing.
- `WidgetProjectionStore.swift` — the App-Group `UserDefaults` bridge. `@unchecked Sendable`
  (its only member is a thread-safe `UserDefaults`). A missing suite makes it an inert
  no-op; a corrupt or schema-incompatible payload reads as `nil`, never a throw.
- `WidgetDeepLink.swift` — the neutral `timeframe://{timer,today,statistics,history}`
  vocabulary; parse + build, unknown URLs → `nil`.
- `WidgetTimelinePolicy.swift` — the pure timeline decision: entry instants + a
  `WidgetRefreshPolicy` (`.after(Date)` / `.never`). No WidgetKit types.

### App-side writer (`time_frame/Widgets/` — app target only)

- `WidgetProjectionMapper.swift` — `@MainActor` map from `SessionCoordinator`/`TimerEngine`
  to a `WidgetProjection` (in-memory timestamp math, no persistence access), mirroring
  `MenuBarPresentationState`.
- `WidgetProjectionWriter.swift` — observes the same `SessionLifecycleEvent` fan-out as
  Calendar/Notifications (plus the coordinator's meaningful-transition hook), writes the
  projection, and calls `WidgetCenter.shared.reloadAllTimelines()`. Fully failure-isolated:
  a widget write can never touch the timer.
- `WidgetDeepLink+AppSection.swift` — maps a parsed deep link onto the existing
  `AppSection`. `ContentView.onOpenURL` applies it, reusing the one window and its screens.
- `TodaySummary` — the two "today" numbers, computed once by the app from the **same**
  `StatisticsAggregator` the dashboard uses (`StatisticsPeriod.today`), handed to the mapper.

### Widget extension (`TimeFrameWidgets/` — appex target)

- `TimeFrameWidgetsBundle.swift` — `@main WidgetBundle` + `TimeFrameTimerWidget`
  (`StaticConfiguration`; **no App Intents** this milestone) supporting `.systemSmall` and
  `.systemMedium`; deterministic `#Preview`s for every state.
- `TimeFrameWidgetProvider.swift` — `TimelineProvider`: reads the store, asks
  `WidgetTimelinePolicy` for entries + reload, maps to WidgetKit's `TimelineReloadPolicy`.
  Missing/corrupt projection → stable `.unavailable` entry.
- `TimeFrameWidgetEntry.swift` — `TimelineEntry` carrying only a date + the projection.
- `TimeFrameWidgetView.swift` — the per-state SwiftUI surfaces (idle / running focus /
  running break / paused / completed / interrupted / unavailable), accessibility, deep link.
- `TimeFrameWidgetPreviewData.swift` — fixed sample projections (no `Date.now` / store /
  engine).
- `WidgetFormatting.swift` — small display formatters (clock, focus duration, spoken).

## 3. Timeline policy

| State | Entries | Reload |
|-------|---------|--------|
| running (future end) | `[now, plannedEnd]` | `.after(plannedEnd)` |
| running (no/past end) | `[now]` | `.after(now + 1h)` conservative |
| **paused** | `[now]` (one, frozen) | `.never` — never an artificial tick |
| idle / completed / interrupted / unavailable | `[now]` | `.after(now + 1h)` conservative |

Running reloads land on the interval's planned end (the meaningful boundary), where the
app has already rewritten the projection for the next interval — auto focus→break→focus
advances fire the coordinator's meaningful-transition hook, so the store is fresh there
without any per-tick write.

## 4. App Group

Both the app and the widget declare the App Group **`group.abirbarman.com.time-frame`** in
their entitlements (`time_frame/time_frame.entitlements`,
`TimeFrameWidgets/TimeFrameWidgets.entitlements`). It is the only shared channel. If the
suite cannot be opened, the store is inert and the widget shows its `.unavailable`
fallback — never a crash.

## 5. Deep links

The app registers the `timeframe` URL scheme via `CFBundleURLTypes` in
`time_frame-Info.plist` (merged with the generated Info.plist). A widget tap opens
`timeframe://timer|today|statistics|history`; `ContentView.onOpenURL` maps it to the
matching `AppSection` and selects it in the existing sidebar. Unknown URLs are ignored.

## 6. Xcode project

- New target **`TimeFrameWidgets`** (`com.apple.product-type.app-extension`), bundle id
  `abirbarman.com.time-frame.TimeFrameWidgets`, embedded in the app's `Contents/PlugIns`.
- The `Shared/` files are compiled into **both** the app and the widget via explicit build
  membership (no framework, no synchronized-group ambiguity), so there is a single source
  of truth for the projection types while keeping the widget free of the app model layer.
- The widget's `TimeFrameWidgets/` folder is a file-system-synchronized group: new widget
  sources are compiled automatically.

## 7. What this milestone deliberately does **not** do

No App Intents command/control (only a `StaticConfiguration`), no Live Activities, no
CloudKit/sync, no Siri/Shortcuts, no new SwiftData schema (**stays V5**), no new timer
behavior, and no Statistics-dashboard duplication in the widget. See the Non-Goals in the
milestone brief and ADR-055.

> **Follow-up (Milestone 12):** App Intents, Shortcuts & Siri are added as a *separate*
> integration surface (not a widget configuration) that reuses the same `timeframe://` deep
> link and the same authoritative projection pattern as the widget. The widget itself is
> unchanged and stays a `StaticConfiguration`. See `docs/21-APP-INTENTS.md`.

> **Follow-up (Milestone 13):** iCloud/CloudKit sync is added to the SwiftData store, but the
> widget path is **unchanged**: it keeps reading the **local App Group** `WidgetProjectionStore`
> written by `WidgetProjectionWriter`. The widget imports no CloudKit and no SwiftData, and never
> accesses CloudKit directly — `SwiftData/CloudKit → local app projection → App Group → WidgetKit`
> (ADR-060). Regression covered by `CloudPersistenceRegressionTests`. See
> `docs/22-ICLOUD-CLOUDKIT.md`.

> **Follow-up (Milestone 14):** the widget becomes **user-configurable** — the `StaticConfiguration`
> becomes an **`AppIntentConfiguration`** (same `kind` `"TimeFrameTimerWidget"`, same families, same
> App Group), and the provider becomes an `AppIntentTimelineProvider`. Configuration
> (`TimeFrameWidgetConfiguration`: display mode / tap destination / countdown) is a **pure
> presentation projection** that never affects timing (ADR-064): the pure `WidgetTimelineBuilder`
> derives entries + reload from the projection's state alone. Two **additive optional** projection
> fields (`completedFocusIntervalsToday`, `focusTrendToday`) feed the new Today/Statistics modes with
> **no schema-version bump** (still `1`) — the trend is computed by the app from the same
> `StatisticsAggregator` the dashboard uses. The widget stays read-only and CloudKit-independent. See
> `docs/23-CONFIGURABLE-WIDGETS.md`.

> **Follow-up (Milestone 15):** the widget becomes **interactive** — per-state `Button(intent:)`
> controls (Pause/Resume/Skip/Restart/Stop/Start). The widget stays a **read-only projection**: the
> buttons are thin App Intents that WidgetKit runs in the **app process**, routing through the existing
> `AppIntentSessionActions` seam to the one `SessionCoordinator`; the widget owns no timer, writes
> nothing, and the countdown stays a `Text(timerInterval:)` repaint. The projection is still produced
> only by `WidgetProjectionWriter`, which reloads on a meaningful transition after each action — never
> per tick (ADR-069/071). See `docs/24-INTERACTIVE-WIDGETS.md`.

> **Milestone 16 note.** The WidgetKit projection is unchanged. A Live Activity would be a *separate*
> read-only surface (its own `LiveSessionProjection`, not the App Group `WidgetProjection`), driven by
> `LiveActivityCoordinator` on the same lifecycle seam — but ActivityKit is unavailable on native
> macOS, so no Live Activity is built here. See `docs/25-LIVE-ACTIVITIES.md`.

> **Follow-up (Milestone 20):** the **iOS Home Screen widget** is added to the existing
> `TimeFrameiOSWidgets` extension, reusing the **same** `WidgetProjection`, App Group
> (`group.abirbarman.com.time-frame`), `WidgetProjectionWriter`, `TimeFrameWidgetConfigurationIntent`,
> pure `WidgetTimelineBuilder`, and M15 `WidgetControlSet` control seam as the macOS widget — a second
> presentation surface over the one timer, not a new data path. Families small/medium/large; modes
> Timer/Today/Statistics; configuration presentation-only; countdown a `Text(timerInterval:)` repaint.
> The macOS widget stack is unchanged; the projection/App-Group format and schema (**V6**) are
> unchanged (ADR-084/085). See `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
