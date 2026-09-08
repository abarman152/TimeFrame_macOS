//
//  UserNotificationService.swift
//  time_frame
//
//  The **only** file in Time Frame that imports UserNotifications. It adapts the app's
//  pure notification vocabulary (descriptors, categories, statuses, actions) to
//  `UNUserNotificationCenter` and back. No `UNNotificationRequest` /
//  `UNMutableNotificationContent` / `UNNotificationResponse` ever escapes this type
//  (§9). Raw UserNotifications errors are mapped to `NotificationIntegrationError` so
//  the coordinator and UI never see a technical error (§49).
//

import Foundation
import UserNotifications
import os

/// Production `NotificationScheduling` backed by the system notification center.
///
/// A single `UNUserNotificationCenter.current()` is used for the app's lifetime. All
/// work happens on the main actor; the operations are small and infrequent (only on
/// meaningful transitions — §53). The type is the center's delegate so it can turn a
/// user's response into a pure `ReceivedNotificationAction` (§37).
@MainActor
final class UserNotificationService: NSObject, NotificationScheduling {

    private let center = UNUserNotificationCenter.current()

    /// Invoked on the main actor when the user responds to a Time Frame notification.
    var onAction: ((ReceivedNotificationAction) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: Authorization

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        let current = await center.notificationSettings().authorizationStatus
        if current == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                AppLog.notifications.error("Notification authorization request failed: \(String(describing: error), privacy: .public)")
            }
        }
        let status = await authorizationStatus()
        AppLog.notifications.info("Notification authorization status: \(status.rawValue, privacy: .public).")
        return status
    }

    // MARK: Categories

    func registerCategories(_ categories: [NotificationCategoryDescriptor]) {
        let unCategories = categories.map { descriptor -> UNNotificationCategory in
            let actions = descriptor.actions.compactMap(Self.action(for:))
            return UNNotificationCategory(
                identifier: descriptor.category.identifier,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
        }
        center.setNotificationCategories(Set(unCategories))
    }

    // MARK: Scheduling

    func schedule(_ descriptor: NotificationDescriptor) async throws {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        if let subtitle = descriptor.subtitle { content.subtitle = subtitle }
        content.body = descriptor.body
        // Only attach the category (and therefore action buttons) when actions are
        // enabled; the semantic category is still used for identity/dedup elsewhere.
        if descriptor.showsActions { content.categoryIdentifier = descriptor.category.identifier }
        // Group a session's notifications together in the notification center.
        content.threadIdentifier = descriptor.sessionID.uuidString
        content.userInfo = ["sessionID": descriptor.sessionID.uuidString]
        content.sound = Self.sound(for: descriptor.sound)
        // Pomodoro transitions are ordinary, non-alarm notifications (§42): the
        // standard active level, never time-sensitive or critical (which would bypass
        // Focus / Do Not Disturb).
        content.interruptionLevel = .active

        let trigger = Self.trigger(for: descriptor.fireDate)
        let request = UNNotificationRequest(
            identifier: descriptor.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            AppLog.notifications.info("Scheduled notification \(descriptor.category.rawValue, privacy: .public).")
        } catch {
            AppLog.notifications.error("Notification scheduling failed: \(String(describing: error), privacy: .public)")
            throw NotificationIntegrationError.schedulingFailed
        }
    }

    func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelPending(withPrefix prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let matching = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !matching.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: matching)
        AppLog.notifications.info("Cancelled \(matching.count, privacy: .public) pending notification(s).")
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    // MARK: Mapping helpers

    /// Builds a time-interval trigger for a future fire date, or nil to deliver
    /// immediately. `UNTimeIntervalNotificationTrigger` requires a strictly positive
    /// interval, so a past/near date delivers now.
    private static func trigger(for fireDate: Date?) -> UNNotificationTrigger? {
        guard let fireDate else { return nil }
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }

    private static func sound(for sound: NotificationSound) -> UNNotificationSound? {
        switch sound {
        case .default: return .default
        case .none: return nil
        }
    }

    private static func action(for action: NotificationAction) -> UNNotificationAction? {
        // The `open` action is the default body tap, not a button.
        guard action != .open else { return nil }
        var options: UNNotificationActionOptions = []
        if action.isDestructive { options.insert(.destructive) }
        return UNNotificationAction(identifier: action.identifier, title: action.title, options: options)
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .authorized // App Clip only; treat as authorized if seen.
        @unknown default: return .denied
        }
    }

    /// Parses a raw response's action identifier into a pure `NotificationAction`, or
    /// nil for a dismissal we ignore.
    nonisolated private static func action(fromResponseIdentifier identifier: String) -> NotificationAction? {
        if identifier == UNNotificationDefaultActionIdentifier { return .open }
        if identifier == UNNotificationDismissActionIdentifier { return nil }
        return NotificationAction.allCases.first { $0.identifier == identifier }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UserNotificationService: UNUserNotificationCenterDelegate {

    /// Present Time Frame notifications even when the app is frontmost, so a session
    /// running in the open app still alerts the user.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Route a user's response back into the app as a pure action. Parsing is done off
    /// the raw response here (the only place a `UNNotificationResponse` exists); the
    /// pure value is then handed to `onAction` on the main actor (§37).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let action = Self.action(fromResponseIdentifier: response.actionIdentifier) else { return }
        let sessionID = (response.notification.request.content.userInfo["sessionID"] as? String)
            .flatMap(UUID.init(uuidString:))
        let received = ReceivedNotificationAction(action: action, sessionID: sessionID)
        Task { @MainActor [weak self] in
            self?.onAction?(received)
        }
    }
}
