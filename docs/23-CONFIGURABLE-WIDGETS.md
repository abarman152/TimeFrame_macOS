# 23 — Configurable WidgetKit Experience (Milestone 14)

> **Milestone 20/21 note.** The iOS Home Screen widget (M20) and the iOS Lock Screen accessory widgets
> (M21) reuse this **same** `TimeFrameWidgetConfigurationIntent` (`AppIntentConfiguration`) — one
> configuration system across macOS, iOS Home Screen, and iOS Lock Screen. On accessory families the
> configuration stays presentation-only and degrades information density per family. See
> `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

Milestone 14 upgrades the Milestone 11 widget from a fixed `StaticConfiguration` into a
**user-configurable** widget backed by Apple's modern **`AppIntentConfiguration`**. The widget
stays what it has always been — a **read-only projection** of the one authoritative
`TimerEngine`/`SessionCoordinator` — and gains a small, pure configuration that changes
**presentation only** (ADR-064 … ADR-068). It builds directly on M11 (WidgetKit) and M12 (App
Intents) and reuses the M13 persistence untouched.

## 1. Principle — one timer, many surfaces, now configurable

```
TimerEngine → SessionCoordinator → WidgetProjectionWriter → App Group store
                                                              │
                                              (read-only)     ▼
                            TimeFrameWidgetConfigurationIntent → WidgetTimelineProvider
                                        (WidgetKit-owned)         │  WidgetTimelineBuilder
                                                                  ▼
                                                        Configurable Widget (view)
