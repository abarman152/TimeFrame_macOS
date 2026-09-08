# 37 — Milestone 28: Menu Bar Popover UX, Quick Start Pinning & the Icon System

Milestone 28 reshapes the macOS menu bar popover around what a user actually reaches for —
the timer, its controls, and the things they start most often — and gives Templates and Plans
a visual identity that follows them everywhere.

It is a **presentation and library milestone**. It adds no timing authority, no second store,
no clock, and no polling. There is still exactly one `TimerEngine`, one `SessionCoordinator`,
and one mutation seam.

- **Decisions:** ADR-102 (popover hierarchy + gear menu), ADR-103 (icon catalog),
  ADR-104 (pinning on the model), ADR-105 (event-driven Quick Start refresh).
- **Schema:** **V6 → V7** — attributes only, on the same six models.
- **Verification:** macOS **928 tests / 196 suites**, iOS **105 tests** (iPhone and iPad),
  Debug and Release, 0 compiler warnings.

---

## 1. What changed, in one screen

Before, the popover ended in four permanent navigation rows — Open Time Frame, Settings,
History, Quit — which took roughly a third of its height regardless of what the user was
doing. Starting a familiar task still meant opening the main window.

```
   READY                              RUNNING / PAUSED

   [ icon ]              [gear]       [ task name ]          [gear]
     Time Frame                         [ configuration ]
     Ready to focus
                                            FOCUS
   ─────────────────────────                44:48
   QUICK START      Pinned  3               Paused
                                          ○ ○ ○ ○
   [icon] Deep Work        [play]        Session 1 of 4
          Template - 50 min focus       Next  Short Break - 5 min
          - 10 min break
                                       [Pause] [Skip] [Restart] [Stop]
   [icon] Study            [play]
          Template - 25 min focus       ─────────────────────────
          - 5 min break                 QUICK START      Pinned  3

   [icon] Weekly Focus     [play]       [icon] Deep Work        [play]
          Plan - 4 focus sessions       [icon] Study            [play]
          - 3h 20m

   [        Start Timer        ]
```

The gear opens:

```
   Open Time Frame
   Settings
   History
   ──────────────
   Quit Time Frame
```

---

## 2. Popover hierarchy (ADR-102)

### 2.1 The gear menu

`Views/MenuBar/MenuBarGearMenu.swift` is a native SwiftUI `Menu` with a `gearshape` label,
placed in the header's top-trailing corner as an overlay so it never shifts the centred
identity block.

| Item | SF Symbol | Action |
| --- | --- | --- |
| Open Time Frame | `macwindow` | `openWindow(id: "main")` |
| Settings | `gearshape` | `AppNavigation.request(.settings)` then open the window |
| History | `clock.arrow.circlepath` | `AppNavigation.request(.history)` then open the window |
| Quit Time Frame | `power` | `NSApplication.shared.terminate(nil)` |

These are the **same** actions, wired the **same** way, as Milestone 8 — the same
accessibility identifiers (`timeFrame.menuBar.openApp`, `.settings`, `.history`, `.quit`),
the same one `WindowGroup`, the same `AppNavigation` seam. Only their location changed.
`MenuBarPopoverStructureTests` fails the build if any of those identifiers reappears outside
`MenuBarGearMenu.swift`.

The gear's accessibility label is **"Settings and More"**, with a hint naming its contents,
because a lone gear glyph does not say what it opens.

### 2.2 Layout order

| State | Order |
| --- | --- |
| Ready / interrupted | identity, Quick Start, Start Timer |
| Running / paused | identity, countdown block, transport controls, Quick Start |
| Completed | identity ("Session complete"), Quick Start, Start New Session |

**The transport controls and the countdown are laid out outside any scroll view.** As shipped
in Milestone 28 the pinned list itself scrolled inside a bounded height (190 pt, about three
rows), so however many items were pinned the controls stayed put.

