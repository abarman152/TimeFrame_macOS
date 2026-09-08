//
//  TFPageHeader.swift
//  time_frame (Milestone 29)
//
//  The one page header used by every content screen: a large title, an optional one-line
//  explanation, and an optional trailing control aligned to the title's baseline block.
//
//  Every screen having the same header is what makes the app read as one product rather than
//  eight separately-styled pages (§18). Milestone 30 moved the sizes themselves into
//  `TFTypography`, so the type scale is a decision recorded in the design system rather than a
//  convention repeated at every call site (ADR-108). It is presentation-only: it owns no state, performs no
//  work, and is never on the timer's control path.
//

import SwiftUI

struct TFPageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.l) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TFTypography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(TFTypography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: TFSpacing.s)
            accessory()
        }
    }
}

extension TFPageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() })
    }
}

/// A quiet section heading inside a page: a title, an optional caption underneath, and an
/// optional trailing control (a filter, a "Manage…" link). The pairing of a bold section
/// title with a compact trailing control is the rhythm every redesigned screen uses.
struct TFSectionHeader<Accessory: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TFTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption)
                        .font(TFTypography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: TFSpacing.s)
            accessory()
        }
    }
}

extension TFSectionHeader where Accessory == EmptyView {
    init(title: String, caption: String? = nil) {
        self.init(title: title, caption: caption, accessory: { EmptyView() })
    }
}
