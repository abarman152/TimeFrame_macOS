//
//  TimeFrameSchema.swift
//  time_frame
//
//  The versioned SwiftData schema and migration plan for Time Frame.
//

import Foundation
import SwiftData

/// Version 1 of the Time Frame persistence schema (Milestone 1).
///
/// Retained as a historical version anchor only. Milestone 1 persisted **no
/// durable session or interval data** — its UI drove an in-memory engine, and
/// the sole stored row was an idempotently re-seeded default configuration — so
/// there is no user data contract to migrate faithfully. Milestone 2 supersedes
/// this with `TimeFrameSchemaV2`; see ADR-016 in `docs/DECISIONS.md` for why an
/// old on-disk store is rebuilt rather than migrated field-by-field.
enum TimeFrameSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PomodoroConfiguration.self, FocusSession.self, SessionInterval.self]
    }
}

/// Version 2 of the Time Frame persistence schema (Milestone 2).
///
/// Adds the persisted session lifecycle: `FocusSession.status` is now a
/// dedicated `SessionStatus` (with `planned`/`interrupted`), `SessionInterval`
/// carries an `IntervalStatus` plus recovery anchors (`targetEndAt`,
/// `remainingAtPause`), and `PomodoroConfiguration` gains `isDefault`. This is
/// the current schema the app runs on.
enum TimeFrameSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PomodoroConfiguration.self, FocusSession.self, SessionInterval.self]
    }
}

/// Version 3 of the Time Frame persistence schema (Milestone 3).
///
/// Adds `FocusSession.configurationName`: the configuration's name frozen at the
/// moment the session started, so the History screen stays historically accurate
/// even after the configuration is renamed or deleted (ADR-019).
///
/// Like V1/V2 this version references the *current* model types (the project
/// does not keep frozen per-version copies of the `@Model` classes). Following
/// the store's established policy (ADR-016), an older on-disk store that is not
/// structurally identical to the current schema is **rebuilt** by
/// `PersistenceController` rather than field-migrated — the only data lost is the
/// re-seedable default configuration and any dev-only prior sessions. The store
/// therefore has no field-level migration stage; incompatible opens throw and are
/// caught and rebuilt.
enum TimeFrameSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PomodoroConfiguration.self, FocusSession.self, SessionInterval.self]
    }
}

/// Version 4 of the Time Frame persistence schema (Milestone 4).
///
/// Adds the `TaskTemplate` `@Model`: a reusable task definition that references a
/// `PomodoroConfiguration` (via a new nullify relationship on the configuration's
/// `taskTemplates` inverse). Templates are a *starting point* for sessions and
/// carry no historical data of their own (ADR-021).
///
/// Like V1–V3 this version references the *current* model types (the project does
/// not keep frozen per-version copies of the `@Model` classes). Following the
/// store's established policy (ADR-016/019), an older on-disk store that is not
/// structurally identical to the current schema is **rebuilt** by
/// `PersistenceController` rather than field-migrated — the only data lost is the
/// re-seedable default configuration and any dev-only prior sessions/templates.
/// The store therefore has no field-level migration stage; incompatible opens
/// throw and are caught and rebuilt.
enum TimeFrameSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PomodoroConfiguration.self, FocusSession.self, SessionInterval.self, TaskTemplate.self]
    }
}

/// Version 5 of the Time Frame persistence schema (Milestone 5).
///
/// Adds the Session Planner models: `SessionPlan` and its owned, ordered
/// `SessionPlanItem`s (a new nullify relationship on the configuration's
/// `planItems` inverse), plus a frozen `SessionInterval.configurationName` so a
/// session started from a multi-configuration plan records which configuration each
/// focus used. Plans are a *planning* layer — they carry no timer state and starting
/// one produces an independent `FocusSession` through the existing engine (ADR-026/028).
///
/// Like V1–V4 this version references the *current* model types (the project does
/// not keep frozen per-version copies of the `@Model` classes). Following the
/// store's established policy (ADR-016/019/021), an older on-disk store that is not
/// structurally identical to the current schema is **rebuilt** by
/// `PersistenceController` rather than field-migrated — the only data lost is the
/// re-seedable default configuration and any dev-only prior sessions/templates/plans.
/// The store therefore has no field-level migration stage; incompatible opens throw
/// and are caught and rebuilt.
enum TimeFrameSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PomodoroConfiguration.self, FocusSession.self, SessionInterval.self,
            TaskTemplate.self, SessionPlan.self, SessionPlanItem.self
        ]
    }
}

