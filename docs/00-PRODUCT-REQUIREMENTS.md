# 00 — Product Requirements

**Product:** Time Frame — a native macOS 27 Pomodoro and productivity app, with a native
iOS/iPadOS companion (Milestone 18).
**Status:** Milestone 18 (iOS/iPadOS companion + real Live Activities). The macOS app remains the
primary product and is ActivityKit-free; the iOS/iPadOS companion reuses the same shared `Core/`
domain (one `TimerEngine`, one `SessionCoordinator`) and adds real ActivityKit Live Activities.
Cross-device CloudKit sync is prepared but requires a paid Apple Developer team (documented blocker).
**Milestone 19** hardened that readiness: CloudKit capability is now an explicit, unit-tested seam,
cross-device/merge/fallback behaviour is proven deterministically, and the free-team blocker is kept
honest by the release-gate audit — no entitlement is fabricated and real cross-device sync stays
unverified by design (see `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`).
**Milestone 20** completed the iOS productivity layer: a configurable **iOS Home Screen widget**
(small/medium/large; Timer/Today/Statistics) and **iOS local notifications**, plus companion UI
polish — all reusing the existing projection/App-Group/config-intent/control seams and the neutral
notification stack (now shared via `Core/`), with no second timer, no schema change (V6), and no
CloudKit (see `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`).
**Milestone 21** extended the iOS WidgetKit experience to the **Lock Screen** (accessory circular /
rectangular / inline) and **StandBy** — read-only projections in the same extension reusing the same
projection/App-Group/configuration pipeline, with a pure per-family presentation mapper, read-only
accessory surfaces, no second timer/clock/mutation seam, no schema change (V6), and no CloudKit (see
`docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`).
**Milestone 22** added native iOS **Control Center** controls (WidgetKit `ControlWidget`, iOS 18+) —
Start/Pause/Resume/Skip/Stop as a command adapter over the one timer, reusing the Milestone-15 mutation
seam, with a pure Foundation-only decision layer, no second timer/clock/store/router, iOS-only (macOS
stays `ControlWidget`-free), CloudKit-independent, and no schema change (V6) (see
`docs/31-CONTROL-CENTER-CONTROLS.md`).
This document defines the functional boundaries of the product and, explicitly, what is *not* being
built yet.

---

## 1. Vision

Time Frame helps a person structure focused work using the Pomodoro technique:
alternating focus intervals with short and long breaks, organized into
configurable sessions. Over subsequent milestones it grows into a full macOS
productivity tool with reusable configurations, task templates, session
planning, Calendar integration, notifications, a menu-bar timer, and history.

## 2. Core concepts

| Concept | Meaning |
|---|---|
| **Pomodoro configuration** | A named rhythm: focus / short-break / long-break durations, how many focus sessions occur before a long break, and a default total number of sessions. |
| **Focus session** | One run of a plan — in progress or completed — built from a configuration. |
| **Session interval** | A single unit within a session: a focus block, a short break, or a long break. |
| **Session plan** | The ordered sequence of intervals generated from a configuration. |

## 3. Pomodoro feature set (functional requirements)

The Pomodoro engine supports:

- Custom **focus** duration.
- Custom **short-break** duration.
- Custom **long-break** duration.
- Configurable **number of sessions** (focus blocks).
- Configurable **long-break interval** (focus blocks between long breaks).
- **Pause** and **Resume** (preserving remaining time exactly).
- **Stop** (end the whole session).
- **Skip** (end the current interval, advance to the next, preserve history).
- **Restart** (restart the current interval from its full duration).
- **Session completion** (reaching the end of the plan).
- **Break transitions** (automatic focus → break → focus progression).

**Implemented in Milestone 1** as `TimerEngine` — see `docs/03-TIMER-ENGINE.md`.

## 4. Configurations

Users will eventually create and manage multiple named configurations, e.g.
Classic Pomodoro, Deep Work, Study, Coding, Research, Custom. The persisted
`PomodoroConfiguration` model already supports naming and all rhythm values.

**Milestone 1:** the model exists and a "Classic Pomodoro" default is seeded on
first launch. Configuration management **UI** is a later milestone.

## 5. Task Templates (later milestone)

Users will create reusable task templates. A template **references a
`PomodoroConfiguration`** rather than duplicating its values. The data
architecture keeps this open (see `docs/02-DATA-MODEL.md` §"Future direction").

**Milestone 1:** not implemented; architecture must not prevent it.

## 6. Session Planning (Milestone 5 — implemented)

