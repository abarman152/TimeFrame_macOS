<div align="center">
  <img src="assets/time-frame-logo.png" alt="Time Frame" width="96">
  <h1>Time Frame for macOS</h1>
  <p>Focus better, one session at a time.</p>
</div>

---

> **About the screenshots.** This guide contains no images. Screen capture is unavailable in the
> environment where it was written, and no mockups have been substituted. Every screen described here
> was opened and read in the running macOS application, so the descriptions are accurate. See the
> [macOS screenshot inventory](assets/screenshots/macos/README.md) for the details and for how to
> capture the set yourself.

## Contents

1. [What Time Frame is](#1-what-time-frame-is)
2. [Quick start](#2-quick-start)
3. [Choosing the right feature](#3-choosing-the-right-feature)
4. [Understanding the timer](#4-understanding-the-timer)
5. [Starting a focus session](#5-starting-a-focus-session)
6. [Pausing and resuming](#6-pausing-and-resuming)
7. [Skipping an interval](#7-skipping-an-interval)
8. [Restarting an interval](#8-restarting-an-interval)
9. [Stopping a session](#9-stopping-a-session)
10. [Understanding Pomodoro cycles](#10-understanding-pomodoro-cycles)
11. [Timer configurations](#11-timer-configurations)
12. [Configuration recipes](#12-configuration-recipes)
13. [Templates](#13-templates)
14. [Plans](#14-plans)
15. [Today](#15-today)
16. [History](#16-history)
17. [Statistics](#17-statistics)
18. [The menu bar](#18-the-menu-bar)
19. [Widgets](#19-widgets)
20. [Notifications](#20-notifications)
21. [Calendar](#21-calendar)
22. [Settings](#22-settings)
23. [Keyboard shortcuts](#23-keyboard-shortcuts)
24. [A workday with Time Frame](#24-a-workday-with-time-frame)
25. [Troubleshooting](#25-troubleshooting)
26. [Accessibility](#26-accessibility)
27. [Data and privacy](#27-data-and-privacy)
28. [FAQ](#28-faq)
29. [Known limitations](#29-known-limitations)
30. [Feature reference](#30-feature-reference)
31. [Windows, the Dock, and opening at login](#31-windows-the-dock-and-opening-at-login)

---

## 1. What Time Frame is

Time Frame is a focus timer for the Mac. You decide how long you want to concentrate, press start, and
it runs the session for you: focus, break, focus, break, until you are done. Everything you complete
is recorded, so you can look back at what you actually did.

The idea it is built on is that the timer should be trustworthy. Time Frame works out the remaining
time from real clock times rather than counting seconds as they go by. That means the countdown stays
correct if your Mac goes to sleep, if you close the window, or if you quit the app in the middle of a
session and open it again later.

## 2. Quick start

1. **Open Time Frame.** It opens on the Timer screen with the heading "Ready to Focus".
2. **Type what you are working on** in the Task field. This is required; the Start button stays
   disabled until you fill it in.
3. **Pick a configuration** from the pop-up menu. A summary appears underneath it, for example
   "25 min focus / 5 min short break / 15 min long break / 4 sessions, long break every 4".
4. **Set how many focus sessions** you want in this run using the Focus Sessions stepper. This applies
   to this run only and never changes the saved configuration.
5. **Check the Session Plan** listed below, which shows every interval in order with its length.
6. **Press Start**, or use Command-Return.
7. **Work.** The screen switches to the running timer.
8. **Take the break** when the focus interval ends. Time Frame moves into it by itself.
9. **Keep going** until the last interval finishes, and the session completes on its own.

## 3. Choosing the right feature

This is the section to read if the app has more screens than you expected. Each one answers a
different question.

| I want to... | Use | Why |
|---|---|---|
| Start focused work right now | **Timer** | It is the only place a session is started. Type a task, pick a configuration, press Start. |
| Change how long focus and breaks last | **Configurations** | Durations live in a saved configuration, not on the Timer screen. Edit one, or create another. |
| Switch between different kinds of work | **Configurations** | Keep one configuration per working style and choose it when you start. |
| Reuse a task I run often | **Templates** | Saves a task name and its configuration together so you do not retype them. |
| Run a session that changes pace partway through | **Plans** | A plan is an ordered list of intervals that can mix configurations in one session. |
| See what I have done today | **Today** | A two-number summary of the day: focus sessions and focus time. |
| See the individual sessions I ran | **History** | A list of every recorded session, newest first, grouped by day. |
| Understand my longer-term patterns | **Statistics** | Totals, completion rate, averages and trends over a day, week or month. |
| Control the timer without opening the window | **Menu bar** | The status item shows the countdown and gives you the controls. |
| Glance at the timer from the desktop | **Widget** | A read-only view in Notification Centre. |
| Be told when a focus period or break begins | **Notifications** | Turn them on in Settings so you do not have to watch the screen. |
| Have my focus time appear in my calendar | **Calendar** | Optional; mirrors sessions into Apple Calendar. |

The distinction people find least obvious is **Today versus History versus Statistics**:

- **Today** answers "how much have I done today?" It is two numbers.
- **History** answers "what exactly did I run, and how did each one end?" It is a list of sessions.
- **Statistics** answers "how am I doing over time?" It has averages, a completion rate and a trend
  against the previous period.

## 4. Understanding the timer

While a session is running, the Timer screen shows, from top to bottom:

| Element | What it means |
|---|---|
| **Task name** | What you typed when you started. |
| **Configuration name** | The configuration this session is running, frozen at the moment you started. |
| **Phase** | A small tinted label reading FOCUS, SHORT BREAK or LONG BREAK. The label, not the colour, is what carries the meaning. |
| **Countdown** | Large monospaced digits showing the time left in the current interval. |
| **Progress dots** | One dot per focus session in the run. Completed and in-progress dots are filled. |
| **Session position** | For example "Session 1 of 4". |
| **Controls** | Pause (or Resume), Stop, Restart and Skip. |
| **Calendar status** | A quiet line about calendar syncing, shown only if Calendar integration is on. |
| **Next** | What comes after this interval, and how long it is. |

When you pause, the countdown dims, an explicit **Paused** label appears beside a pause icon, and the
first control changes from Pause to Resume.

## 5. Starting a focus session

Go to **Timer** in the sidebar. The screen asks four things, in the order you decide them.

**Task** is required. The Start button is disabled until you type something. This is deliberate: the
task name is what identifies the session in History later, so a session always has a name. The
**Recent Tasks** menu beside the label fills the field with something you focused on before.

**Configuration** chooses the recipe. The card shows the configuration's name and, on one line, the
focus length, both break lengths and how many focus sessions it suggests. Click it to choose a
different one; **Manage Configurations** opens the Configurations screen.

**Focus Sessions** overrides the number of focus sessions for this run only. The saved configuration
is never modified by this stepper.

**Session Plan** lists exactly what will happen: every focus interval and every break, in order, with
lengths. Check it before you start if you are using an unfamiliar configuration. The **Show** menu
narrows the list to focus intervals or breaks only — it changes what you are reading, never what will
run.

**Quick Start**, in the top-right corner, starts one of your pinned templates or plans straight away,
without filling anything in. It is the same pinned list the menu bar shows.

Press **Start**, or Command-Return.

What happens next: the screen switches to the running timer, the first focus interval begins, and the
session is recorded immediately. It appears in History straight away with a running status, not only
once it finishes.

## 6. Pausing and resuming

Press **Pause**, or the Space bar.

The countdown freezes exactly where it is. No time passes while you are paused, however long you leave
it. The countdown dims and a **Paused** label appears so the state is unmistakable.

Press **Resume**, or Space again, to carry on from the same point.

**When to pause:** anything that genuinely interrupts the work, such as a phone call. If you are only
switching windows for a moment, there is no need.

## 7. Skipping an interval

Press **Skip**, or the Right Arrow key.

Skip ends the current interval immediately and starts the next one. If you skip the last interval, the
session completes.

The interval you skipped is still recorded, marked as skipped rather than completed. **Skipped
intervals do not count toward your focus totals** in Today or Statistics, which keeps those numbers
honest.

**When to use it:** you finished early and want to move to the break, or you do not want the break and
would rather get back to work.

## 8. Restarting an interval

Press **Restart**, or the R key.

Restart puts the current interval back to its full length. The rest of the session is untouched, and
no new interval is added to the session.

**When to use it:** you started focusing, got pulled away almost immediately, and would rather begin
this interval again than continue with a few minutes gone.

## 9. Stopping a session

Press **Stop**, or the Escape key.

Stop ends the whole session. Intervals you already completed are kept. The interval you were in is
recorded as cancelled.

The session stays in History with a **Stopped** badge. Stopping never deletes anything.

**Stop versus Skip:** Skip moves on within the session. Stop ends the session.

## 10. Understanding Pomodoro cycles

A session is a sequence of intervals. Time Frame builds that sequence from the configuration you
chose. With a configuration set to a long break after every 4 focus sessions, a four-session run looks
like this:

```text
Focus
  |
  v
Short Break
  |
  v
Focus
  |
  v
Short Break
  |
  v
Focus
  |
  v
Short Break
  |
  v
Focus
  |
  v
Long Break
```

The long break replaces the short one after the configured number of focus sessions. You can see the
exact sequence for any configuration before you start, in the Session Plan list on the Timer screen.

Time Frame moves from one interval to the next by itself. You do not have to press anything when a
focus interval ends.

## 11. Timer configurations

A configuration is a saved recipe. Open **Configurations** in the sidebar to manage them.

The list shows each configuration with its summary, and the one currently used for new sessions is
marked **Default**.

### Creating one

Press the **+** button at the top right. A sheet appears with:

| Field | Meaning | Range |
|---|---|---|
| **Name** | What you call it | Cannot be empty |
| **Focus** | Length of one focus interval | 1 to 480 minutes |
| **Short Break** | The break between focus intervals | 0 to 480 minutes |
| **Long Break** | The longer break | 0 to 480 minutes |
| **Long Break After** | How many focus sessions before a long break | 1 to 12 |
| **Default Sessions** | How many focus sessions a run starts with | 1 to 24 |

All durations are entered in whole minutes using steppers. Press **Save**, or **Cancel** to discard.

### Editing, renaming and deleting

Select a configuration to edit it; the same sheet appears with its current values. Renaming is just
editing the Name field.

**Editing or deleting a configuration never changes your history.** When a session starts it takes its
own copy of the values it needs, including the name. A session you ran last week keeps the name it had
then, even if you rename or delete that configuration afterwards.

Editing a configuration also does not affect a session that is currently running.

### Choosing the default

The default is set in **Settings**, under Default Configuration. New sessions start from it.

## 12. Configuration recipes

Time Frame does not ship preset configurations beyond the one it creates on first launch
("Classic Pomodoro", 25 minutes of focus with four sessions). The following are suggestions for
configurations **you** would create, not features of the app.

### Deep work

Long focus, short breaks, few sessions. Use when the work needs a long run-up and interruptions are
expensive, such as writing or debugging something intricate.

### Short tasks

Shorter focus, frequent breaks. Use when you are working through a queue of small items and want
regular checkpoints.

### Study

Moderate focus with a reliable long break after a few rounds. Use when you are revising and want
structure imposed rather than deciding when to stop.

### Meetings-heavy day

Short focus blocks that fit between commitments. Use when you only have fragments of time and want to
capture them rather than lose them.

## 13. Templates

**Templates** save a task name together with a configuration, so a task you run regularly can be
started without retyping it.

If you have not created any, the screen shows an empty state with a **Create Template** button. Use the
**+** button in the toolbar to add one, and the search field beside it to find one in a long list.

Each row shows the template's icon, its name, the task it starts, and its configuration and session
count. The row's play button starts it; the **…** button holds every other action.

A template's page shows its details, then one prominent **Start**, a secondary **Create Plan**, and a
**Pinned to Quick Start** switch. **Edit** and a **…** menu sit beside the name. **Duplicate** and
**Delete** are grouped separately under **Manage**, so a destructive action never sits beside Start.

Starting a session from a template copies its values into the normal setup screen. The running session
is independent of the template afterwards, so editing the template later does not disturb a session
already in progress.

Each template carries an **icon** you pick when creating or editing it, shown in the list, on the
template's page, and in Quick Start.

**Pin to Quick Start** (the switch on the template's page, or the pin item in its **…** or right-click
menu) puts it in the menu bar and in the Timer screen's Quick Start menu, ready to start in one click.
Renaming a pinned template keeps the pin; deleting it removes it from Quick Start. See section 18.

**When to use it:** you find yourself typing the same task name several times a week.

## 14. Plans

A **Plan** is an ordered list of intervals that you design yourself, and it can mix configurations
within one session. The list shows each plan with a summary such as "3 focus sessions · 1h 40m ·
Updated yesterday", plus its session count, total duration, and configuration — "Custom" when the
plan deliberately mixes them. Search and the **+** button are in the toolbar.

A plan's page shows its details, then every interval it will run with its start offset, then one
prominent **Start**, a secondary **Add to Calendar**, and a **Pinned to Quick Start** switch.
**Edit** and a **…** menu sit beside the name; **Duplicate** and **Delete** are grouped under
**Manage**.

A plan is a planning tool, not a second timer. Starting one runs it through exactly the same timer as
any other session, and freezes its values at that moment, so editing or deleting the plan afterwards
cannot affect a session that is already running or one already recorded.

In History, a session started from a plan that used more than one configuration shows
**Multiple configurations** where a single configuration name would otherwise appear.

Like templates, plans carry an **icon** and can be **pinned to Quick Start**, so a plan you run
weekly is one click away from the menu bar or the Timer screen.

**When to use it:** a session where the pace should change partway through, for example a long focus
block first and shorter ones afterwards.

## 15. Today

**Today** is the calm summary screen. It shows a greeting and the date, a card to start a session if
none is running, and **Today's Focus**: the number of focus sessions and the total focus time for
today.

Only intervals that ran to their planned end are counted. A skipped interval or a session you stopped
early does not add to these numbers.

**When to use it:** a quick check on how the day is going, without reading a list or a chart.

## 16. History

**History** lists your recorded sessions, newest first, grouped under day headings such as "Today" and
"Yesterday".

Each row shows:

- the **task name** you gave the session;
- the **configuration name** it ran under, frozen at the time, or "Multiple configurations" for a
  session built from a plan that mixed several;
- **how many sessions completed and the total focus time**, for example "3 completed sessions, 1h 20m";
- a **status badge**: Completed, Stopped, or an interrupted marker.

**When to use it:** you want to know what you actually ran and how each one ended, rather than a total.

## 17. Statistics

**Statistics** summarises your history over a period you choose from the pop-up menu at the top.

The metric cards are:

| Metric | What it means | Why you might care |
|---|---|---|
| **Focus Time** | Total time in focus intervals that ran to their planned end, with the number of intervals underneath | The headline number: time actually focused, not time the app was open |
| **Sessions** | How many sessions completed, out of how many started | Shows whether you are finishing what you begin |
| **Completion Rate** | Completed sessions as a percentage of started ones | A single measure of follow-through. Shows a dash if nothing was started |
| **Average Focus** | Average length of a completed focus interval | Tells you the size of block you actually sustain, which may differ from what you configure |
| **Break Time** | Total time in completed breaks | Whether you are taking the breaks or skipping them |
| **Longest Session** | The most focus time in any one session | Your best sustained run in the period |
| **Stopped** | Sessions you ended early | High numbers suggest the configuration is too ambitious |
| **Interrupted** | Sessions that could not be resumed | Only shown when there are any |

Below the cards:

- **Focus Trend** compares this period with the previous one, showing both totals, the difference and
  the percentage change.
- **Focus by Configuration** breaks focus time down by the configuration each session ran under, using
  the frozen names, so a renamed or deleted configuration still shows its historical results correctly.
- Charts show focus by day and sessions completed by day.

Statistics is recalculated from your history every time you look at it. Nothing is stored separately,
so it can never disagree with History.

**When to use it:** at the end of a week or month, when you want patterns rather than today's number.

## 18. The menu bar

Time Frame can place an item in the macOS menu bar. It shows the current phase and, if you want, a live
countdown. Clicking it opens a small panel with the session, its controls, and your Quick Start items.

### What the panel shows

**When nothing is running:** the app name, "Ready to focus", your Quick Start items, and a **Start
Timer** button that opens the setup screen.

**While a session runs:** the task and configuration names, the phase, the countdown, the paused
label when paused, the focus progress dots, "Session X of N", the next interval and its length, and
four controls:

| Control | While running | While paused |
|---|---|---|
| First | Pause | Resume |
| Second | Skip | Skip |
| Third | Restart | Restart |
| Fourth | Stop | Stop |

Nothing in the panel scrolls. Three pinned items are shown as rows and are always fully visible; if
you have pinned more, a **"N more…"** menu below them starts any of the rest. The controls therefore
stay in place however many items you pin.

### The gear

The gear in the top-right corner holds the actions you need occasionally, so they do not take space
from the timer:

| Item | What it does |
|---|---|
| Open Time Frame | Brings the main window forward |
| Settings | Opens the main window on Settings |
| History | Opens the main window on History |
| Quit Time Frame | Quits Time Frame |

### Quick Start

Quick Start lists the Templates and Plans you have pinned. Click one to start it immediately —
you do not have to open the main window first. The same list is available from the **Quick Start**
menu in the Timer screen's header.

To pin something, go to its page (Templates or Plans), open the item, and turn on **Pinned to Quick
Start**. You can also use the item's **…** menu in the list, or right-click the row. Both Quick Start
surfaces update straight away; you do not need to restart Time Frame.

Each row shows the item's icon, its name, whether it is a Template or a Plan, and a short summary —
"50 min focus - 10 min break" for a template, "4 focus sessions - 3h 20m" for a plan.

Things worth knowing:

- **Renaming a pinned item keeps it pinned.** The pin follows the item, not its name.
- **Deleting a pinned item removes it from Quick Start.** Nothing is left behind.
- **Editing an item never unpins it.**
- **Duplicating an item copies its icon but not its pin** — the copy starts unpinned.
- If an item's configuration was deleted, it stays in the list but cannot be started, and says why.
- Quick Start items are listed in the order you pinned them, oldest first.

### Icons

Templates and Plans each carry an icon you pick when creating or editing them, from a curated list
grouped into Focus, Study, Work, Wellbeing and General. The icon appears in the item's list row, on
its page, in its editor, and in Quick Start, so you can recognise it at a glance. Every icon also has
a name, which is what VoiceOver reads.

**Closing the main window does not stop your session, and does not quit the app.** As long as Time
Frame is in the menu bar, it keeps running with its session intact. (This was confirmed directly: with
the window closed, the application was still running.)

**When to use the menu bar instead of the main window:** almost always, while you are actually
working. Open the main window to set a session up, to manage configurations, or to look at History and
Statistics. Then close it and use the menu bar to watch the countdown and to pause, resume, skip or
stop, so Time Frame does not take up screen space during the work it is timing.

Both the menu bar item and the countdown inside it can be turned off in Settings.

## 19. Widgets

Time Frame provides a macOS widget for Notification Centre, in small and medium sizes. Add it by
opening Notification Centre, scrolling to the bottom, choosing Edit Widgets, and selecting Time Frame.

A widget can be configured, by right-clicking it and choosing Edit Widget, to show one of three
things:

### Timer widget

Shows the running session: phase, countdown and session position.

**Best for:** checking how long is left without switching to Time Frame at all.

### Today widget

Shows today's focus time and completed sessions.

**Best for:** a progress check during the day.

### Statistics widget

Shows a focus glance with a trend against the previous day.

**Best for:** a longer-term sense of how you are doing, at a glance.

You can also choose where clicking the widget takes you, and whether the countdown is shown.

Widgets update when the session meaningfully changes, not every second, so a short delay is normal and
expected.

## 20. Notifications

Notifications tell you when a focus period or a break begins, and when a session finishes, so you do
not have to watch the countdown.

Turn them on in **Settings**, under Notifications. The first time, macOS asks for permission. Once
granted, you can choose individually:

- Focus sessions start
- Short breaks start
- Long breaks start
- Session completes

And two style options:

- **Sound** — whether notifications make a sound.
- **Action buttons** — whether the notification carries Pause and Skip buttons you can use directly
  from the notification, without switching to the app.

**If you decline permission**, Time Frame says so and offers to open System Settings. **Your timer
always works either way.** Notifications are a convenience layered on top of the session; nothing
about the timer depends on them.

**When to use them:** whenever Time Frame is not visible on screen, which is most of the time if you
are using the menu bar.

## 21. Calendar

Time Frame can mirror your focus sessions into Apple Calendar as events, so your focus time appears
alongside your meetings.

Turn it on in **Settings**, under Calendar. macOS asks for calendar access separately; until you grant
it, Settings shows "Calendar access is required to create and update Time Frame events" with an
**Allow Calendar Access** button, and the Timer screen shows a quiet "Calendar access needed" line.

As with notifications, this is optional and isolated: **the timer always works even if Calendar is off,
unavailable, or fails.**

**When to use it:** you share a calendar with colleagues and want your focus blocks to be visible, or
you want a record of your day in one place.

## 22. Settings

Settings has eight sections.

**General — Open at Login**
What it does: registers Time Frame as a macOS login item, so it opens automatically when you log in
to your Mac. Turning it off removes the login item.
When to change it: turn it on if you want your timer, menu bar item and widgets available from the
moment you sit down.
What the switch means: it shows what macOS actually holds, not what Time Frame remembers. If the
registration is refused, the switch stays **off** and the reason appears underneath. If macOS wants
you to approve the item first, the switch reads off and an **Open Login Items Settings** button
appears — the item will not launch until you allow it there. You can also change it directly in
System Settings ▸ General ▸ Login Items & Extensions; Time Frame picks that up the next time you
open Settings.

**Default Configuration**
What it does: chooses which configuration new sessions start from.
When to change it: when your usual working style changes.

**Calendar Integration**
What it does: turns calendar mirroring on or off, and requests calendar access.
When to change it: turn it on if you want focus sessions in your calendar. Leave it off otherwise;
nothing else depends on it.

**Notifications**
What it does: the master switch for notifications. When on and authorised, it reveals which events to
be notified about, plus the Sound and Action buttons options.
When to change it: turn it on if you work with the window closed.

**Show in Menu Bar**
What it does: shows or hides the Time Frame status item.
When to change it: leave it on unless you keep a very sparse menu bar. Note that the menu bar item is
what keeps the app running when the window is closed.

**Show countdown in menu bar**
What it does: shows the remaining time next to the status icon, rather than the phase alone.
When to change it: turn it off if you find a visible countdown distracting, while still keeping the
controls.

**iCloud Sync**
What it does: intended to sync configurations, templates, plans and history between devices. It shows
a **Status** line and an **iCloud Account** line, and notes that changes take effect the next time you
open Time Frame.
When to change it: **there is currently no reason to.** Status reads **Unavailable** in this build even
when an iCloud account is available, because the app is not provisioned for iCloud. See
[Data and privacy](#27-data-and-privacy).

**Keyboard Shortcuts**
A read-only reference list. See the next section.

**About**
The application name and version.

## 23. Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Start session | Command-Return |
| Pause / Resume | Space |
| Stop session | Escape |
| Restart interval | R |
| Skip interval | Right Arrow |
| New template / plan / configuration (on that screen) | Command-N |
| Edit the open template or plan | Command-E |
| Start the open template or plan | Command-Return |

These are listed inside the app under Settings, Keyboard Shortcuts.

## 24. A workday with Time Frame

**Before you start**
Open Time Frame. If today needs a different rhythm from usual, pick a different configuration, or
create one in Configurations.

**Setting up the first session**
On the Timer screen, type the task, choose the configuration, and set how many focus sessions you want
this time. Glance at the Session Plan so you know what you have committed to.

**During focus**
Start the session and close the main window. Watch the countdown in the menu bar. If you are
interrupted, press Space to pause and Space again to come back.

**During the break**
Let it run. Time Frame moves into the break by itself and back into focus when the break ends. If you
would rather return early, press Skip.

**Partway through the day**
Open Today for a two-number check on progress.

**When something changes**
If a session no longer matches what you are doing, Stop it and start a new one with the right task
name. Stopping keeps what you completed.

**End of the day**
Open History to see the sessions you ran and how each ended.

**End of the week**
Open Statistics, switch the period to the week, and look at the completion rate and the trend rather
than the raw total. If Stopped is high, the configuration is probably too ambitious; try a shorter
focus duration.

## 25. Troubleshooting

**The countdown does not appear to be updating.**
Time Frame works out the remaining time from real clock times, so the displayed value is correct even
if a redraw is late. Switch to another app and back, or open the menu bar item, to force a repaint. If
the window is genuinely unresponsive, quit and reopen; your session is restored from its recorded
timeline.

**Pause or another control does nothing.**
Make sure the Time Frame window is focused, since Space, Escape, R and Right Arrow are keyboard
shortcuts that need focus. If a control still does nothing, use the menu bar panel, which routes to
the same session.

**Notifications are not arriving.**
Check three things in order. First, in Time Frame's Settings, that Notifications is on and the specific
event is enabled. Second, that you granted permission when macOS asked; if you declined, Settings shows
that and offers to open System Settings. Third, whether a Focus mode is filtering them. Time Frame's
notifications are ordinary notifications and respect Do Not Disturb.

**The widget is not updating.**
Widgets refresh when the session meaningfully changes, not every second, so a short delay is normal. If
it never updates, open Time Frame once; the widget reads a summary that the app publishes.

**A configuration has disappeared.**
Configurations are only removed when you delete them. Deleting one does not delete the sessions you ran
with it. Those sessions keep the name they had at the time and still appear in History and Statistics.

**I quit the app during a session.**
Open it again. If the session can be safely restored it resumes, fast-forwarded through any intervals
that ended while the app was closed. If it cannot be restored, it is marked interrupted, kept in
History, and Time Frame shows a calm notice rather than losing it.

**My Mac went to sleep during a session.**
The session reconciles the moment the Mac wakes and shows the true remaining time. If intervals ended
while it was asleep, Time Frame catches up through them.

**I closed the window and thought I had quit.**
Closing the window does not quit Time Frame while the menu bar item is enabled. That is what keeps your
session running. Quit from the menu bar or with Command-Q if you really want to stop the app.

**Calendar events are not being created.**
Settings will show whether calendar access has been granted. Until it is, the Timer screen shows
"Calendar access needed". Grant access with the Allow Calendar Access button.

**iCloud says Unavailable.**
That is expected in this build. See [Data and privacy](#27-data-and-privacy).

### Clicking the Dock icon does not bring the window back

If Time Frame is running with no window — you closed it and the menu bar kept it alive — a Dock click
creates the window again. If the window is minimized, or Time Frame is hidden, the same click
restores and focuses the one you already have. You will never end up with two.

### Time Frame quit when I closed the window

It should not. Closing the window leaves the app running in the menu bar. If Time Frame is not in
your menu bar, check Settings ▸ Show in Menu Bar — the status item is what keeps the app running with
the window closed.

### Open at Login shows off after I turned it on

The switch reflects what macOS actually holds. Either the registration was refused — the reason
appears under the toggle — or macOS is waiting for you to approve the item, in which case Time Frame
offers **Open Login Items Settings**. Until you allow it there, it will not launch at login, so the
switch does not claim that it will.

## 26. Accessibility

- **VoiceOver.** The countdown, phase, controls, progress and statistics carry explicit labels and
  values. The countdown is marked as frequently updating, so VoiceOver does not interrupt every second.
  Statistics and Today figures are grouped so each card reads as a single item.
- **Keyboard.** Every timer control has a keyboard shortcut, listed in
  [Keyboard shortcuts](#23-keyboard-shortcuts), so a session can be run without the mouse.
- **State is never colour alone.** Paused shows an explicit "Paused" label beside its icon, and each
  phase is named in text as well as tinted.
- **Dynamic Type.** Layouts use text styles rather than fixed sizes.
- **Reduce Motion.** Animations go through a Reduce Motion-aware path.

Verification note: this is verified from the source, from automated accessibility-text tests, and from
inspecting the running application. It has **not** been validated by using VoiceOver.

## 27. Data and privacy

**What is stored.** Your configurations, templates, plans, and the history of your sessions and their
intervals.

**Where.** Locally on your Mac, in the application's own database. There is no Time Frame account, no
analytics, no tracking, and no server that your focus data is sent to. Time Frame works entirely
offline.

**What widgets can see.** Widgets run separately from the app and cannot read its database. The app
publishes a small summary — the current phase, the interval's start and end times, and today's totals —
into a shared container that the widget reads. It contains no personal content beyond your task and
configuration names.

**Notifications** are scheduled locally through macOS. Nothing is sent anywhere.

**Calendar.** If you turn Calendar integration on, Time Frame creates events in the calendar you
choose, using your task names. That data goes wherever your calendar already syncs. It is off until you
enable it and grant access.

**iCloud sync is currently disabled.** The Settings screen shows Status: **Unavailable**, even when the
iCloud Account line reads Available. The application is built with a personal Apple developer team,
which cannot provision the iCloud capability, so the entitlement is deliberately absent and no cloud
container is used. Your data stays on this Mac. Cross-device sync has never been enabled or verified.

## 28. FAQ

**What is the difference between Focus and a break?**
Focus is the working interval and the only kind that counts toward your focus totals. Breaks are rest
intervals between focus intervals; short ones between each, a long one after several.

**Can I pause a timer?**
Yes, with the Pause button or the Space bar. The countdown freezes and no time passes while paused.

**Can I create multiple configurations?**
Yes, as many as you like, in Configurations. One is marked as the default for new sessions.

**What happens when I stop?**
The session ends. What you completed is kept, the interval you were in is recorded as cancelled, and
the session stays in History with a Stopped badge. Nothing is deleted.

**Where do I see today's sessions?**
Today for the totals; History for the individual sessions.

**What is the difference between Today and Statistics?**
Today is two numbers for the current day. Statistics covers a period you choose and adds completion
rate, averages, a trend against the previous period, and a per-configuration breakdown.

**Can I control Time Frame from the menu bar?**
Yes. The status item shows the phase and optionally the countdown, and its panel has the controls.

**Do widgets run their own timer?**
No. A widget displays the session that the app is running, or takes you to it.

**What happens when my Mac sleeps?**
Nothing is lost. On wake, Time Frame reconciles against the real clock and shows the true remaining
time, catching up through any intervals that ended while it was asleep.

**Does Time Frame sync through iCloud?**
No. Sync is disabled in this build.

**What happens if notifications are disabled?**
The timer runs exactly as normal. You simply are not told when intervals change.

**Do skipped intervals count toward my focus time?**
No. Only intervals that ran to their planned end count.

**Does closing the window stop my session?**
No, as long as the menu bar item is enabled. The app keeps running with the session intact.

## 29. Known limitations

**Verified limitations of the product**

- iCloud sync is disabled; Settings reports it as Unavailable and no data leaves the Mac.
- Live Activities and Control Center controls are not available on macOS. Apple does not offer
  ActivityKit or Control Center widgets to native Mac applications; those features exist in the iPhone
  and iPad app.
- Configurations must be created on macOS. The iPhone and iPad app can choose an existing configuration
  but cannot create or edit one.

**Limitations of the environment this guide was written in**

- No macOS screenshots could be captured. Screen capture requires a permission the documentation
  tooling does not have. Every screen was inspected in the running application instead. See the
  [screenshot inventory](assets/screenshots/macos/README.md).
- The menu bar item could not be inspected visually, because a third-party menu bar manager on the test
  Mac had collapsed it. Its behaviour is documented from the source and from Settings.

**Not validated**

- VoiceOver has not been used to validate the accessibility support described above.
- Notification banner delivery and calendar event creation were not exercised end to end; both require
  permissions that were not granted during this pass.

## 30. Feature reference

| Feature | Purpose | Best used when |
|---|---|---|
| **Timer** | Set up and run a focus session | Always. It is the only place a session starts. |
| **Configurations** | Saved focus and break durations | You want to change how long intervals last, or keep several working styles |
| **Templates** | A saved task name plus its configuration | You run the same named task regularly |
| **Plans** | An ordered, possibly mixed-configuration session | The pace should change partway through a session |
| **Today** | Today's focus sessions and focus time | A quick progress check |
| **History** | Every recorded session and how it ended | You want to see what you actually ran |
| **Statistics** | Totals, completion rate, averages, trend | Reviewing a week or a month |
| **Menu bar** | Countdown and controls without the window | While you are actually working |
| **Widgets** | A read-only glance from Notification Centre | You want the state visible without opening anything |
| **Notifications** | Alerts at interval boundaries | Time Frame is not visible on screen |
| **Calendar** | Focus sessions mirrored into Apple Calendar | You want focus time visible alongside meetings |
| **Settings** | Defaults, integrations, shortcuts | Setting things up once, then rarely |

---

Technical details of how any of this works are in the
[Developer Overview](36-DEVELOPER-OVERVIEW.md) and the
[Architecture documentation](01-ARCHITECTURE.md). For the iPhone and iPad app, see the
[cross-platform User Guide](35-USER-GUIDE.md).

---

## 31. Windows, the Dock, and opening at login

### One window

Time Frame uses a **single main application window**. Opening Time Frame from the Dock, the menu
bar, or anywhere else focuses the window you already have instead of creating another one. There is
no New Window command, because a second window is not something the app can produce.

| What you do | What happens |
|---|---|
| Click the Dock icon while Time Frame is running | The existing window comes to the front and becomes active |
| Click the Dock icon while the window is minimized | The window is restored from the Dock and focused |
| Click the Dock icon while Time Frame is hidden (⌘H) | Time Frame is unhidden and the window focused |
| Menu bar ▸ gear ▸ Open Time Frame | The existing window comes forward |
| Menu bar ▸ gear ▸ Settings or History | That same window comes forward, on that screen |
| Do any of these repeatedly | Still exactly one window |
| Close the window (⌘W or the red button) | The window closes. Time Frame keeps running in the menu bar, and a running session keeps running |
| Open Time Frame again afterwards | A new main window is created |

Bringing the window forward uses ordinary macOS activation, so it looks like focusing any other
window. It does **not** change your sidebar selection (unless you asked for Settings or History), your
scroll position, or anything you had typed — and it never restarts, resets or duplicates a running
Pomodoro.

### If you close the window

Time Frame does not quit. The menu bar item keeps the app — and your session — alive, which is the
point of having it. To quit, use ⌘Q or the gear menu's **Quit Time Frame**.

If you have also turned the menu bar off in Settings, the Dock icon is your only way back to the
window. That is worth knowing before you hide both.

### Opening at login

Settings ▸ General ▸ **Open at Login**. See [Settings](#22-settings) for what the switch means when
macOS refuses or wants approval.

Time Frame opens normally when it launches at login: one window, your library, and the menu bar item
if you have it enabled. It does not start a session by itself.
