# macOS Screenshot Inventory

Screenshots of the Time Frame macOS application. **Every image here is a real capture of the
running app.** Nothing is a mockup, a render, or a placeholder.

## What is captured

Captured on 2026-09-07 from a Debug build of the Milestone 30 source, on macOS 27, in Dark Mode,
at a window size of 1180 x 800 points (2x Retina, so 2360 x 1600 pixels). The system accent colour
on the capture machine is purple; the app takes its accent from the system, so on a machine set to
blue these screens render blue. That is `TFPalette` following `Color.accentColor` as intended, not
a hard-coded palette.

The data shown is sample data created for the capture — one template, "Deep Focus" / "Write the
design document".

> **Correction.** An earlier version of this note claimed the unsigned build "ran against its own
> container". That is wrong. The macOS app is **not sandboxed**: its SwiftData store is
> `~/Library/Application Support/default.store` and its preferences live in the
> `abirbarman.com.time-frame` defaults domain. A locally built copy shares both with the installed
> app. See ADR-109 and `docs/40-M31-...` for the data-loss defect this exposed.

| File | Screen | Shows |
|---|---|---|
| `01-timer-idle.png` | Timer, idle | Page header with Quick Start, task field with Recent Tasks, the configuration card and its one-line summary, the compact session stepper, the filtered session-plan preview, and the compact Start with its "Enter a task to start." explanation |
| `02-timer-running.png` | Timer, running | Task, configuration, phase, countdown, progress dots, session position, the four controls, next-interval line |
| `03-timer-paused.png` | Timer, paused | Dimmed countdown with an explicit "Paused" label and icon; Pause becomes Resume |
| `04-templates.png` | Templates, list | A card row with the chosen icon, the Pinned marker, the task, the configuration line, and trailing Start and overflow controls |
| `05-template-detail.png` | Template detail | Icon, name, Edit and overflow beside the title, the Template Details card, the compact Start / Create Plan / pin switch row, and the Manage group |
| `06-template-editor-new.png` | Template editor, create | The `TFSheetHeader`, real field labels with separate prompts, the icon picker, the configuration picker and its summary, and the session stepper |
| `07-template-editor-edit.png` | Template editor, edit | The same editor opened from the detail page's **Edit**, correctly populated with the existing template (ADR-106) |
| `08-menu-bar.png` | Menu bar popover, idle | The gear in the corner, the identity block, the Quick Start section with its pin count and one pinned row, and the Start Timer fallback — with no scrolling region |

## What is not captured

No image exists yet for: Plans (list and detail), the Plan editor, Configurations, the
Configuration editor, History, Statistics, Today, Settings, the session-complete state, or the menu
bar popover while a session runs.

These screens were **not** captured rather than captured badly. Batch capture through the
accessibility API proved unreliable in this session — the sidebar selection and the screenshot
raced, so a run produced images that lagged one screen behind the selection. Every image in the
table above was taken individually and inspected before being committed; the rest were discarded
instead of being shipped mislabelled.

They remain covered by the written descriptions in the
[macOS User Guide](../../../35-MACOS-USER-GUIDE.md), which come from direct inspection of the
running application.

## What was verified live, beyond the images

The following were exercised in the running application during the Milestone 30 session, not
merely inspected:

| Flow | Result |
|---|---|
| Create a template | Saved; appears in the list with its icon, task and configuration line |
| **Template detail → Edit** | The editor sheet opens over the detail page, correctly populated (this is the ADR-106 defect, confirmed fixed on screen) |
| Edit → rename → Save | The detail page, the window title and the list all update immediately; **no duplicate row is created**; task, configuration, icon and session count are preserved |
| Pin to Quick Start | The Pinned marker appears in the list, and the pin reaches the menu bar's Quick Start section without an app restart |
| Start from the menu bar's Quick Start | A session starts through the existing seam and the Timer screen shows it running |
| Pause | Responds immediately; the countdown freezes and stays frozen (checked again minutes later, still frozen) |
| Resume (Space) | Responds immediately; the countdown resumes from the frozen value |
| Stop | Returns to the setup screen, and the completed run appears in Recent Tasks |
| CPU while a session runs | 0.0–2.7% steady, with brief transients on interaction |
| CPU while paused | 0.0% — the heartbeat stops rather than idling (M26) |

## How to capture the remaining screens

Screen Recording and Accessibility must both be granted to the application that runs the tooling
(System Settings, Privacy and Security), and it must be quit and reopened for the grants to take
effect. Then, with Time Frame running:

```bash
screencapture -x -R80,60,1180,800 docs/assets/screenshots/macos/09-plans.png
```

Select the screen first, confirm on screen that the selection actually changed, and only then
capture — a scripted select-then-capture loop is what produced the off-by-one images described
above.

## Verification status

- Application verified: yes, built, launched and driven.
- Screenshot verified: yes, for the eight files listed above; each was inspected after capture.
- Remaining screens: described in the User Guide, not yet photographed.
- Fabricated images: none.
