//
//  LoginItemService.swift
//  time_frame (Milestone 32)
//
//  "Open at Login", isolated behind a service (ADR-112).
//
//  This is the ONLY file that imports ServiceManagement, mirroring how EventKit lives only in
//  `EventKitCalendarService` and UserNotifications only in `UserNotificationService`. The rest
//  of the app talks to `LoginItemManaging`, so the coordinator and the Settings surface are
//  testable without registering anything on the developer's machine.
//
//  The registration itself is macOS's modern `SMAppService.mainApp`: the app registers *itself*
//  as a login item, with no helper bundle and no deprecated `LSSharedFileList` /
//  `SMLoginItemSetEnabled` call. Crucially, `SMAppService` also *reports* the real state, which
//  is what lets the toggle reflect what the system actually believes rather than a remembered
//  preference (§4).
//

import Foundation
import ServiceManagement
import os

/// What macOS says about Time Frame's login item. Read from the system, never stored.
enum LoginItemStatus: String, Equatable, Sendable {
    /// Registered: macOS will launch Time Frame at login.
    case enabled
    /// Not registered. macOS reports this both for "never registered" and "registered then
    /// removed"; from the user's point of view they are the same thing — off.
    case disabled
    /// Registered, but the user has not approved it in System Settings › General › Login
    /// Items. It will not launch until they do, so the toggle must not read as on.
    case requiresApproval
    /// The system could not answer (an unknown status from a future OS). Treated as "not on"
    /// and surfaced as unavailable rather than guessed.
    case unavailable

    /// Whether the toggle should read as on. Only an approved registration counts.
    var isEnabled: Bool { self == .enabled }
}

/// The closed set of ways "Open at Login" can fail. A leaked `SMAppService` error is never
/// shown to the user (mirrors `TimeFrameIntentError` and `CalendarIntegrationError`).
enum LoginItemError: Equatable, Sendable, LocalizedError {
    /// macOS refused the registration.
    case registrationFailed
    /// macOS refused to remove the login item.
    case unregistrationFailed
    /// Registered, but waiting for the user's approval in System Settings.
    case requiresApproval
    /// Login items are not available for this build (unsigned, or a system that cannot
    /// answer). Reported honestly rather than shown as a working switch.
    case unavailable

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Time Frame couldn't be added to your login items."
        case .unregistrationFailed:
            return "Time Frame couldn't be removed from your login items."
        case .requiresApproval:
            return "Time Frame needs your approval to open at login."
        case .unavailable:
            return "Open at Login isn't available for this copy of Time Frame."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .registrationFailed, .unregistrationFailed:
            return "You can change this in System Settings › General › Login Items & Extensions."
        case .requiresApproval:
            return "Allow Time Frame in System Settings › General › Login Items & Extensions."
        case .unavailable:
            return "This usually means the app isn't signed. A release build can register itself."
        }
    }

    /// Whether offering "Open Login Items Settings" helps for this failure.
    var suggestsSystemSettings: Bool { self != .unavailable }
}

/// The isolation seam. Injectable so the coordinator, the Settings surface, and the tests
/// never touch the real login-item database.
protocol LoginItemManaging: Sendable {
    /// The system's current answer. Cheap, synchronous, and authoritative.
    func currentStatus() -> LoginItemStatus
    /// Registers the app as a login item.
    func register() async throws
    /// Removes the app from the user's login items.
    func unregister() async throws
    /// Opens System Settings at the Login Items pane, for a registration awaiting approval.
    func openSystemSettings()
}

/// The production implementation, over `SMAppService.mainApp`.
///
/// `register()`/`unregister()` are `nonisolated async`, so the ServiceManagement calls run off
/// the main actor and a slow response can never block the timer's UI (§29). They are called
/// exactly once per user action — never retried in a loop (§3).
struct SMAppServiceLoginItem: LoginItemManaging {

    func currentStatus() -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .notFound: return .disabled
        case .requiresApproval: return .requiresApproval
        @unknown default: return .unavailable
        }
    }

    func register() async throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            AppLog.appLifecycle.error("Login item registration failed.")
            throw LoginItemError.registrationFailed
        }
    }

    func unregister() async throws {
        do {
            try await SMAppService.mainApp.unregister()
        } catch {
            AppLog.appLifecycle.error("Login item removal failed.")
            throw LoginItemError.unregistrationFailed
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The service used while the app target is hosting the unit tests, and anywhere login items
/// genuinely cannot work. It reports `unavailable` and does nothing, so the suite can never
/// register the developer's build as a login item (the hermeticity rule of ADR-077).
struct UnavailableLoginItemService: LoginItemManaging {
    func currentStatus() -> LoginItemStatus { .unavailable }
    func register() async throws { throw LoginItemError.unavailable }
    func unregister() async throws { throw LoginItemError.unavailable }
    func openSystemSettings() {}
}