```

The configuration answers three questions and nothing else:

- **Display** — Current Timer, Today's Focus, or Statistics.
- **Open When Tapped** — Timer, Today, Statistics, or History.
- **Countdown** — Show or Hide.

It never changes what the projection *is*, only which slice is shown and where a tap goes. The
widget still creates **no** timer, decrements **no** counter, imports **no** SwiftData / CloudKit /
app model layer, and reads **only** the local App Group projection.

## 2. Configuration model (pure, `Shared/`)

`Shared/TimeFrameWidgetConfiguration.swift` — Foundation-only, compiled into **both** app and
widget:

- `WidgetDisplayMode` — `timer` / `today` / `statistics` (stable raw values).
- `WidgetDestination` — `timer` / `today` / `statistics` / `history`; each maps 1:1 to an existing
  `WidgetDeepLink` (and thus an existing `AppSection`).
- `TimeFrameWidgetConfiguration` — `displayMode` + `destination` + `showsCountdown`;
  `Codable`/`Hashable`/`Sendable`; a canonical `.default` (`Current Timer → Timer → countdown on`).

Everything **decodes defensively**: an unknown enum raw value or a missing field degrades to the
safe default rather than throwing, so a partial or forward-incompatible value always yields a usable
widget (ADR-066). The type is named `TimeFrameWidgetConfiguration` (not `WidgetConfiguration`) to
avoid colliding with WidgetKit's own `WidgetConfiguration` protocol inside the widget target.

## 3. `AppIntentConfiguration` intent (`Shared/`)

`Shared/TimeFrameWidgetConfigurationIntent.swift` — the `WidgetConfigurationIntent` WidgetKit
presents in the standard widget editor. It imports `AppIntents` (the **only** shared file that
does) and is compiled into both the app and the widget so the widget can reference it and the app
test target can exercise it deterministically.

- Three `@Parameter`s backed by `AppEnum`s with plain, non-technical `DisplayRepresentation`s:
  - `content: WidgetContentOption` — **Current Timer** / **Today's Focus** / **Statistics**.
  - `destination: WidgetDestinationOption` — **Timer** / **Today** / **Statistics** / **History**.
  - `countdown: WidgetCountdownOption` — **Show Countdown** / **Hide Countdown**.
- Each has a default, so a freshly-added widget starts at the safe default.
- `var configuration: TimeFrameWidgetConfiguration` maps the three choices to the pure model.

The intent has **no side effects** — it never touches the timer, coordinator, store, or any model.
**WidgetKit owns and persists** the user's choice against the installed widget; the app persists
**nothing** for widget configuration — no `UserDefaults`, no SwiftData (ADR-065).

## 4. Timeline provider & builder

`TimeFrameWidgetProvider` is now an **`AppIntentTimelineProvider`** (`Intent =
TimeFrameWidgetConfigurationIntent`). For each refresh it:

1. reads the last projection from the App Group store (missing/corrupt → stable `.unavailable`);
2. resolves the user's `TimeFrameWidgetConfiguration` from the intent (missing/malformed →
   `.default`);
3. asks the pure `WidgetTimelineBuilder` for entries + reload policy.

`WidgetTimelineBuilder` (pure, `Shared/`) wraps `WidgetTimelinePolicy`: the entry instants and
reload policy come **solely** from the projection's state — the configuration is carried onto each
entry but **never** affects timing. Switching Timer / Today / Statistics therefore can never
introduce a second clock or a per-second reload (ADR-064), a fact pinned by
`ConfiguredWidgetTimelineTests` (all three modes yield identical timing for the same projection).

## 5. Timeline policy (unchanged from M11)

| State | Entries | Reload |
|-------|---------|--------|
| running (future end) | `[now, plannedEnd]` | `.after(plannedEnd)` |
| running (no/past end) | `[now]` | conservative `.after(now + 1h)` |
| **paused** | `[now]` (frozen) | `.never` |
| idle / completed / interrupted / unavailable | `[now]` | conservative `.after(now + 1h)` |

The live countdown "ticks" via SwiftUI's `Text(timerInterval:)` between the projection's frozen
anchors — a repaint, never a widget-owned clock. `showsCountdown == false` replaces the live text
with a calm status word (a quiet variant); the timeline is identical.

## 6. Display modes (the view)

`TimeFrameWidgetView` switches on `configuration.displayMode`:

- **Timer** — the M11 per-state content (idle / running focus / running break / paused / completed /
  interrupted / unavailable), now countdown-aware.
- **Today** — focus time today (primary) + completed sessions and (medium) completed focus
  intervals; a graceful "No focus yet today" when there is no data.
- **Statistics** — focus today (primary) + completed sessions + a trend badge (up/down/steady vs the
  prior day); "No statistics yet" when unavailable.

Small widgets show one primary + one secondary metric; medium widgets show two–three. The view never
reproduces the full Statistics dashboard — it stays glanceable.

## 7. Today / Statistics projection data

Two **additive optional** fields on `WidgetProjection` feed the new modes (ADR-067):

- `completedFocusIntervalsToday: Int?`
- `focusTrendToday: WidgetFocusTrend?` (`up`/`down`/`steady`)

The app computes them from the **same** `StatisticsAggregator`/`StatisticsComparison` the dashboard
uses (today vs the prior day via `StatisticsPeriod.today.previousRange()`), in
`time_frameApp.todaySummary` — a single fetch that mutates nothing. The widget **never aggregates**;
it renders the frozen values. No `StatisticsAggregator` logic is duplicated in the widget.

Because the fields are optional and additive, `currentSchemaVersion` stays **1** and the storage key
stays `…v1`: an M11-shaped payload simply reads them as `nil`, while an incompatible `schemaVersion`
is still rejected (`nil`), never blindly decoded.

## 8. Deep links (reused from M11)

Tap destinations reuse the neutral `timeframe://{timer,today,statistics,history}` scheme and the
existing `ContentView.onOpenURL` → `AppSection` mapping. The widget attaches
`configuration.destination.deepLink.url`; unknown URLs are ignored safely. No new navigation
mechanism was created.

## 9. App Group, offline & CloudKit independence

- **App Group** `group.abirbarman.com.time-frame` — **unchanged**; the only channel between app and
  widget. A missing/denied suite makes the widget render its stable `.unavailable` fallback.
- The widget works **offline**, **without iCloud**, and with **CloudKit disabled or unavailable**:
  it reads only the local projection. M13 CloudKit mirroring stays **below** the repositories and is
  never the widget's data source (ADR-068). Proven by `WidgetCloudKitIndependenceTests`.

## 10. Accessibility

Every configurable option has a plain title and subtitle (no raw enum names reach users). Widget
content combines into a meaningful VoiceOver label in every state — countdown hidden, no active
session, no history today, zero focus, statistics unavailable, completed, interrupted, and the
`.unavailable` fallback. State is **never** conveyed by colour alone: each phase and the trend badge
pair a tint with an SF Symbol and a word; decorative symbols are hidden from assistive tech; text
uses system styles for Dynamic Type.

## 11. Migration / backward compatibility

- Widget `kind` (`"TimeFrameTimerWidget"`), families (`.systemSmall`/`.systemMedium`), and the App
  Group are **unchanged**, so existing installed widgets migrate in place — only the configuration
  mechanism changed (`Static` → `AppIntent`).
- The projection store **format** is preserved (schema version 1, same key); additive optional
  fields are backward- and forward-compatible.
- SwiftData schema stays **V6** (no change).