Users build persisted, editable multi-session plans (`SessionPlan`/
`SessionPlanItem`), preview them, and start them. A plan is frozen into a value
snapshot and run through the existing engine — the planner is not a second timer.
Plans may mix configurations, and a running/historical session is independent of the
saved plan and its configurations. See `docs/14-SESSION-PLANNER.md`.

## 7. Apple Calendar (later milestone)

EventKit integration to create customized Apple Calendar events for planned
sessions. To be isolated behind a service. **Not in Milestone 1.**

## 8. Notifications (Milestone 7 — implemented)

Native macOS local notifications for interval transitions and session completion,
isolated behind a service (`NotificationCoordinator` → `UserNotificationService`) that
subscribes to the same pure `SessionLifecycleEvent` seam as Calendar. Optional and
off by default; permission is requested contextually, never on launch. **Implemented**:
Focus / Short break / Long break start and Session complete notifications, per-category
+ sound + action-button preferences, Pause/Skip/Open actions routed through
`SessionCoordinator`, recovery/sleep-wake reconciliation, and total failure isolation
(a notification failure never affects the timer). **Deferred**: a distinct "Plan
complete" message (a running session carries no plan identity by design). See
`docs/16-NOTIFICATIONS.md`.

## 9. Menu Bar (Milestone 8 — implemented)

A native macOS `MenuBarExtra` giving quick visibility and control of the active session
without opening the main window, isolated as a presentation/control surface over the one
`TimerEngine`/`SessionCoordinator`. **Implemented**: a compact status title (phase +
countdown), a `.window` popover for every state (idle / focus / short break / long break /
paused / completed / interrupted), transport controls (Pause/Resume/Skip/Stop/Restart) that
route through `SessionCoordinator`, "Open Time Frame / Settings / History / Quit" that reuse
the one window and its screens, recovery/sleep-wake correctness, a "Show in Menu Bar"
preference (default on) in `UserDefaults`, and full accessibility. The menu bar owns **no**
timer and persists no timer state; a Calendar or Notification failure can never break it,
and disabling it never affects the timer. **Deferred**: a dynamic per-phase icon and direct
"start from Template/Plan" from the menu bar. See `docs/17-MENU-BAR.md`.

## 10. History & statistics (later milestone)

Recording completed sessions and deriving statistics. The `FocusSession` /
`SessionInterval` models are shaped to record this, and the engine keeps an
in-memory `IntervalRecord` history, but **live recording and statistics are not
implemented in Milestone 1.**

## 11. UI / Liquid Glass Visual Identity (Milestone 9 — implemented)

The full modern macOS 27 visual experience and Liquid Glass treatment.
**Implemented in Milestone 9** as a presentation-only design system
(`Support/DesignSystem/`) applied across every screen: semantic tokens/colour, a
consistent typography and corner language, selective Liquid Glass on control/primary
surfaces (with ordinary content kept quiet), Reduce-Motion-aware animation, and a
unified macOS 27 window. The timer core is unchanged (ADR-050). See
`docs/18-LIQUID-GLASS-DESIGN.md`. Milestone 1 shipped only a minimal, intentionally
unstyled harness to prove the core drives end-to-end; that is now superseded by the
Milestone 9 visual identity.

---

## 12. Explicit V1 (Milestone 1) boundaries — NOT implemented now

The following are deliberately **out of scope** for Milestone 1 and must not be
implemented unless explicitly requested:

- Apple Calendar / EventKit
- Notifications
- Menu bar
- ~~Widgets~~ (implemented in Milestone 11; made **configurable** via `AppIntentConfiguration` in
  Milestone 14 — see `docs/23-CONFIGURABLE-WIDGETS.md`)
- App Intents
- Siri
- iCloud / CloudKit
- ~~Advanced statistics / analytics~~ (implemented in Milestone 10 as a read-only Statistics
  & Productivity Analytics dashboard; see `docs/19-STATISTICS.md`)
- ~~Liquid Glass visual polish~~ (implemented in Milestone 9) / ~~final analytics dashboard~~
  (implemented in Milestone 10)
- Task Template UI
- Session Planner UI
- Complex animations
- Subscription / payment system
- User accounts / authentication
- Networking

## 13. Milestone 1 deliverables (in scope)

- Product, architecture, data-model, timer-engine, and testing documentation.
- SwiftData domain models with relationships, delete rules, and a versioned
  schema.
- A reliable, SwiftUI-independent timer engine driven by an injectable clock.
- Multi-session sequence generation with short/long-break logic and final-
  session completion.
- Deterministic Swift Testing unit tests for the engine and persistence.
- A building macOS 27 target and a launching app.