> **Superseded by ADR-107 (Milestone 29).** The popover no longer scrolls at all. The pinned
> list is capped at `MenuBarQuickStartView.visibleLimit` rows and the remainder moved into a
> compact "More" menu. `MenuBarPopoverLayoutTests` now asserts that **no** menu-bar view
> contains a `ScrollView`; the bounded-`maxHeight` assertion described here no longer applies.

### 2.3 Transport controls

Running and paused now offer the same four controls, so the row never re-flows into a
different shape mid-session — only the first button's verb and glyph change.

| State | Controls |
| --- | --- |
| Running | Pause (`pause.fill`), Skip (`forward.end.fill`), Restart (`arrow.counterclockwise`), Stop (`stop.fill`) |
| Paused | Resume (`play.fill`), Skip, Restart, Stop |

Each button is a glyph above a word, so no action is carried by an icon alone. Restart is
newly available while running (previously paused-only); it routes through the existing
`MenuBarCoordinator.restart()` → `SessionCoordinator.restart()`, which already existed and
is already covered by `MenuBarControlTests`.

Routing is unchanged:

```
popover control → MenuBarCoordinator → SessionCoordinator → TimerEngine
```

`ProductionReadinessM28Tests.menuBarRoutingUnchanged` asserts the adapter still calls
`session.pause()/resume()/skip()/stop()/restart()` and never touches the engine directly.

### 2.4 Timer information preserved

Nothing was dropped from the countdown block: phase label, large countdown, the paused
label, the focus progress dots, "Session X of N", and "Next <phase> - <duration>" all remain
(`MenuBarTimerView`, unchanged). The countdown is still a `TimelineView` **repaint** of
`TimerEngine.remaining` in the popover, and the status-item **label** still contains no
`TimelineView` (ADR-101, re-asserted by `MenuBarPopoverLayoutTests.labelHasNoTimelineView`).

---

## 3. The icon system (ADR-103)

### 3.1 The catalog

`Core/Support/TimeFrameIcon.swift` defines a closed set of 31 icons in five categories.
Each entry has four things:

| Field | Purpose |
| --- | --- |
| `rawValue` | the **stable persisted identifier**, a plain dot-free token (e.g. `laptop`) |
| `symbolName` | the SF Symbol it renders as (e.g. `laptopcomputer`) |
| `displayName` | the human-readable name shown and spoken (e.g. "Laptop") |
| `category` | Focus, Study, Work, Wellbeing, or General |

| Category | Icons |
| --- | --- |
| Focus | Brain, Laptop, Desktop, Keyboard, Pencil, Target, Scope |
| Study | Book, Closed Book, Textbook, Graduation Cap, Desk, Notebook |
| Work | Briefcase, Chart, Calendar, People, Checklist |
| Wellbeing | Walk, Run, Leaf, Coffee, Moon, Rest |
| General | Star, Bolt, Flag, Checkmark, Timer, Clock, Grid |

Two properties make this a catalog rather than a convention:

1. **Only a catalog member can be stored.** The persisted value is the identifier, never an
   SF Symbol name and never free text. The editor's control is a typed `Picker` over the
   enum, so an arbitrary symbol string cannot be selected, typed, or pasted in.
2. **Only this file maps an identifier to a symbol.** Views ask a template or plan for its
   `icon` and render `icon.symbolName`.

The identifier is deliberately decoupled from the symbol name so a symbol can be swapped for
a better one in a future OS without rewriting stored rows — and so a dotted symbol name can
never itself be a valid stored identifier.

### 3.2 Resolution and fallback

```swift
TimeFrameIconIdentifier.resolve(_ rawValue: String?, fallback: TimeFrameIconIdentifier)
```

An unknown, empty, or absent value resolves to the type's default rather than reaching
`Image(systemName:)`. So a corrupt row, a downgrade, or a value written by a newer build
still renders. Defaults: **Target** for a Template, **Checklist** for a Plan.

