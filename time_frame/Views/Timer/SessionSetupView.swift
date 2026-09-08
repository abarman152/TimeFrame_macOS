//
//  SessionSetupView.swift
//  time_frame
//
//  The pre-run setup: enter a task, pick a configuration, choose how many focus
//  sessions, preview the plan, and start. A task name is required; the saved
//  configuration is never mutated by the session-count choice.
//
//  ## Milestone 29 layout
//  The screen is now a single column of labelled sections, in the order the decision is
//  actually made — task, configuration, session count, preview, start:
//
//    • a page header ("Timer" + one line of guidance) with Quick Start in the top-right,
//      reading the SAME pinned projection the menu bar uses (never a second source);
//    • the task field, with a Recent Tasks menu that fills it from bounded history;
//    • the configuration as one card — icon, name, and its durations in a single summary
//      line — chosen through a native menu, with a quiet "Manage Configurations" link;
//    • a compact session stepper (not a full-width control);
//    • the interval preview inside one card, with a Show filter;
//    • exactly ONE prominent action: Start — compact and content-sized, not a full-width
//      slab (Milestone 30, ADR-108).
//
//  It still owns no timer: Start goes through the existing `SessionCoordinator.startSession`,
//  and Quick Start goes through the existing `QuickStartCoordinator` seam.
//

import SwiftUI
import SwiftData

/// The bounded descriptor behind the Recent Tasks menu. Deliberately limited: the menu only
/// ever offers a handful of names, so history can grow without this read growing with it
/// (M26, ADR-100).
private enum RecentTaskQuery {
    static let limit = 60

    static var descriptor: FetchDescriptor<FocusSession> {
        var descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\FocusSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}

/// How much of the generated plan the preview lists.
private enum SessionPlanFilter: String, CaseIterable, Identifiable {
    case all
    case focus
    case breaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Sessions"
        case .focus: "Focus Only"
        case .breaks: "Breaks Only"
        }
    }

    func includes(_ phase: TimerPhase) -> Bool {
        switch self {
        case .all: true
        case .focus: phase.isFocus
        case .breaks: phase.isBreak
        }
    }
}

struct SessionSetupView: View {
    let coordinator: SessionCoordinator
    /// The shared Quick Start projection (pinned Templates and Plans). Read-only here; a
    /// start routes through the coordinator's existing seam.
    let quickStart: QuickStartCoordinator
    /// Values queued by a Task Template's "Start". Applied to the editable fields
    /// on appear/change and then cleared, so per-run edits never flow back to the
    /// template (ADR-025). A binding so this screen can clear it once consumed.
    @Binding var pendingSetup: SessionSetupPrefill?
    /// Navigates to the Configurations area (used by the empty state and the Manage link).
    let openConfigurations: () -> Void

    @Query(sort: \PomodoroConfiguration.createdAt, order: .reverse)
    private var configurations: [PomodoroConfiguration]

    @Query(RecentTaskQuery.descriptor)
    private var recentSessions: [FocusSession]

    @State private var taskName: String = ""
    @State private var selectedConfigurationID: UUID?
    @State private var totalSessions: Int = 4
    @State private var errorMessage: String?
    @State private var planFilter: SessionPlanFilter = .all

    /// Set while applying a template prefill so the configuration-driven count
    /// reset does not clobber the prefill's per-run session count.
    @State private var suppressNextCountSync = false

    @FocusState private var taskFieldFocused: Bool

    private var selectedConfiguration: PomodoroConfiguration? {
        configurations.first { $0.id == selectedConfigurationID } ?? configurations.first
    }

    private var draft: SessionSetupDraft {
        SessionSetupDraft(taskName: taskName, totalSessions: totalSessions)
    }

