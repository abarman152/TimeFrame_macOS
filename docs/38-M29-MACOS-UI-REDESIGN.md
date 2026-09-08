# Milestone 29 — macOS Interface Redesign, Shared Design System, and the Editor Presentation Fix

**Status:** implemented
**Scope:** macOS presentation layer, plus one shared design-system file compiled into both platforms
**Schema:** unchanged (**V7**)
**Timer authority:** unchanged — one `TimerEngine`, one `SessionCoordinator`, one mutation seam

---

## 1. What this milestone is

Milestone 29 is a **presentation** milestone with one genuine defect fix inside it.

By Milestone 28 the macOS app had every feature it needed, but the screens had grown up one at a
time. Each carried its own idea of a header, a card, a row and a button, and the detail pages had
accumulated a stack of full-width filled controls where "Start", "Create Plan", "Pin", "Duplicate"
and "Delete" all shouted at the same volume. This milestone gives the eight screens one visual
language, and fixes the reason two of the app's most important buttons — Template **Edit** and Plan
**Edit** — did nothing when pressed.

Three rules govern everything below:

1. **No new timing authority.** No screen in this milestone owns a timer, a clock, a countdown, or a
   second store. `SessionSetupView`, the detail pages, and the menu bar contain no `Timer(`,
   `Task.sleep`, `asyncAfter`, `scheduledTimer` or `DispatchSourceTimer` — asserted by
   `EditorPresentationStructureTests` and the existing `MenuBarPopoverLayoutTests`.
2. **No feature was removed to make the design work.** Every action that existed before still
   exists: it may have moved from a full-width button into a row's overflow menu or a detail page's
   "More" menu, but nothing was dropped, and every list still has its context menu.
3. **Design lives in the design system, not in the screens.** New shared vocabulary went into
   `Core/Support/DesignSystem/` and `time_frame/Views/Components/`, and the screens compose it.

---

## 2. The Edit defect (ADR-106)

### 2.1 Symptom

On a Template's detail page, pressing **Edit** did nothing. The same was true on a Plan's detail
page. Every *other* action on those pages worked: Start, Duplicate, Delete, the pin toggle, Create
Plan, Add to Calendar.

### 2.2 Diagnosis

The distinguishing feature of Edit was that it was the only action that reached **out of** the detail
page. Both detail pages took an `onEdit` closure from their list:

```
TemplateListView                       ← owns `editorTarget` and `.sheet(item:)`
└── NavigationStack
    └── navigationDestination(UUID)
        └── TemplateDetailView(onEdit: { editorTarget = .edit($0) })
```

The state *was* being set — the fix is not a wiring bug. The problem is that on macOS, a
`.sheet(item:)` attached to a `NavigationStack` is not presented while a `navigationDestination` is
pushed. The request is held. Popping back to the list then presents the sheet, so the editor appeared
*later*, over the wrong screen, apparently unprompted.

This was confirmed by driving the running app: pressing Edit on the detail page produced no sheet;
navigating back to the list immediately produced the editor, correctly populated with the item being
edited.

### 2.3 Fix

Each detail page now presents its own editor, from its own state, in the view that is actually on
screen:

```swift
@State private var editingTemplate: TaskTemplate?
...
.sheet(item: $editingTemplate) { TemplateEditorView(coordinator: coordinator, existing: $0) }
```

`onEdit` is gone from both detail pages and both lists no longer inject an editor closure into a
pushed destination. The lists keep their own `.sheet` for **Create** and for their own row actions,
where the root view is on screen and presentation works.

Nothing below the view layer changed. It is the same `TemplateEditorView` / `PlanEditorView`, saving
through the same `TaskTemplateRepository.update` / `SessionPlanRepository.update`, so identity, the
pin, the icon, the timeline and history are all unaffected.

### 2.4 What is now guaranteed by tests

`time_frameTests/EditorFlowTests.swift` covers both halves of the defect.

Behaviour (`TemplateEditFlowTests`, `PlanEditFlowTests`):