`TimeFrameIconCatalogTests` renders every catalog symbol through
`NSImage(systemSymbolName:)`, so a typo in the catalog fails the build rather than showing a
missing glyph to a user.

### 3.3 Where an icon appears

`TimeFrameIconPicker` (the one picker) and `TimeFrameIconBadge` (the one renderer) live in
`Views/Components/TimeFrameIconPicker.swift`. The chosen icon appears in:

- the Templates list row and the Plans list row;
- the Template detail header and the Plan detail header (plus a named "Icon" row);
- the Template editor and the Plan editor;
- the menu bar's Quick Start list.

The picker is a native `Picker` with a section per category, showing glyph plus name, with
an explicit "<Name> icon" accessibility label per option. A native pop-up button was chosen
over a grid so keyboard navigation, type-select, focus ring, and VoiceOver work without
being reimplemented, and so the control stays compact inside a `Form`.

`ProductionReadinessM28Tests` asserts that the raw `iconIdentifier` string is read in exactly
four files (the two models and their two repositories) and that no view ever passes it to
`systemName:`.

---

## 4. Quick Start pinning (ADR-104)

### 4.1 Where pin state lives

Pin state is stored **on the item itself**:

```swift
var isPinned: Bool = false
var pinnedAt: Date?
```

on both `TaskTemplate` and `SessionPlan`, keyed by their existing stable `UUID`. There is no
pin table, no UserDefaults key, and no App Group key. That single decision gives four
properties for free, each of which is a test:

| Behaviour | Why it holds |
| --- | --- |
| **Rename keeps the pin** | identity is the `id`; the name is not part of it |
| **Delete removes it from Quick Start** | the pin lived on the row that went away — nothing to reconcile |
| **Edit never changes the pin** | `isPinned` is deliberately not part of the draft |
| **Duplicate copies the icon, not the pin** | pinning is an explicit choice about one item |

Pinning is idempotent: re-pinning an already pinned item keeps its original `pinnedAt`, so
the Quick Start order never jumps.

### 4.2 The pin control

Pin/unpin appears on the Template detail page, the Plan detail page, both list context menus,
and both list leading swipe actions. All wording comes from one pure type,
`QuickStartPinPresentation`, so every surface says and speaks the same thing:

| Surface | Unpinned | Pinned |
| --- | --- | --- |
| Detail button title | "Pin to Quick Start" (`pin`) | "Pinned to Quick Start" (`pin.fill`) |
| Menu / swipe title | "Pin to Quick Start" | "Remove from Quick Start" |
| VoiceOver label | "Pin Deep Work to Quick Start" | "Remove Deep Work from Quick Start" |

It is an ordinary reversible preference, so it is one click with immediate feedback — **no
confirmation dialog**. A pinned item also shows a "Pinned" marker in its list row, stated as
a word rather than a glyph alone.

### 4.3 The Quick Start list

`Core/Services/QuickStart/` holds three small pieces:

| File | Role |
| --- | --- |
| `QuickStartItem.swift` | the pure row value + `QuickStartOrder`, the one comparator |
| `QuickStartProvider.swift` | maps pinned templates/plans to rows (read-only) |
| `QuickStartCoordinator.swift` | the `@Observable` adapter the popover reads and starts from |

A row carries the item's `id`, kind, name, subtitle, icon, whether it is startable, and its
pin date. Subtitles are read from the item's **live** data, so an edited configuration shows
its new durations with nothing cached to invalidate:

- Template: `50 min focus - 10 min break`
- Plan: `4 focus sessions - 3h 20m`

**Ordering** is oldest pin first — the order the user built by pinning, which never reshuffles
on a rename or an edit. Ties (equal instants, or an older row with no recorded date) fall back
to name and then id, so the comparator is total and deterministic.

**Type is stated in words.** Each row reads `Template - <summary>` or `Plan - <summary>`,
because the icon is the user's personal marker and carries no type meaning.

