//
//  NotificationDescriptor.swift
//  time_frame
//
//  The core, framework-independent representation of a notification Time Frame wants
//  to deliver or schedule. Deliberately free of UserNotifications: the adapter is the
//  only place a descriptor becomes a `UNNotificationRequest` (§10/§48). Everything the
//  scheduler and tests need is a pure value.
//

import Foundation

/// A stable, namespaced identifier for a Time Frame notification.
///
/// Identity is `session id + interval index + type` (§34) — never the title — so a
/// notification can be replaced, cancelled, and de-duplicated. All identifiers share
/// the `root` prefix, and each session's share a per-session prefix, so Time Frame can
/// cancel *only its own* notifications (§35) and only those of one session.
nonisolated enum NotificationIdentifier {
    /// The shared root for every Time Frame notification.
    static let root = "com.timeframe.notification"

    /// The prefix matching *every* Time Frame notification (for a global cancel that
    /// still never touches another app's notifications).
    static let rootPrefix = "\(root)."

    /// The prefix matching every notification belonging to one session.
    static func sessionPrefix(_ sessionID: UUID) -> String {
        "\(root).\(sessionID.uuidString)."
    }

    /// The identifier for the notification announcing the start of interval `index`.
    static func transition(sessionID: UUID, intervalIndex: Int) -> String {
        "\(root).\(sessionID.uuidString).\(intervalIndex).transition"
    }

    /// The identifier for a session's single completion notification.
    static func completion(sessionID: UUID) -> String {
        "\(root).\(sessionID.uuidString).completion"
    }
}

/// The rendered text of a notification: a title, an optional subtitle (the task), and
/// a concise body. Produced purely by `NotificationContentGenerator`.
nonisolated struct NotificationContent: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let body: String
}

/// A pure value describing one notification to schedule or deliver.
///
/// Contains **no** `UNNotificationRequest`, `UNNotificationContent`, or
/// `UNNotificationTrigger`. `fireDate == nil` means "deliver as soon as possible"; a
/// future date becomes a time-interval trigger inside the adapter (§21).
nonisolated struct NotificationDescriptor: Equatable, Sendable, Identifiable {
    /// The stable, namespaced identifier (see `NotificationIdentifier`).
    let identifier: String
    let content: NotificationContent
    /// When the notification should fire, or nil to deliver immediately.
    let fireDate: Date?
    let category: NotificationCategory
    let sound: NotificationSound
    /// Whether the delivered notification should carry action buttons. When false the
    /// adapter omits the category identifier so no buttons appear (the "actions"
    /// preference is off).
    let showsActions: Bool
    /// The session this notification belongs to (carried in `userInfo` so a response
    /// can be routed back to the right session — §34/§40).
    let sessionID: UUID

    var id: String { identifier }

    var title: String { content.title }
    var subtitle: String? { content.subtitle }
    var body: String { content.body }
}
