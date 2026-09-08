//
//  EmptyStateView.swift
//  time_frame
//
//  A small, reusable empty-state built on the native `ContentUnavailableView`.
//

import SwiftUI

/// A consistent empty state with an optional primary action.
///
/// Wraps `ContentUnavailableView` so every screen's "nothing here yet" state
/// looks native and identical, with room for a single call-to-action button.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                // The single call-to-action is the dominant control on an empty state
                // (§53), rendered as a prominent Liquid Glass button.
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
