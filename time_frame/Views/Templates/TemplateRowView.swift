//
//  TemplateRowView.swift
//  time_frame
//
//  A single row in the Templates list: the chosen icon, the template name (with its Pinned
//  and Default markers), the task it starts, and a compact "configuration · N sessions" line.
//  A missing configuration is shown with words and an icon, never colour alone.
//
//  Milestone 29: the row became a card with a leading icon tile. It renders *content only* —
//  the row's trailing controls are composed by the list outside the navigation link, so a
//  Start or overflow click is never swallowed by the link that wraps the content.
//

import SwiftUI

struct TemplateRowView: View {
    let template: TaskTemplate

    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.m) {
            TimeFrameIconTile(icon: template.icon, size: .medium)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TFSpacing.s) {
                    Text(template.name)
                        .font(.headline)
                        .lineLimit(1)
                    if template.isPinned { QuickStartPinnedMarker() }
                    if template.isDefault { TFDefaultMarker() }
                }

                Text(template.taskName.isEmpty ? "No task" : template.taskName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if template.hasConfiguration {
                    Text(TemplateRowPresentation.configurationLine(for: template))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label("Configuration unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(TFPalette.warning)
                }
            }

            Spacer(minLength: TFSpacing.s)
        }
        .padding(.leading, TFSpacing.m)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// The row's words in one place, so the list and its VoiceOver label agree.
enum TemplateRowPresentation {

    /// "Classic Pomodoro · 4 sessions" — pluralised in Swift, because inflection markup only
    /// renders when the literal goes straight to `Text`.
    static func configurationLine(for template: TaskTemplate) -> String {
        let sessions = template.defaultTotalSessions == 1 ? "1 session" : "\(template.defaultTotalSessions) sessions"
        return "\(template.displayConfigurationName) · \(sessions)"
    }

    /// The VoiceOver phrasing for the row as a whole.
    static func accessibilityLabel(for template: TaskTemplate) -> String {
        let task = template.taskName.isEmpty ? "No task" : template.taskName
        let config = template.hasConfiguration
            ? "\(template.displayConfigurationName), \(template.defaultTotalSessions) sessions"
            : "Configuration unavailable"
        let defaultNote = template.isDefault ? ", default template" : ""
        let pinNote = template.isPinned ? ", pinned to Quick Start" : ""
        return "\(template.name)\(defaultNote)\(pinNote), \(task), \(config)"
    }
}

/// The "Default" marker shared by templates and configurations. States the word, so the
/// status never depends on the tint alone.
struct TFDefaultMarker: View {
    var accessibilityText: String = "Default"

    var body: some View {
        Text("Default")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(.tint)
            .accessibilityLabel(accessibilityText)
    }
}

/// The trailing controls a list row carries: a start affordance and an overflow menu, laid
/// out beside — never inside — the row's navigation link.
struct TFRowActions<RowMenu: View>: View {
    /// Starts the item. `nil` hides the control (the item cannot start).
    var start: (() -> Void)?
    var startLabel: String
    var startHelp: String
    var isStartEnabled: Bool = true
    var menuLabel: String
    @ViewBuilder var menu: () -> RowMenu

    var body: some View {
        HStack(spacing: 2) {
            if let start {
                Button(action: start) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(!isStartEnabled)
                .accessibilityLabel(startLabel)
                .help(startHelp)
            }

            Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(menuLabel)
        }
        .padding(.trailing, TFSpacing.s)
    }
}
