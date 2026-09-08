# Milestone 30 — Design System Consolidation

A presentation-consistency milestone. It adds no feature, no store, no timing authority and
no schema change. Its subject is the last place where Time Frame's macOS interface still
spoke with two voices: the size of a control, and the size of a word.

There remains exactly one `TimerEngine`, one `SessionCoordinator`, one mutation seam and one
Quick Start projection. The SwiftData schema stays **V7**.

## Why this milestone exists

Milestone 29 unified the eight macOS screens behind one set of components: one page header,
one content card, one detail row, one icon tile, one Manage group. What it did not do was move
the two most-repeated *values* into the design system.

Two consequences survived into the shipped build:

**The Timer screen's Start action was a full-width filled slab.** Every other action in the app
is sized to its content at the native macOS control height; Start alone spanned the content
column at `.controlSize(.large)`. A full-width filled button at the foot of a column of labelled
fields is a web form's submit button, and it made the app's most important screen read as the
one screen that was not native.

**The type scale was a convention, not a decision.** `TFSpacing`, `TFRadius`, `TFMotion` and
`TFPalette` were centralised in Milestone 9; typography never was. Each screen reached for
`.largeTitle.weight(.bold)`, `.headline`, `.subheadline` and `.caption` directly. The result
looked consistent because the same four values happened to be chosen everywhere — which is a
convention held in sixty files, and one edit away from drifting.

## What changed

### 1. The type scale moved into the design system

`Core/Support/DesignSystem/TimeFrameDesign.swift` gains `TFTypography`, which names the roles
the product actually uses rather than the fonts it happens to call:

| Role | Value | Used for |
| --- | --- | --- |
| `pageTitle` | `.largeTitle.weight(.bold)` | the screen's name — "Timer", "Templates", "Plans" |
| `subjectTitle` | `.title.weight(.bold)` | a detail page's subject (a template's or plan's own name) |
| `sectionTitle` | `.headline` | a group heading inside a page — "Task", "Session Plan" |
| `rowTitle` | `.headline` | the leading text of a list row |
| `body` | `.body` | ordinary reading text and text-field content |
| `secondary` | `.subheadline` | a title's one-line qualifier, rendered `.secondary` |
| `metadata` | `.caption` | a row's metrics line, a caption under a heading |
| `numericValue` | `.body.monospacedDigit()` | a value that must not jitter as it changes |
| `groupTitle` | `.subheadline.weight(.semibold)` | a grouped card's heading — "Template Details", "Manage" |
| `rowLabel` / `rowValue` | `.subheadline` / `.subheadline.weight(.medium)` | the two halves of a detail row |

These are native system fonts throughout — no custom faces, no arbitrary point sizes — so they
continue to respond to the user's text-size and accessibility settings.

The shared components (`TFPageHeader`, `TFSectionHeader`, `TFDetailCard`, `TFDetailActions`)
now read their sizes from this scale. Because every screen composes those components, changing
what a section title looks like is one edit.

### 2. The control-size rule became explicit

The same file gains `TFControl` and two view modifiers that encode the rule in one place:

```swift
func tfPrimaryAction(minimumWidth: CGFloat = TFControl.primaryMinimumWidth) -> some View
func tfSecondaryAction() -> some View
```

The rule:

- a screen has **exactly one** prominent action, and it is sized to its content;
- supporting actions are bordered and sized to their content, at the same height, so a row of
  actions shares a baseline;
- `primaryMinimumWidth` (108 pt) is a *floor*, giving the prominent action presence without
  stretching it — a longer title still fits;
- `.regular` is the control size, not `.large`. `.large` is a banner height and was making
  ordinary page actions read as banners.

`tfPrimaryAction` deliberately offers **no** full-width variant. A control that should span its
container states that at the call site, and exactly one does (below).

### 3. The Timer screen's Start became a compact action

`SessionSetupView.startButton` no longer spans the content column. It is a content-sized
prominent action carrying the shared treatment, aligned to the leading edge with the rest of the
screen's content.

A second, smaller change came with it: when Start is unavailable, the screen now says
*"Enter a task to start."* beside it. Previously the only signal was the button being dim, which
is state carried by appearance alone.

### 4. The detail pages share the same control height

