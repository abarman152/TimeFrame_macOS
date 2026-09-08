//
//  MenuBarQuickStartView.swift
//  time_frame (Milestone 28; layout revised in Milestone 29)
//
//  The Quick Start section of the popover: the user's pinned Templates and Plans, each
//  startable in one click (ADR-104).
//
//  It renders a pure `[QuickStartItem]` projection and routes a start through
//  `QuickStartCoordinator` → `AppIntentSessionActions` → `SessionCoordinator` — the same
//  single mutation seam the widget controls and Siri use. It owns no timer, no clock, and no
//  storage; the list is rebuilt from the authoritative repositories whenever they change.
//
//  ## Layout rule (Milestone 29, ADR-107)
//  The focus-item list does **not** scroll. A menu-bar popover is a glance-and-go surface: a
//  scroll view there is slow to hit, hides its own contents, and turns the popover into a
//  miniature of the app. So the section shows at most `visibleLimit` pinned items — always
//  fully visible, never clipped — and any remaining pins are reachable through a compact
//  "More" menu that starts them directly. Nothing is lost and nothing scrolls.
//

import SwiftUI

struct MenuBarQuickStartView: View {
    let quickStart: QuickStartCoordinator

    /// The most pinned items the popover will ever lay out as rows. Beyond this, the rest are
    /// offered by the "More" menu rather than by making the section scroll.
    static let visibleLimit = 3

    /// The rows that are drawn, and the overflow that goes into the More menu.
    private var visibleItems: [QuickStartItem] {
        Array(quickStart.items.prefix(Self.visibleLimit))
    }

    private var overflowItems: [QuickStartItem] {
        Array(quickStart.items.dropFirst(Self.visibleLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            sectionHeader

            if quickStart.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(visibleItems) { item in
                        MenuBarQuickStartRowView(item: item,
                                                 isEnabled: quickStart.canStart && item.isStartable,
                                                 action: { quickStart.start(item) })
                    }
                }
                .accessibilityIdentifier("timeFrame.menuBar.quickStart.list")

                if !overflowItems.isEmpty {
                    moreMenu
                }
            }

            if let message = quickStart.lastErrorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("timeFrame.menuBar.quickStart.error")
            }
        }
        .accessibilityIdentifier("timeFrame.menuBar.quickStart")
        // A failure message belongs to the interaction that produced it, not to the surface.
        .onAppear { quickStart.clearError() }
    }

    // MARK: Header

    private var sectionHeader: some View {
        HStack(spacing: TFSpacing.xs) {
            Text("Quick Start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            Spacer(minLength: TFSpacing.s)
            if !quickStart.isEmpty {
                // "Pinned · N" is stated in words as well as the pin glyph, so the count is
                // never carried by an icon alone.
                HStack(spacing: 4) {
                    Text("Pinned")
                    Image(systemName: "pin.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text("\(quickStart.items.count)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(quickStart.items.count) pinned")
            }
        }
    }

    // MARK: Overflow

    /// The remaining pins, reachable in one click without the section ever scrolling.
    private var moreMenu: some View {
        Menu {
            ForEach(overflowItems) { item in
                Button {
                    quickStart.start(item)
                } label: {
                    Label(item.displayName, systemImage: item.icon.symbolName)
                }
                .disabled(!quickStart.canStart || !item.isStartable)
                .help(item.unavailableReason ?? item.subtitle)
            }
        } label: {
            Text("\(overflowItems.count) more…")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("\(overflowItems.count) more pinned items")
        .accessibilityHint("Starts one of your other pinned templates or plans")
        .accessibilityIdentifier("timeFrame.menuBar.quickStart.more")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            Text("Pin a template or plan to start it from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: TFSpacing.s) {
                pinDestination("Templates", section: .templates)
                pinDestination("Plans", section: .plans)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("timeFrame.menuBar.quickStart.empty")
    }

    private func pinDestination(_ title: String, section: AppSection) -> some View {
        MenuBarOpenSectionButton(title: title, section: section)
    }
}
