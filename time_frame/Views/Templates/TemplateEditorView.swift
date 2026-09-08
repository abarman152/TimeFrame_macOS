//
//  TemplateEditorView.swift
//  time_frame
//
//  Create or edit a TaskTemplate in a sheet. Uses the dedicated
//  `TaskTemplateValidation` layer (the view never re-implements the rules) and
//  shows errors in friendly language. The persisted template is only mutated on
//  Save; Cancel discards the in-memory form state.
//

import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    let coordinator: SessionCoordinator
    /// The template to edit, or `nil` to create a new one.
    let existing: TaskTemplate?

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PomodoroConfiguration.createdAt, order: .reverse)
    private var configurations: [PomodoroConfiguration]

    @State private var name: String = ""
    @State private var taskName: String = ""
    @State private var selectedConfigurationID: UUID?
    @State private var totalSessions: Int = 4
    @State private var icon: TimeFrameIconIdentifier = .templateDefault
    @State private var validationMessages: [String] = []

    private var isEditing: Bool { existing != nil }

    /// The draft the current inputs represent.
    private var draft: TaskTemplateDraft {
        TaskTemplateDraft(
            name: name,
            taskName: taskName,
            configurationID: selectedConfigurationID,
            defaultTotalSessions: totalSessions,
            icon: icon
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TFSheetHeader(title: isEditing ? "Edit Template" : "New Template",
                          subtitle: isEditing
                              ? "Changes apply to this template only — sessions you already ran are unchanged."
                              : "A reusable starting point for sessions you run often.")

            Form {
                Section {
                    // The field's *label* is the label; the example is a prompt. Passing the
                    // example as the label made a macOS Form render "e.g. Research" as the row
                    // title and squeeze the value into the trailing edge.
                    TextField("Name", text: $name, prompt: Text("e.g. Research"))
                        .accessibilityIdentifier("template.name")

                    TextField("Task", text: $taskName,
                              prompt: Text("What the session will focus on"))
                        .accessibilityIdentifier("template.taskName")

                    TimeFrameIconPicker(selection: $icon)
                        .accessibilityIdentifier("template.icon")
                } header: {
                    Text("Template")
                } footer: {
                    Text("The icon is shown in the Templates list, the menu bar's Quick Start, and the widget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Configuration") {
                    if configurations.isEmpty {
                        Label("Create a configuration first, then choose it here.",
                              systemImage: "slider.horizontal.3")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Configuration", selection: $selectedConfigurationID) {
                            Text("None").tag(UUID?.none)
                            ForEach(configurations) { config in
                                Text(config.isDefault ? "\(config.name) (Default)" : config.name)
                                    .tag(config.id as UUID?)
                            }
                        }
                        .accessibilityIdentifier("template.configuration")

                        if let config = selectedConfiguration {
                            ConfigurationSummaryView(configuration: config)
                        }
                    }
                }

                Section("Sessions") {
                    Stepper(value: $totalSessions, in: 1...ConfigurationLimits.maxTotalSessions) {
                        LabeledContent("Default Sessions") { Text("\(totalSessions)") }
                    }
                    .accessibilityIdentifier("template.sessions")
                    .accessibilityValue("\(totalSessions)")
                }

                if !validationMessages.isEmpty {
                    Section {
                        ForEach(validationMessages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel and discard changes")
                    .accessibilityIdentifier("template.cancel")
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel(isEditing ? "Save changes to this template" : "Save the new template")
                    .accessibilityIdentifier("template.save")
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 500)
        .onAppear(perform: loadExisting)
    }

    private var selectedConfiguration: PomodoroConfiguration? {
        configurations.first { $0.id == selectedConfigurationID }
    }

    private func loadExisting() {
        if let existing {
            name = existing.name
            taskName = existing.taskName
            selectedConfigurationID = existing.configuration?.id
            totalSessions = min(max(1, existing.defaultTotalSessions), ConfigurationLimits.maxTotalSessions)
            icon = existing.icon
        } else {
            // New template: default the configuration to the user's default (or the
            // most recent), so the common case needs no extra tap.
            selectedConfigurationID = (configurations.first { $0.isDefault } ?? configurations.first)?.id
        }
    }

    private func save() {
        // Validate up front so we can show every violated rule at once.
        let errors = draft.validate()
        guard errors.isEmpty else {
            validationMessages = errors.map(\.message)
            return
        }
        do {
            if let existing {
                try coordinator.templates.update(existing, with: draft)
            } else {
                try coordinator.templates.create(draft)
            }
            dismiss()
        } catch let PersistenceError.invalidTemplate(errors) {
            validationMessages = errors.map(\.message)
        } catch {
            validationMessages = [(error as? LocalizedError)?.errorDescription ?? "Couldn't save the template."]
        }
    }
}
