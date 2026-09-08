//
//  TimeFrameIconCatalogTests.swift
//  time_frameTests (Milestone 28)
//
//  The icon catalog is the app's guarantee that a template's or plan's icon is always a
//  real, renderable SF Symbol chosen from a closed set — never an arbitrary string that
//  reached `Image(systemName:)` from stored data (ADR-103). These tests hold that guarantee:
//
//   • every catalog entry names a symbol the system can actually render (so a typo in the
//     catalog fails the build, not the user's screen);
//   • identifiers are stable and distinct, because they are what gets persisted;
//   • an unknown, empty, or absent stored value resolves to a sensible default;
//   • the categories partition the catalog, so the picker can never hide an icon.
//

import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import time_frame

@Suite("Icon catalog")
struct TimeFrameIconCatalogTests {

    @Test("Every catalog icon names a real, renderable SF Symbol")
    func everySymbolResolves() throws {
        #if canImport(AppKit)
        for icon in TimeFrameIconIdentifier.allCases {
            let image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil)
            #expect(image != nil, "\(icon.rawValue) names a missing SF Symbol: \(icon.symbolName)")
        }
        #endif
    }

    @Test("Stable identifiers are distinct and non-empty")
    func identifiersAreStable() {
        let ids = TimeFrameIconIdentifier.allCases.map(\.rawValue)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test("The persisted identifier is a plain token, independent of the SF Symbol name")
    func identifierIsIndependentOfSymbol() {
        // Identifiers are dot-free tokens, so no dotted SF Symbol name can ever be a valid
        // stored identifier — which is what lets a symbol be swapped for a better one later
        // without rewriting stored rows.
        #expect(TimeFrameIconIdentifier.allCases.allSatisfy { !$0.rawValue.contains(".") })
        #expect(TimeFrameIconIdentifier.laptop.symbolName == "laptopcomputer")
        #expect(TimeFrameIconIdentifier.bookClosed.symbolName == "book.closed")
        #expect(TimeFrameIconIdentifier.graduationCap.symbolName == "graduationcap")
        #expect(TimeFrameIconIdentifier.people.symbolName == "person.2")
        // And every dotted symbol is reachable only through its own plain identifier.
        for icon in TimeFrameIconIdentifier.allCases where icon.symbolName.contains(".") {
            #expect(TimeFrameIconIdentifier(rawValue: icon.symbolName) == nil)
        }
    }

    @Test("Display names are unique, non-empty, and human readable")
    func displayNames() {
        let names = TimeFrameIconIdentifier.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        // No raw dotted symbol syntax leaking into user-facing text.
        #expect(names.allSatisfy { !$0.contains(".") })
    }

    @Test("Accessibility labels name the icon and say it is an icon")
    func accessibilityLabels() {
        #expect(TimeFrameIconIdentifier.laptop.accessibilityLabel == "Laptop icon")
        #expect(TimeFrameIconIdentifier.book.accessibilityLabel == "Book icon")
        #expect(TimeFrameIconIdentifier.briefcase.accessibilityLabel == "Briefcase icon")
        #expect(TimeFrameIconIdentifier.allCases.allSatisfy { $0.accessibilityLabel.hasSuffix(" icon") })
    }

    @Test("Categories partition the catalog with nothing left out")
    func categoriesPartitionTheCatalog() {
        var seen: [TimeFrameIconIdentifier] = []
        for category in TimeFrameIconCategory.allCases {
            let icons = TimeFrameIconIdentifier.icons(in: category)
            #expect(!icons.isEmpty, "\(category.rawValue) has no icons")
            #expect(icons.allSatisfy { $0.category == category })
            seen.append(contentsOf: icons)
        }
        #expect(Set(seen) == Set(TimeFrameIconIdentifier.allCases))
        #expect(seen.count == TimeFrameIconIdentifier.allCases.count)
    }

    @Test("Category display names are present and distinct")
    func categoryNames() {
        let names = TimeFrameIconCategory.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    // MARK: Resolution

    @Test("A known identifier resolves to itself")
    func resolvesKnown() {
        for icon in TimeFrameIconIdentifier.allCases {
            #expect(TimeFrameIconIdentifier.resolve(icon.rawValue, fallback: .star) == icon)
        }
    }

    @Test("An unknown, empty, or absent identifier falls back")
    func resolvesUnknownToFallback() {
        #expect(TimeFrameIconIdentifier.resolve("not-an-icon", fallback: .target) == .target)
        #expect(TimeFrameIconIdentifier.resolve("", fallback: .target) == .target)
        #expect(TimeFrameIconIdentifier.resolve(nil, fallback: .list) == .list)
        // An SF Symbol name is deliberately NOT a valid stored identifier: stored data can
        // never smuggle a symbol name through the resolver.
        #expect(TimeFrameIconIdentifier.resolve("laptopcomputer", fallback: .target) == .target)
        #expect(TimeFrameIconIdentifier.resolve("trash.fill", fallback: .target) == .target)
    }

    @Test("The defaults are catalog members with renderable symbols")
    func defaults() {
        #expect(TimeFrameIconIdentifier.allCases.contains(.templateDefault))
        #expect(TimeFrameIconIdentifier.allCases.contains(.planDefault))
        #expect(!TimeFrameIconIdentifier.templateDefault.symbolName.isEmpty)
        #expect(!TimeFrameIconIdentifier.planDefault.symbolName.isEmpty)
    }

    @Test("Codable round-trips through the stable identifier")
    func codableRoundTrip() throws {
        for icon in TimeFrameIconIdentifier.allCases {
            let data = try JSONEncoder().encode(icon)
            let decoded = try JSONDecoder().decode(TimeFrameIconIdentifier.self, from: data)
            #expect(decoded == icon)
        }
    }
}
