//
//  ProductionReadinessM32Tests.swift
//  time_frameTests (Milestone 32)
//
//  The single-window and login-item invariants, enforced by scanning the source tree.
//
//  The duplicate window was not a bug in one button. It was four buttons that each held the
//  window-opening capability and each did the same three lines slightly differently, over a
//  `WindowGroup` — a scene type whose entire purpose is to allow more than one window. A fifth
//  button would have arrived the same way. These audits fail the build if it does:
//
//    • the app declares a single-instance `Window`, never a `WindowGroup`;
//    • only the window service touches `openWindow`, `makeKeyAndOrderFront`, `deminiaturize`,
//      or `NSApplication.activate`;
//    • no boolean stands in for the window's real state (§6);
//    • ServiceManagement is imported by exactly one file, and the login item is never
//      persisted in UserDefaults (§4).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Production readiness — Milestone 32")
struct ProductionReadinessM32Tests {

    // MARK: Paths

    private var windowServiceFiles: [String] {
        ["MainWindowPolicy.swift", "MainWindowPresenter.swift", "AppKitMainWindowHost.swift",
         "MainWindowPresentation.swift", "TimeFrameAppDelegate.swift"]
    }

    private func appSource(_ relativePath: String) -> String {
        SourceAudit.code(SourceAudit.appTarget().appendingPathComponent(relativePath))
    }

    private func appSourceKeepingStrings(_ relativePath: String) -> String {
        SourceAudit.codeKeepingStrings(SourceAudit.appTarget().appendingPathComponent(relativePath))
    }

    // MARK: 1 — One main window, expressed by the scene type

    @Test("The window service exists where the audit expects it")
    func windowServiceExists() {
        for name in windowServiceFiles {
            let text = appSource("Services/Window/\(name)")
            #expect(text.isEmpty == false, "Services/Window/\(name) not found")
        }
    }

