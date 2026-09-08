//
//  ProductionReadinessM30Tests.swift
//  time_frameTests (Milestone 30)
//
//  Milestone 30 is a presentation-consistency milestone (ADR-108). It adds no feature, no
//  store and no timing authority; its two rules are easy to state and easy to lose again, so
//  they are audited here rather than left to review:
//
//   1. **One compact primary action per screen.** A page-level action is sized to its content
//      at the native macOS control height. A filled slab that spans its container is a phone
//      convention; used for "Start" it made the Timer screen read as a web form. The only
//      deliberate exception is the menu-bar popover's single fallback action, whose container
//      genuinely is the width of the control — and it says so at the call site.
//
//   2. **The type scale lives in the design system.** The six roles the product uses are named
//      in `TFTypography`, so "what a section title looks like" is one edit rather than sixty.
//
//  Both are source audits, because both are structural properties of the view tree that a
//  value test cannot observe. They deliberately do not assert pixel geometry — this suite
//  proves the rule is applied, not that a particular screenshot was matched.
//
//  The milestone changes no runtime architecture, and the last two tests hold that line:
//  the design system still imports none of the domain, and the redesigned screens introduce
//  no scheduling primitive of their own.
//

import Foundation
import Testing
@testable import time_frame

@Suite("M30 — compact page actions")
struct M30CompactActionTests {

    /// The screens whose page-level actions Milestone 30 re-sized. Each is a page that offers
    /// a prominent action plus supporting ones, which is exactly where the slab crept in.
    private static let redesignedPages = [
        "Views/Timer/SessionSetupView.swift",
        "Views/Templates/TemplateDetailView.swift",
        "Views/Plans/PlanDetailView.swift"
    ]

    private func page(_ path: String) -> String {
        SourceAudit.code(SourceAudit.appTarget().appendingPathComponent(path))
    }

    @Test("Every redesigned page sizes its actions through the shared treatment")
    func pagesUseTheSharedTreatment() {
        for path in Self.redesignedPages {
            let text = page(path)
            #expect(text.contains("tfPrimaryAction()"),
                    "\(path) must size its one prominent action with tfPrimaryAction()")
        }
    }

    @Test("No redesigned page inflates a page action to .large")
    func noLargePageActions() {
        // `.large` is a banner height. The transport controls on the running Timer screen and
        // the menu-bar popover keep it deliberately — those are centrepiece surfaces, not
        // page actions — so the rule is scoped to the pages that offer a form-like choice.
        for path in Self.redesignedPages {
            let text = page(path)
            #expect(!text.contains("controlSize(.large)"),
                    "\(path) must use the shared control size, not .large")
        }
    }

    @Test("The Timer screen's Start is content-sized, not a full-width slab")
    func timerStartIsNotFullWidth() {
        let text = page("Views/Timer/SessionSetupView.swift")
        guard let range = text.range(of: "var startButton") else {
            Issue.record("SessionSetupView must still define startButton")
            return
        }
        // Bounded window: enough to cover the property, short enough that an unrelated
        // `maxWidth` further down the file cannot fail this.
        let block = text[range.upperBound...].prefix(1400)
        #expect(!block.contains("frame(maxWidth: .infinity)"),
                "The Timer screen's Start must be sized to its content (ADR-108)")
        #expect(block.contains("tfPrimaryAction()"))
    }

    @Test("The menu bar's fallback is the one action that spans its container, by intent")
    func menuBarFallbackIsTheOnlyFullWidthAction() {
        // The popover is 288 pt wide and offers exactly one action when nothing is running;
        // there, spanning the width is the correct native treatment. Recording it here means
        // a second full-width action elsewhere has to argue with this test first.
        let menuBar = SourceAudit.code(
            SourceAudit.appTarget().appendingPathComponent("Views/MenuBar/TimeFrameMenuBarView.swift"))
        #expect(menuBar.contains("frame(maxWidth: .infinity)"),
                "The popover's fallback start deliberately spans the popover's width")
    }

    @Test("A disabled Start explains itself in words, not by dimming alone")
    func disabledStartIsExplained() {
        let text = SourceAudit.codeKeepingStrings(
            SourceAudit.appTarget().appendingPathComponent("Views/Timer/SessionSetupView.swift"))
        #expect(text.contains("Enter a task to start."),
                "Why Start is unavailable must be stated, not carried by appearance alone (§48)")
    }
}

@Suite("M30 — the Quick Start row fits its popover")
struct M30QuickStartRowTests {

    private var row: String {
        SourceAudit.code(SourceAudit.appTarget()
            .appendingPathComponent("Views/MenuBar/MenuBarQuickStartRowView.swift"))
    }

