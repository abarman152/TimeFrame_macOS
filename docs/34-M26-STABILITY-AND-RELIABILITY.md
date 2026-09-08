# 34 — Milestone 26: Stability, Freeze, Concurrency & Production Reliability

**Status:** complete (macOS + iOS).
**Scope:** a hardening milestone. No features, no rewrites, no schema change (stays **V6**).
**ADRs:** ADR-099 (heartbeat lifetime + presentation deferral), ADR-100 (period-bounded statistics).

---

## 1. Executive summary

Users reported the app intermittently freezing while a Pomodoro was running, with Pause/Stop/Skip
becoming unresponsive. The cause was **not** the timer. `TimerEngine` was and remains correct and
timestamp-authoritative; the freeze came from two independent defects that both saturated the **main
actor**, which is where every timer control runs.

Both were reproduced deterministically against the shipping code before any fix was written:

| # | Defect | Reproduced measurement |
|---|---|---|
| 1 | **Heartbeat multiplication** — a cancelled tick loop cleared the handle to a *newer* one, orphaning it and defeating the duplicate guard | live tick loops grew by **one per pause→resume→control cycle**: 11 concurrent loops after 10 cycles, unbounded |
| 2 | **Unbounded statistics on the mutation path** — the widget projection writer ran a full-history fetch + two aggregations *synchronously inside* `pause()`/`resume()`/`stop()`/`skip()` | **5.6 ms** per control at 10 recorded sessions vs **770 ms** at 2,000 — a **137×** regression that grows forever |
| 3 | **`TimelineView` inside the `MenuBarExtra` label** — SwiftUI re-renders a status-item label *synchronously*, and the `TimelineView` re-armed during that render, collapsing its 1 s delay to zero | main thread pinned at **100% CPU**, 199/199 samples in the loop — a true hang, triggered the instant a session started |

Defects 1 and 2 degrade responsiveness progressively. **Defect 3 is a true hang** — an unbounded
SwiftUI update loop that pins the main thread the moment `engine.state` becomes `.running`, i.e. the
instant a session is started. It was found by running the real app and sampling it, after the
domain-level start path measured fast and flat (§23).

Defect 3 was also self-perpetuating across launches: the frozen app could never stop the session, so
it stayed `running` in the store, and every subsequent launch recovered it and froze again before the
window was usable.

All three are fixed architecturally (ADR-099, ADR-100, ADR-101), not masked. After the fixes:

- a timer control performs **zero** statistics reads;
- pause/resume latency is **independent of recorded history** (137× → **1.0×**);
- heartbeats settle at exactly **one** while running, **zero** otherwise, across 100-cycle stress runs;
- the app, launched against the very store that reproduced the hang, sits at **1–2% CPU and idle**
  instead of 100% CPU and unresponsive.

No second timer, clock, coordinator, store, or polling loop was introduced.

---

## 2. The reported freeze

> "The app can freeze/hang while a Pomodoro session is running, causing Pause/Stop/Skip to become
> unresponsive."

Characteristics that the root causes explain:

- **Intermittent** — defect 2's severity scales with accumulated history, so it is invisible on a
  fresh install and severe on a well-used one; defect 1 needs a specific (but common) interleaving.
- **Only while running** — both live on paths that only execute during an active session.
- **Affects Pause/Stop/Skip together** — they share the lifecycle fan-out and the main actor.
- **Gets worse over time** — defect 2 grows with every recorded session, without bound.

---

## 3. Baseline (measured, not assumed)

