//
//  PlanDetailView.swift
//  time_frame
//
//  A single plan's detail: a summary, the interval timeline, and the page's actions. Start
//  freezes the plan into an execution snapshot and runs it through the existing
//  `SessionCoordinator` — it never builds a `FocusSession` here (ADR-028). Deleting a plan
//  never touches historical or running sessions (ADR-029).
//
//  ## Milestone 29 — the Edit fix (ADR-106)
//  Editing used to be delegated to `PlanListView` via an `onEdit` closure, whose
//  `.sheet(item:)` is attached to the `NavigationStack`. On macOS a sheet requested from the
//  stack's ROOT while a `navigationDestination` is pushed is not presented — it is held until
//  the stack pops back, so "Edit" here looked dead and the editor then appeared unexpectedly
//  over the list. This page now presents its own editor, from its own state, in the view that
//  is on screen. It is the SAME `PlanEditorView` saving through the SAME
//  `SessionPlanRepository.update`, so the plan keeps its identity, its items, and its pin.
//
//  ## Milestone 29 — action hierarchy
//  One prominent action (Start); Add to Calendar is a bordered secondary; pinning is a switch;
//  Edit and the overflow menu sit with the title; Duplicate and Delete live in a quieter
//  "Manage" group, where Delete is the page's only red control.
//

import SwiftUI

struct PlanDetailView: View {
    let coordinator: SessionCoordinator
    let calendarCoordinator: CalendarCoordinator
    let plan: SessionPlan
    /// Called after a session was successfully started, to switch to the Timer.
    let onStarted: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// The editor sheet is owned HERE, by the view that is on screen when Edit is pressed.
    @State private var editingPlan: SessionPlan?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @State private var activeSessionBlocked = false
    @State private var showingCalendarSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                header
                TFDetailCard(title: "Plan Details", rows: detailRows)
                if !plan.isStartable {
                    TFNoticeBanner(message: "A focus interval lost its configuration. Edit the plan and choose a configuration before starting.")
                }

                VStack(alignment: .leading, spacing: TFSpacing.s) {
                    TFSectionHeader(title: "Sessions",
                                    caption: "Every interval this plan will run, in order.")
                    PlanPreviewView(snapshot: plan.executionSnapshot)
                }

                actions
                Divider().padding(.vertical, TFSpacing.xs)
                TFManageSection(
                    duplicate: duplicate,
                    delete: { confirmingDelete = true },
                    duplicateIdentifier: "plan.detail.duplicate",
                    deleteIdentifier: "plan.detail.delete",
                    itemDescription: planName
                )
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(planName)
        .sheet(item: $editingPlan) { target in
            PlanEditorView(coordinator: coordinator, existing: target)
        }
        .alert("Couldn't Start Session", isPresented: $activeSessionBlocked) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A session is already active. Stop it before starting a new one.")
        }
        .alert("Plan Error",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete \(planName)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Plan", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the plan only. Any session you've started from it, your History, and any calendar events, are not affected.")
        }
        .sheet(isPresented: $showingCalendarSheet) {
            CalendarEventPreviewView(calendarCoordinator: calendarCoordinator, plan: plan)
        }
    }

    private var planName: String { plan.name.isEmpty ? "Untitled Plan" : plan.name }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: TFSpacing.m) {
            TimeFrameIconTile(icon: plan.icon, size: .large)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TFSpacing.s) {
                    Text(planName)
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    if plan.isPinned { QuickStartPinnedMarker() }
                }
                Text(plan.taskName.isEmpty ? "No task" : plan.taskName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: TFSpacing.m)

            HStack(spacing: TFSpacing.s) {
                Button { editingPlan = plan } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Edit \(planName)")
                .accessibilityHint("Opens the plan editor")
                .accessibilityIdentifier("plan.detail.edit")
                .help("Edit this plan (Command-E)")

                Menu {
                    overflowMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions")
                .accessibilityIdentifier("plan.detail.more")
            }
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        QuickStartPinMenuButton(name: planName, isPinned: plan.isPinned, action: togglePin)
        Button { showingCalendarSheet = true } label: {
            Label(calendarButtonTitle, systemImage: "calendar.badge.plus")
        }
        .disabled(!plan.isStartable)
        Button(action: duplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Details

    private var detailRows: [TFDetailRow] {
        [
            TFDetailRow("Focus sessions", "\(plan.focusCount)", systemImage: "brain.head.profile"),
            TFDetailRow("Intervals", "\(plan.items.count)", systemImage: "list.number"),
            TFDetailRow("Total duration", TimeFormatting.compactDuration(plan.totalDuration),
                        systemImage: "timer"),
            TFDetailRow("Configuration", PlanRowPresentation.configurationChip(for: plan),
                        systemImage: "slider.horizontal.3", isWarning: !plan.isStartable),
            TFDetailRow("Last updated", plan.updatedAt.formatted(.relative(presentation: .named)),
                        systemImage: "clock.arrow.circlepath"),
            TFDetailRow("Icon", plan.icon.displayName, systemImage: plan.icon.symbolName)
        ]
    }

    // MARK: Actions

    /// `ViewThatFits` keeps the row on one line when the window is wide and wraps the pin
    /// switch onto its own line when it is narrow, so the page never scrolls sideways.
    private var actions: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TFSpacing.s) {
                    primaryActions
                    Spacer(minLength: TFSpacing.s)
                    pinToggle
                }
                VStack(alignment: .leading, spacing: TFSpacing.s) {
                    HStack(spacing: TFSpacing.s) { primaryActions }
                    pinToggle
                }
            }

            Text("Pinned plans appear in the menu bar and widget for quick access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        Button(action: start) {
            Label("Start", systemImage: "play.fill")
        }
        .tfPrimaryAction()
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!plan.isStartable)
        .accessibilityLabel("Start \(planName)")
        .accessibilityIdentifier("plan.detail.start")
        .help("Start a session from this plan (Command-Return)")

        Button { showingCalendarSheet = true } label: {
            Label(calendarButtonTitle, systemImage: "calendar.badge.plus")
        }
        .tfSecondaryAction()
        .buttonStyle(.bordered)
        .disabled(!plan.isStartable)
        .accessibilityLabel(calendarButtonTitle)
        .accessibilityHint("Adds this plan's intervals to Apple Calendar")
        .accessibilityIdentifier("plan.detail.addToCalendar")
        .help("Add this plan to Apple Calendar")
    }

    private var pinToggle: some View {
        QuickStartPinButton(
            name: planName,
            isPinned: plan.isPinned,
            action: togglePin,
            identifier: "plan.detail.pin"
        )
        .fixedSize()
    }

    private var calendarButtonTitle: String {
        calendarCoordinator.record(for: plan) != nil ? "Update in Calendar" : "Add to Calendar"
    }

    // MARK: Actions

    private func start() {
        guard plan.isStartable else { return }
        guard !coordinator.engine.state.isActive else {
            activeSessionBlocked = true
            return
        }
        do {
            if try coordinator.startPlan(plan.executionSnapshot) != nil {
                onStarted()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Toggles the Quick Start pin. Immediate and reversible — no confirmation dialog for an
    /// ordinary preference. The repository's change hook republishes the menu bar's Quick
    /// Start list, so the popover updates without an app restart (ADR-104/105).
    private func togglePin() {
        perform { try coordinator.plans.setPinned(plan, !plan.isPinned) }
    }

    private func duplicate() {
        perform { try coordinator.plans.duplicate(plan) }
    }

    private func delete() {
        do {
            try coordinator.plans.delete(plan)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
