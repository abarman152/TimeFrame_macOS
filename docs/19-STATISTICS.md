# 19 — Statistics & Productivity Analytics (Milestone 10)

Time Frame turns its persisted session history into a productivity dashboard: focus
time, completion rate, daily and configuration breakdowns, trends, and the most
productive day, for a range of periods. This document describes the architecture,
the data sources and aggregation rules, date-range semantics, metric definitions, the
chart strategy, empty states, accessibility, performance, and testing.

> **Statistics are a read-only projection of history.** The statistics layer never
> mutates the `TimerEngine`, `SessionCoordinator`, `FocusSession`, `SessionInterval`,
> a configuration, a template, or a plan. There is **one timer** and **one historical
> source of truth**; statistics only *read* it. Nothing here introduces a second timer,
> a second clock, or a second database.

---

## 1. Architecture

```
                 SwiftData history (FocusSession / SessionInterval)
                                   │
                     ┌─────────────┴──────────────┐
                     ▼                             ▼
        @Query in StatisticsView          StatisticsRepository        ← read-only fetch
                     │                             │  (single fetch; @MainActor)
                     └──────────────┬──────────────┘
                                    ▼
                          [SessionStatInput]                          ← pure, Sendable values
                                    │
                          StatisticsAggregator                        ← pure, deterministic
                                    ▼
                          StatisticsSnapshot                          ← immutable result value
                                    ▼
                    StatisticsView  /  TodayView (.today)             ← SwiftUI presentation
                                    ▼
                             Swift Charts
```

Dependencies point downward only, matching the app's layering. The aggregator depends
on neither SwiftUI nor SwiftData; the pure value types import only `Foundation`.

### Files

- `Statistics/` — the pure, SwiftUI/SwiftData-free engine:
  - `StatisticsInput.swift` — `SessionStatInput` / `IntervalStatInput` (the aggregation input).
  - `StatisticsPeriod.swift` — `StatisticsPeriod` + `StatisticsDateRange` (range semantics).
  - `StatisticsSnapshot.swift` — `StatisticsSnapshot`, `DailyStatistics`,
    `ConfigurationStatistics`, `StatisticsComparison` (the results).
  - `StatisticsAggregator.swift` — the deterministic aggregation.
- `Services/Statistics/StatisticsRepository.swift` — the `@MainActor` read-only fetch that
  maps `FocusSession` → `SessionStatInput`. The mapping lives here so the pure value type
  imports only Foundation; the SwiftUI dashboard reuses the same mapping via `@Query`.
- `Views/Statistics/`
  - `StatisticsView.swift` — the dashboard (metric cards, trend, most-productive day, charts).
  - `StatisticsPeriodPicker.swift` — the period selector + custom-range editor.
  - `StatisticsCharts.swift` — the Swift Charts (focus by day, sessions by day, configuration).
- `Views/Today/TodayView.swift` — refactored to draw its two figures from the **same**
  aggregator over the `.today` period (no duplicate aggregation).
- `Views/AppSection.swift`, `ContentView.swift` — add and route the `Statistics` sidebar section.

---

## 2. Data sources & the read-only rule

Statistics consume exactly the rows History browses: `FocusSession` and its owned
`SessionInterval`s. There is **no second analytics store** and **no persisted derived
statistics** — a snapshot is recomputed from history on demand, so if the app restarts
the same history yields the same numbers (statistics are fully reproducible).

The repository performs a **single fetch** per call and maps each session into an
immutable `SessionStatInput` (copying only frozen values, never a live configuration
reference). The aggregator then works entirely in memory. No query runs per chart
point, per day, or per SwiftUI redraw, and there is no `Timer`/`TimelineView`/clock in
the statistics layer at all.

---

## 3. Aggregation rules

Two attribution rules, applied consistently (and covered by tests):

- **Session-level metrics** — *started*, *completed*, *stopped*, *interrupted* sessions,
  *completion rate*, and *longest focus session* — count a session when its `startedAt`
  falls in the range. A `planned` (never-started) session has no `startedAt` and is
  excluded from every "started" figure.
