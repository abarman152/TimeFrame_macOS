//
//  IntentDependencies.swift
//  time_frame (Milestone 12)
//
//  How the App Intents layer reaches the app's ONE authoritative `SessionCoordinator` and
//  the persisted repositories, without a global singleton and without a second timer or a
//  second database (ADR-059). The app registers its already-owned instances with the App
//  Intents `AppDependencyManager` at launch; intents and entity queries declare
//  `@AppDependency` to receive exactly those instances when the runtime invokes them in the
//  app process.
//
//  This is a *locator*, not new state: the coordinator is still created and owned by
//  `time_frameApp`, and the data provider only vends repositories over the app's existing
//  `ModelContainer`. Nothing here mutates the timer or persists anything of its own.
//

import Foundation
import SwiftData
import AppIntents

/// A tiny, read-through provider that vends the persistence repositories the App Intents
/// entity queries need. It holds the app's existing `ModelContainer` and builds a repository
/// over its main context on demand — the same repositories the UI uses (ADR-057). `@MainActor`
/// (hence `Sendable`) because SwiftData's `mainContext` is main-actor isolated.
@MainActor
final class IntentDataProvider {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    var templates: TaskTemplateRepository { TaskTemplateRepository(context: container.mainContext) }
    var plans: SessionPlanRepository { SessionPlanRepository(context: container.mainContext) }
    var configurations: ConfigurationRepository { ConfigurationRepository(context: container.mainContext) }
}

/// Registers the app's authoritative instances with the App Intents dependency manager, so
/// intents (`@AppDependency var coordinator`) and entity queries (`@AppDependency var data`)
/// receive the *same* coordinator and container the rest of the app uses.
///
/// Called once from `time_frameApp.init()` on a normal launch. Skipped while hosting unit
/// tests: the test suite exercises the intents' logic directly against its own in-memory
/// coordinators and repositories (mirroring every other layer's tests), so the live store is
/// never advertised to — or touched by — the runner.
@MainActor
enum TimeFrameAppIntents {
    static func registerDependencies(coordinator: SessionCoordinator, container: ModelContainer) {
        // Build the main-actor provider here (this method is `@MainActor`), then hand the
        // already-constructed, Sendable instance to the dependency manager — the registration
        // autoclosure is nonisolated and must not itself call a main-actor initializer.
        let dataProvider = IntentDataProvider(container: container)
        AppDependencyManager.shared.add(dependency: coordinator)
        AppDependencyManager.shared.add(dependency: dataProvider)
    }

    /// Advertises the app's widget-control router (Milestone 15) so the shared widget-control
    /// intents — run by the system in the app process when a widget button is pressed — resolve
    /// the SAME router the app wired to `AppIntentSessionActions` and the widget projection
    /// writer (ADR-069). Built app-side and passed in already-constructed, mirroring the
    /// coordinator/data-provider registration above. Skipped while hosting unit tests.
    static func registerWidgetControl(_ actions: WidgetControlActions) {
        AppDependencyManager.shared.add(dependency: actions)
    }
}
