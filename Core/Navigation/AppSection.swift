//
//  AppSection.swift
//  time_frame
//
//  The top-level navigation destinations shown in the sidebar.
//

import Foundation

/// The primary areas of the app, listed in the macOS sidebar in this order.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today
    case timer
    case templates
    case plans
    case configurations
    case history
    case statistics
    case settings

    var id: Self { self }

    /// The sidebar label.
    var title: String {
        switch self {
        case .today: "Today"
        case .timer: "Timer"
        case .templates: "Templates"
        case .plans: "Plans"
        case .configurations: "Configurations"
        case .history: "History"
        case .statistics: "Statistics"
        case .settings: "Settings"
        }
    }

    /// The SF Symbol shown beside the label.
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .timer: "timer"
        case .templates: "square.stack.3d.up"
        case .plans: "list.bullet.rectangle"
        case .configurations: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        case .statistics: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}
