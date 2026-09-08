//
//  CalendarEventPreviewView.swift
//  time_frame
//
//  The "Add to Calendar" sheet for a plan (§29/§50). It shows exactly what will be
//  created, lets the user pick the start time, calendar, style, and (for a single
//  event) the title, and gates on Calendar permission. Nothing here can affect a
//  timer — it only ever writes calendar events for a *plan*.
//

import SwiftUI

struct CalendarEventPreviewView: View {
    @Bindable var calendarCoordinator: CalendarCoordinator
    let plan: SessionPlan

    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var style: CalendarEventStyle = .singlePlan
    @State private var calendarID: String?
    @State private var titleOverride = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var status: CalendarAuthorizationStatus { calendarCoordinator.authorizationStatus }
    private var alreadyAdded: Bool { calendarCoordinator.record(for: plan) != nil }

    var body: some View {
        NavigationStack {
            Form {
                if status.isSufficient {
                    previewSection
                    optionsSection
                    if alreadyAdded { alreadyAddedNotice }
                } else {
                    permissionSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to Calendar")
            .frame(minWidth: 420, minHeight: 460)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("calendar.preview.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(alreadyAdded ? "Update Calendar" : "Add to Calendar", action: add)
                        .disabled(!status.isSufficient || isWorking)
                        .accessibilityIdentifier("calendar.preview.add")
                }
            }
            .task { await load() }
            .alert("Calendar Error",
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        Section("Preview") {
            LabeledContent("Plan", value: plan.name.isEmpty ? "Untitled Plan" : plan.name)
            if !plan.taskName.isEmpty { LabeledContent("Task", value: plan.taskName) }
            LabeledContent("When", value: timeRangeText)
            LabeledContent("Sessions", value: "\(plan.focusCount) focus · \(breakCount) breaks")
            LabeledContent("Events created", value: "\(draftCount)")
        }
        .accessibilityIdentifier("calendar.preview.summary")
    }

    private var optionsSection: some View {
        Section("Options") {
            DatePicker("Starts", selection: $startDate)
                .accessibilityIdentifier("calendar.preview.start")

            CalendarPickerView(calendars: calendarCoordinator.availableCalendars, selection: $calendarID)

            Picker("Event Style", selection: $style) {
                ForEach(CalendarEventStyle.allCases) { style in
                    Text(style.displayLabel).tag(style)
                }
            }
            .accessibilityIdentifier("calendar.preview.style")

            if style == .singlePlan {
                TextField("Event Title", text: $titleOverride, prompt: Text(defaultTitle))
                    .accessibilityIdentifier("calendar.preview.title")
            }
        }
    }

    private var alreadyAddedNotice: some View {
        Section {
            Label {
                Text("This plan is already on your calendar. Adding again replaces the existing event(s).")
            } icon: {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(.green)
            }
            .font(.callout)
        }
    }

    private var permissionSection: some View {
        Section {
            switch status {
            case .notDetermined:
                Text("Time Frame needs Calendar access to create events.")
                Button("Allow Calendar Access") {
                    Task { await calendarCoordinator.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("calendar.preview.allowAccess")
            case .restricted:
                Text("Calendar access is restricted on this Mac.")
            default:
                Text("Calendar access is turned off. Enable it in System Settings, then try again.")
                Button("Open System Settings") { calendarCoordinator.openSystemSettings() }
                    .accessibilityIdentifier("calendar.preview.openSystemSettings")
            }
        }
    }

    // MARK: Derived

    private var drafts: [CalendarEventDraft] {
        calendarCoordinator.previewDrafts(
            for: plan,
            startDate: startDate,
            style: style,
            calendarIdentifier: calendarID,
            titleOverride: style == .singlePlan ? titleOverride : nil
        )
    }

    private var draftCount: Int { max(1, drafts.count) }
    private var breakCount: Int { plan.orderedItems.filter { $0.phase.isBreak }.count }
    private var defaultTitle: String { plan.taskName.isEmpty ? plan.name : plan.taskName }

    private var timeRangeText: String {
        let start = startDate
        let end = startDate.addingTimeInterval(plan.totalDuration)
        let startText = start.formatted(date: .abbreviated, time: .shortened)
        let endText = end.formatted(date: .omitted, time: .shortened)
        return "\(startText) – \(endText)"
    }

    // MARK: Actions

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        style = calendarCoordinator.preferences.eventStyle
        calendarID = calendarCoordinator.preferences.defaultCalendarIdentifier
        calendarCoordinator.refreshAuthorization()
        if status.isSufficient { await calendarCoordinator.loadCalendars() }
    }

    private func add() {
        isWorking = true
        Task {
            let ok = await calendarCoordinator.addPlan(
                plan,
                startDate: startDate,
                style: style,
                calendarIdentifier: calendarID,
                titleOverride: style == .singlePlan ? titleOverride : nil
            )
            isWorking = false
            if ok {
                dismiss()
            } else {
                errorMessage = calendarCoordinator.lastErrorMessage ?? "Couldn't add the event to your calendar."
            }
        }
    }
}