    @Test("The app declares a single-instance Window, never a WindowGroup")
    func sceneIsSingleInstance() {
        let app = appSourceKeepingStrings("time_frameApp.swift")
        #expect(app.contains("Window(\"Time Frame\", id: MainWindow.id)"),
                "The main scene must be a single-instance `Window`")
        #expect(!SourceAudit.references(app, "WindowGroup"),
                "A WindowGroup permits a second window by design (ADR-111)")
    }

    @Test("No production source anywhere declares a WindowGroup")
    func noWindowGroupAnywhere() {
        let offenders = SourceAudit.filesReferencing(["WindowGroup"],
                                                     in: SourceAudit.productionRoots())
        #expect(offenders.isEmpty, "WindowGroup found in: \(offenders)")
    }

    // MARK: 2 — One pathway

    @Test("openWindow is reachable from exactly one file")
    func oneOpener() {
        let offenders = SourceAudit.filesReferencing(["openWindow"],
                                                     in: SourceAudit.productionRoots())
        #expect(offenders == ["MainWindowPresentation.swift"],
                "Every surface must ask the presenter, not open a window itself: \(offenders)")
    }

    @Test("Window ordering and focus live only in the AppKit host")
    func oneFocusImplementation() {
        let tokens = ["makeKeyAndOrderFront", "orderFront", "orderFrontRegardless",
                      "deminiaturize", "unhide"]
        let offenders = SourceAudit.filesReferencing(tokens, in: SourceAudit.productionRoots())
            .filter { $0 != "AppKitMainWindowHost.swift" && $0 != "MainWindowPresenter.swift"
                        && $0 != "MainWindowPolicy.swift" }
        #expect(offenders.isEmpty,
                "Window ordering must go through AppKitMainWindowHost: \(offenders)")
    }

    @Test("Application activation is confined to the window host and the notification opener")
    func activationIsConfined() {
        // `NotificationCoordinator` brings the app forward when the user opens a notification.
        // It activates the *application* and cannot create a window, so it is not a
        // window-creation path — but it is listed here so any new activator is caught.
        let offenders = SourceAudit.filesReferencing(["NSApplication.shared.activate", "NSApp.activate"],
                                                     in: SourceAudit.productionRoots())
        #expect(offenders == ["AppKitMainWindowHost.swift", "NotificationCoordinator.swift"],
                "Unexpected application activators: \(offenders)")
    }

    @Test("The menu bar asks for the window and decides nothing")
    func menuBarUsesTheSeam() {
        for name in ["MenuBarGearMenu.swift", "MenuBarOpenSectionButton.swift",
                     "TimeFrameMenuBarView.swift"] {
            let text = appSource("Views/MenuBar/\(name)")
            #expect(text.contains("showMainWindow"), "\(name) must use the one seam")
            #expect(!SourceAudit.references(text, "openWindow"),
                    "\(name) must not open a window itself")
            #expect(!text.contains("NSApplication.shared.activate"),
                    "\(name) must not activate the app itself")
        }
    }

    @Test("The reopen handler consults real window state, not hasVisibleWindows")
    func reopenUsesRealState() {
        let delegate = appSource("Services/Window/TimeFrameAppDelegate.swift")
        #expect(delegate.contains("applicationShouldHandleReopen"))
        #expect(delegate.contains("windowPresenter.showMainWindow()"),
                "A Dock reopen must go through the same presenter as every other surface")
        // `hasVisibleWindows` is false for a minimized window and for a hidden app; branching
        // on it is what produced a second window while the first sat in the Dock.
        #expect(!delegate.contains("if hasVisibleWindows"),
                "The reopen must not branch on hasVisibleWindows")
    }

    @Test("Closing the main window does not quit the app, so a session survives Cmd-W")
    func closingTheWindowDoesNotTerminate() {
        // A single-instance `Window` terminates the app on close unless this is answered —
        // unlike the `WindowGroup` it replaced. Without it, Cmd-W ends a running Pomodoro.
        let delegate = appSource("Services/Window/TimeFrameAppDelegate.swift")
        #expect(delegate.contains("func applicationShouldTerminateAfterLastWindowClosed"),
                "The single-instance Window scene must be told not to quit on close")
        let body = delegate.components(separatedBy: "applicationShouldTerminateAfterLastWindowClosed")
            .last ?? ""
        #expect(body.contains("false"),
                "It must return false — the menu bar keeps the app and its session alive")
    }

    // MARK: 3 — No boolean stands in for the window (§6)

    @Test("Window state is read from the window, never cached in a flag")
    func noWindowBoolean() {
        for name in windowServiceFiles {
            let text = appSource("Services/Window/\(name)")
            for forbidden in ["windowIsOpen", "windowAlreadyOpen", "hasMainWindow",
                              "didOpenWindow", "isWindowOpen"] {
                #expect(!text.contains(forbidden),
                        "\(name) caches window state in `\(forbidden)` — read the window (§6)")
            }
        }
    }

    @Test("The host holds its window weakly, so a closed window leaves nothing behind")
    func windowIsHeldWeakly() {
        let host = appSource("Services/Window/AppKitMainWindowHost.swift")
        #expect(host.contains("private weak var registeredWindow"),
                "A strong NSWindow reference outlives the window the user closed (§13)")
        #expect(host.contains("NSWindow.willCloseNotification"),
                "A closed window must deregister itself")
    }

    @Test("The policy is pure: no AppKit, no SwiftUI, no timer")
    func policyIsPure() {
        let policy = appSource("Services/Window/MainWindowPolicy.swift")
        for forbidden in ["import AppKit", "import SwiftUI", "import SwiftData",
                          "NSWindow", "NSApplication"] {
            #expect(!policy.contains(forbidden),
                    "MainWindowPolicy must stay decidable without AppKit — found \(forbidden)")
        }
    }

    @Test("The window layer introduces no scheduling primitive and no polling")
    func windowLayerHasNoClock() {
        for name in windowServiceFiles {
            let text = appSource("Services/Window/\(name)")
            for primitive in ["Task.sleep", "Timer(", "scheduledTimer", "asyncAfter",
                              "DispatchSourceTimer", "TimelineView", "while "] {
                #expect(!SourceAudit.references(text, primitive),
                        "\(name) must add no clock or poll — found \(primitive)")
            }
        }
    }

    @Test("The window layer owns no timer, session, or store")
    func windowLayerOwnsNoDomain() {
        for name in windowServiceFiles {
            let text = appSource("Services/Window/\(name)")
            for forbidden in ["TimerEngine(", "SessionCoordinator(", "import SwiftData",
                              "ModelContext", "save()"] {
                #expect(!text.contains(forbidden),
                        "\(name) must stay window-only — found \(forbidden)")
            }
        }
    }

    @Test("Focusing a window uses native activation, with no artificial highlight (§16)")
    func nativeHighlightOnly() {
        let host = appSource("Services/Window/AppKitMainWindowHost.swift")
        for forbidden in ["withAnimation", "flash", "pulse", "shake", "NSHapticFeedback"] {
            #expect(!text(host, contains: forbidden),
                    "Window focus must look like every other macOS window — found \(forbidden)")
        }
    }

    private func text(_ source: String, contains token: String) -> Bool {
        source.localizedCaseInsensitiveContains(token)
    }

    // MARK: 4 — Open at Login is real, not remembered (§2/§4)


    @Test("SMAppService is reached only through the isolated service")
    func smAppServiceIsIsolated() {
        // `SMAppService.` — the type being *used*. The concrete service's own name
        // (`SMAppServiceLoginItem`) is named at the app's launch wiring, which is the seam
        // being injected, not a second place that talks to ServiceManagement.
        let users = SourceAudit.filesReferencing(["SMAppService."], in: SourceAudit.productionRoots())
        #expect(users == ["LoginItemService.swift"], "SMAppService leaked into: \(users)")
    }

    @Test("No deprecated login-item mechanism is used")
    func noDeprecatedLoginItemAPI() {
        let tokens = ["SMLoginItemSetEnabled", "LSSharedFileList", "kLSSharedFileListSessionLoginItems",
                      "SMJobBless"]
        let offenders = SourceAudit.filesReferencing(tokens, in: SourceAudit.productionRoots())
        #expect(offenders.isEmpty, "Deprecated login-item API used in: \(offenders)")
    }

    @Test("The login item is never persisted — the system's registration is the truth")
    func noFakeLoginItemPreference() {
        for name in ["Services/Login/LoginItemService.swift",
                     "Services/Login/LoginItemCoordinator.swift",
                     "Views/Settings/LoginItemSettingsSection.swift"] {
            let text = appSource(name)
            #expect(!text.contains("UserDefaults"),
                    "\(name) must not store the login-item state (§4)")
            #expect(!text.contains("@AppStorage"),
                    "\(name) must not store the login-item state (§4)")
        }
    }

    @Test("Every change re-reads the system before reporting a result")
    func statusIsReadBack() {
        let coordinator = appSource("Services/Login/LoginItemCoordinator.swift")
        #expect(coordinator.contains("status = service.currentStatus()"),
                "setEnabled must end by re-reading the system, not by trusting the request")
        #expect(coordinator.contains("var isEnabled: Bool { status.isEnabled }"),
                "The toggle must be derived from the system status")
    }

    @Test("A change in flight cannot become a retry loop (§3)")
    func noRetryLoop() {
        let coordinator = appSource("Services/Login/LoginItemCoordinator.swift")
        #expect(coordinator.contains("guard !isChanging else { return }"))
        for primitive in ["Task.sleep", "Timer(", "scheduledTimer", "asyncAfter", "while ", "repeat "] {
            #expect(!SourceAudit.references(coordinator, primitive),
                    "The login-item coordinator must not retry on a schedule — found \(primitive)")
        }
    }

    @Test("The setting is a native toggle with an accessibility label (§22/§23)")
    func settingIsNative() {
        let section = appSourceKeepingStrings("Views/Settings/LoginItemSettingsSection.swift")
        #expect(section.contains("Toggle(\"Open at Login\""))
        #expect(section.contains("Open Time Frame at Login"), "the accessibility label")
        #expect(section.contains("settings.general.openAtLogin"))
        #expect(section.contains("Automatically open Time Frame when you log in to your Mac."))
        // Native controls only — no bespoke switch, card, or gradient (§22).
        for forbidden in ["LinearGradient", "RoundedRectangle(cornerRadius: 24", "ToggleStyle("] {
            #expect(!section.contains(forbidden), "found \(forbidden)")
        }
    }

    @Test("Launch keeps the suite out of the real login-item database (ADR-077)")
    func testHostUsesUnavailableService() {
        let app = appSource("time_frameApp.swift")
        #expect(app.contains("isHostingUnitTests ? UnavailableLoginItemService() : SMAppServiceLoginItem()"),
                "The test host must never register the developer's build as a login item")
    }

    // MARK: 5 — Nothing else changed


    @Test("Exactly one application delegate exists")
    func oneAppDelegate() {
        let delegates = SourceAudit.swiftSources(inAnyOf: SourceAudit.productionRoots())
            .filter { SourceAudit.code($0).contains("NSApplicationDelegate {") }
            .map { $0.lastPathComponent }
        #expect(delegates == ["TimeFrameAppDelegate.swift"], "Found: \(delegates)")

        // …and it is installed exactly once.
        let adaptors = SourceAudit.swiftSources(inAnyOf: SourceAudit.productionRoots())
            .filter { SourceAudit.code($0).contains("NSApplicationDelegateAdaptor") }
            .map { $0.lastPathComponent }
        #expect(adaptors == ["time_frameApp.swift"], "Found: \(adaptors)")
    }

    @Test("Exactly one main-window presenter type exists")
    func onePresenter() {
        let declaring = SourceAudit.swiftSources(inAnyOf: SourceAudit.productionRoots())
            .filter { SourceAudit.code($0).contains("final class MainWindowPresenter") }
            .map { $0.lastPathComponent }
        #expect(declaring == ["MainWindowPresenter.swift"])
    }

    @Test("The window and login layers persist nothing to the store")
    func noPersistenceChange() {
        for name in windowServiceFiles.map({ "Services/Window/\($0)" })
            + ["Services/Login/LoginItemService.swift", "Services/Login/LoginItemCoordinator.swift"] {
            let text = appSource(name)
            #expect(!text.contains("ModelContainer"), "\(name) must not touch persistence")
            #expect(!text.contains("FetchDescriptor"), "\(name) must not touch persistence")
        }
    }

    @Test("The macOS deep-link scheme and App Group are unchanged")
    func integrationsUnchanged() {
        let deepLink = SourceAudit.codeKeepingStrings(
            SourceAudit.shared().appendingPathComponent("WidgetDeepLink.swift"))
        #expect(deepLink.contains("timeframe"), "the deep-link scheme must not change")
    }
}
