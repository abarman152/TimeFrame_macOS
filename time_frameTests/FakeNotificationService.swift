//
//  FakeNotificationService.swift
//  time_frameTests
//
//  A deterministic, in-memory NotificationScheduling for tests. No UserNotifications,
//  no real notification center, no permission prompt (§52). Authorization status and
//  per-operation failures are configurable so every branch (including scheduling
//  failure and permission denial) can be exercised.
//

import Foundation
@testable import time_frame

@MainActor
final class FakeNotificationService: NotificationScheduling {

    // MARK: Configurable state

    var status: NotificationAuthorizationStatus
    /// The status a `requestAuthorization()` resolves to when currently `.notDetermined`.
    var grantsOnRequest: NotificationAuthorizationStatus

    /// Inject a failure into `schedule` (nil = succeed).
    var failSchedule: NotificationIntegrationError?

    // MARK: Observed effects

    /// The currently pending notifications, keyed by identifier (a schedule with an
    /// existing identifier replaces it, mirroring UNUserNotificationCenter).
    private(set) var pending: [String: NotificationDescriptor] = [:]
    private(set) var scheduleCount = 0
    private(set) var cancelledIdentifiers: [String] = []
    private(set) var cancelPrefixCount = 0
    private(set) var requestCount = 0
    private(set) var registeredCategories: [NotificationCategoryDescriptor] = []

    var onAction: ((ReceivedNotificationAction) -> Void)?

    init(
        status: NotificationAuthorizationStatus = .authorized,
        grantsOnRequest: NotificationAuthorizationStatus = .authorized
    ) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    // MARK: NotificationScheduling

    func authorizationStatus() async -> NotificationAuthorizationStatus { status }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        requestCount += 1
        if status == .notDetermined { status = grantsOnRequest }
        return status
    }

    func registerCategories(_ categories: [NotificationCategoryDescriptor]) {
        registeredCategories = categories
    }

    func schedule(_ descriptor: NotificationDescriptor) async throws {
        if let failSchedule { throw failSchedule }
        scheduleCount += 1
        pending[descriptor.identifier] = descriptor
    }

    func cancel(identifiers: [String]) {
        cancelledIdentifiers.append(contentsOf: identifiers)
        for identifier in identifiers { pending[identifier] = nil }
    }

    func cancelPending(withPrefix prefix: String) async {
        cancelPrefixCount += 1
        let matching = pending.keys.filter { $0.hasPrefix(prefix) }
        for identifier in matching { pending[identifier] = nil }
        cancelledIdentifiers.append(contentsOf: matching)
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) }

    // MARK: Test helpers

    /// Delivers a user response to the coordinator, as macOS would.
    func simulateAction(_ received: ReceivedNotificationAction) {
        onAction?(received)
    }

    var pendingDescriptors: [NotificationDescriptor] { Array(pending.values) }
    var pendingCount: Int { pending.count }

    /// Pending descriptors of a given category.
    func pending(ofCategory category: NotificationCategory) -> [NotificationDescriptor] {
        pendingDescriptors.filter { $0.category == category }
    }
}