| Guarantee | Test |
|---|---|
| Editing updates the same row; `id` and `createdAt` survive | `editPreservesIdentity` |
| Editing never inserts a second row | `editCreatesNoDuplicate` / `editPreservesIdentity` |
| A rename keeps the pin **and** its Quick Start position | `editKeepsPin` |
| The icon round-trips as a catalog identifier, never a symbol name | `editPersistsIcon` |
| Changing the configuration re-points the template | `editChangesConfiguration` |
| Editing the timeline replaces intervals and re-normalises order | `editChangesItems` |
| An invalid edit is rejected and leaves the row untouched | `invalidEditIsRejected` |
| Cancel mutates nothing — the editor only writes in `save()` | `cancelMutatesNothing` |
| Saving republishes Quick Start through the repositories' `onChange` hook | `editRefreshesQuickStart` |
| Editing a plan mid-session never disturbs the running timer | `editDoesNotTouchTheTimer` |

Structure (`EditorPresentationStructureTests`) — because a behaviour test cannot see a presentation
bug:

- each detail page contains its own `.sheet(item:)` for the editor;
- neither detail page contains `onEdit`;
- neither list passes `onEdit:` into a pushed destination;
- editing still routes through `coordinator.templates.update` / `coordinator.plans.update`;
- neither detail page nor the Timer setup screen introduces a scheduling primitive.

---

## 3. The menu bar no longer scrolls (ADR-107)

Milestone 28 put the Quick Start list inside a height-bounded `ScrollView` so a long list of pins
could not push the transport controls off screen. That solved the layout problem but produced a
popover whose contents were partly hidden and slow to hit.

Milestone 29 removes scrolling from the popover entirely:

- `MenuBarQuickStartView.visibleLimit` (3) rows are drawn, always fully visible;
- any pins beyond that are offered by a compact **"N more…"** native menu that starts them directly;
- nothing is dropped, and no part of the popover scrolls.

`MenuBarPopoverLayoutTests` was updated from "the pinned list is the one scrolling region, and it is
height-bounded" to **no menu-bar view may contain a `ScrollView` at all**, plus assertions that the
cap is explicit, that the overflow is reachable, and that the limit stays small.

The seam is unchanged: a Quick Start row still routes
`QuickStartCoordinator → AppIntentSessionActions → SessionCoordinator → TimerEngine`, and the
status-item label still contains no `TimelineView` (ADR-101).

---

## 4. The design system

### 4.1 Shared (both platforms)

`Core/Support/DesignSystem/TimeFrameGlass.swift` gained the app's one content-surface definition:

- `tfCard(cornerRadius:isSelected:)` — a `.quinary` fill plus a `.separator` hairline border;
- `TFRowDivider(leadingInset:)` — the inset hairline used *inside* a card;
- `tfQuietSurface(cornerRadius:)` now **delegates to `tfCard`**, so the two near-identical surfaces
  the app had become one. Every existing caller (Statistics cards, Today's summary, the menu-bar
  rows) inherited the unified look without being edited.

`Core/Support/DesignSystem/TimeFrameDesign.swift` gained three tokens: `TFSpacing.wideColumn` (720,
the column width for list and detail screens), `TFSpacing.iconTile`, and `TFRadius.tile`.

Glass is unchanged and still reserved for floating control regions and the primary action
(ADR-051) — cards are not glass.

### 4.2 macOS components (`time_frame/Views/Components/`)

| Component | Purpose |
|---|---|
| `TFPageHeader` | The large title + one-line explanation + optional trailing control every screen opens with |
| `TFSectionHeader` | A section title + caption + optional trailing control (a filter, a "Manage…" link) |
| `TFDetailCard` / `TFDetailRow` | The grouped "Details" card on both detail pages: symbol, label, value, hairline-divided |
| `TimeFrameIconTile` / `TFSymbolTile` | The one rounded-square container a chosen icon (or a view-chosen symbol) is drawn in, at three sizes |
| `TFRowActions` | A list row's trailing Start + overflow controls, laid out **beside** the navigation link so a click on them is never swallowed by it |
| `TFManageSection` | The quiet Duplicate / Delete group at the foot of a detail page |
| `TFNoticeBanner` | The caution note shown when an item cannot start |
| `TFSheetHeader` | A title block for an editor sheet — a macOS sheet has no navigation bar, so `navigationTitle` rendered nothing there |
| `TFChip` | A small, quiet metadata chip (used on Plan rows) |
| `TFDefaultMarker` | The "Default" marker shared by templates and configurations |