    var body: some View {
        Group {
            if configurations.isEmpty {
                EmptyStateView(
                    title: "No Configurations",
                    systemImage: "slider.horizontal.3",
                    message: "Create your first Pomodoro configuration to start focusing.",
                    actionTitle: "Create Configuration",
                    action: openConfigurations
                )
            } else {
                setupForm
            }
        }
        .navigationTitle("Timer")
        .onAppear {
            syncSelectionDefaults()
            applyPendingSetupIfNeeded()
            quickStart.refresh()
        }
        .onChange(of: configurations.map(\.id)) { _, _ in syncSelectionDefaults() }
        .onChange(of: selectedConfigurationID) { _, _ in syncSessionCountToConfiguration() }
        .onChange(of: pendingSetup) { _, _ in applyPendingSetupIfNeeded() }
        .alert("Couldn't Start Session",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var setupForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                TFPageHeader(title: "Timer",
                             subtitle: "Choose a task and configuration to begin.") {
                    quickStartMenu
                }

                taskSection
                configurationSection
                sessionCountSection

                if let selectedConfiguration {
                    planSection(for: selectedConfiguration)
                }

                startButton
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Quick Start

    /// Pinned Templates and Plans, straight from the shared projection. This is the same
    /// `QuickStartCoordinator` the menu bar uses — there is no second Quick Start list.
    private var quickStartMenu: some View {
        Menu {
            if quickStart.items.isEmpty {
                Text("Pin a template or plan to see it here")
            } else {
                ForEach(quickStart.items) { item in
                    Button {
                        quickStart.start(item)
                    } label: {
                        Label(item.displayName, systemImage: item.icon.symbolName)
                    }
                    .disabled(!quickStart.canStart || !item.isStartable)
                    .help(item.unavailableReason ?? item.subtitle)
                }
            }
        } label: {
            Label("Quick Start", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.subheadline)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize()
        .accessibilityLabel("Quick Start")
        .accessibilityHint("Start one of your pinned templates or plans")
        .accessibilityIdentifier("timeFrame.timer.quickStart")
        .help("Start a pinned template or plan")
    }

    // MARK: Task

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            TFSectionHeader(title: "Task") {
                recentTasksMenu
            }
            TextField("What are you focusing on?", text: $taskName)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, TFSpacing.m)
                .padding(.vertical, 10)
                .tfCard(cornerRadius: TFRadius.medium)
                .focused($taskFieldFocused)
                .onSubmit(startIfPossible)
                .accessibilityLabel("Task name")
                .accessibilityIdentifier("timeFrame.timer.taskField")
        }
    }

