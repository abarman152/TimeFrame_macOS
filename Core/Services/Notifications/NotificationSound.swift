//
//  NotificationSound.swift
//  time_frame
//
//  The (deliberately small) set of notification sound choices. Pure vocabulary —
//  the adapter maps it to a `UNNotificationSound`. No custom audio assets (§41).
//

import Foundation

/// How a Time Frame notification sounds.
nonisolated enum NotificationSound: String, Codable, Sendable, CaseIterable, Hashable {
    /// The system default notification sound.
    case `default`
    /// Silent (banner/list only).
    case none
}
