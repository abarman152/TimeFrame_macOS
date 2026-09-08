//
//  TimeFrameDesign.swift
//  time_frame
//
//  The visual design tokens for Time Frame's macOS 27 Liquid Glass identity
//  (Milestone 9; ADR-050/051/052/053). This is a *presentation-only* system: it
//  defines spacing, corner radii, motion, semantic colour, and typography so every
//  screen speaks the same visual language. It contains no timer, persistence, or
//  session logic and imports none of the domain — the design system can never
//  change how the engine behaves (ADR-050). Keep additions here small and shared;
//  do not scatter ad-hoc constants through the views.
//

import SwiftUI

// MARK: - Spacing

/// The shared spacing scale. Views compose these instead of hard-coding numbers so
/// rhythm stays consistent across every screen (§79).
enum TFSpacing {
    /// 4 — hairline gaps inside a tightly-related pair (icon ↔ label).
    static let xs: CGFloat = 4
    /// 8 — related elements within a group.
    static let s: CGFloat = 8
    /// 12 — standard control spacing.
    static let m: CGFloat = 12
    /// 16 — card interior padding / grouped rows.
    static let l: CGFloat = 16
    /// 20 — spacing between stacked sections.
    static let xl: CGFloat = 20
    /// 28 — outer screen padding for content columns.
    static let xxl: CGFloat = 28
    /// 36 — generous breathing room around the timer centrepiece.
    static let xxxl: CGFloat = 36

    /// The maximum width of a centred reading/content column, so wide windows keep
    /// the focus content calm and centred rather than stretched (§71).
    static let contentColumn: CGFloat = 560

    /// A wider column for list/detail screens that carry rows with a trailing value
    /// (Templates, Plans, Configurations, History). Wide enough to breathe on a large
    /// display, narrow enough that a row never becomes a stretched web table (§71).
    static let wideColumn: CGFloat = 720

    /// The height of a compact row's icon container, shared by every leading icon tile so
    /// the icon column aligns across screens.
    static let iconTile: CGFloat = 34
}

// MARK: - Corner radii

/// The shared corner-radius language. A small number of consistent radii keeps the
/// "corner language" coherent (§79) and lets glass and quiet surfaces align.
enum TFRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    /// For the largest floating glass surfaces (timer control group, popover).
    static let xLarge: CGFloat = 22
    /// The rounded-square container behind a leading icon.
    static let tile: CGFloat = 9
}

// MARK: - Semantic colour

/// The single source of semantic colour for the app. Values are system colours and
/// the app accent — never hard-coded RGB (§10) — so they adapt to Light/Dark mode
/// and accessibility settings automatically. Essential state is always paired with a
/// label/icon as well, so colour is never the sole carrier of meaning (§48).
enum TFPalette {
    /// Focus has a subtle identity built on the app accent; it should not dominate
    /// the screen (§11).
    static let focus = Color.accentColor
    /// Short break — distinct from focus but part of the same system (§12).
    static let shortBreak = Color.teal
    /// Long break — distinct again, still within the family (§12).
    static let longBreak = Color.indigo
    /// A running (in-progress) accent, used sparingly alongside a label.
    static let running = Color.green
    /// Paused — always paired with a "Paused" label/icon (§17/§48).
    static let paused = Color.orange
    /// A finished, rewarding-but-restrained accent (§18).
    static let completed = Color.accentColor
    /// A non-blocking caution accent (interrupted recovery, warnings).
    static let warning = Color.yellow
    /// The native destructive treatment tint.
    static let destructive = Color.red
}

// MARK: - Motion

/// The shared animation vocabulary. Animations are presentation-only and never
/// participate in timer correctness (ADR-053); the timer's remaining time is always
/// derived from the engine, never from an animation's progress (§39/§95). Apply
/// these via `tfAnimation(_:value:)` so they automatically yield to Reduce Motion.
enum TFMotion {
    /// A calm transition for state changes (idle → running, running → complete).
    static let state: Animation = .smooth(duration: 0.35)
    /// A subtle transition for phase changes (Focus → Break); never keyed on the
    /// per-second countdown (§40).
    static let phase: Animation = .smooth(duration: 0.45)
    /// A quick response for control/selection feedback.
    static let control: Animation = .snappy(duration: 0.2)
}

extension View {
    /// Applies an animation that automatically disables itself under Reduce Motion,
    /// while the underlying state change still happens instantly (§41). Use this in
    /// place of `.animation(_:value:)` for every decorative transition so motion
    /// accessibility is handled in one place.
    func tfAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(TFAnimationModifier(animation: animation, value: value))
    }
}

