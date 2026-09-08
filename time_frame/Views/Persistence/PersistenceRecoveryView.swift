//
//  PersistenceRecoveryView.swift
//  time_frame (Milestone 31)
//
//  What Time Frame shows when it could not open the user's data (ADR-109).
//
//  ## Why this screen exists
//  The failure this milestone fixes was not only that the store was deleted — it was that
//  the app then looked *completely normal*. An empty Templates list and an empty History
//  are indistinguishable from a fresh install, so the user's first signal that years of
//  history had gone was the absence of something they had to think to look for.
//
//  So a failed open now takes over the window. The app says plainly that it could not open
//  the data, says just as plainly that **nothing has been deleted**, and offers three
//  actions — one of which, and only one, is destructive-adjacent, and it asks first.
//
//  Presentation only: it owns no store, opens no database, and performs no filesystem work
//  itself. Every action is a closure supplied by the app.
//

import SwiftUI

struct PersistenceRecoveryView: View {
    let failure: StoreOpenFailure
    /// Re-attempts the same open. Changes nothing on disk either way.
    let retry: () -> Void
    /// Reveals the folder containing the store, so the user can copy it somewhere safe.
    let revealInFinder: () -> Void
    /// Moves the existing store into a timestamped recovery folder and starts fresh.
    /// Confirmed first — this is the only action that changes anything.
    let startFresh: () -> Void

    @State private var confirmingStartFresh = false

    var body: some View {
        VStack(spacing: TFSpacing.xl) {
            Spacer(minLength: 0)

            VStack(spacing: TFSpacing.m) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(TFPalette.warning)
                    .accessibilityHidden(true)

                Text("Time Frame couldn't open your data")
                    .font(TFTypography.pageTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                // The single most important sentence on this screen.
                Text("Your data has not been deleted.")
                    .font(TFTypography.sectionTitle)
                    .foregroundStyle(TFPalette.running)

                Text(failure.kind.userExplanation)
                    .font(TFTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(failure.kind.userSuggestion)
                    .font(TFTypography.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 460)

            actions

            // The technical detail, available but not shouted. Useful in a support report;
            // it names the failure and its codes, never the user's content.
            DisclosureGroup("Details") {
                Text(failure.underlying)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, TFSpacing.xs)
            }
            .font(TFTypography.metadata)
            .frame(maxWidth: 460)
            .accessibilityIdentifier("persistence.recovery.details")

            Spacer(minLength: 0)
        }
        .padding(TFSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("persistence.recovery")
        .confirmationDialog(
            "Start with an empty Time Frame?",
            isPresented: $confirmingStartFresh,
            titleVisibility: .visible
        ) {
            Button("Keep My Data and Start Fresh") { startFresh() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your existing data will be moved to a dated folder called \"\(StoreQuarantine.directoryName)\" beside it, so you can recover it later. It is not deleted.")
        }
    }

    /// One prominent action, sized to its content (ADR-108). "Try Again" leads because it is
    /// the only action that costs nothing — for a locked file it is also the fix.
    private var actions: some View {
        HStack(spacing: TFSpacing.s) {
            Button(action: retry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .tfPrimaryAction()
            .buttonStyle(.glassProminent)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityHint("Attempts to open your data again. Nothing is changed either way.")
            .accessibilityIdentifier("persistence.recovery.retry")

            Button(action: revealInFinder) {
                Label("Show in Finder", systemImage: "folder")
            }
            .tfSecondaryAction()
            .buttonStyle(.bordered)
            .accessibilityHint("Opens the folder containing your data so you can make a copy")
            .accessibilityIdentifier("persistence.recovery.reveal")

            Button { confirmingStartFresh = true } label: {
                Label("Continue Without Existing Data", systemImage: "archivebox")
            }
            .tfSecondaryAction()
            .buttonStyle(.bordered)
            .accessibilityHint("Moves your existing data to a dated recovery folder and starts with an empty library. Asks for confirmation first.")
            .accessibilityIdentifier("persistence.recovery.startFresh")
        }
    }
}