/// Version 6 of the Time Frame persistence schema (Milestone 13).
///
/// Makes the schema **CloudKit-compatible** so SwiftData can mirror the store to
/// the user's private CloudKit database (ADR-060/061). Two changes, both required
/// by CloudKit's constraints:
///
/// 1. The `#Unique<…>([\.id])` constraint is **removed from every model**. CloudKit
///    mirroring does not support unique constraints, and — importantly — leaving one
///    in place breaks the *local* store too once a CloudKit-backed configuration is
///    used. Identity is still a freshly minted `UUID`; the repositories never reuse
///    ids, so uniqueness holds in practice without a database-level constraint.
/// 2. `FocusSession` gains an **optional** `originatingDeviceID` — the device that
///    started a session — so timer recovery stays device-local across synced
///    devices (ADR-063). Optional, so it is CloudKit-legal and back-compatible.
///
/// The model *set* is unchanged from V5 (same six types). Like V1–V5, this version
/// references the *current* model types (the project keeps no frozen per-version
/// copies). Following the store's established policy (ADR-016/019/021), an older
/// on-disk store that is not structurally identical to the current schema is
/// **rebuilt** by `PersistenceController` rather than field-migrated — the only data
/// lost is the re-seedable default configuration and any dev-only prior
/// sessions/templates/plans. The store therefore has no field-level migration stage;
/// incompatible opens throw and are caught and rebuilt.
enum TimeFrameSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PomodoroConfiguration.self, FocusSession.self, SessionInterval.self,
            TaskTemplate.self, SessionPlan.self, SessionPlanItem.self
        ]
    }
}

/// Version 7 of the Time Frame persistence schema (Milestone 28).
///
/// Adds the Quick Start identity fields to the two *reusable definition* models —
/// `TaskTemplate` and `SessionPlan`. The model **set** is unchanged (the same six
/// types as V5/V6); only attributes are added, and each is either defaulted or
/// optional, so the change is CloudKit-legal (ADR-061) and lightweight-migratable:
///
/// - `iconIdentifier: String` (defaulted) — the stable catalog identifier of the
///   user's chosen icon. Never an SF Symbol name, never free text; it is resolved
///   through `TimeFrameIconIdentifier` and falls back to the type's default when it
///   is not recognised (ADR-103).
/// - `isPinned: Bool` (defaulted) + `pinnedAt: Date?` (optional) — whether the item
///   is pinned to Quick Start and when. Pin state lives on the item itself, keyed by
///   its stable `id`, so a rename keeps the pin and a delete removes the item from
///   Quick Start with no orphaned side table to reconcile (ADR-104).
///
/// Like V1–V6, this version references the *current* model types (the project keeps
/// no frozen per-version copies). Because every added attribute carries a default or
/// is optional, SwiftData opens an existing V6 store in place.
///
/// **Milestone 31:** that sentence used to be an unverified claim — nothing in the codebase
/// could write a V6 store, so nothing could execute the upgrade. It is now proven by
/// `PersistenceMigrationV6ToV7Tests`, which writes a genuine V6 store through frozen V6 model
/// copies (`SchemaV6Fixture`, test target only) and reopens it here: identities, values,
/// timestamps, relationships and session history all survive, and the attributes added above
/// read as their defaults on rows that predate them.
///
/// If a store cannot be opened at all it is now **preserved and reported**, never rebuilt —
/// ADR-016's rebuild-on-incompatibility safety net was removed in Milestone 31 because it
/// destroyed real user data (ADR-109).
enum TimeFrameSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PomodoroConfiguration.self, FocusSession.self, SessionInterval.self,
            TaskTemplate.self, SessionPlan.self, SessionPlanItem.self
        ]
    }
}

/// The current schema version alias. One place to bump when a new version ships.
typealias TimeFrameSchemaLatest = TimeFrameSchemaV7

/// The migration plan across shipped schema versions.
///
/// The plan targets `TimeFrameSchemaV7` directly with no field-level stages. V7 only
/// **adds** defaulted/optional attributes to two existing models, so SwiftData's lightweight
/// migration opens an existing V6 store in place — verified end-to-end against a real V6 store
/// by `PersistenceMigrationV6ToV7Tests`, not assumed.
///
/// An older on-disk store that cannot be opened against the current schema is **preserved and
/// reported** (ADR-109). It is never rebuilt: the previous policy answered a failed open by
/// deleting the user's data, and it destroyed a real library before it was removed.
///
/// Any future version that changes an attribute's *shape* — a rename, a type change, a new
/// non-optional without a default — must append its `VersionedSchema` (with frozen model
/// copies) and a concrete `MigrationStage` here, and ship a fixture test alongside it. A
/// schema version whose migration has never been executed is not a migration.
enum TimeFrameMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TimeFrameSchemaV7.self]
    }

    static var stages: [MigrationStage] { [] }
}