Symbols for these come from the *view*, never from stored data. A template's or plan's own icon still
comes only from the closed catalog (`TimeFrameIconIdentifier.symbolName`, ADR-103).

### 4.3 The action hierarchy rule

Every detail page now follows one rule, expressed in `TFManageSection` and the pages themselves:

- **one** prominent action per page (Start), rendered `.glassProminent`;
- supporting actions are `.bordered` and sized to their content;
- a preference (pinning) is a `Toggle`, not a button;
- destructive actions live in a separate "Manage" group, where Delete is the page's only red control;
- secondary and rarely-used actions live in an overflow `Menu` beside the title.

---

## 5. Screen by screen

### 5.1 Sidebar

Order unchanged (Today, Timer, Templates, Plans, Configurations, History, Statistics, Settings).
Every glyph now renders at one weight and one rendering mode (`.medium`, `.hierarchical`), the list
uses `.listStyle(.sidebar)`, and the column is 190–300pt wide. Navigation behaviour, the menu-bar
navigation seam, and `timeframe://` deep links are untouched.

### 5.2 Timer (`SessionSetupView`)

Rebuilt around the decision the user is actually making:

- **Header** — "Timer" + "Choose a task and configuration to begin.", with **Quick Start** in the
  top-right. That menu reads the *same* `QuickStartCoordinator` the menu bar uses and starts through
  the *same* seam — there is no second Quick Start list.
- **Task** — a card-styled field with a **Recent Tasks** menu. Recent names come from a bounded
  `FetchDescriptor` (`fetchLimit` 60, deduplicated to 8), so history can grow without this read
  growing with it (M26, ADR-100). No new repository.
- **Configuration** — one card: icon tile, name, and the durations on a single summary line
  ("45 min focus · 5 min short break · 15 min long break · 4 sessions"), chosen through a native
  menu, with a quiet **Manage Configurations** link.
- **Focus Sessions** — a compact −/value/+ stepper that reads to VoiceOver as one adjustable element
  ("Focus sessions, 4"), not a full-width control.
- **Session Plan** — the generated intervals in one card, with a **Show** filter (All Sessions /
  Focus Only / Breaks Only). The filter is presentation-only: it narrows what is *listed* and can
  never change the plan the engine runs.
- **Start** — the single prominent action.

The running-session view, `TimerControls`, `TimerDisplay` and `SessionProgressView` are unchanged.

### 5.3 Templates and Plans

Both lists gained the page header, a native `.searchable` filter, and card rows with a leading icon
tile, the Pinned/Default markers, a summary line, and trailing Start + overflow controls. Plans rows
also carry three quiet chips (sessions, total, configuration — "Custom" when the plan deliberately
mixes configurations, ADR-030) and a "N plans" footer.

Both detail pages follow the action hierarchy in §4.3, present a "Template Details" / "Plan Details"
card, and own their editor sheet (§2). The Plan detail page also lists its intervals under a
**Sessions** section.

### 5.4 Configurations

Card rows with the four defining numbers in one compact metric strip instead of four stacked grey
lines, so configurations can be compared at a glance. Double-click-to-edit became a single click on
the row; the overflow menu and context menu keep every previous action.

### 5.5 History

Page header, day headings that now state the day's completed focus time, and card rows with a
status-tinted tile, the task, the frozen configuration name, "N of M focus sessions · duration", the
status, and the start time. Still strictly read-only.

### 5.6 Statistics

Gained the shared page header and the shared column width. The aggregation, the period picker and the
charts are unchanged — it remains a read-only projection with no clock.

### 5.7 Editors

Both editor sheets gained `TFSheetHeader`, so they open with a title that says whether you are
creating or editing.

Both had a real field-labelling bug: the *prompt* was being passed as the field's label, so a macOS
grouped `Form` rendered "e.g. Research" as the row title and squeezed the value against the trailing
edge, and a plain `List` row (the Plan editor, which must stay a `List` for drag-to-reorder) rendered
no label at all. Fields now carry a real label and a separate prompt, and the Plan editor's two text
fields use `LabeledContent`.

---

## 6. Verification

