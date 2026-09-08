//
//  TemplateDetailView.swift
//  time_frame
//
//  A single template's detail: its task, configuration, the configuration's durations, and
//  the default session count, plus the page's actions. Start reuses the existing
//  session-setup path — it never creates a `FocusSession` here (ADR-025).
//
//  ## Milestone 29 — the Edit fix (ADR-106)
//  Editing used to be delegated upward: this page called an `onEdit` closure that set state on
//  `TemplateListView`, whose `.sheet(item:)` is attached to the `NavigationStack`. On macOS a
//  sheet requested from the stack's ROOT while a `navigationDestination` is pushed does not
//  present — the request is held until the stack pops back, at which point the editor appears
//  unexpectedly over the list. So "Edit" on this page looked dead.
//
//  The page therefore presents its own editor, from its own state, in the view that is
//  actually on screen. Nothing else changed: it is the SAME `TemplateEditorView`, saving
//  through the SAME `TaskTemplateRepository.update`, so the template keeps its identity, its
//  pin, and its history.
//
//  ## Milestone 29 — action hierarchy
//  One prominent action (Start); Create Plan is a bordered secondary; pinning is a switch;
//  Edit and the overflow menu sit with the title; Duplicate and Delete live in a quieter
//  "Manage" group. Delete is the only red control on the page.
//

import SwiftUI

struct TemplateDetailView: View {
    let coordinator: SessionCoordinator
    let template: TaskTemplate
    /// Queues this template's values on the Timer setup screen (ADR-025).
    let startFromTemplate: (TaskTemplate) -> Void
    /// Generates a plan from this template and opens the Plans editor. The template
    /// is never modified.
    let createPlan: (TaskTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The editor sheet is owned HERE, by the view that is on screen when Edit is pressed.
    @State private var editingTemplate: TaskTemplate?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @State private var activeSessionBlocked = false

    private var configuration: PomodoroConfiguration? { template.configuration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                header
                TFDetailCard(title: "Template Details", rows: detailRows)
                if !template.hasConfiguration {
                    TFNoticeBanner(message: "This template's configuration was removed. Choose a configuration before starting.")
                }
                actions
                Divider().padding(.vertical, TFSpacing.xs)
                TFManageSection(
                    duplicate: duplicate,
                    delete: { confirmingDelete = true },
                    duplicateIdentifier: "template.detail.duplicate",
                    deleteIdentifier: "template.detail.delete",
                    itemDescription: template.name
                )
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(template.name)
        .sheet(item: $editingTemplate) { target in
            TemplateEditorView(coordinator: coordinator, existing: target)
        }
        .alert("Couldn't Start Session", isPresented: $activeSessionBlocked) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A session is already active. Stop it before starting a new one.")
        }
        .alert("Template Error",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete \(template.name)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Template", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the reusable template. Your completed sessions are kept in History and are not affected.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: TFSpacing.m) {
            TimeFrameIconTile(icon: template.icon, size: .large)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TFSpacing.s) {
                    Text(template.name)
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    if template.isPinned { QuickStartPinnedMarker() }
                    if template.isDefault { TFDefaultMarker(accessibilityText: "Default template") }
                }
                Text(template.taskName.isEmpty ? "No task" : template.taskName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: TFSpacing.m)

            HStack(spacing: TFSpacing.s) {
                Button { editingTemplate = template } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Edit \(template.name)")
                .accessibilityHint("Opens the template editor")
                .accessibilityIdentifier("template.detail.edit")
                .help("Edit this template (Command-E)")

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
                .accessibilityIdentifier("template.detail.more")
            }
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        QuickStartPinMenuButton(name: template.name, isPinned: template.isPinned, action: togglePin)
        if template.isDefault {
            Button { setDefault(false) } label: { Label("Remove Default", systemImage: "star.slash") }
        } else {
            Button { setDefault(true) } label: { Label("Set as Default", systemImage: "star") }
        }
        Button(action: duplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Details

    private var detailRows: [TFDetailRow] {
        var rows: [TFDetailRow] = [
            TFDetailRow("Task", template.taskName.isEmpty ? "No task" : template.taskName,
                        systemImage: "doc.text"),
            TFDetailRow("Configuration", template.displayConfigurationName,
                        systemImage: "slider.horizontal.3",
                        isWarning: !template.hasConfiguration)
        ]
        if let configuration {
            rows.append(TFDetailRow("Focus", TimeFormatting.minutesLabel(configuration.focusDuration),
                                    systemImage: "timer"))
            rows.append(TFDetailRow("Break", TimeFormatting.minutesLabel(configuration.shortBreakDuration),
                                    systemImage: "cup.and.saucer"))
            rows.append(TFDetailRow("Long Break", TimeFormatting.minutesLabel(configuration.longBreakDuration),
                                    systemImage: "figure.walk"))
        }
        rows.append(TFDetailRow("Sessions", "\(template.defaultTotalSessions)",
                                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"))
        rows.append(TFDetailRow("Icon", template.icon.displayName, systemImage: template.icon.symbolName))
        return rows
    }

    // MARK: Actions

    /// One prominent action, one bordered secondary, and the pin preference as a switch.
    ///
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

            Text("Pinned templates appear in the menu bar and widget for quick access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pinToggle: some View {
        QuickStartPinButton(
            name: template.name,
            isPinned: template.isPinned,
            action: togglePin,
            identifier: "template.detail.pin"
        )
        .fixedSize()
    }

    @ViewBuilder
    private var primaryActions: some View {
        Group {
            if template.hasConfiguration {
                    Button(action: start) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .tfPrimaryAction()
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Start a session from \(template.name)")
                    .accessibilityIdentifier("template.detail.start")
                    .help("Start a session from this template (Command-Return)")

                    Button { createPlan(template) } label: {
                        Label("Create Plan", systemImage: "list.bullet.rectangle")
                    }
                    .tfSecondaryAction()
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Create a plan from \(template.name)")
                    .accessibilityIdentifier("template.detail.createPlan")
                    .help("Build a multi-session plan from this template")
                } else {
                    Button { editingTemplate = template } label: {
                        Label("Choose Configuration", systemImage: "slider.horizontal.3")
                    }
                    .tfSecondaryAction()
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("template.detail.chooseConfiguration")
            }
        }
    }

    private func start() {
        guard template.hasConfiguration else { return }
        guard !coordinator.engine.state.isActive else {
            activeSessionBlocked = true
            return
        }
        startFromTemplate(template)
    }

    /// Toggles the Quick Start pin. Immediate and reversible — no confirmation dialog for an
    /// ordinary preference. The repository's change hook republishes the menu bar's Quick
    /// Start list, so the popover updates without an app restart (ADR-104/105).
    private func togglePin() {
        perform { try coordinator.templates.setPinned(template, !template.isPinned) }
    }

    private func setDefault(_ makeDefault: Bool) {
        perform {
            if makeDefault {
                try coordinator.templates.setDefault(template)
            } else {
                try coordinator.templates.clearDefault(template)
            }
        }
    }

    private func duplicate() {
        perform { try coordinator.templates.duplicate(template) }
    }

    private func delete() {
        do {
            try coordinator.templates.delete(template)
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
