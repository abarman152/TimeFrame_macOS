//
//  PlanEditorView.swift
//  time_frame
//
//  Create or edit a Session Plan in a sheet: name, task, and an editable timeline
//  of intervals (add / remove / reorder / edit). The persisted plan is only mutated
//  on Save (via SessionPlanRepository); Cancel discards the in-memory draft. Uses
//  the dedicated SessionPlanValidation layer — the view never re-implements rules.
//  Ordering is derived from the timeline's position and normalized on save.
//

import SwiftUI
import SwiftData

struct PlanEditorView: View {
    let coordinator: SessionCoordinator
    /// The plan to edit, or `nil` to create a new one.
    let existing: SessionPlan?
    /// A pre-filled draft (e.g. generated from a template or configuration) used
    /// when creating a new plan. Ignored when `existing` is set.
    var seed: SessionPlanDraft?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var taskName: String = ""
    @State private var items: [PlanItemDraft] = []
    @State private var icon: TimeFrameIconIdentifier = .planDefault
    @State private var validationMessages: [String] = []
    @State private var itemEditorTarget: ItemEditorTarget?
    @State private var loaded = false

    private var isEditing: Bool { existing != nil }

    private var draft: SessionPlanDraft {
        SessionPlanDraft(name: name, taskName: taskName, items: items, icon: icon).normalized
    }

    /// Configuration to pre-select when adding a new focus item: the first focus
    /// item's configuration, so a multi-focus plan keeps adding the same one.
    private var defaultConfigurationID: UUID? {
        items.first { $0.isFocus }?.configurationID
    }

    var body: some View {
        VStack(spacing: 0) {
            TFSheetHeader(title: isEditing ? "Edit Plan" : "New Plan",
                          subtitle: isEditing
                              ? "Changes apply to this plan only — sessions you already ran are unchanged."
                              : "Build the exact sequence of focus intervals and breaks you want to run.")

            List {
                Section("Plan") {
                    // `LabeledContent` because this container is a `List` (kept for the
                    // timeline's drag-to-reorder), and a plain `List` row does not render a
                    // `TextField`'s own label — which is why these two fields used to appear
                    // as unlabelled boxes.
                    LabeledContent("Name") {
                        TextField("Name", text: $name,
                                  prompt: Text("e.g. Research Deep Work"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Plan name")
                            .accessibilityIdentifier("plan.name")
                    }
                    LabeledContent("Task") {
                        TextField("Task", text: $taskName,
                                  prompt: Text("What you'll focus on"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Task")
                            .accessibilityIdentifier("plan.taskName")
                    }
                    TimeFrameIconPicker(selection: $icon)
                        .accessibilityIdentifier("plan.icon")
                }

                timelineSection

                summarySection

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

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel and discard changes")
                    .accessibilityIdentifier("plan.cancel")
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel(isEditing ? "Save changes to this plan" : "Save the new plan")
                    .accessibilityIdentifier("plan.save")
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 560)
        .onAppear(perform: loadIfNeeded)
        .sheet(item: $itemEditorTarget) { target in
            PlanItemEditorView(
                existing: target.item,
                defaultConfigurationID: defaultConfigurationID,
                onCommit: commitItem
            )
        }
    }

    // MARK: Sections

    private var timelineSection: some View {
        Section {
            if items.isEmpty {
                Text("Add focus intervals and breaks to build the plan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    Button {
                        itemEditorTarget = .edit(pair.element)
                    } label: {
                        PlanItemRowView(number: pair.offset + 1, item: pair.element)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowMenu(at: pair.offset) }
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                }
            }
        } header: {
            HStack {
                Text("Timeline")
                Spacer()
                Button {
                    itemEditorTarget = .add
                } label: {
                    Label("Add Interval", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("plan.addItem")
            }
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Focus sessions") {
                Text("\(draft.focusCount)").monospacedDigit()
            }
            LabeledContent("Total duration") {
                Text(TimeFormatting.compactDuration(draft.totalDuration)).monospacedDigit()
            }
            .accessibilityIdentifier("plan.totalDuration")
        }
    }

    @ViewBuilder
    private func rowMenu(at index: Int) -> some View {
        Button { itemEditorTarget = .edit(items[index]) } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button { duplicateItem(at: index) } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        if index > 0 {
            Button { items.swapAt(index, index - 1) } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
        }
        if index < items.count - 1 {
            Button { items.swapAt(index, index + 1) } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
        }
        Divider()
        Button(role: .destructive) { items.remove(at: index) } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    // MARK: Item editing

    /// Adds a new item or replaces an edited one (matched by id).
    private func commitItem(_ item: PlanItemDraft) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    private func duplicateItem(at index: Int) {
        var copy = items[index]
        copy.id = UUID()
        items.insert(copy, at: index + 1)
    }

    // MARK: Load / Save

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            let d = existing.draft
            name = d.name
            taskName = d.taskName
            items = d.items
            icon = d.icon
        } else if let seed {
            name = seed.name
            taskName = seed.taskName
            items = seed.items
            icon = seed.icon
        }
    }

    private func save() {
        let candidate = draft
        let errors = candidate.validate()
        guard errors.isEmpty else {
            validationMessages = errors.map(\.message)
            return
        }
        do {
            if let existing {
                try coordinator.plans.update(existing, with: candidate)
            } else {
                try coordinator.plans.create(candidate)
            }
            dismiss()
        } catch let PersistenceError.invalidPlan(errors) {
            validationMessages = errors.map(\.message)
        } catch {
            validationMessages = [(error as? LocalizedError)?.errorDescription ?? "Couldn't save the plan."]
        }
    }

    /// The item editor's add/edit target, made Identifiable for `.sheet(item:)`.
    private enum ItemEditorTarget: Identifiable {
        case add
        case edit(PlanItemDraft)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let item): item.id.uuidString
            }
        }

        var item: PlanItemDraft? {
            switch self {
            case .add: nil
            case .edit(let item): item
            }
        }
    }
}
