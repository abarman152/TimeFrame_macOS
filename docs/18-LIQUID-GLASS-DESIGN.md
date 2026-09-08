# 18 — macOS 27 Liquid Glass Visual Identity (Milestone 9)

Time Frame's visual identity. This milestone is **presentation-only**: it changes how the
app looks, not what it does. The `TimerEngine`, `SessionCoordinator`, `SessionLifecycleEvent`
seam, SwiftData schema (**V5**), and the Calendar / Notification / Menu Bar architectures are
unchanged. See `docs/12-CORE-UI.md` for the screens themselves and `DECISIONS.md` (ADR-050–053)
for the governing decisions.

## Visual principles

Time Frame should feel **calm, focused, minimal, premium, native, and quiet**. The UI
communicates *focus*, not "productivity dashboard." Concretely:

- The **countdown is the centrepiece**; everything else is secondary to it.
- **Glass establishes hierarchy** — it marks controls and important surfaces, and is used
  sparingly. Ordinary content stays visually quiet.
- **No decoration for its own sake**: no full-screen gradients, image/animated backgrounds,
  neon colours, confetti, or per-second animation.

## Component architecture

```
Support/DesignSystem/           ← tokens + glass vocabulary (imports no domain)
  TimeFrameDesign.swift         ← TFSpacing, TFRadius, TFMotion, TFPalette, tfAnimation
  TimeFrameGlass.swift          ← tfGlassSurface (glass), tfQuietSurface (quiet)
        │
        ▼
Views/…                         ← screens compose the tokens + native glass APIs
```

The design system is a leaf: views depend on it; it depends on nothing in `Timer/`,
`Services/`, or `Models/`. This is what keeps the milestone presentation-only (ADR-050).

## Liquid Glass usage

The app targets **macOS 27 only**, so the native APIs are used directly with **no availability
fallback** (per CLAUDE.md). Verified present in the installed SDK (`SwiftUICore`):
`glassEffect(_:in:)`, `GlassEffectContainer`, `Glass.regular/.clear` with `.tint(_:)` /
`.interactive(_:)`, `glassEffectID`/`glassEffectUnion`/`glassEffectTransition`, and the button
styles `.glass` / `.glassProminent`.

### Where glass IS used (floating / interactive / primary)

| Surface | Treatment |
|---|---|
| Timer transport (Pause/Resume/Stop/Restart/Skip) | `GlassEffectContainer` of `.glassProminent` (dominant) + `.glass` (secondary) |
| Setup **Start**, Completion **Start New Session**, detail **Start**, editor **Save**, empty-state CTA | `.glassProminent` — one dominant action per surface |
| Today "current session" card | `tfGlassSurface` |
| Completion summary metrics | `tfGlassSurface` |
| Menu-bar transport buttons | `GlassEffectContainer` of `.glassProminent` + `.glass` |

### Where glass is deliberately NOT used (quiet content)

- List rows (Templates / Plans / Configurations / History) — native `List`, no per-row glass.
- Summary/detail cards, the setup & plan **timeline previews** — `tfQuietSurface` (a subtle
  system fill, not glass).
- The menu-bar **popover panel** — keeps the system `MenuBarExtra(.window)` background; the
  glass buttons sit on it without an extra nested glass surface (avoids glass-on-glass).
- Recovery / incomplete banners — a tinted rounded fill, not glass.

`GlassEffectContainer` groups sibling glass so they share one sampling region (glass cannot
sample glass); containers are **not** nested (ADR-051).

## Design tokens

- **Spacing** — `TFSpacing.xs/s/m/l/xl/xxl/xxxl` (4→36) plus `contentColumn` (560pt max reading
  width), so content columns stay centred and calm on wide windows.
- **Radius** — `TFRadius.small/medium/large/xLarge` (8→22); one consistent corner language.
- **Motion** — `TFMotion.state/phase/control`; see Animation below.

## Colour system

`TFPalette` is the single source of semantic colour — **system colours and the app accent
only, never hard-coded RGB** — so it adapts to Light/Dark and accessibility automatically:

