//
//  PlanItemEditorView.swift
//  time_frame
//
//  Add or edit a single plan interval in a sheet: its type (focus / short break /
//  long break), the configuration a focus interval uses, and its duration. The
//  duration defaults from the selected configuration but is independently editable
//  and never writes back to the configuration. Returns a value-typed `PlanItemDraft`
//  to the plan editor; nothing is persisted here.
//

import SwiftUI
import SwiftData

struct PlanItemEditorView: View {
    /// The item being edited, or `nil` to add a new one.
    let existing: PlanItemDraft?
    /// Pre-selected configuration for a new focus item (e.g. the plan's first focus
    /// configuration), so the common case needs no extra tap.
    let defaultConfigurationID: UUID?
    /// Called with the finished draft when the user taps Add / Save.
    let onCommit: (PlanItemDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PomodoroConfiguration.createdAt, order: .reverse)
    private var configurations: [PomodoroConfiguration]

    @State private var phase: TimerPhase = .focus
    @State private var selectedConfigurationID: UUID?
    @State private var durationMinutes: Int = 25

    private var isEditing: Bool { existing != nil }
    private let maxMinutes = Int(PlanLimits.maxItemDuration / 60)

    private var selectedConfiguration: PomodoroConfiguration? {
        configurations.first { $0.id == selectedConfigurationID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Type") {
                    Picker("Type", selection: $phase) {
                        ForEach(TimerPhase.allCases, id: \.self) { phase in
                            Text(phase.displayLabel).tag(phase)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("planItem.type")
                }

                if phase == .focus {
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
                            .accessibilityIdentifier("planItem.configuration")
                        }
                    }
                }

                Section("Duration") {
                    Stepper(value: $durationMinutes, in: 1...maxMinutes) {
                        LabeledContent("Minutes") { Text("\(durationMinutes)") }
                    }
                    .accessibilityIdentifier("planItem.duration")
                    .accessibilityValue("\(durationMinutes) minutes")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(phase == .focus && selectedConfigurationID == nil)
                    .accessibilityIdentifier("planItem.commit")
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 320)
        .navigationTitle(isEditing ? "Edit Interval" : "Add Interval")
        .onAppear(perform: load)
        .onChange(of: phase) { _, newPhase in applyPhaseDefault(newPhase) }
        .onChange(of: selectedConfigurationID) { _, _ in applyConfigurationDefaultDuration() }
    }

    // MARK: State

    private func load() {
        if let existing {
            phase = existing.phase
            selectedConfigurationID = existing.configurationID
            durationMinutes = clampMinutes(Int((existing.duration / 60).rounded()))
        } else {
            phase = .focus
            selectedConfigurationID = defaultConfigurationID
                ?? (configurations.first { $0.isDefault } ?? configurations.first)?.id
            applyConfigurationDefaultDuration()
        }
    }

    /// Applies a sensible default duration for the newly selected type.
    private func applyPhaseDefault(_ newPhase: TimerPhase) {
        switch newPhase {
        case .focus:
            if selectedConfigurationID == nil {
                selectedConfigurationID = (configurations.first { $0.isDefault } ?? configurations.first)?.id
            }
            applyConfigurationDefaultDuration()
        case .shortBreak:
            durationMinutes = clampMinutes(Int(((selectedConfiguration?.shortBreakDuration ?? 5 * 60) / 60).rounded()))
        case .longBreak:
            durationMinutes = clampMinutes(Int(((selectedConfiguration?.longBreakDuration ?? 15 * 60) / 60).rounded()))
        }
    }

    /// Seeds the duration from the selected configuration's focus length (focus
    /// items only). Purely a default — the user may then override it.
    private func applyConfigurationDefaultDuration() {
        guard phase == .focus, let config = selectedConfiguration else { return }
        durationMinutes = clampMinutes(Int((config.focusDuration / 60).rounded()))
    }

    private func clampMinutes(_ value: Int) -> Int {
        min(max(1, value), maxMinutes)
    }

    // MARK: Commit

    private func commit() {
        let isFocus = phase == .focus
        let draft = PlanItemDraft(
            id: existing?.id ?? UUID(),
            order: existing?.order ?? 0,
            phase: phase,
            duration: TimeInterval(durationMinutes * 60),
            configurationID: isFocus ? selectedConfigurationID : nil,
            configurationName: isFocus ? (selectedConfiguration?.name ?? "") : ""
        )
        onCommit(draft)
        dismiss()
    }
}