**An item that lost its configuration is still listed**, with its start control disabled and
the reason in words ("Needs a configuration before it can start") — the pin is never silently
discarded.

### 4.4 Starting from Quick Start

A tap routes through the seam that already exists:

```
Quick Start row
  → QuickStartCoordinator.start(item)
  → AppIntentSessionActions.startTemplate(id:) / .startPlan(id:)
  → SessionCoordinator.startSession / .startPlan
  → TimerEngine
```

No new start path was introduced. The template chain stays
`TaskTemplate → SessionSetupPrefill → startSession`; the plan chain stays
`SessionPlan.executionSnapshot → startPlan`.

The list is a **display cache**, not a source of truth: a start re-resolves the authoritative
template or plan by id. So a stale row for a deleted item fails safely through the existing
closed `TimeFrameIntentError` set — a message in the popover, no phantom session, and the
timer left exactly as it was. `requireNoActiveSession()` makes rapid taps idempotent.

### 4.5 Relationship to the M23 App Group catalog

The App Group `QuickStartCatalog` (Milestone 23) is **unchanged**. It exists for a different
consumer with a different constraint: the iOS Control Center picker runs in a widget-extension
process that cannot import SwiftData, so it needs a cross-process snapshot of the user's
**configurations**.

The macOS popover runs in the app process and reads the repositories directly, which is
strictly better there — no snapshot to go stale. Both read from the same authoritative models;
neither is a second store, and pin state is persisted in exactly one place.

---

## 5. Event-driven refresh (ADR-105)

`TaskTemplateRepository` and `SessionPlanRepository` gained the same neutral, opaque
`onChange` hook `ConfigurationRepository` has carried since Milestone 24 (ADR-097). It fires
after every successful mutation: create, update, delete, duplicate, default, pin.

```
repository mutation
  → onChange (opaque; the repository knows nothing about who cares)
  → SessionCoordinator forwards it (owns no Quick Start knowledge)
  → QuickStartCoordinator.refresh()
  → the popover redraws through Observation
```

`SessionCoordinator.init` gained one optional parameter, `onLibraryChanged`, forwarded to
both repositories exactly as `onConfigurationsChanged` is forwarded to the configuration
repository. It is forwarded only — nothing about the timer changed.

**There is no polling and no timer.** Pin an item, open the menu bar, and it is there — no
restart. Unpin it and it is gone. `ProductionReadinessM28Tests` fails the build if the Quick
Start layer contains `Timer(`, `Task.sleep`, `asyncAfter`, `scheduledTimer`,
`DispatchSourceTimer`, `TimelineView`, or `publish(every`, and re-asserts that
`SessionCoordinator.swift` remains the only file in `Core/` containing `Task.sleep` (ADR-099).

The persistence layer stays ignorant of its observers: the repositories are asserted to
mention neither `QuickStartCoordinator`, `MenuBar`, nor `WidgetKit`.

---

## 6. Schema V7

`TimeFrameSchemaV7` adds three attributes to each of `TaskTemplate` and `SessionPlan`:

| Attribute | Type | Note |
| --- | --- | --- |
| `iconIdentifier` | `String` | defaulted to the type's catalog default |
| `isPinned` | `Bool` | defaulted to `false` |
| `pinnedAt` | `Date?` | optional; `nil` whenever unpinned |

The **model set is unchanged** — the same six types as V5/V6. Every added attribute is
defaulted or optional, so it is CloudKit-legal (ADR-061) and lightweight-migratable: SwiftData
opens an existing V6 store in place. The established rebuild-on-incompatibility safety net
(ADR-016) still applies if a store cannot be opened at all.

`ProductionReadinessM28Tests` asserts V7 has six entities, no uniqueness constraint, and that
each of the six new attributes is optional or defaulted.