Measured on this checkout before any change. **Note:** the build command documented in `CLAUDE.md`
fails on this machine with a provisioning error (`No profiles for 'abirbarman.com.time-frame' were
found`), unrelated to code. All builds and tests below therefore use ad-hoc signing:
`CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.

| Item | Baseline |
|---|---|
| macOS Debug build | Yes — `** BUILD SUCCEEDED **` |
| macOS tests | Yes — **808 tests / 181 suites** |
| iOS Debug build | Yes — |
| iPhone 17 Pro tests | Yes — **101 passed / 0 failed** |
| iPad Pro 11-inch (M5) tests | Yes — **101 passed / 0 failed** |
| Compiler warnings | **0** |
| Git | working tree **clean** at `218d015 privacy` |

Repository layout note: the git root is the **inner** `time_frame/time_frame` directory. `docs/`,
`CLAUDE.md` and `README.md` live **outside** the repository and are untracked.

The 6 lines matching `warning:` in a test log are **CoreData runtime logs**
("Dropping Indexes for Persistent History"), identical before and after this milestone. Compiler
warnings — matched as `path:line:col: warning:` — are **0** throughout.

---

## 4. Reproduction methodology

Deterministic and in-tree. The engine runs on the injected `MockTimeSource`, so no test waits real
seconds for timer behaviour; the only real waits drain already-enqueued main-actor follow-up tasks.

**Defect 1** required a diagnostic to observe, so `SessionCoordinator.activeTickerCount` was added
first (with no fix) and the interleaving driven explicitly: pause → resume → *let the cancelled
heartbeat unwind* → issue another control. The count grew monotonically: 2, 3, 4 … 11 over ten cycles.

A naive "50 tight pause/resume cycles" does **not** reproduce it — the cancelled tasks all unwind after
the loop and settle back to one. The bug needs a control *after* a cancelled generation has unwound.
That is why the regression test drains between cycles.

**Defect 3** could not be found this way at all. The domain start path measures **fast and flat**
(~17–28 ms per start, no growth as sessions accumulate — see §17), which ruled out the timer, the
repositories, the notification builder and the lifecycle fan-out. The freeze was therefore in a layer
no unit test covers, so it was found by **running the built app and sampling the live process**
(`sample <pid>`), which showed the main thread pinned in one SwiftUI cycle. Causation was then
established by patch-and-measure against the real app: remove the suspect, rebuild, relaunch, compare
CPU. That method also **falsified** the first mechanism hypothesis (§5.3).

**Defect 2** was measured with the real app wiring — the projection writer subscribed to the lifecycle
fan-out using the same full-history `todaySummary` provider both apps install — against seeded
histories of 10 and 2,000 completed sessions, timing 10 pause/resume pairs. The projection store was
inert and WidgetKit reload was a no-op, so the number measures **only** the statistics cost, not the
App Group write or the XPC reload.

---

## 5. Root causes

### 5.1 Heartbeat multiplication (ADR-099)

```swift
ticker = Task { [weak self, tickInterval] in
    while !Task.isCancelled { … try? await Task.sleep(for: tickInterval) }
    self?.ticker = nil          // ← clears whatever is there, including a NEWER heartbeat
}
```

A cancelled heartbeat does not stop instantly — it resumes from `Task.sleep` on a later main-actor
turn. `pause()` cancels it and nils the handle; `resume()` then creates a new one. When the old
generation finally unwinds it executes `self?.ticker = nil`, discarding the reference to the **live**
loop. That loop is now unreferenced (so `stopTicking()` cannot cancel it) and `ticker == nil` defeats
the `guard ticker == nil` duplicate check, so the next control starts another. Each surviving loop
wakes the main actor every 250 ms.

The loop does self-terminate when the engine leaves `.running`, which is why the app recovers after a
stop — and why the freeze looked intermittent rather than permanent.

### 5.2 Unbounded statistics on the mutation path (ADR-100 + ADR-099)

`SessionCoordinator.pause()` → `emit { .paused($0) }` → the app's fan-out closure →
`WidgetProjectionWriter.handle(_:)` → `update()` → `todayProvider()` →
`StatisticsRepository.sessionInputs()`.

`sessionInputs()` fetches **every** `FocusSession` with no predicate and no limit, and maps each one —
which faults in that session's `SessionInterval` rows. The app then runs **two** full aggregations
(today and yesterday). All of it synchronous, all on the main actor, all inside `pause()`.

The same unbounded pattern appeared in four screens (§9).

---

### 5.3 `TimelineView` in the `MenuBarExtra` label (ADR-101)

Found by running the built app and sampling it — not by reading code. With a session recovered as
running, the process sat at 100% CPU with **199 of 199** main-thread samples inside one cycle:

```
AppMenuBarExtrasController.makeMenuBarExtras
  → MenuBarExtraController.updateConfiguration
    → ViewGraphRootValueUpdater.invalidateProperties
      → MenuBarExtraHost.requestUpdate(after:)
        → UpdateGroup.dispatchActions
          → MenuBarExtraController.updateButton
            → -[NSStatusBarButton setImage:]   (re-rendering the SF Symbol, forever)
