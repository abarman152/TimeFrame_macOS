# 03 — Timer Engine

> **Milestone 18 note.** The engine is **unchanged** by M18 (no behaviour, no timer, no schema
> change). Its source moved from `time_frame/Timer/` into the shared **`Core/Timer/`** group so it
> compiles into both the macOS app and the iOS companion — there is still exactly **one** `TimerEngine`
> and **one** `SessionCoordinator`, now shared across platforms. The iOS Live Activity reads the same
> derived state; it never advances the engine (ADR-078/079).

The `TimerEngine` is the heart of Time Frame: a reliable, deterministic Pomodoro
state machine with no dependency on SwiftUI or SwiftData. This document is the
specification of its states, transitions, and accuracy model, and it matches the
implementation in `Timer/`.

---

## 1. Building blocks

| Type | File | Role |
|---|---|---|
| `TimerState` | `Timer/TimerState.swift` | lifecycle state: `idle`, `running`, `paused`, `completed`, `cancelled` |
| `TimerPhase` | `Timer/TimerPhase.swift` | interval kind: `focus`, `shortBreak`, `longBreak` |
| `PlannedInterval` / `IntervalPlan` | `Timer/IntervalPlan.swift` | the generated interval sequence |
| `PomodoroConfigurationSnapshot` | `Timer/PomodoroConfigurationSnapshot.swift` | validated value the plan is generated from |
| `TimeProviding` / `SystemTimeSource` | `Timer/TimeSource.swift` | injectable authoritative clock |
| `IntervalRecord` / `IntervalOutcome` | `Timer/IntervalRecord.swift` | in-memory history of ended intervals |
| `TimerEngineSnapshot` | `Timer/TimerEngineSnapshot.swift` | pure-value engine state for recovery (no SwiftData) |
| `TimerEngine` | `Timer/TimerEngine.swift` | the state machine |
| `SessionCoordinator` | `Timer/SessionCoordinator.swift` | heartbeat + persistence + recovery driver |

## 2. Session sequence generation

The plan is **generated from configuration, never hardcoded**. For `N` total
focus sessions and a long-break interval `L`:

- For each focus block `k` in `1…N`: append a **focus** interval, then a break.
- The break after focus `k` is a **long break** when `k % L == 0`, otherwise a
  **short break**.
- A break follows *every* focus block, including the last.

Example — `N = 4`, `L = 4`:

```
Focus, Short, Focus, Short, Focus, Short, Focus, Long
```

Example — `N = 4`, `L = 2`:

```
Focus, Short, Focus, Long, Focus, Short, Focus, Long
```

Durations map by phase (focus → focus duration, etc.). Indices are contiguous
and 0-based. Implemented in `IntervalPlan.init(configuration:)`; verified by
`IntervalPlanTests`.

> Design note: a trailing break after the final focus is intentional and matches
> the Milestone 1 specification. Making the trailing break optional is a possible
> later configuration flag (recorded in `DECISIONS.md`).

## 3. State machine

States: `idle`, `running`, `paused`, `completed`, `cancelled`.
Phases (only meaningful while active): `focus`, `shortBreak`, `longBreak`.

```
              start
   IDLE ───────────────► RUNNING (focus #1)
                            │
        interval reaches    │  synchronize(): now ≥ targetEnd
        its planned end     ▼
                         RUNNING (next interval)  ── … repeats through the plan …
                            │
   pause │  ▲ resume        │  last interval ends
         ▼  │               ▼
        PAUSED           COMPLETED

   from RUNNING or PAUSED:
     stop  ──► CANCELLED        (current interval recorded as .cancelled)
     skip  ──► RUNNING (next)   (current interval recorded as .skipped)
              or COMPLETED if no next interval
     restart ─► same state, current interval reset to full duration
```

Control messages that do not apply to the current state are **ignored**
(no-ops). For example `pause` while `idle`, `resume` while `running`, or `start`
while `running` all do nothing. Verified by
`TimerEngineStateTests.invalidTransitionsIgnored`.

### Transition table

| From | Message | To | Effect |
|---|---|---|---|
| idle | start | running | index 0, clear history, anchor interval 0 |
| running | pause | paused | capture remaining, drop the running anchor |
| paused | resume | running | re-anchor end to `now + remaining` |
| running | synchronize (past end) | running / completed | complete + advance, or finish |
| running/paused | stop | cancelled | record current interval `.cancelled` |
| running/paused | skip | running / completed | record `.skipped`, advance |
| running/paused | restart | running / paused | reset current interval to full duration |
| completed/cancelled | reset | idle | same plan, cleared history |

## 4. Accuracy — authoritative timeline (critical)

The engine **never** decrements a counter once per second. Each running interval
is anchored to a target end `Date`:

```
intervalEndDate = intervalStartDate + plannedDuration
remaining(now)  = max(0, intervalEndDate − now)
```

`now` comes exclusively from the injected `TimeProviding`. Consequences:

- **Delayed / missed ticks are harmless.** `remaining` is always recomputed from
  timestamps, so a late tick simply yields a smaller remaining value.
- **Sleep / backgrounding are handled.** Wall-clock `Date` keeps advancing while
  the machine sleeps, so on the next `synchronize()` the engine sees the true
  elapsed time.
- **No drift accumulates.** When an interval completes, the next interval is
  anchored to the *planned* end of the previous one (not to `now`), so rounding
  never compounds across a long session.

### `synchronize()` — the tick

`synchronize()` is the only place automatic progression happens:

```
while running and now ≥ intervalEndDate:
    record current interval as .completed (endedAt = planned end)
    advance to next interval
    if a next interval exists:
        anchor it: start = previous planned end, end = start + its duration
        (loop again — this fast-forwards through intervals missed during sleep)
    else:
        state = completed
```

A single `synchronize()` after a long gap can therefore complete several
intervals at once. Verified by
`TimerEngineSequenceTests.fastForwardThroughSleep` and
`delayedTickChainsIntervals`.

## 5. Controls in detail

- **start** — from `idle` only. Sets index 0, clears history, anchors the first
  interval, and synchronizes.
- **pause** — from `running`. Captures `remaining` into `remainingWhenPaused` and
  drops the end anchor, so the clock advancing no longer reduces remaining.
- **resume** — from `paused`. Re-anchors `end = now + remainingWhenPaused`. It
  **does not reset** the interval. Resuming an interval that was paused at exactly
  0 completes it immediately (a `synchronize()` runs after resume).
- **stop** — from `running`/`paused`. Records the in-progress interval with
  outcome `.cancelled` (history preserved), clears anchors, state → `cancelled`.
- **skip** — from `running`/`paused`. Records the current interval as `.skipped`
  (never discarded) and advances. The next interval begins **running**; if there
  is none, state → `completed`.
- **restart** — from `running`/`paused`. Resets the current interval to its full
  configured duration **without** disturbing the rest of the plan or the index.
  While `running` it re-anchors from `now`; while `paused` it restores full
  remaining and stays paused.
- **reset** — returns a finished engine to `idle` with the same plan and cleared
  history.
- **load(plan:)** — replaces the plan while `idle`; **ignored while active** so a
  run is never corrupted.

## 6. History

The engine keeps an in-memory `completedIntervals: [IntervalRecord]`. Every
interval that ends — whether completed, skipped, or cancelled — appends a record
(`index`, `phase`, `plannedDuration`, `startedAt`, `endedAt`, `outcome`). This
guarantees skip/stop never silently lose session history and provides the raw
material for persisted history/statistics in a later milestone.

## 7. Restoration (recovery seam)

For app-relaunch and sleep/wake recovery (Milestone 2), the engine can be rebuilt
from a **pure value** without importing SwiftData:

- `TimerEngineSnapshot` captures `state`, `currentIndex`, `completedIntervals`,
  and the timeline anchors (`intervalStartDate`, `intervalEndDate`,
  `remainingWhenPaused`).
- `restore(from:)` applies a snapshot, but **only from `idle`** and only for a
  `.running`/`.paused` snapshot whose `currentIndex` is valid — otherwise it is
  ignored, so an active run is never corrupted.
- Read-only accessors `currentIntervalStart` / `currentIntervalEnd` let the
  persistence layer record the timeline; the engine stays the only writer.

Recovery flow: the persistence side reads the stored rows, assembles the
snapshot, calls `restore(from:)`, then (for a running session) `synchronize()` to
fast-forward through intervals missed while away. See
`docs/04-SESSION-LIFECYCLE.md` and ADR-012/014. Verified by
`TimerEngineRestoreTests` and `SessionRecoveryTests`.

## 8. Driving the engine

- **Production:** `SessionCoordinator` (`@MainActor`, `@Observable`) owns a
  cancellable `Task` that calls `synchronize()` roughly every 250 ms while
  running and stops when the session is not running. Each meaningful transition
  is mirrored into SwiftData (the engine itself does no persistence). Because
  correctness lives in the timestamp math, the exact cadence does not affect
  accuracy.
- **Tests:** advance a `MockTimeSource` by hand and call `synchronize()` (or the
  coordinator's `tick()`) directly. No real time passes.

## 9. Independence & testability guarantees

- `TimerEngine` imports only `Foundation` and `Observation` — **no SwiftUI, no
  SwiftData.** Recovery crosses the boundary as plain values
  (`TimerEngineSnapshot`), never a persistence type.
- All time is injected; there is no hidden `Date()` or `Timer` inside the engine.
- The engine can be fully driven and asserted without launching a UI, which is
  exactly how `TimerEngine*Tests` operate.
- The engine imports **no EventKit and no UserNotifications**. The Calendar and
  Notification integrations are pure *observers* of the timer's transitions (via the
  `SessionLifecycleEvent` seam); they derive their representations from the engine's
  authoritative timestamps and can never feed timing back into it (ADR-035/039). A
  notification is scheduled to fire at an interval's authoritative target end — the same
  timeline math the engine uses — never from a per-second callback. See
  `docs/16-NOTIFICATIONS.md`.
- **App Intents (Milestone 12)** are one more surface that *drives* the engine only through
  `SessionCoordinator` (start/pause/resume/skip/restart/stop) and *reads* it through the pure
  `AppIntentSessionState` projection. No intent touches the engine directly, holds timer state,
  or introduces any timer primitive — the engine stays the single timer authority (ADR-056).
  See `docs/21-APP-INTENTS.md`.

## 10. Boundary hardening (Milestone 17)

M17 changes **no engine semantics**. It adds `TimerBoundaryHardeningTests` to lock in the properties
that follow from the timestamp-authoritative model: `remaining` is never negative (no NaN, no negative
countdown) however far past an interval end the clock runs; a **backwards** system-clock correction never
corrupts the run and self-heals moving forward; skip/stop exactly at a boundary behave; a 24-hour interval
computes correctly; and a **ten-year** sleep/wake gap fast-forwards to completion in a single
`synchronize()` without hanging. A whole-tree source audit additionally asserts the engine performs no
scheduling and that `TimerEngine` is declared once and constructed only by `SessionCoordinator`
(ADR-077). See `docs/26-PRODUCTION-READINESS.md`.