- **Interval-level metrics** — *focus/break time*, *completed focus-interval count*, and
  the *daily* and *configuration* breakdowns — count a **completed** interval when its
  end instant (`endedAt`, falling back to `startedAt`) falls in the range.

Only intervals with status `completed` contribute to focus/break totals. An interval is
**never** treated as "focused" merely because its configured duration elapsed —
`pending`, `running`, `paused`, `skipped`, and `cancelled` intervals are excluded, exactly
as History treats them. For a completed interval the frozen `plannedDuration` is the time
actually focused/rested (it ran to its planned end), which is the deterministic figure
History already reports.

Attributing an interval by its **own** end instant (not the session's start) is what makes
a session that crosses midnight bank each interval on the correct day.

### Configuration attribution (survives rename/delete)

Focus time is grouped by a **frozen** configuration name: the interval's own
`configurationName` when present (multi-configuration plans freeze one per focus),
otherwise the session-level frozen name, otherwise `"No configuration"`. Because the name
is frozen at session start, renaming or deleting a configuration never rewrites history
(ADR-019/028). Task/template/plan attribution beyond this frozen name is **not** persisted
today — see §9.

---

## 4. Date-range semantics

`StatisticsPeriod` resolves to a half-open `[start, end)` `StatisticsDateRange` using the
**user's own `Calendar`** (local time zone). All day/week/month stepping goes through
`Calendar` arithmetic (`dateInterval(of:)`, `date(byAdding:)`), never a hard-coded 86 400
seconds, so:

- midnight boundaries are exact (half-open ranges never double-count the boundary instant);
- a 23- or 25-hour **DST** day is handled correctly (a week spanning a DST change still has
  seven day buckets, each aligned to the start of its local day);
- grouping uses the calendar's **time zone**, not UTC (a 23:30-local focus lands on the
  local day).

Supported periods: **Today, Yesterday, This Week, Last Week, This Month, Last Month,
Custom**. A custom range is inclusive of both chosen days and is normalised to
`[startOfDay(start), startOfDay(end)+1 day)`; the picker's date-field bounds enforce
`start ≤ end`, so an impossible range cannot be built. Range resolution takes an injected
reference date, so it is deterministic under test.

---

## 5. Metric definitions

| Metric | Definition |
| --- | --- |
| **Focus time** | Σ `plannedDuration` of completed focus intervals ending in range. |
| **Break time** | Σ `plannedDuration` of completed break intervals ending in range (kept separate from focus). |
| **Completed focus intervals** | Count of completed focus intervals ending in range. |
| **Started sessions** | Sessions with `startedAt` in range. |
| **Completed sessions** | Started sessions with status `completed`. |
| **Completion rate** | completed ÷ started; **nil** when nothing started (shown as "—", never a divide-by-zero). |
| **Stopped sessions** | Started sessions with status `cancelled`. |
| **Interrupted sessions** | Started sessions with status `interrupted`. |
| **Average focus interval** | focus time ÷ completed focus intervals; **nil** when none. |
| **Longest focus session** | Largest single-session total completed-focus time among sessions in range. |
| **Daily breakdown** | One continuous bucket per calendar day in range (zero-days included). |
| **Configuration breakdown** | Focus time per frozen configuration name, descending. |
| **Most productive day** | Day with the most focus; **nil** when no day had focus. |
| **Focus trend** | Current-period focus vs the previous equivalent period: absolute + % change (% is **nil** when the previous period was zero). |

---

## 6. Charts

Native **Swift Charts**, each a read-only projection of an already-computed snapshot:

1. **Focus by Day** — `BarMark`, minutes per day (weekday axis for week-length ranges, day
   number for longer ranges). Shown only for multi-day periods.
2. **Sessions Completed** — `BarMark`, completed sessions per day. Shown only for multi-day periods.
3. **Focus by Configuration** — horizontal `BarMark` with a trailing duration annotation.