## Implemented beyond the foundation

Milestones 3–12 are implemented: Core UI, Task Templates, Session Planner, Calendar/EventKit,
Notifications, Menu Bar, Liquid Glass, Statistics, WidgetKit, and — in **Milestone 12** —
**App Intents, Shortcuts & Siri**. App Intents are an integration surface only: they drive the
one `SessionCoordinator`/`TimerEngine` (no second timer, no new persistence, schema stays V5).
See `docs/21-APP-INTENTS.md`.

**Milestone 13** adds **iCloud/CloudKit synchronization** of the SwiftData store across the
user's Apple devices. It is **local-first** and a **persistence transport only**: sync is
SwiftData's native mirroring below the repositories (no file imports CloudKit), the timer stays
timestamp-authoritative and works fully offline, a CloudKit failure falls back to the preserved
local store, and a running session is device-local (never a second timer across devices). The
schema bumps **V5 → V6** solely to drop `#Unique` (CloudKit-incompatible). Enabling real sync
requires a paid Apple Developer team + iCloud entitlement/container (a personal team cannot), so
production sync is **not** verified. See `docs/22-ICLOUD-CLOUDKIT.md`.

**Milestone 14** makes the WidgetKit widget **user-configurable** via `AppIntentConfiguration`:
in the standard macOS widget editor the user chooses the content (Current Timer / Today's Focus /
Statistics), the tap destination (Timer / Today / Statistics / History), and countdown visibility.
The configuration is a **pure presentation projection** — it changes rendering only and can never
touch the one `TimerEngine`/`SessionCoordinator`; the widget stays **read-only** over the local App
Group projection (no second timer, no SwiftData/CloudKit in the widget). The widget `kind`, families
(`.systemSmall`/`.systemMedium`), App Group, and schema (**V6**) are unchanged. See
`docs/23-CONFIGURABLE-WIDGETS.md`.

**Milestone 15** makes the widget **interactive**: per-state `Button(intent:)` controls
(Pause / Resume / Skip / Restart / Stop / Start) let the user command the timer directly from the
widget. Each button is a thin App Intent that WidgetKit runs in the **app process**, routing through
the existing Milestone-12 `AppIntentSessionActions` seam to the one `SessionCoordinator` — so there is
still exactly **one** timer. The widget stays a **read-only projection**: it owns no timer state, the
countdown remains a `Text(timerInterval:)` repaint, controls appear in **Timer** mode only
(Today/Statistics stay read-only), and which controls show is a pure function of the projection state.
Actions fail safely and can never stop or corrupt the timer; the widget `kind`, families, App Group,
and schema (**V6**) are unchanged. See `docs/24-INTERACTIVE-WIDGETS.md`.

**Milestone 16 (Live Session Surface / ActivityKit).** A first-class Live Activity was investigated
and found **unavailable on native macOS**: ActivityKit is `@available(macOS, unavailable)` (macOS-SDK
support is for Mac Catalyst only). As a native macOS app, Time Frame **cannot** ship a Live Activity,
so this is delivered as a **platform-feasibility milestone** — the reusable, platform-neutral
live-session projection core is built and tested, but no macOS ActivityKit implementation is
fabricated and the macOS product is unchanged. A Live Activity remains a **V-next / iOS-companion**
item. Schema stays **V6**. See `docs/25-LIVE-ACTIVITIES.md`.

**Milestone 17 (Production Hardening & Release Readiness).** A hardening milestone — **no new
features** — that takes the app toward a release candidate while preserving every M1–M16 invariant.
It adds an automated **production-readiness audit** (a source-boundary release gate), migration/store
robustness, large-history stress, accessibility and keyboard regression guards, a consolidated
integration-failure isolation test, timer boundary hardening, and a release-configuration audit. The
suite grew **602 → 653 tests / 122 → 137 suites** (0 warnings); the **Debug and Release** builds both
succeed (widget embedded); the schema stays **V6**. **CloudKit production sync remains a documented
release blocker** (needs a paid Apple Developer team + iCloud container), and distribution
signing/notarization is not configured. See `docs/26-PRODUCTION-READINESS.md` and ADR-077.

## Milestone 24 — Product identity (2026-08-17)

The shipping user-facing product name is **Time Frame**; the app icon is the single supplied logo
(`tf_logo.png`), used unaltered for Light and Dark on macOS and iOS/iPadOS. Internal identifiers, the
App Group, the `timeframe://` scheme, and the SwiftData schema (V6) are unchanged. M24 is identity +
on-device UX validation + polish — no new V1 scope. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md`
(ADR-096/097/098).