    @Test("The visible secondary line is the summary alone, so the durations are not truncated")
    func visibleLineIsTheSummary() {
        // In a 288 pt popover, prefixing the kind pushed "25 min focus · 5 min break" past the
        // truncation point, so the row read "Template · 25 min focus · 5 mi…" — it truncated
        // exactly the numbers the user is choosing between.
        #expect(row.contains("Text(item.subtitle)"),
                "The visible line must show the summary, not a kind-prefixed string")
    }

    @Test("The kind is still spoken, so nothing is lost for VoiceOver")
    func kindIsStillSpoken() {
        #expect(row.contains("accessibilityValue(secondaryLine)"),
                "The kind must still reach VoiceOver through the row's value")
        // `secondaryLine` builds its text by interpolation, and `SourceAudit.code` blanks
        // string literals — so this one has to read the source with literals preserved.
        let withStrings = SourceAudit.codeKeepingStrings(SourceAudit.appTarget()
            .appendingPathComponent("Views/MenuBar/MenuBarQuickStartRowView.swift"))
        #expect(withStrings.contains("item.kind.displayName"),
                "The spoken value must still name the kind in words (§48)")
    }

    @Test("The row states essential state in words, never by dimming alone")
    func disabledRowExplainsItself() {
        let item = SourceAudit.codeKeepingStrings(SourceAudit.core()
            .appendingPathComponent("Services/QuickStart/QuickStartItem.swift"))
        #expect(item.contains("Needs a configuration before it can start"))
    }
}

@Suite("M30 — the type scale is centralised")
struct M30TypographyTests {

    private var design: String {
        SourceAudit.code(SourceAudit.core()
            .appendingPathComponent("Support/DesignSystem/TimeFrameDesign.swift"))
    }

    @Test("The design system names every type role the product uses")
    func typeRolesExist() {
        let text = design
        for role in ["pageTitle", "subjectTitle", "sectionTitle", "rowTitle",
                     "body", "secondary", "metadata", "numericValue",
                     "groupTitle", "rowLabel", "rowValue"] {
            #expect(text.contains("static let \(role): Font"),
                    "TFTypography must name the \(role) role")
        }
    }

    @Test("The design system names the control-size rule")
    func controlRuleExists() {
        let text = design
        #expect(text.contains("enum TFControl"))
        #expect(text.contains("primaryMinimumWidth"))
        #expect(text.contains("func tfPrimaryAction"))
        #expect(text.contains("func tfSecondaryAction"))
    }

    @Test("The shared components read their sizes from the scale, not from literals")
    func sharedComponentsUseTheScale() {
        let components = ["Views/Components/TFPageHeader.swift",
                          "Views/Components/TFDetailCard.swift",
                          "Views/Components/TFDetailActions.swift"]
        for path in components {
            let text = SourceAudit.code(SourceAudit.appTarget().appendingPathComponent(path))
            #expect(text.contains("TFTypography."),
                    "\(path) must take its type sizes from TFTypography")
            #expect(!text.contains("largeTitle"),
                    "\(path) must not hard-code a title size next to the shared scale")
        }
    }
}

@Suite("M30 — no architectural change")
struct M30ArchitectureTests {

    @Test("The design system still imports none of the domain")
    func designSystemStaysPresentational() {
        for file in ["TimeFrameDesign.swift", "TimeFrameGlass.swift"] {
            let url = SourceAudit.core().appendingPathComponent("Support/DesignSystem/\(file)")
            let text = SourceAudit.code(url)
            for forbidden in ["import SwiftData", "import WidgetKit", "import AppIntents",
                             "import CloudKit", "import ActivityKit",
                             "TimerEngine", "SessionCoordinator"] {
                #expect(!text.contains(forbidden),
                        "\(file) must stay presentation-only — found \(forbidden)")
            }
        }
    }

    @Test("The redesigned screens introduce no scheduling primitive")
    func noNewClock() {
        let pages = ["Views/Timer/SessionSetupView.swift",
                     "Views/Templates/TemplateDetailView.swift",
                     "Views/Plans/PlanDetailView.swift",
                     "Views/Components/TFPageHeader.swift",
                     "Views/Components/TFDetailCard.swift",
                     "Views/Components/TFDetailActions.swift"]
        for path in pages {
            let text = SourceAudit.code(SourceAudit.appTarget().appendingPathComponent(path))
            for primitive in ["Task.sleep", "asyncAfter", "scheduledTimer",
                              "DispatchSourceTimer", "TimelineView"] {
                #expect(!text.contains(primitive),
                        "\(path) must add no clock of its own — found \(primitive)")
            }
        }
    }
}
