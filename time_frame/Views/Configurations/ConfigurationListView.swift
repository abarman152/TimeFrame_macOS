//
//  ConfigurationListView.swift
//  time_frame
//
//  Manage Pomodoro configurations: create, edit, duplicate, set default, delete.
//  All persistence goes through the ConfigurationRepository (via the
//  coordinator); the view never touches the ModelContext directly.
//
//  Milestone 29: the screen adopted the shared page header and card rows, and each row now
//  carries the same trailing Edit/overflow affordance as Templates and Plans, so the three
//  library screens behave identically.
//

import SwiftUI
import SwiftData

struct ConfigurationListView: View {
    let coordinator: SessionCoordinator
    /// Generates a plan from a configuration's defaults and opens the Plans editor
    /// (owned by the app root). The configuration is never modified.
    let createPlanFromConfiguration: (PomodoroConfiguration) -> Void

    @Query(sort: \PomodoroConfiguration.createdAt, order: .reverse)
    private var configurations: [PomodoroConfiguration]

    @State private var editorTarget: EditorTarget?
    @State private var configurationToDelete: PomodoroConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        content
        .navigationTitle("Configurations")
        .toolbar {
            ToolbarItem {
                Button {
                    editorTarget = .create
                } label: {
                    Label("New Configuration", systemImage: "plus")
                }
                .help("Create a new configuration (Command-N)")
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("configuration.new")
            }
        }
        .sheet(item: $editorTarget) { target in
            ConfigurationEditorView(coordinator: coordinator, existing: target.configuration)
        }
        .confirmationDialog(
            "Delete this configuration?",
            isPresented: Binding(get: { configurationToDelete != nil },
                                 set: { if !$0 { configurationToDelete = nil } }),
            presenting: configurationToDelete
        ) { config in
            Button("Delete \(config.name)", role: .destructive) { delete(config) }
            Button("Cancel", role: .cancel) { configurationToDelete = nil }
        } message: { config in
            Text(deleteMessage(for: config))
        }
        .alert("Configuration Error",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if configurations.isEmpty {
            EmptyStateView(
                title: "No Configurations",
                systemImage: "slider.horizontal.3",
                message: "Create your first Pomodoro configuration to get started.",
                actionTitle: "Create Configuration",
                action: { editorTarget = .create }
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.l) {
                TFPageHeader(title: "Configurations",
                             subtitle: "The durations and session counts your timers run on.")

                LazyVStack(spacing: TFSpacing.s) {
                    ForEach(configurations) { config in
                        row(for: config)
                    }
                }
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(for config: PomodoroConfiguration) -> some View {
        HStack(spacing: 0) {
            Button {
                editorTarget = .edit(config)
            } label: {
                ConfigurationRowView(configuration: config)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ConfigurationRowPresentation.accessibilityLabel(for: config))
            .accessibilityHint("Opens the configuration editor")

            TFRowActions(
                start: nil,
                startLabel: "",
                startHelp: "",
                menuLabel: "More actions for \(config.name)",
                menu: { rowMenu(config) }
            )
        }
        .tfCard()
        .contextMenu { rowMenu(config) }
        .accessibilityIdentifier("configuration.row.\(config.id.uuidString)")
    }

    @ViewBuilder
    private func rowMenu(_ config: PomodoroConfiguration) -> some View {
        Button { editorTarget = .edit(config) } label: { Label("Edit", systemImage: "pencil") }
        Button { duplicate(config) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { createPlanFromConfiguration(config) } label: { Label("Create Plan", systemImage: "list.bullet.rectangle") }
        if !config.isDefault {
            Button { setDefault(config) } label: { Label("Set as Default", systemImage: "star") }
        }
        Divider()
        Button(role: .destructive) { configurationToDelete = config } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Explains, before deletion, what a configuration is used by. History always
    /// survives (sessions freeze their own plan and configuration name); templates
    /// survive too but their reference is cleared, so they need a new configuration
    /// before they can start (ADR-024).
    private func deleteMessage(for config: PomodoroConfiguration) -> String {
        let sessionCount = config.focusSessions.count
        let templateCount = config.taskTemplates.count
        var parts: [String] = []
        if sessionCount > 0 {
            let noun = sessionCount == 1 ? "past session" : "past sessions"
            parts.append("It's used by \(sessionCount) \(noun), which stay in History and remain accurate.")
        }
        if templateCount > 0 {
            let noun = templateCount == 1 ? "task template" : "task templates"
            parts.append("\(templateCount) \(noun) will need a new configuration before they can start; the templates themselves are kept.")
        }
        if parts.isEmpty {
            return "This can't be undone."
        }
        return parts.joined(separator: " ")
    }

    // MARK: Actions

    private func duplicate(_ config: PomodoroConfiguration) {
        perform { try coordinator.configurations.duplicate(config) }
    }

    private func setDefault(_ config: PomodoroConfiguration) {
        perform { try coordinator.configurations.setDefault(config) }
    }

    private func delete(_ config: PomodoroConfiguration) {
        perform { try coordinator.configurations.delete(config) }
        configurationToDelete = nil
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
        case edit(PomodoroConfiguration)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let config): config.id.uuidString
            }
        }

        var configuration: PomodoroConfiguration? {
            switch self {
            case .create: nil
            case .edit(let config): config
            }
        }
    }
}
