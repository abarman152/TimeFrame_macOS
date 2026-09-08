<div align="center">

<img src="docs/assets/time-frame-logo.png" alt="Time Frame" width="120">

# Time Frame

**A native macOS Pomodoro focus timer, built around one authoritative clock.**

[![Platform](https://img.shields.io/badge/Platform-macOS%2027-black)](#platform-support)
[![Swift](https://img.shields.io/badge/Swift-6.4%20toolchain%20%7C%205%20language%20mode-orange)](#requirements)
[![Xcode](https://img.shields.io/badge/Xcode-27.0-blue)](#requirements)
[![UI](https://img.shields.io/badge/UI-SwiftUI-blue)](#architecture)
[![Persistence](https://img.shields.io/badge/Persistence-SwiftData%20V7-purple)](#persistence)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-macOS%201020-brightgreen)](#testing)

</div>

---

## Overview

Time Frame runs Pomodoro-style focus sessions: you choose how long to concentrate, and it takes you
through focus intervals and breaks, recording what you actually completed.

The engineering idea behind it is that a timer should be trustworthy. Time Frame derives elapsed time
from real timestamps rather than counting ticks, so sleep, backgrounding, locking and relaunch are
ordinary cases rather than special ones. There is exactly **one** timer engine in a running app, and
every system surface Apple offers — Home Screen and Lock Screen widgets, Control Center controls, Live
Activities, App Shortcuts, notifications, the macOS menu bar — is either a read-only projection of
that engine or a thin command adapter back into it. Nothing owns a second clock.

It is not a cross-platform wrapper. The macOS app and the iOS app are separate native targets that
compile the same platform-neutral domain core.

## User guide

New to Time Frame, or want to know which feature to use when?

- **[macOS User Guide](docs/35-MACOS-USER-GUIDE.md)** — the Mac manual: every screen and setting, a
  [Choosing the right feature](docs/35-MACOS-USER-GUIDE.md#3-choosing-the-right-feature) decision
  table, [keyboard shortcuts](docs/35-MACOS-USER-GUIDE.md#23-keyboard-shortcuts),
  [a workday walkthrough](docs/35-MACOS-USER-GUIDE.md#24-a-workday-with-time-frame),
  [troubleshooting](docs/35-MACOS-USER-GUIDE.md#25-troubleshooting) and an FAQ.
- **[macOS User Guide](docs/35-MACOS-USER-GUIDE.md)** — every screen, in order.

## Features

- Pomodoro focus sessions with configurable focus, short-break and long-break intervals
- Saved timer configurations, with a default used by new sessions
- Task templates and multi-configuration session plans, each with a chosen icon
- Quick Start: pin the templates and plans you use most and launch them from the macOS menu bar
- Session history that preserves the configuration name each session ran under
- Today summary and a Statistics dashboard over day, week and month
- Home Screen widgets in three sizes and three modes, with interactive controls
- Lock Screen accessory widgets: circular, rectangular and inline
- StandBy support through the existing Home Screen widgets
- Live Activities with Dynamic Island presentation
- Control Center controls, including a configurable quick-start control
- Local notifications anchored to interval boundaries, with action buttons
- App Intents and App Shortcuts for Siri and system automation
- A macOS menu bar popover with the full transport controls, Quick Start, and a gear menu for
  secondary actions, plus an optional live countdown in the status item
- Calendar integration on macOS
- Open at Login, and a single main window that every entry point reuses
- VoiceOver labels, Dynamic Type support, and state never carried by colour alone

## How it works

1. Create a configuration on macOS, or use the "Classic Pomodoro" one Time Frame seeds on first
   launch.
2. Start a session. Time Frame runs focus intervals and breaks in order.
3. Pause, resume, skip, restart or stop at any point, from the app, a widget, Control Center, a
   notification, the Live Activity, or Siri.
4. The session completes on its own, and is recorded in History.
5. Today and Statistics summarise what you actually completed.

## Platform support

| Platform | Minimum | Status |
|---|---|---|
| macOS | 27 | Full application, verified on real hardware |

**This repository contains the macOS application only.** Time Frame also has an iOS and iPadOS
companion — Live Activities, Lock Screen widgets and Control Center controls — built from the same
shared `Core/`. That companion is not part of this repository.

Live Activities and Control Center controls do not exist on macOS: Apple does not offer ActivityKit
or `ControlWidget` to native Mac applications.

| Capability | macOS |
|---|---|
| Focus timer | Yes |
| Configurations, templates and plans | Yes |
| Today, History, Statistics | Yes |
| Home Screen widgets | Yes |
| Local notifications | Yes |
| Menu bar popover with Quick Start | Yes |
| Calendar integration | Yes |
| App Intents and Shortcuts | Yes |
| Open at Login | Yes |
| iCloud sync | Disabled (needs a paid Apple Developer team) |


## Screens

The macOS window is a sidebar split view. Every screen opens with the same header — a title, one line
of guidance, and, where useful, a single control on the right — and groups related content into the
same card surface, so the eight areas read as one application.

### Timer

The primary screen, and the only place a session is started from the app.

When nothing is running it asks four things, in the order you decide them: what you are focusing on
(with a **Recent Tasks** menu that fills the field from your own history), which configuration to
run, how many focus sessions, and then it previews the exact interval sequence before you commit.
The preview has a **Show** filter (All Sessions / Focus Only / Breaks Only) which changes only what
is listed, never what runs. **Quick Start** sits in the header for the times you already know which
saved timer you want.

While a session runs the screen becomes the countdown, the phase, the paused state, the session
position, what is next, and the transport controls: Pause or Resume, Skip, Restart, Stop.

The countdown is derived from the engine's timestamps, not counted. Sleeping, locking, closing the
window or relaunching does not lose time.

### Templates

Reusable focus setups for work you come back to: a name, the task the session will focus on, a
configuration to run, a default number of sessions, and an icon.

A template **references** its configuration rather than copying it, and starting from a template
**copies** its values into the ordinary setup path — so the running session is independent of the
template, and editing or deleting the template later never disturbs a session or your history.

The list supports search, and each row starts the template or opens its overflow menu directly. The
detail page has one prominent action (Start), a secondary Create Plan, a switch for pinning to Quick
Start, and a quieter Manage group for Duplicate and Delete.

### Plans

For a session that is not a uniform repetition: an explicit, ordered timeline of focus intervals and
breaks, where each focus interval may use a **different** configuration.

Starting a plan freezes it into an immutable snapshot and runs that through the same engine, so
editing or deleting the plan afterwards cannot change a session that is already running or already
recorded. The list shows each plan's session count, total duration and configuration ("Custom" when
it deliberately mixes them); the detail page lists every interval with its start offset.

### Configurations

The durations your timers run on: focus, short break, long break, how many sessions, and how often a
long break falls. One configuration is the default that new sessions start from.

Each row shows all five numbers in one strip so configurations can be compared at a glance. Deleting
a configuration explains first what uses it: history keeps its own frozen copy and stays accurate,
and templates survive but need a new configuration before they can start.

### History

Every session you have run, newest first, grouped by day, with each day heading stating that day's
completed focus time. A row shows the task, the configuration name **frozen at the time it ran**, how
many focus intervals of how many were completed, the final status and the start time. Opening a row
shows every interval and what happened to it.

History is strictly read-only, and it never changes when a configuration is later edited or deleted.

### Today and Statistics

Today is a light dashboard over the current day. Statistics covers day, week, month or a custom
range, with focus time, completed sessions, completion rate, average focus, break time, longest
session, and a trend against the previous period. Both are read-only projections of the same history,
computed by the same aggregator, so they can never disagree.

## The macOS menu bar

The menu bar item is a control surface over the one running timer, not a second timer. Clicking
it opens a compact popover.

**When nothing is running** it shows the app identity, your pinned Quick Start items, and a
Start Timer action that opens the setup screen.

**While a session runs** it shows the phase, the countdown, the paused state when paused, the
focus progress dots, "Session X of N", the next interval and its length, and the four transport
controls: Pause or Resume, Skip, Restart, Stop. Quick Start stays below them.

**Nothing in the popover scrolls.** It is a glance-and-go surface, so the pinned list is capped at
three rows that are always fully visible, and any further pins are offered by a compact "N more…"
menu that starts them directly. The transport controls therefore can never be pushed off screen,
however many items you pin, and nothing is hidden inside a scroll view.

**The gear** in the top-right corner holds the secondary actions, so they never take space from
the timer:

| Item | What it does |
|---|---|
| Open Time Frame | Brings the existing main window forward, or creates it if you closed it |
| Settings | Brings that same window forward on Settings |
| History | Brings that same window forward on History |
| Quit Time Frame | Quits the application |

### Quick Start

Pin a Template or a Plan from its own page — its detail view or its list's overflow or context menu
— and it appears in Quick Start ready to start in one click. Quick Start is offered in two places:
the menu bar popover, and the Timer screen's header. Both read the **same** pinned projection and
start through the **same** command seam, so there is no second Quick Start list to keep in sync.
Pinning takes one click with no confirmation, and both surfaces reflect it immediately, with no
restart.

Pin state is stored on the item itself and keyed by its stable identifier, so:

- renaming a pinned item keeps the pin;
- deleting a pinned item removes it from Quick Start;
- editing an item never silently changes what you pinned;
- duplicating an item copies its icon but not its pin.

An item whose configuration was deleted is still listed, with its start control disabled and the
reason stated, so a pin is never silently discarded.

### Icons

Templates and Plans each carry an icon you choose from a curated catalog of SF Symbols, grouped
into Focus, Study, Work, Wellbeing and General. The icon follows the item everywhere it appears:
its list row, its detail page, its editor, and Quick Start.

Time Frame stores a stable identifier rather than a symbol name, and resolves it through one
catalog, so an unrecognised stored value falls back to a sensible default instead of rendering a
missing glyph. Icons are chosen from a native picker showing each option's glyph and name; there
is no free-text symbol field.

## Open at Login

Settings ▸ General:

```
General
    Open at Login                                              [ toggle ]
    Automatically open Time Frame when you log in to your Mac.
```

Turn it on and macOS launches Time Frame when you log in. Turn it off and the login item is removed.

The toggle shows what macOS **actually** holds, not what Time Frame remembers. It is registered
through `SMAppService`, the modern login-item API, and the switch is read back from the system on
launch, whenever Settings appears, and after every change:

- if registration fails, the switch stays **off** and states why;
- if removal fails, it stays **on**;
- if macOS wants you to approve the item first, it reads off and offers **Open Login Items
  Settings**, because it will not launch until you approve it.

Nothing about the login item is stored in Time Frame's preferences, so the setting cannot drift out
of step with the system. You can change it in System Settings ▸ General ▸ Login Items & Extensions
at any time; Time Frame picks that up the next time you open Settings.

## Window management

**Time Frame uses a single main application window.** Opening Time Frame from the Dock, the menu
bar, or any other application entry point focuses the existing window instead of creating
duplicates.

| Action | What happens |
|---|---|
| Click the Dock icon while Time Frame is running | The existing window is activated and brought to the front |
| Click the Dock icon while the window is minimized | The window is restored from the Dock and focused — not duplicated |
| Click the Dock icon while Time Frame is hidden | The app is unhidden and the window focused |
| Menu bar ▸ gear ▸ Open Time Frame / Settings / History | The existing window comes forward, on that screen |
| Repeat any of the above | Still exactly one window |
| Close the window | The window closes; Time Frame keeps running in the menu bar, and a running session keeps running |
| Open Time Frame again after closing it | A new main window is created |
| Quit | ⌘Q, or the gear menu's Quit Time Frame |

Focusing the window is window behaviour only. It does not reset your sidebar selection, scroll
position, or anything you had typed, and it never restarts, resets, or duplicates a running
Pomodoro. Bringing the window forward uses the ordinary macOS activation, so it looks exactly like
focusing any other window — there is no custom flash or highlight.

There is no File ▸ New Window command, because a second window is not something the app can produce:
the main scene is a single-instance SwiftUI `Window`, and every surface that can ask for it routes
through one presenter. See [ADR-111](docs/DECISIONS.md) and
[docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md](docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md).

## Architecture

```text
                    SwiftUI views
                          |
                          v
        Coordinators and integration adapters
      (menu bar, calendar, notifications, widgets,
              Live Activity, App Intents)
                          |
                          v
                  SessionCoordinator          <-- the one control seam
                          |
                          v
                     TimerEngine              <-- the one timing authority
                          |
                          v
              SwiftData repositories
```

Dependencies point downward only. `TimerEngine` imports neither SwiftUI nor SwiftData, and reads time
through an injected clock, which makes the whole timing model deterministically testable.

Four invariants hold the design together, and each is enforced by an automated source audit that fails
the build if it regresses:

- **One `TimerEngine` and one `SessionCoordinator`** per running app.
- **Timestamp-authoritative timing.** A running interval is anchored to a target end date; remaining
  time is always `targetEnd - now`. Nothing decrements a counter.
- **One mutation seam.** Every command, from every surface, converges on `SessionCoordinator`.
- **Nothing unbounded on the control path.** Lifecycle events are emitted synchronously, so observers
  may only do work derived from in-memory anchors; anything that reads the store is deferred and
  coalesced.

See the [Developer Overview](docs/36-DEVELOPER-OVERVIEW.md) and
[Architecture](docs/01-ARCHITECTURE.md).

### Widget architecture

Widget extensions run in a separate process and cannot read the application's database. The bridge is
a single small `Codable` value:

```text
SessionCoordinator -- lifecycle event --> WidgetProjectionWriter
                                                 |
                                     WidgetProjection in an App Group
                                                 |
                     +---------------------------+---------------------------+
                     |                           |                           |
              Home Screen widget       Lock Screen accessory        Control Center
```

The App Group is `group.abirbarman.com.time-frame`. The projection carries the interval's frozen start
and end anchors, so every surface renders its countdown with `Text(timerInterval:)` between those
anchors — a repaint, not a clock. The projection is written only on meaningful transitions, never per
tick.

### Command seam

```text
Widget button / Control Center / App Shortcut / notification action
                              |
                     WidgetControlActions
                              |
                   AppIntentSessionActions
                              |
                     SessionCoordinator --> TimerEngine
```

WidgetKit runs a widget-button intent in the application's own process, where the router is
registered. Failures surface as a closed error set, never a leaked framework error.

### Notifications

The notification stack is shared by macOS and iOS and isolated behind a protocol, with
`UserNotificationService` as the only file importing UserNotifications. Notifications are scheduled
from the engine's frozen interval-end anchors — one per boundary, never on a tick — with deterministic
identifiers so reconciliation is idempotent. Every failure is caught: a notification problem can never
stop or corrupt a session.

### Persistence

SwiftData with a versioned schema, currently **V7**, and a migration plan. Repositories are the only
types that touch a `ModelContext`.

V7 adds the Quick Start icon and pin attributes to `TaskTemplate` and `SessionPlan`. The model set
is unchanged — the same six types since V5 — and every added attribute is defaulted or optional, so
an existing store opens in place.

Historical identity is frozen: a session copies the values it needs when it starts, including the
configuration's name, so renaming or deleting a configuration never rewrites history.

`PersistenceController` degrades safely to the preserved local store if a cloud store cannot be
opened — never to an empty in-memory store, and never in a way that blocks the timer.

### CloudKit

> **iCloud synchronization is disabled.** This project is developed with a personal (free) Apple
> Developer team, which cannot provision the iCloud capability. The iCloud entitlement is deliberately
> absent, no CloudKit container is used, and `CloudKitCapability.entitledInThisBuild` is `false`, so
> both applications launch local-first. A test fails the build if the entitlement and that constant
> ever disagree.
>
> Cross-device synchronization has **never been enabled or verified**. The application does not claim
> working CloudKit sync.

No file in the codebase imports CloudKit. Sync, when it is eventually enabled, is SwiftData's native
mirroring beneath the repositories.

### Design system

Presentation lives in one place, not per screen. `Core/Support/DesignSystem/` defines the spacing and
radius scales, the type scale (`TFTypography`), the control-size rule (`TFControl`, with the
`tfPrimaryAction` / `tfSecondaryAction` treatments), the semantic palette, the Reduce-Motion-aware
animation vocabulary, the Liquid Glass surfaces, and the one content card (`tfCard`) every grouped
surface in the app uses.
`time_frame/Views/Components/` builds the shared macOS pieces on top of it: the page and section
headers, the details card, the icon tile, a list row's trailing controls, the Manage group, the
notice banner, and the editor-sheet header.

The design system imports none of the domain, and no file under `Core/Timer/`, `Core/Models/` or
`Core/Services/` changes for a visual reason. Glass is used selectively, for the primary action and
floating control regions; ordinary content sits on the quiet card. Colour is always paired with a
label or icon, and every screen is one design in both Light and Dark Mode rather than two.

Each page has exactly one prominent action, sized to its content at the native macOS control
height — never a full-width filled slab. Supporting actions are bordered and match that height,
preferences are switches, and destructive actions live in their own quieter group. The single
deliberate exception is the menu-bar popover's fallback action, whose container genuinely is the
width of the control.

### Calendar integration

macOS only, and entirely optional. `EventKitCalendarService` is the only file in the codebase that
imports EventKit; `TimerEngine` and the domain import none of it. A `CalendarCoordinator` subscribes
to the same pure `SessionLifecycleEvent` seam that notifications and the widget projection use, so
the three integrations are independent and none can influence another.

From a Plan's detail page you can add its intervals to Apple Calendar, and update them afterwards.
Calendar settings and the mapping from a plan to the event it created are stored in `UserDefaults`,
not in the SwiftData store. A Calendar failure is surfaced quietly and can never stop, delay or
corrupt a running timer — an isolation property covered by its own tests.

### Accessibility

VoiceOver labels and values on the countdown, phase, controls and statistics; the countdown is marked
as frequently updating so it does not interrupt continuously. Every menu bar control names what it
acts on ("Skip Interval", "Start Deep Work", "Pin Deep Work to Quick Start", "Settings and More"),
each Quick Start row is a single focus stop, and a disabled control always explains itself in
words. Dynamic Type throughout, with the timer
screen scrolling rather than clipping at accessibility sizes. State is never carried by colour alone.
Animations respect Reduce Motion.

This is verified from source and by automated accessibility-text tests. It has **not** been validated
with VoiceOver on physical hardware.

## Requirements

| | |
|---|---|
| Xcode | 27.0 |
| Swift | 6.4 toolchain, Swift 5 language mode |
| macOS deployment target | 27.0 |
| Apple account | Any Apple ID. A paid membership is **not** required to build and run; see the limits under [Installation](#installation-and-development-setup) |

## Distribution

Time Frame ships as **source only**. There is no downloadable app, and that is a deliberate
consequence of not holding a paid Apple Developer membership rather than an oversight:

| | Needs paid membership |
|---|---|
| Developer ID certificate (signing for other machines) | Yes |
| Notarization (no Gatekeeper warning) | Yes |
| Mac App Store | Yes |
| Building and running it yourself | **No** |

Distributing an unsigned binary was considered and rejected. On macOS 15 and later the
right-click-to-open bypass is gone, so every user would have to approve the app in System Settings,
and an ad-hoc signature has no team identifier — which means the App Group is denied and every
widget surface stops receiving data. Source distribution keeps the sandbox, the App Group and the
widgets intact.

## Installation and development setup

Time Frame is distributed as source. There is no signed, notarized download: that requires a
Developer ID certificate, which is only available with a paid Apple Developer membership. Building
it yourself takes a few minutes and produces an app signed for your own machine.

### Build and run

1. Open `time_frame.xcodeproj` in Xcode 27.
2. **Change the bundle identifier and App Group** — see below. Signing fails until you do.
3. Select your team under Signing and Capabilities for the `time_frame` and `TimeFrameWidgets`
   targets.
4. Choose the `time_frame` scheme and My Mac as the destination.
5. Build and run.

### You must change two identifiers

The identifiers in this repository are registered to the original author's team, so signing will
fail for anyone else until they are replaced with your own:

| What | Current value | Where |
|---|---|---|
| Bundle identifier | `abirbarman.com.time-frame` | Signing and Capabilities, all four targets |
| App Group | `group.abirbarman.com.time-frame` | two `.entitlements` files, plus `Shared/WidgetProjectionStore.swift` |

The App Group string is repeated across the two entitlements files, one Swift constant and a
handful of test assertions that check the literal value. Changing it means a
find-and-replace across all of them. Consolidating this into a single configurable value is
outstanding work.

The App Group is what the widgets, Lock Screen widgets and Control Center controls read the timer
projection from. If you skip it, the app still runs and keeps time correctly; those surfaces just
show no live data.

### What a free Apple account gives you

A free (personal) Apple ID can sign and run the app, with limits worth knowing before you start:

- **Provisioning profiles last 7 days** and are locked to the machine that built them. After that
  the app stops launching and you rebuild. This applies to macOS as well as iOS.
- **No Developer ID**, so you cannot produce a build for anyone else, and you cannot notarize.
- **CloudKit sync stays disabled** — it needs a paid team. The app is local-first by design and
  `CloudKitCapability.entitledInThisBuild` is `false`; see [ADR-080](docs/DECISIONS.md).
- **App Groups on iOS are not confirmed to be available** on a personal team. They work on macOS —
  verified. On iOS this is untested; if the capability is unavailable, the iOS widgets, Live
  Activity and Control Center controls will not receive data.

### Signing off entirely

For command-line builds and tests you can skip signing:

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

This also **strips entitlements**, which disables the sandbox and the App Group. The app then falls
back to an unsandboxed store path shared with any other app that does the same — see
[Data Safety and Recovery](#data-safety-and-recovery). Use it for CI and tests, not for daily use.

### Build instructions (command line)

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame \
  -destination 'platform=macOS' build
```


Run `xcodebuild` invocations serially; concurrent runs contend on the shared DerivedData build
database.

## Testing

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame \
  -destination 'platform=macOS' test
```


Measured on 2026-09-07:

| Suite | Result |
|---|---|
| macOS | 949 tests in 200 suites, all passing |
| macOS Debug build | Succeeds, 0 compiler warnings |
| macOS Release build | Succeeds, 0 compiler warnings |

Tests fall into four kinds: deterministic domain tests driven by a mock clock, persistence and
integration tests over in-memory stores, isolation tests proving a failing integration cannot corrupt
a session, and **source-boundary audits** that scan the tree and fail the build if an architectural
invariant regresses — a second engine, a second scheduling primitive, SwiftData inside a widget
extension, ActivityKit outside iOS, a CloudKit import, or a schema-version change.

The domain suite never waits a real second; the engine is driven through an injected clock.

## Repository layout

The repository root holds the Xcode project, the source, `README.md`, `LICENSE`, `CLAUDE.md` and
`docs/`. There is no nesting: what you clone is what Xcode opens.

## Project structure

```text
Core/                    Platform-neutral domain, compiled into both apps
  Models/                SwiftData models
  Timer/                 TimerEngine, SessionCoordinator, plan value types
  Statistics/            Pure aggregation
  Services/              Persistence, notifications, cloud, Quick Start, Live Activity core
  Support/               Pure helpers, the icon catalog, the design system
  Intents/               App Intents and the command seam
  Widgets/               App-side projection writer and mapper
Shared/                  Foundation-only value types shared with extensions
time_frame/              macOS application
  Services/Window/       The single-window policy, presenter, AppKit host, app delegate
  Services/Login/        Open at Login, isolated behind SMAppService
  Services/MenuBar/      The menu bar adapter
  Views/                 The screens, the menu bar popover, and the shared components
TimeFrameWidgets/        macOS widget extension
time_frameTests/         macOS test bundle
docs/                    Documentation
```

## Documentation

| Document | For |
|---|---|
| [Documentation index](docs/README.md) | Everything, organised |
| [macOS User Guide](docs/35-MACOS-USER-GUIDE.md) | Using Time Frame on the Mac: every screen, which feature to use when, shortcuts, troubleshooting, FAQ |
| [macOS User Guide](docs/35-MACOS-USER-GUIDE.md) | Every screen of the macOS app, in order |
| [Developer Overview](docs/36-DEVELOPER-OVERVIEW.md) | Orientation, concurrency model, invariants |
| [Architecture](docs/01-ARCHITECTURE.md) | The full architecture |
| [Data Model](docs/02-DATA-MODEL.md) | SwiftData models and schema V7 |
| [Timer Engine](docs/03-TIMER-ENGINE.md) | The state machine specification |
| [Testing Plan](docs/10-TESTING-PLAN.md) | Test strategy |
| [WidgetKit](docs/20-WIDGETKIT.md) | Widget projection and App Group |
| [Control Center](docs/31-CONTROL-CENTER-CONTROLS.md) | Control architecture |
| [iCloud and CloudKit](docs/22-ICLOUD-CLOUDKIT.md) | Sync transport and its current status |
| [Stability and Reliability](docs/34-M26-STABILITY-AND-RELIABILITY.md) | The freeze investigation and its concurrency rules |
| [Menu Bar, Quick Start and Icons](docs/37-M28-MENU-BAR-QUICK-START-ICONS.md) | The popover hierarchy, pinning, and the icon catalog |
| [macOS Interface Redesign](docs/38-M29-MACOS-UI-REDESIGN.md) | The design system, the screen-by-screen redesign, and the editor presentation fix |
| [Design System Consolidation](docs/39-M30-DESIGN-SYSTEM-CONSOLIDATION.md) | The type scale, the control-size rule, and the compact primary action |
| [Data Safety and Recovery](docs/40-M31-DATA-SAFETY-AND-RECOVERY.md) | Why a store that cannot be opened is preserved, how recovery works, and store isolation for development |
| [Product Name and Icon](docs/42-M33-PRODUCT-NAME-AND-ICON.md) | The user-facing name, which identifiers stay internal, and how the app icon is configured |
| [Open at Login and Window Management](docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md) | The single-window architecture, Dock reopen, and the login item |
| [Decisions](docs/DECISIONS.md) | Every architectural decision record |
| [Changelog](docs/CHANGELOG.md) | What changed, milestone by milestone |

## Architecture decisions

Every structural decision is recorded as a numbered ADR in [`docs/DECISIONS.md`](docs/DECISIONS.md),
with the context that forced it and the consequences it accepted. The ones that constrain day-to-day
work most:

| ADR | Decision |
|---|---|
| ADR-045 / ADR-049 | The menu bar is a presentation and control surface over the one coordinator, never a second timer |
| ADR-055 | Widget surfaces are a read-only projection written to an App Group; the extension imports no SwiftData |
| ADR-056 | Every App Intent acts only through the one `AppIntentSessionActions` seam |
| ADR-063 | Timer execution is device-local; a session synced from another device is never resumed here |
| ADR-069 | Widget and Control Center buttons route through that same single mutation seam |
| ADR-099 / ADR-100 | Nothing on the timer control path may do unbounded or persistence-heavy work |
| ADR-101 | A `MenuBarExtra` label must never contain a `TimelineView` |
| ADR-103 | Icons are a closed catalog; the persisted value is a stable identifier, never a symbol name |
| ADR-104 | Pin state lives on the pinned item, keyed by its identifier |
| ADR-106 | A pushed detail page presents its own editor sheet |
| ADR-107 | The menu bar popover does not scroll |
| ADR-111 | There is one main window and one pathway to it; a Dock reopen focuses it rather than duplicating it |
| ADR-112 | The login item is registered with `SMAppService`, and the system — never a stored preference — is the source of truth |

Many of these are enforced mechanically. The `ProductionReadiness*` suites scan the source tree and
fail the build if an invariant regresses.

## Troubleshooting

**A build fails with a code-signing error.** The project uses manual signing for
`abirbarman.com.time-frame`. Set your own team in Signing and Capabilities, or add
`CODE_SIGNING_ALLOWED=NO` to a command-line build.

**Widgets, Control Center or the Live Activity show placeholder data.** An unsigned build carries no
entitlements, so the App Group container the widget reads is unavailable. Build with your own signing
team.

**Two `xcodebuild` runs interfere with each other.** Run them serially; concurrent runs contend on
the shared DerivedData build database.

**The menu bar item is missing.** Settings has a "Show in Menu Bar" preference. Toggling it never
affects a running session.

**A template or plan says it needs a configuration.** Its configuration was deleted. Open it, choose
a configuration, and save — the item itself was never lost.

**A session was running when the app last quit.** On the next launch Time Frame reconciles it against
the real timeline: intervals whose planned end has passed are completed, and the session either
resumes or is recorded as interrupted. Recovery is device-local, so a session running on another
device is never taken over here.

**Clicking the Dock icon does not bring the window back.** If Time Frame is running with no window
— you closed it, and the menu bar kept the app alive — a Dock click creates the window again. If the
window is minimized or Time Frame is hidden, the same click restores and focuses the existing one.
Either way you get exactly one window; the app cannot open a second.

**Time Frame quit when I closed the window.** It should not: closing the window leaves the app
running in the menu bar, and a running session keeps running. If Time Frame is not in your menu bar,
check Settings ▸ Menu Bar ▸ Show in Menu Bar — with the menu bar hidden and the window closed, the
Dock icon is the only way back.

**Open at Login is off even though I turned it on.** The switch reflects what macOS actually holds,
not what you asked for. Two common causes: the registration was refused (the reason is shown under
the toggle), or macOS is waiting for you to approve the item — in which case Time Frame offers
**Open Login Items Settings**, and the item will not launch until you allow it there.

**History or Statistics look wrong after editing a configuration.** They should not change. Each
session freezes its own plan and configuration name when it starts, so editing or deleting a
configuration never rewrites what has already been recorded.

## Data Safety and Recovery

Time Frame keeps its data in a SwiftData store at `~/Library/Application Support/default.store`,
alongside its `-wal` and `-shm` sidecar files.

**The app never deletes that store because it could not open it.** If the store cannot be opened —
a schema it does not understand, a damaged file, a permissions problem, a lock held by another
copy — Time Frame does not replace it with an empty one. It leaves every byte where it is, shows a
recovery screen instead of the library, and waits for you to choose:

- **Try Again** re-attempts the open and changes nothing either way. For a store locked by another
  running copy, this is usually the whole fix.
- **Show in Finder** reveals the store so you can copy it somewhere safe first.
- **Continue Without Existing Data** moves the existing store — with both sidecars — into a dated
  folder named `TimeFrame Recovery` beside it, then starts with an empty library. It asks for
  confirmation first, it never overwrites an earlier recovery copy, and if the move cannot be
  performed the app stays in recovery rather than proceeding.

This matters because the alternative is invisible: an app that quietly rebuilds a store looks
exactly like a fresh install, so the loss is not noticed until you go looking for something that
is no longer there. See [ADR-109](docs/DECISIONS.md) and
[Data Safety and Recovery](docs/40-M31-DATA-SAFETY-AND-RECOVERY.md).

### Migrations

Schema upgrades are additive and are tested against a real store written by the previous schema
version, not assumed. The V6 → V7 upgrade is covered by `PersistenceMigrationV6ToV7Tests`, which
writes a realistic V6 library and verifies that identities, values, timestamps, relationships and
session history all survive.

### Development store isolation

A locally built copy of a non-sandboxed macOS app resolves to the same store as an installed copy.
To avoid a development build touching real data:

- the test suite always uses an isolated store under the temporary directory — enforced by a test
  that checks the *live* environment;
- any build can be redirected with an environment variable on the scheme's Run action:

```bash
TIMEFRAME_STORE_DIRECTORY=/tmp/timeframe-dev
```

Note that the bundle identifier is deliberately unchanged, so a development build still shares
`UserDefaults` — settings and permissions — with an installed copy. Only the SwiftData store is
isolated.

## Privacy

Time Frame stores your configurations, templates, plans and session history locally on your device.
There is no account, no analytics, no tracking, and no network service that your data is sent to. The
application works entirely offline.

Widgets and Control Center read a small shared summary — current phase, interval anchors, today's
totals — from an App Group container. Notifications are scheduled locally through the system
notification service.

See [Data and privacy](docs/35-USER-GUIDE.md#17-data-and-privacy) and the
[privacy nutrition labels](docs/appstore/PRIVACY-NUTRITION-LABELS.md).

## Security

Documented here only where it has been verified:

- The application makes no network requests and has no server component.
- No credentials, tokens, API keys or signing material are committed to the repository; an automated
  audit checks for committed secrets.
- No iCloud entitlement is declared, and no CloudKit container is contacted.
- Data is stored in the application's own container, protected by the operating system's standard
  file protection. Time Frame does **not** add its own encryption layer, and no claim of
  application-level encryption is made.

## Known limitations

- iCloud sync is disabled, and cross-device sync has never been verified. It requires a paid Apple
  Developer team.
- Configurations, task templates and session plans can only be created and edited on macOS.
- Live Activities and Control Center controls are unavailable on macOS by platform constraint.
- Physical-device behaviour is unverified: notification banners, StandBy, the Dynamic Island, and
  VoiceOver have been validated only from source, tests and simulators.
- macOS screenshots cover eight screens; Plans, Configurations, History, Statistics, Today and
  Settings are documented in prose but not yet photographed. See the
  [macOS screenshot inventory](docs/assets/screenshots/macos/README.md).
- Pinning to Quick Start, and the icon picker, are macOS-only. A pinned item's icon is stored in the
  shared model, so it is visible wherever iOS shows the item.
- There is no continuous integration. The test numbers above were measured locally.

## Roadmap

Only work that is already documented as deferred is listed here.

- Enable and verify CloudKit synchronization once a paid Apple Developer team is available, including
  two-device sync and production schema deployment.
- Physical-device validation of Live Activities, the Dynamic Island, StandBy, Control Center,
  notification delivery and VoiceOver.
- Configuration management on iPhone and iPad.
- A Quick Start surface on iPhone and iPad. The pin and icon data are platform-neutral, so an iOS
  surface can reuse them unchanged.
- Template and plan icons in widget surfaces. Widgets currently project the running session, which
  has no icon of its own.

## Contributing

This is a personal project and there is no formal contribution process, issue tracker, or public
repository. If you are working in this codebase, read
[`CLAUDE.md`](CLAUDE.md) for the operating rules and
[`docs/DECISIONS.md`](docs/DECISIONS.md) before changing anything structural.

## License

Time Frame is released under the **MIT License**. See [LICENSE](LICENSE) for the full text.

In practice: you may use, copy, modify, merge, publish, distribute, sublicense and sell this
software, for any purpose including commercial, free of charge. There is one condition.

### The one condition — attribution

> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.

Keep the copyright line and the licence text with the code. Concretely:

- **Using the source, forking, or building on it** — keep the `LICENSE` file in your copy. That is
  the whole obligation.
- **Shipping an app built from this code** — include the MIT notice somewhere a user can reach it,
  such as an acknowledgements or about screen.
- **Quoting substantial portions in another project** — carry the notice into that project's
  licence file or third-party notices.

A link back is appreciated but is not required by the licence.

The software is provided as is, without warranty. That clause is not decoration: this is a personal
project that has never been notarized or distributed as a binary, and it manages data you may care
about. Read [Data Safety and Recovery](#data-safety-and-recovery) before trusting it with a long
history.

### What the licence does not cover

MIT licenses the **code**. It does not grant rights to the product name or the mark:

- **"Time Frame"** as a product name, and
- the **TF logo** in `Assets.xcassets/AppIcon.appiconset/`

If you distribute a modified build, change the name and the icon so users can tell your version from
this one. This is the usual convention for MIT projects, not an extra restriction on the code — the
code itself remains fully MIT.