Every chart handles empty and single-point data with an **explicit placeholder** (never a
blank axis), uses `TFPalette` colours (so light/dark and accent adapt automatically), and
carries per-mark text labels/values so meaning never rides on colour alone. The trend and
most-productive-day cards give the same information as text.

---

## 7. Empty states

- **New user (no started sessions ever):** a `ContentUnavailableView` — "No Focus Sessions
  Yet" with a **Start Timer** action that navigates to the Timer.
- **History exists but the selected period is empty:** a quiet "No Focus in This Period"
  note (the period picker stays visible so the user can pick another range). Charts and
  breakdowns are hidden rather than shown as zeroes.

---

## 8. Accessibility

- Every metric card is a single combined accessibility element labelled "Title: value, caption".
- Charts add per-mark `accessibilityLabel`/`accessibilityValue` (e.g. "Thursday, 3 hours 45
  minutes of focus") and an overall chart label; colour is always paired with text/number.
- The trend and most-productive-day cards expose a spoken summary via `accessibleClock`.
- Motion uses the Reduce-Motion-aware `tfAnimation`; there is no colour-only signalling.

---

## 9. What is *not* attributed (and why)

Historical sessions persist a frozen configuration name (per session, and per focus for
plan-started sessions) but **do not** persist a durable reference to the originating
`TaskTemplate` or `SessionPlan`. Templates and plans are *starting points* that copy their
values into an independent session (ADR-021/025/028), so a completed session cannot be
reliably attributed back to a specific template or plan. Statistics therefore group by the
frozen **configuration name** and the free-text **task name** only, and do **not** invent a
template/plan relationship that history does not record. Adding such attribution would be a
data-model change (a new persisted reference or frozen id) and belongs to a future
milestone, not M10 — the schema was intentionally left unchanged (see §11).

---

## 10. Performance

Fetch relevant history **once**, aggregate in memory, produce an immutable snapshot. The
aggregation is O(sessions + intervals); the daily breakdown steps day-by-day across the
range only. No caching is introduced (profiling did not demonstrate a need). A test
aggregates a synthetic **1,000-session / 5,000-interval** dataset as a coarse guard against
accidental non-linear cost.

---

## 11. Data model / schema

**No SwiftData schema change.** Every metric is derived from the existing `FocusSession`
and `SessionInterval` fields (status, phase, `plannedDuration`, `startedAt`, `endedAt`, and
the frozen `configurationName`s). The schema stays **V5**. This was anticipated: the models
and the engine's `IntervalRecord` history were shaped in earlier milestones to support
statistics without a redesign (see `docs/DECISIONS.md`).

---

## 12. Testing

Deterministic Swift Testing suites (fixed dates, injected calendar, in-memory store):

- **StatisticsAggregationTests** — focus/break totals, session counts, completion rate,
  averages, longest session, daily and configuration breakdowns.
- **StatisticsDateRangeTests** — today/yesterday/week/month/custom, midnight boundaries,
  time-zone grouping, DST-sensitive spans.
- **StatisticsTrendTests** — current vs previous, positive/negative/zero-previous/identical,
  `previousRange` correctness.
- **StatisticsRepositoryTests** — empty/one/many mapping, renamed and deleted configurations
  (frozen names), read-only (no pending writes).
- **StatisticsEdgeCaseTests** — empty history, zero-duration/incomplete intervals,
  midnight-crossing sessions, a large synthetic dataset.
- **StatisticsApplicationTests** — Statistics in navigation, Today shares the engine, the
  period selector changes results, the empty-state condition, and that reading statistics
  disturbs neither the running timer nor History.

---

## 13. Future extension points

- Persisted template/plan attribution (a data-model milestone; see §9).
- A calendar-style activity heatmap (a clean daily bar chart is shipped instead in M10).
- Streaks / goals, CSV export, and richer per-task analytics.

**App Intents (Milestone 12).** `ShowTimeFrameStatisticsIntent` opens the **existing** Statistics
section (via the `timeframe://statistics` deep link the widgets already use); it adds no second
statistics implementation. The status/current-session intents read only the live session
projection, never historical analytics. See `docs/21-APP-INTENTS.md`.
