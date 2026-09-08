//
//  StatisticsPeriodPicker.swift
//  time_frame
//
//  The period selector for the Statistics dashboard (Milestone 10). A quiet menu of
//  fixed periods plus a Custom option that reveals two native date pickers whose
//  bounds enforce start ≤ end, so an impossible range can never be built. This view
//  only chooses *which* range to view — all aggregation stays in the pure engine.
//

import SwiftUI

/// The user-selectable statistics periods, mapped to the pure `StatisticsPeriod`.
enum StatisticsPeriodChoice: String, CaseIterable, Identifiable {
    case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .lastWeek: "Last Week"
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .custom: "Custom"
        }
    }

    /// Resolves to the pure period, supplying custom bounds only for `.custom`.
    func period(customStart: Date, customEnd: Date) -> StatisticsPeriod {
        switch self {
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .lastWeek: .lastWeek
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .custom: .custom(start: customStart, end: customEnd)
        }
    }
}

/// A menu-style period picker with an inline custom-range editor.
struct StatisticsPeriodPicker: View {
    @Binding var choice: StatisticsPeriodChoice
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.m) {
            Picker("Period", selection: $choice) {
                ForEach(StatisticsPeriodChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Statistics period")

            if choice == .custom {
                customRange
                    .transition(.opacity)
            }
        }
        .tfAnimation(TFMotion.control, value: choice)
    }

    private var customRange: some View {
        HStack(spacing: TFSpacing.l) {
            // Bounds enforce start ≤ end natively: the start can't exceed the end and
            // the end can't precede the start, so no validation error is possible.
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
            DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
        }
        .datePickerStyle(.field)
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.m)
        .tfQuietSurface(cornerRadius: TFRadius.medium)
    }
}