| Token | Role | Value |
|---|---|---|
| `focus` | subtle focus identity | accent |
| `shortBreak` / `longBreak` | distinct but related breaks | teal / indigo |
| `running` / `paused` | live / frozen | green / orange |
| `completed` | finished | accent |
| `warning` / `destructive` | caution / destructive | yellow / red |

`StatusPresentation` routes its phase/status tints through `TFPalette` (ADR-052). Focus carries
a subtle accent identity — it never floods the screen.

## Typography

Centralised where it matters:

- **Countdown** — `.system(size: 88, weight: .semibold, design: .rounded)`, monospaced digits,
  high contrast. (Menu bar: 44pt, same family.)
- **Phase** — small, **uppercase**, kerned, phase-tinted label.
- **Task** — `.title`, prominent but secondary to the countdown.
- **Supporting metadata** — `.subheadline` / `.caption`, secondary foreground.
- **Controls** — native button typography via `.glass` / `.glassProminent`.

## Animation & Reduce Motion

Animation is centralised in `TFMotion` and applied through `tfAnimation(_:value:)`, which reads
`@Environment(\.accessibilityReduceMotion)` and **disables decorative animation** when Reduce
Motion is on (the underlying state change still happens instantly). Rules:

- Animations key on **discrete state** (phase change, paused) — never on the per-second
  countdown.
- The countdown uses `contentTransition(.numericText())` over an engine-derived value inside a
  **repaint-only** `TimelineView`; it is never scale/opacity/layout-animated each second.
- No new `Timer` / `Task.sleep` / `asyncAfter` / counter decrement was introduced (ADR-053, §96).

## Menu-bar visual treatment

Same design system, kept compact (264pt): a phase-tinted uppercase phase label, the rounded
44pt countdown, focus dots + "Session X of N", and glass transport buttons in a
`GlassEffectContainer`. **Behaviour, projection semantics, control routing, and preferences are
unchanged** (ADR-045–049).

## Light / Dark mode & contrast

No hard-coded black/white backgrounds; every colour is a system colour, material, or `TFPalette`
token, so both appearances and increased-contrast settings are handled by the system. Glass and
quiet surfaces both read correctly in Light and Dark.

## Accessibility

- The spec's `timeFrame.timer.*` identifiers were added (`countdown`, `phase`, `start`, `pause`,
  `resume`, `stop`, `restart`, `skip`, `startNew`); all pre-existing identifiers are preserved
  unchanged (§43).
- State is always conveyed by **label/icon + colour**, never colour alone (Paused, phases,
  statuses) — legible to colour-blind users (§48).
- The countdown keeps its VoiceOver label + spoken value; controls keep native semantics.
- `contentColumn` + native layout keep long task/configuration names and large text sizes from
  clipping.

## Performance

Glass is confined to small control regions and a couple of cards — no large blur regions, no
nested materials, no continuous animation loops. The timer stays lightweight: no SwiftData fetch,
Calendar sync, or notification scheduling on a repaint; `TimelineView` schedules ~1 Hz redraws
only while running (frozen when paused/idle).

## What was deliberately NOT converted to glass

Ordinary content — list rows, summary/detail cards, timeline previews, form fields, recovery
banners, statistics metric cards and charts, and the menu-bar panel background — stays quiet on
purpose. Over-glassing would flatten hierarchy, hurt readability, and cost performance (§8/§58).
Glass is a signal; keeping it rare keeps it meaningful.

## Later reuse (Milestone 10 — Statistics)

The Statistics dashboard (`Views/Statistics/`) **reuses this system unchanged**: `TFSpacing`/
`TFRadius` tokens, the `TFPalette` semantic colours for charts (always paired with text/labels,
never colour-only), `tfQuietSurface` for metric and chart cards, the prominent glass **Start
Timer** button on the new-user empty state, and the Reduce-Motion-aware `tfAnimation`. No new
visual language was introduced, and no design-system file changed for statistics. See
`docs/19-STATISTICS.md`.
