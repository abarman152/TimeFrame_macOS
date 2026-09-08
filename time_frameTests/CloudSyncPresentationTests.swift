//
//  CloudSyncPresentationTests.swift
//  time_frameTests (Milestone 13)
//
//  The pure iCloud-sync presentation projection and the closed reason enum. Every
//  (mode, account, preference) combination maps to exactly one phase, with plain,
//  colour-independent phrasing. No CloudKit, no running app.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Cloud sync presentation state")
struct CloudSyncPresentationTests {

    // MARK: Phase resolution

    @Test("CloudKit active + account available → available")
    func available() {
        let s = CloudSyncPresentationState.resolve(mode: .cloudKit, account: .available, syncEnabled: true)
        #expect(s.phase == .available)
        #expect(s.isSyncing)
    }

    @Test("CloudKit active + syncing flag → syncing")
    func syncing() {
        let s = CloudSyncPresentationState.resolve(mode: .cloudKit, account: .available, syncEnabled: true, isSyncing: true)
        #expect(s.phase == .syncing)
        #expect(s.isSyncing)
    }

    @Test("CloudKit active but no account → unavailable")
    func cloudNoAccount() {
        let s = CloudSyncPresentationState.resolve(mode: .cloudKit, account: .unavailable, syncEnabled: true)
        #expect(s.phase == .unavailable)
        #expect(!s.isSyncing)
    }

    @Test("Local by choice (sync off) → localOnly")
    func localOnly() {
        let s = CloudSyncPresentationState.resolve(mode: .local, account: .available, syncEnabled: false)
        #expect(s.phase == .localOnly)
    }

    @Test("Local while sync wanted → unavailable (needs account)")
    func localWanted() {
        let s = CloudSyncPresentationState.resolve(mode: .local, account: .unavailable, syncEnabled: true)
        #expect(s.phase == .unavailable)
    }

    @Test("Fallback with no account → unavailable")
    func fallbackNoAccount() {
        let s = CloudSyncPresentationState.resolve(mode: .fallback, account: .unavailable, syncEnabled: true)
        #expect(s.phase == .unavailable)
    }

    @Test("Fallback with an account present → error")
    func fallbackError() {
        let s = CloudSyncPresentationState.resolve(mode: .fallback, account: .available, syncEnabled: true)
        #expect(s.phase == .error)
    }

    // MARK: Phrasing (never colour-only)

    @Test("Every phase carries distinct, non-empty text, symbol, and explanation")
    func phrasing() {
        var statusWords: Set<String> = []
        for phase in CloudSyncPresentationState.Phase.allCases {
            let s = state(for: phase)
            #expect(!s.statusText.isEmpty)
            #expect(!s.symbolName.isEmpty)
            #expect(!s.explanation.isEmpty)
            #expect(s.title == "iCloud Sync")
            statusWords.insert(s.statusText)
        }
        // Each phase reads as its own word — no phase relies on colour to be told apart.
        #expect(statusWords.count == CloudSyncPresentationState.Phase.allCases.count)
    }

    // MARK: Reason enum

    @Test("Reason is nil only when actively syncing")
    func reason() {
        #expect(CloudSyncError.reason(mode: .cloudKit, account: .available, syncEnabled: true) == nil)
        #expect(CloudSyncError.reason(mode: .cloudKit, account: .unavailable, syncEnabled: true) == .accountUnavailable)
        #expect(CloudSyncError.reason(mode: .fallback, account: .available, syncEnabled: true) == .cloudKitUnavailable)
        #expect(CloudSyncError.reason(mode: .fallback, account: .unavailable, syncEnabled: true) == .accountUnavailable)
        #expect(CloudSyncError.reason(mode: .local, account: .unavailable, syncEnabled: false) == .syncDisabled)
        #expect(CloudSyncError.reason(mode: .local, account: .unavailable, syncEnabled: true) == .accountUnavailable)
        // Every closed reason has user-facing phrasing.
        for reason in CloudSyncError.allCases {
            #expect(!(reason.errorDescription ?? "").isEmpty)
        }
    }

    // Builds a representative state for a phase by choosing inputs that resolve to it.
    private func state(for phase: CloudSyncPresentationState.Phase) -> CloudSyncPresentationState {
        switch phase {
        case .available:   return .resolve(mode: .cloudKit, account: .available, syncEnabled: true)
        case .syncing:     return .resolve(mode: .cloudKit, account: .available, syncEnabled: true, isSyncing: true)
        case .unavailable: return .resolve(mode: .cloudKit, account: .unavailable, syncEnabled: true)
        case .localOnly:   return .resolve(mode: .local, account: .available, syncEnabled: false)
        case .error:       return .resolve(mode: .fallback, account: .available, syncEnabled: true)
        }
    }
}