private struct TFAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Typography

/// The app's type scale (Milestone 30; ADR-108).
///
/// Every screen used to reach for `.largeTitle.weight(.bold)`, `.headline`, `.subheadline`
/// and `.caption` directly, which meant the hierarchy was a convention held in sixty files
/// rather than a decision recorded in one. The roles below name the six levels the product
/// actually uses, so a change to "what a section title looks like" is one edit here.
///
/// These are native system fonts throughout — no custom faces, no arbitrary point sizes — so
/// they respond to the user's text-size and accessibility settings (§24/§48).
enum TFTypography {
    /// The screen's name: "Timer", "Templates", "Plans". One per screen.
    static let pageTitle: Font = .largeTitle.weight(.bold)
    /// A detail page's subject (a template's or plan's own name), which sits under the
    /// screen's navigation title rather than replacing it.
    static let subjectTitle: Font = .title.weight(.bold)
    /// A group heading inside a page: "Task", "Configuration", "Session Plan", "Manage".
    static let sectionTitle: Font = .headline
    /// The leading text of a row — a template's name, a configuration's name.
    static let rowTitle: Font = .headline
    /// Ordinary reading text and text-field content.
    static let body: Font = .body
    /// Supporting text that qualifies a title: a page's one-line explanation, a row's
    /// subtitle. Rendered `.secondary`.
    static let secondary: Font = .subheadline
    /// Small supporting detail: a row's metrics line, a caption under a section heading.
    /// Rendered `.secondary`.
    static let metadata: Font = .caption
    /// A numeric value that must not jitter as it changes (a countdown, a stepper's count,
    /// a metric). Monospaced digits, never a monospaced face.
    static let numericValue: Font = .body.monospacedDigit()
    /// The heading of a grouped card or a quiet group ("Template Details", "Manage"). Quieter
    /// than a section title because the card's border already separates it from the page.
    static let groupTitle: Font = .subheadline.weight(.semibold)
    /// The leading label of a row inside a grouped detail card ("Task", "Configuration").
    static let rowLabel: Font = .subheadline
    /// The trailing value of a row inside a grouped detail card.
    static let rowValue: Font = .subheadline.weight(.medium)
}

// MARK: - Control metrics

/// The app's control-size rule (Milestone 30; ADR-108).
///
/// macOS actions are sized to their content and sit at the natural control height; a
/// full-width filled slab is a phone convention, and using it for "Start" made the Timer
/// screen read as a web form with a submit button (§22). The rule the app now follows:
///
///   • a screen has **exactly one** prominent action, and it is sized to its content;
///   • supporting actions are bordered and sized to their content;
///   • only a surface that is genuinely as wide as its container — the menu-bar popover's
///     single fallback action — spans its width, and it says so explicitly.
///
/// `minimumWidth` gives the prominent action enough presence to read as primary without
/// stretching; it is a floor, not a fixed width, so a longer title still fits.
enum TFControl {
    /// The floor width of a screen's one prominent action.
    static let primaryMinimumWidth: CGFloat = 108
    /// The control size every page-level action uses. `.regular` is the native macOS
    /// height; `.large` was making ordinary actions read as banners.
    static let actionSize: ControlSize = .regular
}

extension View {
    /// The app's one prominent action treatment: filled, content-sized, with a sensible
    /// floor width. Use this instead of hand-rolling `.glassProminent` + a frame, so the
    /// "one compact primary action" rule lives in a single place.
    ///
    /// Deliberately does **not** offer a full-width variant: a control that should span its
    /// container states that at the call site, and only the menu-bar popover's fallback does.
    func tfPrimaryAction(minimumWidth: CGFloat = TFControl.primaryMinimumWidth) -> some View {
        self
            .frame(minWidth: minimumWidth)
            // `minWidth` alone is still *flexible upward*: in an `HStack` the control would
            // share the leftover width with its siblings and stretch, which is the very slab
            // this rule exists to prevent. `fixedSize` pins the horizontal axis to the ideal
            // width, so the frame's minimum becomes a floor rather than a starting point.
            .fixedSize(horizontal: true, vertical: false)
            .controlSize(TFControl.actionSize)
    }

    /// A supporting action: bordered, content-sized, at the same height as the prominent
    /// one so a row of actions shares a baseline.
    func tfSecondaryAction() -> some View {
        self
            .fixedSize(horizontal: true, vertical: false)
            .controlSize(TFControl.actionSize)
    }
}