Template detail (Start, Create Plan, Choose Configuration) and Plan detail (Start, Add to
Calendar) previously each set `.controlSize(.large)` and a hand-rolled `minWidth` on the label.
They now use `tfPrimaryAction()` / `tfSecondaryAction()`, so the two pages and the Timer screen
share one action height rather than three similar ones.

Nothing about what those actions *do* changed. Start still routes through
`SessionCoordinator`; Add to Calendar still goes through `CalendarCoordinator`; the Manage group
(Duplicate, Delete) is untouched.

### 5. The one deliberate exception, recorded

The menu-bar popover's fallback action (`Start Timer` / `Start New Session`) still spans its
width. The popover is 288 pt wide and offers exactly one action when nothing is running; there,
spanning the width is the correct native treatment, not a slab. `M30CompactActionTests` records
this as intentional, so a second full-width action elsewhere has to argue with a test first.

### 6. Stale documentation corrected

Three places still described the Milestone 28 menu bar, in which the pinned list scrolled inside
a bounded height. ADR-107 removed scrolling from the popover entirely in Milestone 29, and the
code and its tests already matched — only the prose did not:

- the header comment of `TimeFrameMenuBarView.swift`;
- the header comment of `MenuBarPopoverLayoutTests.swift`;
- `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md`, where the section is now marked superseded
  rather than deleted, so the milestone's own record stays intact.

## What did not change

- **The timer.** `TimerEngine`, `SessionCoordinator`, the heartbeat and the lifecycle seam are
  untouched. No file under `Timer/`, `Services/` or `Models/` changed.
- **Persistence.** Schema stays **V7**. No migration, no new store, no new UserDefaults key.
- **Quick Start.** Still one projection, refreshed on the repositories' change hook, shared by
  the Timer screen and the menu bar.
- **The editor flows.** Milestone 29's ADR-106 fix stands unchanged; `EditorFlowTests` (19 tests)
  still covers Template and Plan edit identity, pinning, icons, validation and cancellation.
- **iOS.** No iOS file changed. The design-system additions compile into both targets but are
  adopted only by the macOS views in this milestone.

## Tests

`time_frameTests/ProductionReadinessM30Tests.swift` — 10 tests in 3 suites:

| Suite | Asserts |
| --- | --- |
| `M30CompactActionTests` | each redesigned page sizes actions through the shared treatment; none uses `.controlSize(.large)`; the Timer's Start contains no `frame(maxWidth: .infinity)`; the menu-bar fallback is the one deliberate full-width action; a disabled Start explains itself in words |
| `M30TypographyTests` | every type role exists in `TFTypography`; `TFControl` and both modifiers exist; the shared components read from the scale and hard-code no title size |
| `M30ArchitectureTests` | the design system imports none of the domain; the redesigned screens introduce no `Task.sleep` / `asyncAfter` / `scheduledTimer` / `DispatchSourceTimer` / `TimelineView` |

These are source audits, because both rules are structural properties of the view tree that a
value test cannot observe. They deliberately assert no pixel geometry: they prove the rule is
applied, not that a particular screenshot was matched.

## Verification

| Check | Result |
| --- | --- |
| macOS Debug build | succeeded, 0 compiler warnings |
| macOS Release build | succeeded, 0 compiler warnings |
| macOS test suite | 959 tests in 203 suites passed (baseline 949 / 200) |

## Known limitations

- **No visual capture was performed.** The environment used for this milestone had no screen
  recording or accessibility permission, so no screenshot of the running app was taken and no
  pixel comparison against a reference was made. The visual claims here are claims about the
  code — which control treatment and which type role each screen uses — not about a rendered
  image. The screenshots under `docs/assets/` are unchanged and predate this milestone's
  button-size change.
- **Light Mode was not visually verified** for the same reason. It remains correct by
  construction: every colour is a system colour or the app accent from `TFPalette`, every
  surface is a system material, and no palette is hard-coded to a dark value.
- **The type scale is adopted by the shared components, not by every call site.** Screens that
  compose `TFPageHeader`, `TFSectionHeader`, `TFDetailCard` and `TFDetailActions` get the scale
  for free; a handful of screen-local labels still name their font directly. Migrating those is
  cosmetic and was left out rather than churn sixty files for no visible change.