```

A `MenuBarExtra` **label** is rendered into an `NSStatusBarButton` image and re-rendered
*synchronously* by `MenuBarExtraHost` when its properties invalidate. `TimeFrameMenuBarLabel` used
`TimelineView(.periodic(by: 1))` while running; the `TimelineView` re-arms its schedule during that
render, so the host requested the next update immediately instead of a second later. The `after:`
delay collapsed to zero and the loop never yielded the main thread.

Because the label switches to that branch exactly when `engine.state == .running`, the freeze fired
the instant a session started.

**Two hypotheses were falsified before the fix was found** — recorded because the first plausible
explanation was wrong:

1. *Remove the `TimelineView`* → confirmed causation (100% → 0.6% CPU) but drops the ticking
   countdown, so it is a diagnosis, not a fix.
2. *The loop comes from rebuilding the projection — which reads the SwiftData `activeSession` model —
   inside the `TimelineView` closure.* **False.** Hoisting every observable read outside the schedule
   and leaving only pure arithmetic inside **still span at 99% CPU**. The `TimelineView` itself is the
   problem in this position, whatever it contains.

**Fix.** No `TimelineView` (or any scheduling primitive) in the label. The countdown repaints from
*outside* the render pass, driven by the heartbeat that already exists: `SessionCoordinator` publishes
a display-only `displaySecond` (whole-second instant of the latest tick, written at most once a second,
only from `tick()`). Because the change originates outside rendering it cannot re-trigger itself — the
exact property `TimelineView` lacked here. It is not a second clock: same heartbeat, no authority, no
persistence/notification/projection work on that path. `TimelineView` is unchanged and correct
everywhere else (`TimerDisplay`, `TodayView`, the menu-bar *popover*), which are ordinary hosted view
hierarchies rather than status-item image rendering.

**Verified on the real app**, against the same store that reproduced the hang:

| | CPU | Process state |
|---|---|---|
| Before | 99–100%, climbing | `R` — frozen |
| After | **1–2%**, flat | `S` — idle, responsive |

## 6. TimerEngine analysis

**No defect found. No change made.**

`TimerEngine` is a pure, `Observation`-only state machine with no SwiftUI, no SwiftData, and no clock
of its own. Every interval is anchored to a target end `Date` and remaining time is derived as
`targetEnd - now` through the injected `TimeProviding` — it never decrements a counter. `synchronize()`
fast-forwards through every interval whose planned end has passed, so a missed tick, a sleep, or a
relaunch all reconcile identically.

Audited and confirmed sound: state/phase transitions, pause re-anchoring, skip/restart/stop recording,
completion, restore-from-snapshot, and the `synchronize()` loop (bounded by the plan's interval count,
so a zero-duration interval cannot spin). Clock-goes-backwards is safe (`max(0, end - now)`).

**The timer remains the one timing authority.** The heartbeat only *wakes* the system to re-evaluate;
it is never the source of elapsed time. Nothing in this milestone changed that.

## 7. SessionCoordinator analysis

`SessionCoordinator` is `@MainActor`, so every mutation is already serialised — there is no data race,
no lock, and no actor-reentrancy hazard on the control path. The defect was **task lifetime**, not
mutual exclusion.

Fix: a monotonic `tickerGeneration`. Each heartbeat captures its generation and clears `ticker` only
if still current; `stopTicking()` retires the generation before cancelling. `activeTickerCount`
exposes the `0...1` invariant for testing.

Verified: repeated pause/stop/start are idempotent, a second `startSession` while active is refused
(returns `nil`, no duplicate row), and 100 skips on a finite plan terminate in `.completed` without
wrapping or duplicating.

## 8. Concurrency model

Unchanged and confirmed: one `@MainActor SessionCoordinator` owning one `TimerEngine`. Because both
the UI, the App Intents seam, the widget control router and the notification action router are
main-actor-isolated, "concurrent" commands are actually *serialised* — the correctness question is
idempotence of repeated/invalid transitions, which is covered by `ControlStressTests`, not lock
ordering. No `NSLock`, `os_unfair_lock`, semaphore, `DispatchGroup.wait`, or `DispatchQueue.sync`
exists anywhere in `Core/` (audited by `ProductionReadinessM26Tests`).

## 9. Persistence & UI responsiveness

`reconcile()` performs one bounded `context.save()` per meaningful transition — correct and cheap; it
was **not** a cause and was left alone. `fetchRecoverableSession()` fetches all sessions, but once, at
launch — noted, not changed.

The unbounded work was in the **statistics** reads. All four screens re-ran a full-history
fetch/aggregation on every body pass, and a body pass happens after every store save — i.e. after
every timer control:

| Surface | Before | After |
|---|---|---|
| Widget today summary (both apps) | full history, on the control path | period-bounded, off the control path |
| macOS `TodayView` | all sessions mapped, aggregated **twice** per body | bounded to today, aggregated **once** |
| macOS `StatisticsView` | all sessions mapped, two aggregations per body | bounded to the shown period + its comparison period |
| iOS `TodayScreen` | full fetch **per body evaluation** (no query cache) | bounded to today |
| iOS `StatisticsScreen` | full fetch **per body evaluation** | bounded to the selected period |

The macOS screens keep their `@Query` (it is what invalidates them on a store change) and apply the
pure filter before mapping — mapping is the expensive step, because it faults in intervals.

## 10–14. Projection, widget, Live Activity, notification and App Intent isolation

The dependency direction was already correct and is unchanged:

```
Core/domain → application mutation → projection → presentation adapters
```

- **Notifications** were already exemplary: every scheduler call goes through `deferWork`, which hops
  to a fresh main-actor task, and every failure is caught and turned into a status. Verified: a
  notification failure cannot stop or corrupt a session.
- **Calendar** follows the same `deferCalendarWork` pattern.
- **The projection writer was the exception** — it did its work *synchronously* on the mutation path.
  That is what ADR-099 corrects. It remains failure-isolated: a missing App Group, a failed encode, a
  failed statistics read and a dead WidgetKit reload are each a silent no-op.
- **App Intents / Control Center** still converge on the one seam:
  `Button(intent:) → WidgetControlActions → AppIntentSessionActions → SessionCoordinator → TimerEngine`.
  Unchanged by this milestone.
- **Live Activities** remain iOS-only; macOS stays ActivityKit-free. Unchanged.

`ProjectionFailureIsolationTests` proves every control still succeeds with the projection store, the
statistics provider **and** the WidgetKit reload all unavailable simultaneously.

## 15. Memory / task lifetime

The only sleep-driven loop in `Core/` is the heartbeat — audited structurally. `Task.sleep` appears in
exactly one Core file (`SessionCoordinator.swift`); `Timer(`, `scheduledTimer`, `DispatchSourceTimer`,
`asyncAfter`, `CADisplayLink` and `DispatchQueue` appear nowhere in `Core/`.

The deferred today refresh is a **one-shot** coalesced task, not a loop — pinned by an audit that
rejects `while`/`repeat`/sleep/timer tokens in `WidgetProjectionWriter.swift`.

Leak coverage: 100 start/stop cycles leave **0** heartbeats; 100 pause/resume cycles settle to
**exactly 1**; completion leaves 0. Verified on macOS and iOS.

## 16. Failure injection

| Injected failure | Expected | Result |
|---|---|---|
| App Group unavailable (`WidgetProjectionStore(defaults: nil)`) | every control succeeds | Yes — |
| Statistics provider returns `nil` | control succeeds; session projection still correct, today figures absent | Yes — |
| WidgetKit reload unavailable | session state still correct | Yes — |
| All three at once | full start→pause→resume→skip→restart→stop cycle correct | Yes — |
| Notification scheduler failing | pre-existing `AllIntegrationsFailureIsolationTests` | Yes — |

## 17. Performance results

Ten pause/resume pairs (20 controls) with the real projection wiring, inert store, no WidgetKit:

| Recorded sessions | Before | After |
|---|---|---|
| 10 | 0.112 s | 0.024 s |
| 2,000 | **15.42 s** | **0.023 s** |
| Slowdown factor | **137×** | **1.0×** |
| Statistics reads on the control path | 21 | **0** |

Bounded-vs-unbounded aggregation is asserted **byte-identical** over six ranges (inside, at the edges
of, and entirely outside the seeded window) on both platforms.

Thresholds in the committed tests are deliberately generous (ratio < 5× + 0.5 s, absolute < 1.0 s) so
they assert the *shape of the curve*, not a machine-dependent number.

## 18. Bugs fixed

1. **Heartbeat multiplication / lost cancellation** (unbounded task leak) — ADR-099.
2. **Full-history statistics on the timer control path** (O(lifetime) Pause) — ADR-099/100.
3. **macOS `TodayView` aggregated the full snapshot twice per body pass** — one figure each.
4. **macOS `StatisticsView` mapped all history per body pass** for a bounded period.
5. **iOS `TodayScreen` / `StatisticsScreen` fetched all history per body evaluation**, with no query
   cache to amortise it.
6. **`TimelineView` inside the `MenuBarExtra` label** — an unbounded SwiftUI update loop that pinned
   the main thread at 100% CPU whenever a session was running, and re-froze on every launch because the
   stuck `running` session was recovered — ADR-101.

**Reviewed and deliberately not changed:**

- `PersistenceController.openLocalOrInMemory`'s `try! makeContainer(mode:.local, inMemory: true)` — the
  documented last-resort fallback. An in-memory container over a valid schema cannot fail except on a
  malformed schema, which every test would catch; there is no non-crashing alternative that still
  returns a non-optional `ModelContainer`. Left as-is, with the existing comment.
- `MainActor.assumeIsolated` in the sleep/wake observer — the notification is registered with
  `queue: .main`, so the assumption holds.
- `fetchRecoverableSession()`'s full fetch — once, at launch.
- No `fatalError`, `as!`, empty `catch`, or swallowed-error site was found in production sources.

## 19. Tests

| Suite | Tests | What it pins |
|---|---|---|
| `TimerHeartbeatLifetimeTests` | 6 | multiplication, stop/pause/completion cleanup, 100-cycle stress |
| `ControlPathResponsivenessTests` | 5 | zero statistics reads on the control path; flat latency curve; deferred summary still arrives; bursts coalesce |
| `BoundedStatisticsEquivalenceTests` | 4 | bounded ≡ unbounded aggregation; open sessions admitted; boundary exactness |
| `ProjectionFailureIsolationTests` | 2 | every control survives total projection failure |
| `ControlStressTests` | 5 | repeated/invalid transitions; 100 skips; 100 start/stop cycles |
| `ProductionReadinessM26Tests` | 8 | single scheduling authority, single engine/coordinator, read-only projection & statistics, unchanged identity, generation guard present |
| `IOSHeartbeatLifetimeTests` (iOS) | 2 | heartbeat invariants hold on iOS |
| `IOSControlPathResponsivenessTests` (iOS) | 2 | zero statistics reads; bounded ≡ unbounded on iOS |
| `MenuBarLabelRepaintTests` | 4 | no `TimelineView`/scheduling primitive in the status-item label; the label still observes the display heartbeat; `displaySecond` granularity and non-authority |

Two existing tests were updated — not weakened — to the intentionally changed contract: the today
summary now lands on the coalesced follow-up pass rather than synchronously, so
`WidgetProjectionWriterTests` and `WidgetCloudKitIndependenceTests` now assert **both** the immediate
session write and the deferred today figures.

## 20. Build & test matrix (final, run serially)

| Target | Result |
|---|---|
| macOS Debug build | Yes — `** BUILD SUCCEEDED **` |
| macOS tests | Yes — **841 tests / 188 suites** (from 808/181) |
| macOS Release build | Yes — `** BUILD SUCCEEDED **` |
| iOS Debug build + tests (iPhone 17 Pro) | Yes — **105 passed / 0 failed / 30 suites** (from 101) |
| iOS tests (iPad Pro 11-inch M5) | Yes — **105 passed / 0 failed / 30 suites** (from 101) |
| iOS Release build | Yes — `** BUILD SUCCEEDED **` |
| Compiler warnings (all of the above) | **0** |
| macOS widget `.appex` embedded | Yes — `time_frame.app/Contents/PlugIns/TimeFrameWidgets.appex` |
| iOS widget `.appex` embedded | Yes — `TimeFrameiOS.app/PlugIns/TimeFrameiOSWidgets.appex` |
| App Intents metadata | Yes — `Metadata.appintents` generated; extraction clean |
| Source-boundary audits | Yes — M17, M19–M24 + new M26 all pass |
| Live app, against the store that reproduced the hang | Yes — **1–2% CPU, idle** (was 100%, frozen) |
| SwiftData schema | **V6**, unchanged |
| App Group / deep link | `group.abirbarman.com.time-frame` / `timeframe://`, unchanged |

## 21. Remaining limitations — what was NOT verified

Stated plainly; none of this is claimed as verified.

**Automated / simulator only.** Everything above is `xcodebuild` on this Mac plus the iOS Simulator.

**Physical device — NOT performed** (no device used in this milestone): real iPhone pause/resume feel,
Dynamic Island, Lock Screen accessory widgets, StandBy, Control Center controls, VoiceOver on device,
notification banners, background execution, device sleep/wake.

**Defect 3 *was* observed directly** on this machine: the built app pinned the main thread at 100% CPU
against the reporting store, and dropped to 1–2% after the fix. Defects 1 and 2 were reproduced from
source under conditions matching the reported symptom rather than observed in the field; their
reproductions are committed. If freezes persist, the diagnostics (`activeTickerCount`,
`todayRefreshCount`, `displaySecond`) plus `sample <pid>` are the tools to use.

**What was verified by driving the UI: nothing.** The app was launched and sampled, and its CPU/process
state measured — the countdown ticking, the popover opening, and the controls responding were **not**
exercised by clicking. The menu-bar *popover* still uses a `TimelineView`; it is an ordinary hosted view
hierarchy (like `TimerDisplay`, which works), so it is expected to be fine, but that is **code
inspection, not UI verification**.

**CloudKit — still disabled and unverified.** `CloudKitCapability.entitledInThisBuild == false` on this
personal (free) team build; the iCloud entitlement is not added and no container is invented. Real
two-device sync, merge behaviour against a live container, and Production schema deployment all remain
blocked on a paid Apple Developer team (ADR-080/082). Unchanged by M26.

**Not simulated:** true app termination/relaunch during a live session on device, OS-level main-thread
watchdog behaviour, memory pressure eviction, and real WidgetKit reload budgeting (the tests inject a
no-op reload).

**Provisioning:** the project cannot be signed for distribution on this machine; all builds used ad-hoc
signing.

## 22. Production-readiness checklist

- [x] Reported freeze has a documented, reproduced root cause — two of them
- [x] Root causes fixed architecturally, not masked
- [x] Pause / Stop / Skip / Resume responsive and history-independent
- [x] Timer completion correctness unchanged
- [x] No second timer, clock, coordinator, store, or polling loop
- [x] Persistence cannot block the control path
- [x] Projection / notification / widget failure cannot break session mutation
- [x] Concurrent and repeated commands safe and idempotent
- [x] No task or heartbeat leak across lifecycle transitions
- [x] macOS + iOS (iPhone & iPad) tests pass; Debug + Release build
- [x] 0 compiler warnings
- [x] Source-boundary audits pass; schema stays V6
- [ ] Physical-device validation — **not performed**
- [ ] CloudKit production sync — **blocked (paid team)**