Nine earlier `ProductionReadiness*` suites asserted "the schema is still V6" as shorthand for
"this milestone added no model". Each was **retargeted, not relaxed**: it now asserts the
current version **and** that the entity set is still exactly six, which is the invariant those
milestones actually own. `TimeFrameSchemaV6.versionIdentifier == Schema.Version(6,0,0)`
remains asserted as a historical fact.

---

## 7. Accessibility

| Control | Label |
| --- | --- |
| Gear | "Settings and More" (hint names its four items) |
| Pause | "Pause Timer" |
| Resume | "Resume Timer" |
| Skip | "Skip Interval" |
| Restart | "Restart Timer" |
| Stop | "Stop Timer" |
| Quick Start row | "Start Deep Work" (value: "Template - 50 min focus - 10 min break") |
| Disabled Quick Start row | hint: "Needs a configuration before it can start" |
| Pin | "Pin Deep Work to Quick Start" / "Remove Deep Work from Quick Start" |
| Pinned marker | "Pinned to Quick Start" |
| Icon picker option | "Laptop icon", "Book icon", "Briefcase icon", ... |
| Start Timer | "Start Timer" (hint: "Opens Time Frame to choose what to focus on") |

Principles applied throughout:

- **Nothing is carried by colour, shape, or glyph alone.** Every transport button pairs its
  glyph with a word; the pin state and the pinned marker are stated in words; a Quick Start
  row states its kind in words; a disabled row explains why in words.
- **One row, one control, one VoiceOver element.** A Quick Start row is a single button
  labelled with the action, and the decorative icon and play glyph are
  `accessibilityHidden`, so it does not read as three separate things.
- **The countdown keeps `.updatesFrequently`** (M17) so VoiceOver handles it correctly.

---

## 8. Light and Dark appearance

No colour is hard-coded. Everything uses the existing design system: `TFSpacing`, `TFRadius`,
`TFPalette`, `tfQuietSurface`, `tfGlassSurface`, `.glass` / `.glassProminent` button styles,
and the system accent colour. So both appearances follow the system, and the one Time Frame
logo is unchanged (ADR-096 — no separate light/dark artwork).

---

## 9. Architecture invariants held

| Invariant | How it is enforced |
| --- | --- |
| One `TimerEngine`, one `SessionCoordinator` | source audit counts exactly one declaration of each |
| Quick Start constructs neither | audit forbids `TimerEngine(` / `SessionCoordinator(` in `Core/Services/QuickStart/` |
| One mutation seam | `QuickStartCoordinator` must use `AppIntentSessionActions(`, and must not call the coordinator's own start/control methods |
| No second clock | no scheduling primitive in `Core/Services/QuickStart/` or `Views/MenuBar/`; `Task.sleep` still only in `SessionCoordinator.swift` |
| No polling | refresh is driven by the repositories' `onChange` hooks |
| One pin persistence | `var isPinned` declared only in `TaskTemplate.swift` and `SessionPlan.swift`; no `UserDefaults` in the Quick Start layer |
| One icon resolver | `enum TimeFrameIconIdentifier` declared in exactly one file |
| No loose SF Symbol strings for item icons | `iconIdentifier` read only by the two models and two repositories; never passed to `systemName:` |
| No SwiftData in widget extensions | audited for both widget targets |
| No CloudKit or WidgetKit dependency in Quick Start | audited |
| macOS stays ActivityKit- and `ControlWidget`-free | audited |
| No emoji in production source | audited |
| No milestone label in menu bar copy | audited against real strings |

---

## 10. Tests

