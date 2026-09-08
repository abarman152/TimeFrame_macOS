//
//  PlanListView.swift
//  time_frame
//
//  Manage Session Plans: create, view, edit, duplicate, delete, and start. All
//  persistence goes through the SessionPlanRepository (via the coordinator); the
//  view never touches the ModelContext directly. Starting a plan runs it through the
//  existing SessionCoordinator and switches to the Timer. A pending draft (generated
//  from a template or configuration) is consumed here to open the editor pre-filled.
//
//  ## Milestone 29
//  The screen gained the shared page header, a native `searchable` filter, and card rows.
//  It also stopped owning the *detail* page's editor: a sheet requested from this view while a
//  `navigationDestination` is pushed does not present on macOS until the stack pops back,
//  which is why "Edit" on a plan's detail page did nothing (ADR-106). The detail page now
//  presents its own editor; this list still owns the editor for Create, for a seeded draft,
//  and for its own row actions, where the root view is on screen.
//

import SwiftUI
import SwiftData

struct PlanListView: View {
    let coordinator: SessionCoordinator
    /// The Calendar integration, forwarded to the plan detail's "Add to Calendar".
    let calendarCoordinator: CalendarCoordinator
    /// A draft queued by "Create Plan" on a template/configuration, consumed here to
    /// open the editor pre-filled. A binding so this screen can clear it once used.
    @Binding var pendingDraft: SessionPlanDraft?
    /// Switches the app to the Timer area after a plan starts.
    let openTimer: () -> Void

    @Query(sort: \SessionPlan.updatedAt, order: .reverse)
    private var plans: [SessionPlan]

    @State private var editorTarget: EditorTarget?
    @State private var planToDelete: SessionPlan?
    @State private var errorMessage: String?
    @State private var activeSessionBlocked = false
    @State private var searchText = ""

    /// The plans that match the current search, most recently updated first.
    private var visiblePlans: [SessionPlan] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return plans }
        return plans.filter { plan in
            plan.name.localizedCaseInsensitiveContains(query)
                || plan.taskName.localizedCaseInsensitiveContains(query)
                || PlanRowPresentation.configurationChip(for: plan).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Plans")
            .navigationDestination(for: UUID.self) { id in
                if let plan = plans.first(where: { $0.id == id }) {
                    PlanDetailView(
                        coordinator: coordinator,
                        calendarCoordinator: calendarCoordinator,
                        plan: plan,
                        onStarted: openTimer
                    )
                } else {
                    ContentUnavailableView("Plan Unavailable", systemImage: "questionmark.folder")
                }
            }
            .searchable(text: $searchText, prompt: "Search plans")
            .toolbar {
                ToolbarItem {
                    Button {
                        editorTarget = .create
                    } label: {
                        Label("New Plan", systemImage: "plus")
                    }
                    .help("Create a new plan (Command-N)")
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("plan.new")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            PlanEditorView(coordinator: coordinator, existing: target.plan, seed: target.seed)
        }
        .onAppear(perform: consumePendingDraft)
        .onChange(of: pendingDraft) { _, _ in consumePendingDraft() }
        .confirmationDialog(
            "Delete this plan?",
            isPresented: Binding(get: { planToDelete != nil },
                                 set: { if !$0 { planToDelete = nil } }),
            titleVisibility: .visible,
            presenting: planToDelete
        ) { plan in
            Button("Delete \(plan.name)", role: .destructive) { delete(plan) }
            Button("Cancel", role: .cancel) { planToDelete = nil }
        } message: { _ in
            Text("This removes the plan only. Any session you've started from it, and your History, are not affected.")
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
    }

    @ViewBuilder
    private var content: some View {
        if plans.isEmpty {
            EmptyStateView(
                title: "No Session Plans",
                systemImage: "list.bullet.rectangle",
                message: "Build reusable multi-session plans for longer focus blocks.",
                actionTitle: "Create Plan",
                action: { editorTarget = .create }
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.l) {
                TFPageHeader(title: "Plans",
                             subtitle: "Organize your focus with structured plans.")

                if visiblePlans.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, TFSpacing.xxl)
                } else {
                    LazyVStack(spacing: TFSpacing.s) {
                        ForEach(visiblePlans) { plan in
                            row(for: plan)
                        }
                    }

                    Text(plans.count == 1 ? "1 plan" : "\(plans.count) plans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, TFSpacing.xs)
                }
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(for plan: SessionPlan) -> some View {
        HStack(spacing: 0) {
            NavigationLink(value: plan.id) {
                PlanRowView(plan: plan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlanRowPresentation.accessibilityLabel(for: plan))
            .accessibilityHint("Opens the plan")

            TFRowActions(
                start: plan.isStartable ? { requestStart(plan) } : nil,
                startLabel: "Start \(plan.name)",
                startHelp: "Start a session from this plan",
                menuLabel: "More actions for \(plan.name)",
                menu: { rowMenu(plan) }
            )
        }
        .tfCard()
        .contextMenu { rowMenu(plan) }
        .accessibilityIdentifier("plan.row.\(plan.id.uuidString)")
    }

    @ViewBuilder
    private func rowMenu(_ plan: SessionPlan) -> some View {
        if plan.isStartable {
            Button { requestStart(plan) } label: { Label("Start", systemImage: "play.fill") }
        }
        QuickStartPinMenuButton(name: plan.name,
                                isPinned: plan.isPinned) { togglePin(plan) }
        Button { editorTarget = .edit(plan) } label: { Label("Edit", systemImage: "pencil") }
        Button { duplicate(plan) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { planToDelete = plan } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Actions

    private func consumePendingDraft() {
        guard let draft = pendingDraft else { return }
        editorTarget = .createFrom(draft)
        pendingDraft = nil
    }

    private func requestStart(_ plan: SessionPlan) {
        guard plan.isStartable else { return }
        guard !coordinator.engine.state.isActive else {
            activeSessionBlocked = true
            return
        }
        do {
            if try coordinator.startPlan(plan.executionSnapshot) != nil {
                openTimer()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Toggles the Quick Start pin. Immediate, reversible, and never confirmed by a dialog.
    private func togglePin(_ plan: SessionPlan) {
        perform { try coordinator.plans.setPinned(plan, !plan.isPinned) }
    }

    private func duplicate(_ plan: SessionPlan) {
        perform { try coordinator.plans.duplicate(plan) }
    }

    private func delete(_ plan: SessionPlan) {
        perform { try coordinator.plans.delete(plan) }
        planToDelete = nil
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
        case createFrom(SessionPlanDraft)
        case edit(SessionPlan)

        var id: String {
            switch self {
            case .create: "create"
            case .createFrom: "createFrom"
            case .edit(let plan): plan.id.uuidString
            }
        }

        var plan: SessionPlan? {
            switch self {
            case .edit(let plan): plan
            default: nil
            }
        }

        var seed: SessionPlanDraft? {
            switch self {
            case .createFrom(let draft): draft
            default: nil
            }
        }
    }
}
