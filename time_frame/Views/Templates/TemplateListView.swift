//
//  TemplateListView.swift
//  time_frame
//
//  Manage Task Templates: create, view, edit, duplicate, set default, delete, and
//  start a session from one. All persistence goes through the
//  TaskTemplateRepository (via the coordinator); the view never touches the
//  ModelContext directly. Starting a session reuses the existing setup path.
//
//  ## Milestone 29
//  The screen gained the shared page header, a native `searchable` filter, and card rows.
//  It also stopped owning the *detail* page's editor: a sheet presented from this view while
//  a `navigationDestination` is pushed does not appear on macOS until the stack pops back,
//  which is why "Edit" on a template's detail page did nothing. The detail page now presents
//  its own editor (see `TemplateDetailView`); this list still owns the editor for Create and
//  for its own row actions, where the root view is on screen.
//

import SwiftUI
import SwiftData

struct TemplateListView: View {
    let coordinator: SessionCoordinator
    /// Queues a template's values on the Timer setup screen (owned by the app root).
    let startFromTemplate: (TaskTemplate) -> Void
    /// Generates a plan from the template and opens the Plans editor (owned by the
    /// app root). The template is never modified.
    let createPlanFromTemplate: (TaskTemplate) -> Void

    @Query(sort: \TaskTemplate.createdAt, order: .reverse)
    private var templates: [TaskTemplate]

    @State private var editorTarget: EditorTarget?
    @State private var templateToDelete: TaskTemplate?
    @State private var errorMessage: String?
    @State private var activeSessionBlocked = false
    @State private var searchText = ""

    /// The templates that match the current search, newest first.
    private var visibleTemplates: [TaskTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }
        return templates.filter { template in
            template.name.localizedCaseInsensitiveContains(query)
                || template.taskName.localizedCaseInsensitiveContains(query)
                || template.displayConfigurationName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Templates")
                .navigationDestination(for: UUID.self) { id in
                    if let template = templates.first(where: { $0.id == id }) {
                        TemplateDetailView(
                            coordinator: coordinator,
                            template: template,
                            startFromTemplate: requestStart,
                            createPlan: createPlanFromTemplate
                        )
                    } else {
                        ContentUnavailableView("Template Unavailable", systemImage: "questionmark.folder")
                    }
                }
                .searchable(text: $searchText, prompt: "Search templates")
                .toolbar {
                    ToolbarItem {
                        Button {
                            editorTarget = .create
                        } label: {
                            Label("New Template", systemImage: "plus")
                        }
                        .help("Create a new template (Command-N)")
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityIdentifier("template.new")
                    }
                }
        }
        .sheet(item: $editorTarget) { target in
            TemplateEditorView(coordinator: coordinator, existing: target.template)
        }
        .confirmationDialog(
            "Delete this template?",
            isPresented: Binding(get: { templateToDelete != nil },
                                 set: { if !$0 { templateToDelete = nil } }),
            titleVisibility: .visible,
            presenting: templateToDelete
        ) { template in
            Button("Delete \(template.name)", role: .destructive) { delete(template) }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: { _ in
            Text("This removes the reusable template. Your completed sessions are kept in History and are not affected.")
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
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if templates.isEmpty {
            EmptyStateView(
                title: "No Task Templates",
                systemImage: "square.stack.3d.up",
                message: "Create reusable focus setups for the work you come back to.",
                actionTitle: "Create Template",
                action: { editorTarget = .create }
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.l) {
                TFPageHeader(title: "Templates",
                             subtitle: "Create reusable focus setups for recurring work.")

                if visibleTemplates.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, TFSpacing.xxl)
                } else {
                    LazyVStack(spacing: TFSpacing.s) {
                        ForEach(visibleTemplates) { template in
                            row(for: template)
                        }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(for template: TaskTemplate) -> some View {
        HStack(spacing: 0) {
            // The link wraps only the row's *content*: the trailing controls sit beside it, so
            // a Start or overflow click is never swallowed by the navigation link.
            NavigationLink(value: template.id) {
                TemplateRowView(template: template)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TemplateRowPresentation.accessibilityLabel(for: template))
            .accessibilityHint("Opens the template")

            TFRowActions(
                start: template.hasConfiguration ? { requestStart(template) } : nil,
                startLabel: "Start \(template.name)",
                startHelp: "Start a session from this template",
                menuLabel: "More actions for \(template.name)",
                menu: { rowMenu(template) }
            )
        }
        .tfCard()
        .contextMenu { rowMenu(template) }
        .accessibilityIdentifier("template.row.\(template.id.uuidString)")
    }

    @ViewBuilder
    private func rowMenu(_ template: TaskTemplate) -> some View {
        if template.hasConfiguration {
            Button { requestStart(template) } label: { Label("Start", systemImage: "play.fill") }
            Button { createPlanFromTemplate(template) } label: { Label("Create Plan", systemImage: "list.bullet.rectangle") }
        }
        QuickStartPinMenuButton(name: template.name,
                                isPinned: template.isPinned) { togglePin(template) }
        Button { editorTarget = .edit(template) } label: { Label("Edit", systemImage: "pencil") }
        Button { duplicate(template) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if template.isDefault {
            Button { clearDefault(template) } label: { Label("Remove Default", systemImage: "star.slash") }
        } else {
            Button { setDefault(template) } label: { Label("Set as Default", systemImage: "star") }
        }
        Divider()
        Button(role: .destructive) { templateToDelete = template } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Actions

    /// Starts a run from the template, guarding against a second active session.
    private func requestStart(_ template: TaskTemplate) {
        guard template.hasConfiguration else { return }
        guard !coordinator.engine.state.isActive else {
            activeSessionBlocked = true
            return
        }
        startFromTemplate(template)
    }

    /// Toggles the Quick Start pin. Immediate, reversible, and never confirmed by a dialog.
    private func togglePin(_ template: TaskTemplate) {
        perform { try coordinator.templates.setPinned(template, !template.isPinned) }
    }

    private func duplicate(_ template: TaskTemplate) {
        perform { try coordinator.templates.duplicate(template) }
    }

    private func setDefault(_ template: TaskTemplate) {
        perform { try coordinator.templates.setDefault(template) }
    }

    private func clearDefault(_ template: TaskTemplate) {
        perform { try coordinator.templates.clearDefault(template) }
    }

    private func delete(_ template: TaskTemplate) {
        perform { try coordinator.templates.delete(template) }
        templateToDelete = nil
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// The editor's create/edit target, made Identifiable for `.sheet(item:)`.
    private enum EditorTarget: Identifiable {
        case create
        case edit(TaskTemplate)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let template): template.id.uuidString
            }
        }

        var template: TaskTemplate? {
            switch self {
            case .create: nil
            case .edit(let template): template
            }
        }
    }
}
