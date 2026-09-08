//
//  MockTimeSource.swift
//  time_frameTests
//
//  A deterministic, hand-advanced clock so timer behaviour can be verified
//  instantly instead of waiting real seconds.
//

import Foundation
@testable import time_frame

/// A controllable `TimeProviding` for tests.
///
/// The clock never advances on its own — a test moves it forward explicitly
/// with `advance(by:)`. This lets a 25-minute interval be exercised in
/// microseconds and makes every assertion fully deterministic.
nonisolated final class MockTimeSource: TimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.current = start
    }

    nonisolated func now() -> Date {
        lock.withLock { current }
    }

    /// Moves the clock forward by `seconds`.
    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    /// Sets the clock to an absolute instant.
    func set(to date: Date) {
        lock.withLock { current = date }
    }
}
