# macOS Screenshot Inventory

Screenshots of the Time Frame macOS application. **Every image here is a real capture of the
running app.** Nothing is a mockup, a render, or a placeholder.

## Capture environment

| | |
|---|---|
| Captured | 2026-09-09 (twelve screens); 2026-09-07 (`menu-bar` and the two editor screens) |
| Build | Debug, from source at the current `main` |
| System | macOS 27, Dark Mode |
| Window size | 1180 x 800 points on a 2x Retina display, so **2360 x 1600 pixels** in every file |
| Capture method | `screencapture -x -R<window frame>`, one screen at a time, with the sidebar selection **verified through the accessibility API before each capture** |
| Store | An isolated SwiftData store under the session's temporary directory, via `TIMEFRAME_STORE_DIRECTORY`. The production store at `~/Library/Application Support/default.store` was never opened. |

The system accent colour on the capture machine is purple; the app takes its accent from the
system, so on a machine set to blue these screens render blue. That is `TFPalette` following
`Color.accentColor` as intended, not a hard-coded palette. The sidebar's background tint follows
the desktop picture, which is why captures made on different days differ slightly in hue.

## Sample data

The data shown is **fictional sample data** created for the capture: five configurations, six
task templates, three session plans, and roughly one month of completed session history. There
are no real names, no real email addresses, and no real calendar content in any image.

## What is captured

| File | Screen | Shows |
|---|---|---|
| `active-session.png` | Timer, running | Task, configuration, phase, countdown, progress dots, session position, the four transport controls, next-interval line |
| `session-setup.png` | Timer, idle | Page header with Quick Start, task field with Recent Tasks, the configuration card and its one-line summary, the session stepper, the filtered interval preview, and the compact Start |
| `timer-paused.png` | Timer, paused after relaunch | The "Welcome back — your session was restored" notice, the dimmed frozen countdown with an explicit "Paused" label and icon, and Resume in place of Pause. The remaining time is identical to the value before the app was quit, which is the recovery behaviour, captured rather than described. |
| `configurations.png` | Configurations | Five configurations from 15 to 90 minutes of focus, each showing all five values in one strip, with the default marked |
| `templates.png` | Templates, list | Six templates, each with its chosen icon, task, configuration line, pin marker, and trailing Start and overflow controls |
| `template-detail.png` | Template detail | Icon, name, Edit and overflow beside the title, the Template Details card, the Start / Create Plan / pin switch row, and the Manage group |
| `template-editor-new.png` | Template editor, create | The `TFSheetHeader`, field labels with separate prompts, the icon picker, the configuration picker and its summary, and the session stepper |
| `template-editor-edit.png` | Template editor, edit | The same editor opened from the detail page's **Edit**, correctly populated with the existing template (ADR-106) |
| `plans.png` | Plans, list | Three plans with session count, total duration, and configuration ("Custom" where a plan mixes them) |
| `plan-detail.png` | Plan detail | The Plan Details card, the full ordered timeline with start offsets and per-interval configurations, and the Start / Add to Calendar / pin row |
| `history.png` | History | Sessions grouped by day, newest first, each day heading stating that day's completed focus time; frozen configuration names and per-session status |
| `statistics.png` | Statistics, This Month | Period picker, the four headline metrics, the trend against the previous period, the most productive day, and the Focus by Day chart |
| `today.png` | Today | The in-progress card with its live countdown and Go to Timer action, and today's focus summary |
| `settings.png` | Settings | Open at Login, Default Configuration, Calendar, and Notifications sections |
| `menu-bar.png` | Menu bar popover, idle | The gear in the corner, the identity block, the Quick Start section with its pin count and one pinned row, and the Start Timer fallback — with no scrolling region |

## What is not captured

No image exists yet for: the Plan editor, the Configuration editor, the History detail page, the
session-complete state, or the menu bar popover **while a session runs**. The running popover
could not be captured reliably: a `MenuBarExtra(.window)` popover does not stay open for a
synthesised accessibility press, so the idle capture above is the one that could be taken and
verified by hand.

These screens remain covered by the written descriptions in the
[macOS User Guide](../../../35-MACOS-USER-GUIDE.md), which come from direct inspection of the
running application.

## What was verified live, beyond the images

The following were exercised in the running application during the capture session, not merely
inspected:

| Flow | Result |
|---|---|
| Launch against an isolated store | Opens the seeded library; the production store is untouched |
| Start a session from the Timer screen | Runs through the existing setup path; the countdown is derived, not counted |
| Switch configuration before starting | The interval preview re-derives immediately |
| Open a template's detail page | Populated correctly, with Start, Create Plan, pin switch and Manage group |
| Open a plan's detail page | The full timeline renders with per-interval configurations and start offsets |
| Statistics period change (Today → This Month) | Re-aggregates from the same history; no second data source |
| History over a month of sessions | Grouped by day with per-day focus totals and frozen configuration names |
| Pause, then quit and relaunch the app | The session is restored with the remaining time unchanged to the second, and the app reports that it restored it |
| Relaunch with the window closed | The app stays in the menu bar; activating it recreates exactly one window |

Earlier sessions additionally verified template creation, rename, pinning, Quick Start from the
menu bar, pause/resume/stop, and CPU behaviour (0.0–2.7% while running, 0.0% while paused).

## How to capture more screens

Screen Recording and Accessibility must both be granted to the application that runs the tooling
(System Settings ▸ Privacy & Security), and it must be quit and reopened for the grants to take
effect. Then, with Time Frame running against an isolated store:

```bash
TIMEFRAME_STORE_DIRECTORY=/tmp/timeframe-shots open -n "Time Frame.app"
```

Position the window at exactly 1180 x 800 points on a 2x display, select the screen, **confirm
through the accessibility API that the selection actually changed**, and only then capture the
window's own frame:

```bash
screencapture -x -R<x>,<y>,1180,800 docs/assets/screenshots/macos/<name>.png
```

A scripted select-then-capture loop without that confirmation step is what produced off-by-one
images in an earlier session; every file above was verified after capture.

## Verification status

- Application verified: yes, built, launched and driven.
- Screenshot verified: yes, for every file listed above; each was inspected after capture.
- Sample data: fictional, created for the capture. No personal or private information.
- Fabricated images: none.
