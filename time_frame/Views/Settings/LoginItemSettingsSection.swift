//
//  LoginItemSettingsSection.swift
//  time_frame (Milestone 32)
//
//  Settings › General › Open at Login (ADR-112).
//
//  A native `Toggle` in the existing grouped `Form`, with one line of explanation — the same
//  shape as the Menu Bar and Notifications sections. No card, no gradient, no custom switch.
//
//  The toggle is bound to the *system's* answer, not to a stored preference: turning it on
//  asks macOS to register the login item and then re-reads the status, so a refusal leaves
//  the switch off with the reason stated. It can never show a success the system did not give.
//

import SwiftUI

struct LoginItemSettingsSection: View {
    @Bindable var loginItem: LoginItemCoordinator

    var body: some View {
        Section("General") {
            Toggle("Open at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { newValue in
                    Task { await loginItem.setEnabled(newValue) }
                }
            ))
            .disabled(loginItem.isChanging || !loginItem.isAvailable)
            .accessibilityLabel("Open Time Frame at Login")
            .accessibilityHint("Automatically opens Time Frame when you log in to your Mac")
            .accessibilityIdentifier("settings.general.openAtLogin")

            Text("Automatically open Time Frame when you log in to your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = loginItem.lastError {
                // The words carry the meaning; the colour only reinforces it (§48). Announced
                // as one element so VoiceOver reads the problem and its remedy together.
                VStack(alignment: .leading, spacing: TFSpacing.s) {
                    TFNoticeBanner(message: message(for: error))
                    if error.suggestsSystemSettings {
                        Button("Open Login Items Settings") { loginItem.openSystemSettings() }
                            .accessibilityIdentifier("settings.general.openAtLogin.systemSettings")
                    }
                }
            }
        }
    }

    /// The user-facing sentence for a failure: what happened, then what to do about it.
    private func message(for error: LoginItemError) -> String {
        [error.errorDescription, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