| Check | Result |
|---|---|
| macOS Debug build | Succeeded, **0 warnings** |
| macOS Release build | Succeeded, **0 warnings** |
| macOS test suite | **949 tests in 200 suites passed** |
| iOS test suite (iPhone 17 Pro simulator) | **104 tests passed** |
| Schema | **V7**, unchanged |

Manual verification was performed against the running macOS app (Debug), in both appearances:

- Timer, Templates list, Template detail, Plans list, Plan detail, Configurations, History,
  Statistics, Today — all reviewed on screen;
- **Template Edit** — opens the editor immediately, populated; Save renames in place and the detail
  and list both reflect it; Cancel discards; no duplicate row is created;
- **Plan Edit** — same, with the plan's timeline and pin preserved and "Last updated" refreshed;
- **Timer lifecycle** — Start, Pause, Resume and Stop all exercised on a live session; the countdown
  stayed live throughout and the menu bar stayed in sync;
- **Menu bar popover** — idle and running, showing the gear menu, the three pinned Quick Start rows
  and the transport controls, with no scrolling region;
- **Light Mode** — Timer, Templates and Template detail reviewed; the design is one design, not two.

### 6.1 Not verified

- **macOS screenshots could not be written to disk.** `screencapture` is refused in this environment
  and the automation surface that can produce an image does not expose a writable path. The screens
  above were verified visually; no macOS image files were added, and no mockup was substituted. See
  `docs/assets/screenshots/README.md`.
- **VoiceOver was not run.** Accessibility labels, values, hints and the adjustable stepper action
  were added and are asserted in source, but no screen reader session was performed.
- **CloudKit sync** remains a documented paid-team blocker (ADR-080), unchanged by this milestone.

---

## 7. Files

**Added**

```
time_frame/Views/Components/TFPageHeader.swift
time_frame/Views/Components/TFDetailCard.swift
time_frame/Views/Components/TFDetailActions.swift
time_frame/Views/Components/TFSheetHeader.swift
time_frame/Views/Components/TimeFrameIconTile.swift
time_frameTests/EditorFlowTests.swift
docs/38-M29-MACOS-UI-REDESIGN.md
```

**Changed**

```
Core/Support/DesignSystem/TimeFrameDesign.swift     tokens: wideColumn, iconTile, tile radius
Core/Support/DesignSystem/TimeFrameGlass.swift      tfCard + TFRowDivider; tfQuietSurface unified
time_frame/ContentView.swift                        sidebar styling; Quick Start wired to Timer
time_frame/time_frameApp.swift                      passes the existing QuickStartCoordinator down
time_frame/Views/Timer/SessionSetupView.swift       rebuilt
time_frame/Views/Timer/TimerView.swift              forwards the Quick Start adapter
time_frame/Views/Timer/IntervalPlanPreview.swift    card surface + presentation-only filter
time_frame/Views/Templates/TemplateListView.swift   header, search, card rows
time_frame/Views/Templates/TemplateRowView.swift    content-only row + shared markers
time_frame/Views/Templates/TemplateDetailView.swift own editor sheet (ADR-106) + action hierarchy
time_frame/Views/Templates/TemplateEditorView.swift sheet header, real field labels
time_frame/Views/Plans/PlanListView.swift           header, search, card rows
time_frame/Views/Plans/PlanRowView.swift            content-only row + chips
time_frame/Views/Plans/PlanDetailView.swift         own editor sheet (ADR-106) + action hierarchy
time_frame/Views/Plans/PlanEditorView.swift         sheet header, labelled fields
time_frame/Views/Plans/PlanPreviewView.swift        card surface, numbered intervals
time_frame/Views/Configurations/ConfigurationListView.swift  header, card rows
time_frame/Views/Configurations/ConfigurationRowView.swift   metric strip
time_frame/Views/History/HistoryListView.swift      header, day totals, card rows
time_frame/Views/Statistics/StatisticsView.swift    page header, shared column width
time_frame/Views/Components/QuickStartPinButton.swift  pin becomes a switch in a card
time_frame/Views/MenuBar/MenuBarQuickStartView.swift   no ScrollView; capped list + More (ADR-107)
time_frameTests/MenuBarPopoverLayoutTests.swift        updated to the no-scroll rule
```

**Removed**

Nothing. No feature, no action, no test was removed.
