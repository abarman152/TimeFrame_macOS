//
//  TimeFrameIconTile.swift
//  time_frame (Milestone 29)
//
//  The one container a Template's or Plan's chosen icon is drawn in: a rounded square with a
//  quiet tinted fill and the accent-tinted glyph, at one of three sizes.
//
//  Why a shared container rather than a bare `Image`: the icon appears in the Templates list,
//  the Plans list, both detail headers, the Timer's configuration chooser, and the menu bar's
//  Quick Start rows. Drawing it identically everywhere is what makes those surfaces read as
//  one app. The symbol itself still comes only from the closed catalog
//  (`TimeFrameIconIdentifier.symbolName`, ADR-103) — this view never spells one out.
//
//  The tile is decorative: the item's name always states what it is, so the tile is hidden
//  from VoiceOver and colour is never the sole carrier of meaning (§48).
//

import SwiftUI

struct TimeFrameIconTile: View {

    /// The three sizes the app uses: a list row, a detail header, and a compact inline tile.
    enum Size {
        case small
        case medium
        case large

        var side: CGFloat {
            switch self {
            case .small: 28
            case .medium: TFSpacing.iconTile
            case .large: 46
            }
        }

        var glyph: CGFloat {
            switch self {
            case .small: 14
            case .medium: 16
            case .large: 22
            }
        }

        var radius: CGFloat {
            switch self {
            case .small: 7
            case .medium: TFRadius.tile
            case .large: TFRadius.medium
            }
        }
    }

    let icon: TimeFrameIconIdentifier
    var size: Size = .medium
    /// A tint override for surfaces that are not accent-driven (a disabled row).
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            .fill(tint.opacity(0.14))
            .overlay(
                Image(systemName: icon.symbolName)
                    .font(.system(size: size.glyph, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: size.side, height: size.side)
            .accessibilityHidden(true)
    }
}

/// The same container for a screen that has no catalog icon of its own (a configuration, a
/// history entry): it takes an SF Symbol chosen by the *view*, never by stored data.
struct TFSymbolTile: View {
    let systemImage: String
    var size: TimeFrameIconTile.Size = .medium
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            .fill(tint.opacity(0.14))
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size.glyph, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: size.side, height: size.side)
            .accessibilityHidden(true)
    }
}
