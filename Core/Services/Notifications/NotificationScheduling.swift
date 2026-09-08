//
//  NotificationScheduling.swift
//  time_frame
//
//  The boundary protocol between Time Frame and any notification backend. It trades
//  only in pure value types (descriptors, categories, statuses, actions) — never a
//  `UNNotificationRequest`, `UNUserNotificationCenter`, or `UNNotificationResponse`.
//  `UserNotificationService` is the production adapter; `FakeNotificationService`
//  (test target) drives deterministic tests without touching the real notification
//  center or requiring a permission prompt (§52).
//

import Foundation

/// A description of a notification category to register with the system, so delivered
/// notifications carry the right action buttons. Pure — the adapter maps it to a
/// `UNNotificationCategory`.
nonisolated struct NotificationCategoryDescriptor: Equatable, Sendable {
    let category: NotificationCategory
    /// The actions offered, in display order.
    let actions: [NotificationAction]
}

/// A notification backend Time Frame can schedule, cancel, and read permission from.
///
/// `@MainActor` because the work is small and infrequent (only on meaningful
/// transitions — §53) and the adapter touches AppKit-adjacent state. Every throwing
/// method throws `NotificationIntegrationError`, never a raw UserNotifications error.
@MainActor
protocol NotificationScheduling: AnyObject {

    /// The current authorization status (no prompt).
    func authorizationStatus() async -> NotificationAuthorizationStatus

    /// Requests authorization if undecided, returning the resulting status. Requesting
    /// after a decision does not re-prompt.
    func requestAuthorization() async -> NotificationAuthorizationStatus

    /// Registers the categories (and their actions) the app can deliver. Idempotent;
    /// does not prompt.
    func registerCategories(_ categories: [NotificationCategoryDescriptor])

    /// Schedules (or replaces, by identifier) a single notification.
    func schedule(_ descriptor: NotificationDescriptor) async throws

    /// Cancels the pending notifications with the given identifiers. Safe if some are
    /// already gone.
    func cancel(identifiers: [String])

    /// Cancels every *pending* Time Frame notification whose identifier begins with
    /// `prefix`. Time Frame only ever passes one of its own namespaced prefixes, so it
    /// never removes another app's notifications (§35).
    func cancelPending(withPrefix prefix: String) async

    /// The identifiers of all pending notifications (used by tests and diagnostics).
    func pendingIdentifiers() async -> [String]

    /// A closure invoked (on the main actor) when the user responds to a Time Frame
    /// notification. The adapter parses the raw response into a pure
    /// `ReceivedNotificationAction` before calling this.
    var onAction: ((ReceivedNotificationAction) -> Void)? { get set }
}
