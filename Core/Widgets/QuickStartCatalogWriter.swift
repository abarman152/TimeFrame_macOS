//
//  QuickStartCatalogWriter.swift
//  time_frame (Milestone 23)
//
//  The app-side writer that publishes a lightweight snapshot of the user's saved timer
//  configurations to the App Group, so the configurable Control Center quick-start control can
//  offer them in its picker (Milestone 23). It is the quick-start counterpart of
//  `WidgetProjectionWriter`: it READS the existing `ConfigurationRepository` and WRITES a pure,
//  Foundation-only `QuickStartCatalog` through `QuickStartCatalogStore` — nothing more.
//
//  It is NOT a source of truth for timing: the catalog carries only display values (id + name +
//  a short subtitle). When the control is tapped, the app re-resolves the AUTHORITATIVE live
//  configuration by id through the existing `AppIntentSessionActions.startSession` seam, so a
//  rename or a duration change takes effect on the next tap and a deleted configuration fails
//  safely (ADR-094). This writer constructs no timer, mutates no session, and is fully defensive:
//  any fetch/store failure is swallowed so publishing the picker can never disturb the app or the
//  one timer.
//
//  Lives in `Core/` (compiled into both the macOS app and the iOS companion); it is never
//  compiled into the widget extension, which only READS the catalog through the shared store.
//

import Foundation

/// Publishes the quick-start picker catalog from the app's configuration repository.
@MainActor
enum QuickStartCatalogWriter {

    /// Rebuilds the catalog from the given configuration repository and writes it to the App
    /// Group. Best-effort and non-throwing: a fetch or store failure is swallowed (the timer and
    /// the app are never affected). Newest-first ordering mirrors the repository, so the picker
    /// lists the user's most recent configurations first.
    static func refresh(
        configurations: ConfigurationRepository,
        store: QuickStartCatalogStore? = nil
    ) {
        // Construct the default store inside the (main-actor) body rather than in a default
        // argument, which the compiler evaluates in a nonisolated context.
        let store = store ?? QuickStartCatalogStore()
        let descriptors: [QuickStartTimerDescriptor]
        do {
            descriptors = try configurations.all().map { configuration in
                QuickStartTimerDescriptor(
                    id: configuration.id,
                    name: configuration.name,
                    focusDuration: configuration.focusDuration,
                    defaultTotalSessions: configuration.defaultTotalSessions
                )
            }
        } catch {
            return   // never propagate toward the app or the timer
        }
        _ = store.write(QuickStartCatalog(timers: descriptors))
    }
}