| Suite | Tests | Covers |
| --- | --- | --- |
| `TimeFrameIconCatalogTests` | 10 | symbol resolvability, stable/distinct identifiers, display names, categories partition, resolution and fallback, defaults, Codable |
| `QuickStartPinningTests` | 15 | icon save/load, default icon, invalid-icon fallback, pin/unpin, idempotence, rename-preserves-pin, delete-removes, duplicate behaviour, ordering, change-hook firing |
| `QuickStartProjectionTests` | 12 | empty list, only-pinned, row contents, rename flow-through, delete, unstartable item, mixed ordering, comparator totality, accessibility phrasing, pin phrasing |
| `QuickStartCoordinatorTests` | 10 | shared coordinator, refresh, start template, start plan, blocked while running, stale row, unstartable item, stale plan, error clearing, no clock |
| `MenuBarPopoverStateTests` | 5 | ready, active, paused, completed, restart-while-running |
| `MenuBarPopoverStructureTests` | 8 | gear-only secondary actions, gear symbols, controls never scroll, bounded pinned list, no clock, no `TimelineView` in the label, catalog-rendered icons |
| `ProductionReadinessM28Tests` | 21 | every invariant in section 9 |

Existing suites were preserved. The nine schema assertions were retargeted as described in
section 6; no test was deleted or weakened.

**Measured on 2026-09-06:**

| Target | Result |
| --- | --- |
| macOS Debug test | `** TEST SUCCEEDED **`, **928 tests / 196 suites** (baseline 844 / 189) |
| macOS Debug build | succeeded, 0 compiler warnings |
| macOS Release build | succeeded, 0 compiler warnings |
| iOS test (iPhone 17 Pro) | `** TEST SUCCEEDED **`, **105 tests**, 0 warnings |
| iOS test (iPad Air 11-inch M4) | `** TEST SUCCEEDED **`, **105 tests**, 0 warnings |
| iOS Release build | succeeded, 0 compiler warnings |

The only `warning:` lines in any log are runtime CoreData persistent-history diagnostics,
not compiler warnings.

---

## 11. Manual verification — what was and was not done

**Done.** The Debug app was built and launched from the command line. It ran without
crashing and sat at **0.0% CPU while idle** over five minutes, confirming no regression of
the Milestone 26 status-item spin (ADR-101) from the popover changes.

**Not done.** The popover's appearance and its interactions were **not** visually inspected
in the running app: screen-control access was declined for this session, so no screenshot
could be taken and no click could be driven. The following remain unverified on screen and
should be checked by hand:

1. Ready state: identity, Quick Start list, Start Timer, gear.
2. Active and paused states: countdown, dots, next interval, the four controls.
3. The gear menu opening and dismissing after a selection.
4. Icon picker interaction in both editors, in Light and Dark appearance.
5. Pin and unpin, and the menu bar reflecting it without a restart.
6. Layout with long names, many pins, no pins, and at accessibility text sizes.
7. VoiceOver reading order through the popover.

To do this by hand:

```bash
open /Users/abirbarman/Library/Developer/Xcode/DerivedData/time_frame-buzcgrtpqqhpfgaliomnqxsgqiso/Build/Products/Debug/time_frame.app
```

### Screenshots

**No macOS screenshot was captured for this milestone**, for the same reason recorded in
`docs/assets/screenshots/macos/README.md` for Milestone 27b: screen capture is refused for
this tooling on this machine. No screenshot has been fabricated. The existing verified iPhone
screenshots are untouched and remain accurate — nothing in this milestone changes an iOS
surface.

---

## 12. Deferred

| Item | Why |
| --- | --- |
| Icons in widgets and Live Activities | No widget surface currently displays a Template or Plan identity — they project the **running session**, whose model has no icon. Adding one would mean extending the App Group projection format for no present benefit. |
| Icons in the Control Center quick-start picker | That picker selects **configurations**, which have no icon. Giving configurations icons is a separate, larger change. |
| Pinning configurations | Quick Start pins Templates and Plans, which are the "things you start". A configuration is a rhythm, and the Control Center control already covers starting one. |
| Reordering pins by drag | Order is by pin date, which is stable and predictable. Manual reordering would need a persisted sort index. |
| iOS Quick Start surface | This milestone is scoped to the macOS menu bar. The pin and icon data are platform-neutral (they live in `Core/`), so an iOS surface can reuse them unchanged. |