## 12. Architecture invariants (still true after M14)

Exactly one `TimerEngine` and one `SessionCoordinator`; the widget is read-only, imports no
SwiftData/CloudKit/`TimerEngine`/`SessionCoordinator`, owns no timer state, creates no second clock,
and performs no per-second write; no second database, no new App Group; the M11 kind is stable; M12
App Intents and M13 CloudKit are intact; widget configuration changes presentation only; a widget
failure can never stop the timer, and a CloudKit failure can never make the widget unusable.

## 13. Testing

Deterministic, no Shortcuts/Siri/WidgetKit host or iCloud account required
(`time_frameTests/Widgets/`):

- `WidgetConfigurationTests` — defaults, value sets, deep-link mapping, Codable round-trip, Hashable,
  malformed/partial fallback.
- `WidgetConfigurationIntentTests` — parameter defaults, type/case display representations
  (user-facing wording), choice → configuration mapping.
- `ConfiguredWidgetTimelineTests` — per-state timelines and the timing-invariance proof across the
  three display modes.
- `WidgetProjectionConfigurationTests` — new-field round-trip, M11 backward-compat decode, malformed
  trend, incompatible-version rejection, unchanged schema constants.
- `WidgetConfigurationIsolationTests` — configuring mutates no coordinator/engine/session/interval/
  `ModelContext`.
- `WidgetCloudKitIndependenceTests` — local-only store path + App-Group-unavailable fallback build a
  valid timeline.
- `WidgetConfigurationBoundaryTests` — widget imports no CloudKit/SwiftData/`ModelContext`; the one
  `AppIntents` import in `Shared/` is isolated to the config-intent file; expanded timer-token scan.
- `WidgetProjectionPerformanceTests` — bounded, DB-free timeline + codec throughput.

Plus the M11 suites (`WidgetProjectionMapping/Serialization/Store/Writer`, `WidgetTimelinePolicy`,
`WidgetDeepLink`, `WidgetBoundaryInvariant`) still pass unchanged.

## 14. App Intents metadata

The widget extension runs `ExtractAppIntentsMetadata` automatically (it now links AppIntents via the
shared config-intent file). The built `TimeFrameWidgets.appex/Contents/Resources/Metadata.appintents`
contains `TimeFrameWidgetConfigurationIntent`, its three `AppEnum`s, and their user-facing strings
("Current Timer", "Today's Focus", "Open When Tapped", "Show Countdown"), confirming discovery and
valid display representations. No `.pbxproj` build-phase change was needed for metadata; the three
new `Shared/` files were added to both targets' Sources phases (explicit membership, as `Shared/`
is not a synchronized group).

## 15. Limitations & deferred

- **Manual widget-gallery verification not performed** — no GUI/widget-gallery automation is
  available in this environment, and the widget configuration UI is a macOS system surface. The
  configuration model, intent, timeline, isolation, and boundary are covered by deterministic tests
  and a built-metadata check instead.
- Only `.systemSmall` and `.systemMedium` are supported (unchanged from M11 / product requirements).
- ~~No interactive (button) widgets — out of scope.~~ **Done in Milestone 15** — the configurable
  widget gains `Button(intent:)` controls that route through the one `SessionCoordinator`; see
  `docs/24-INTERACTIVE-WIDGETS.md`. No Live Activities, no Lock Screen accessories — still out of scope.
- CloudKit production sync remains unverified (M13 constraint; a personal Apple Developer team
  cannot enable iCloud).

> **Follow-up (Milestone 15):** the widget becomes **interactive** — per-state `Button(intent:)`
> controls (Pause/Resume/Skip/Restart/Stop/Start) via thin shared App Intents that WidgetKit runs in
> the **app process**, routing through the existing `AppIntentSessionActions` seam to the one
> `SessionCoordinator` (ADR-069). Configuration stays exactly as described here (presentation only),
> controls appear in **Timer** mode only, and the widget still owns no timer, writes nothing, and reads
> only the local App Group projection. See `docs/24-INTERACTIVE-WIDGETS.md`.

> **Follow-up (Milestone 20):** the iOS Home Screen widget reuses this exact configuration system — the
> **same** `TimeFrameWidgetConfiguration` (displayMode / destination / showsCountdown), the **same**
> `TimeFrameWidgetConfigurationIntent` (`AppIntentConfiguration`), and the **same** pure
> `WidgetTimelineBuilder` — so configuration stays presentation-only and can never affect timing on
> either platform. No second configuration system, no schema change (V6). See
> `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
