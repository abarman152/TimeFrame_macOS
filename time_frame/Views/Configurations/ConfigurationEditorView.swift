//
//  ConfigurationEditorView.swift
//  time_frame
//
//  Create or edit a PomodoroConfiguration in a sheet. Durations are entered in
//  whole minutes; validation uses the existing `ConfigurationValidation` layer
//  (the view never re-implements the rules), and errors are shown in friendly
//  language — never a raw Swift error.
//

import SwiftUI

struct ConfigurationEditorView: View {
    let coordinator: SessionCoordinator
    /// The configuration to edit, or `nil` to create a new one.
    let existing: PomodoroConfiguration?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var focusMinutes: Int = 25
    @State private var shortBreakMinutes: Int = 5
    @State private var longBreakMinutes: Int = 15
    @State private var sessionsBeforeLongBreak: Int = 4
    @State private var totalSessions: Int = 4
    @State private var validationMessages: [String] = []

    private var isEditing: Bool { existing != nil }

    /// The draft the current inputs represent (minutes → seconds).
    private var draft: ConfigurationDraft {
        ConfigurationDraft(
            name: name,
            focusDuration: TimeInterval(focusMinutes) * 60,
            shortBreakDuration: TimeInterval(shortBreakMinutes) * 60,
            longBreakDuration: TimeInterval(longBreakMinutes) * 60,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak,
            totalSessions: totalSessions
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Name") {
                    TextField("Configuration name", text: $name)
                }

                Section("Durations") {
                    minuteStepper("Focus", value: $focusMinutes, range: 1...480)
                    minuteStepper("Short Break", value: $shortBreakMinutes, range: 0...480)
                    minuteStepper("Long Break", value: $longBreakMinutes, range: 0...480)
                }

                Section("Sessions") {
                    Stepper(value: $sessionsBeforeLongBreak,
                            in: 1...ConfigurationLimits.maxSessionsBeforeLongBreak) {
                        LabeledContent("Long Break After") {
                            Text("^[\(sessionsBeforeLongBreak) session](inflect: true)")
                        }
                    }
                    Stepper(value: $totalSessions,
                            in: 1...ConfigurationLimits.maxTotalSessions) {
                        LabeledContent("Default Sessions") { Text("\(totalSessions)") }
                    }
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
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 480)
        .navigationTitle(isEditing ? "Edit Configuration" : "New Configuration")
        .onAppear(perform: loadExisting)
    }

    private func minuteStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(label) {
                Text("^[\(value.wrappedValue) minute](inflect: true)")
            }
        }
        .accessibilityValue("\(value.wrappedValue) minutes")
    }

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        focusMinutes = minutes(existing.focusDuration)
        shortBreakMinutes = minutes(existing.shortBreakDuration)
        longBreakMinutes = minutes(existing.longBreakDuration)
        sessionsBeforeLongBreak = existing.sessionsBeforeLongBreak
        totalSessions = existing.defaultTotalSessions
    }

    private func minutes(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds / 60).rounded()))
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
                try coordinator.configurations.update(existing, with: draft)
            } else {
                try coordinator.configurations.create(draft)
            }
            dismiss()
        } catch let PersistenceError.invalidConfiguration(errors) {
            validationMessages = errors.map(\.message)
        } catch {
            validationMessages = [(error as? LocalizedError)?.errorDescription ?? "Couldn't save the configuration."]
        }
    }
}