    /// The most recent distinct task names, newest first. Derived from the bounded recent
    /// query — no new store, no second history surface.
    private var recentTaskNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for session in recentSessions {
            let name = session.taskName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
            if names.count == 8 { break }
        }
        return names
    }

    @ViewBuilder
    private var recentTasksMenu: some View {
        let names = recentTaskNames
        Menu {
            if names.isEmpty {
                Text("No recent tasks yet")
            } else {
                ForEach(names, id: \.self) { name in
                    Button(name) {
                        taskName = name
                        taskFieldFocused = false
                    }
                }
            }
        } label: {
            Text("Recent Tasks")
                .font(.subheadline)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(names.isEmpty)
        .accessibilityLabel("Recent tasks")
        .accessibilityHint("Fills the task field with a task you focused on before")
        .accessibilityIdentifier("timeFrame.timer.recentTasks")
    }

    // MARK: Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            TFSectionHeader(title: "Configuration") {
                Button(action: openConfigurations) {
                    HStack(spacing: 2) {
                        Text("Manage Configurations")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.link)
                .accessibilityLabel("Manage configurations")
                .accessibilityHint("Opens the Configurations screen")
                .accessibilityIdentifier("timeFrame.timer.manageConfigurations")
            }

            configurationChooser
        }
    }

    @ViewBuilder
    private var configurationChooser: some View {
        Menu {
            ForEach(configurations) { config in
                Button {
                    selectedConfigurationID = config.id
                } label: {
                    Text(config.isDefault ? "\(config.name) (Default)" : config.name)
                }
            }
        } label: {
            HStack(spacing: TFSpacing.m) {
                TFSymbolTile(systemImage: "slider.horizontal.3", size: .medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedConfiguration?.name ?? "Choose a configuration")
                        .font(.headline)
                    Text(configurationSummaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: TFSpacing.s)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TFSpacing.m)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // `.button` + `.plain` keeps the custom label exactly as laid out; the borderless
        // menu style collapses a rich label into a compact pill.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .tfCard(cornerRadius: TFRadius.medium)
        .accessibilityLabel("Configuration")
        .accessibilityValue(selectedConfiguration.map { "\($0.name), \(configurationSummaryLine)" } ?? "None chosen")
        .accessibilityHint("Choose which Pomodoro configuration this run uses")
        .accessibilityIdentifier("timeFrame.timer.configuration")
    }

    /// "45 min focus · 5 min short break · 15 min long break · 4 sessions" — one line, so the
    /// chooser stays a single compact row.
    private var configurationSummaryLine: String {
        guard let config = selectedConfiguration else { return "No configuration available" }
        let sessions = config.defaultTotalSessions == 1 ? "1 session" : "\(config.defaultTotalSessions) sessions"
        return [
            "\(TimeFormatting.minutesLabel(config.focusDuration)) focus",
            "\(TimeFormatting.minutesLabel(config.shortBreakDuration)) short break",
            "\(TimeFormatting.minutesLabel(config.longBreakDuration)) long break",
            sessions
        ].joined(separator: " · ")
    }

    // MARK: Focus sessions

    private var sessionCountSection: some View {
        HStack(alignment: .center, spacing: TFSpacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus Sessions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Number of focus sessions for this run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: TFSpacing.s)
            sessionStepper
        }
    }

    private var sessionStepper: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", label: "Decrease focus sessions") {
                totalSessions = max(1, totalSessions - 1)
            }
            .disabled(totalSessions <= 1)

            Text("\(totalSessions)")
                .font(.body.monospacedDigit())
                .frame(minWidth: 30)

            stepperButton(systemImage: "plus", label: "Increase focus sessions") {
                totalSessions = min(ConfigurationLimits.maxTotalSessions, totalSessions + 1)
            }
            .disabled(totalSessions >= ConfigurationLimits.maxTotalSessions)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .tfCard(cornerRadius: TFRadius.medium)
        .fixedSize()
        // One adjustable element for VoiceOver, matching how a native stepper reads.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus sessions")
        .accessibilityValue("\(totalSessions)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: totalSessions = min(ConfigurationLimits.maxTotalSessions, totalSessions + 1)
            case .decrement: totalSessions = max(1, totalSessions - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("timeFrame.timer.sessionStepper")
    }

    private func stepperButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    // MARK: Session plan preview

    private func planSection(for configuration: PomodoroConfiguration) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            TFSectionHeader(title: "Session Plan",
                            caption: "Preview of the session sequence.") {
                HStack(spacing: TFSpacing.xs) {
                    Text("Show:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Show", selection: $planFilter) {
                        ForEach(SessionPlanFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Show")
                    .accessibilityValue(planFilter.title)
                    .accessibilityIdentifier("timeFrame.timer.planFilter")
                }
            }

            IntervalPlanPreview(plan: draft.plan(for: configuration.snapshot),
                                includes: planFilter.includes)
        }
    }

    // MARK: Start

    /// The screen's one prominent action — compact and content-sized, not a full-width slab
    /// (Milestone 30, ADR-108). It sits at the natural macOS control height and carries the
    /// shared `tfPrimaryAction` treatment, so "what a primary action looks like" is one
    /// decision rather than a per-screen guess.
    ///
    /// A disabled Start says why in text as well as by being dim, so the reason is never
    /// carried by appearance alone (§48).
    private var startButton: some View {
        HStack(spacing: TFSpacing.m) {
            Button(action: startIfPossible) {
                Label("Start", systemImage: "play.fill")
            }
            .tfPrimaryAction()
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canStart)
            .help("Start the session (Command-Return)")
            .accessibilityLabel("Start session")
            .accessibilityHint(canStart ? "Begins the first focus interval" : "Enter a task first")
            .accessibilityIdentifier("timeFrame.timer.start")

            if !canStart {
                Text("Enter a task to start.")
                    .font(TFTypography.metadata)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, TFSpacing.xs)
    }

    private var canStart: Bool {
        draft.isValid && selectedConfiguration != nil
    }

    // MARK: Actions

    private func syncSelectionDefaults() {
        if selectedConfiguration == nil {
            selectedConfigurationID = (configurations.first { $0.isDefault } ?? configurations.first)?.id
        }
        syncSessionCountToConfiguration()
    }

    /// Resets the run's session count to the selected configuration's default
    /// (the count is a per-run override, seeded from — but never written back to —
    /// the configuration). Skipped once while a template prefill is being applied,
    /// so the prefill's own session count is preserved.
    private func syncSessionCountToConfiguration() {
        if suppressNextCountSync {
            suppressNextCountSync = false
            return
        }
        if let config = selectedConfiguration {
            totalSessions = min(max(1, config.defaultTotalSessions), ConfigurationLimits.maxTotalSessions)
        }
    }

    /// Copies a queued template prefill (see `SessionSetupPrefill`) into the
    /// editable fields, then clears it. The template's configuration is selected
    /// only if it still exists; the session count is the template's default, which
    /// the user may then change for this run only.
    private func applyPendingSetupIfNeeded() {
        guard let prefill = pendingSetup else { return }
        taskName = prefill.taskName
        if let id = prefill.configurationID,
           id != selectedConfigurationID,
           configurations.contains(where: { $0.id == id }) {
            // Setting the configuration triggers the count-reset onChange; suppress
            // it so the prefill's session count survives.
            suppressNextCountSync = true
            selectedConfigurationID = id
        }
        totalSessions = min(max(1, prefill.totalSessions), ConfigurationLimits.maxTotalSessions)
        pendingSetup = nil
        taskFieldFocused = false
    }

    private func startIfPossible() {
        guard draft.isValid, let configuration = selectedConfiguration else {
            taskFieldFocused = true
            return
        }
        // Defensive: never create a second active session (structurally the setup
        // screen is only shown when no session is active).
        guard !coordinator.engine.state.isActive else {
            errorMessage = "A session is already active. Stop it before starting a new one."
            return
        }
        do {
            try coordinator.startSession(
                configuration: configuration,
                taskName: draft.trimmedTaskName,
                totalSessions: totalSessions
            )
            taskName = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
