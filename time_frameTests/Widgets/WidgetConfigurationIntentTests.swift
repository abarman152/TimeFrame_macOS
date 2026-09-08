//
//  WidgetConfigurationIntentTests.swift
//  time_frameTests (Milestone 14)
//
//  The `WidgetConfigurationIntent` that backs the widget's `AppIntentConfiguration`. These
//  tests pin the parameter defaults, the user-facing display representations (plain, non
//  technical wording), the type display representations, and the mapping from the three
//  App-Intent choices to the pure `TimeFrameWidgetConfiguration` for every combination — all
//  deterministic and with no Shortcuts/Siri host required (ADR-064/065).
//

import Foundation
import AppIntents
import Testing
@testable import time_frame

@Suite("Widget configuration intent")
struct WidgetConfigurationIntentTests {

    // MARK: Parameter defaults

    @Test("A freshly-initialised intent carries the default choices")
    func parameterDefaults() {
        let intent = TimeFrameWidgetConfigurationIntent()
        #expect(intent.content == .currentTimer)
        #expect(intent.destination == .timer)
        #expect(intent.countdown == .show)
        #expect(intent.configuration == .default)
    }

    // MARK: Title & type representations

    @Test("The intent title reads as plain, human wording")
    func title() {
        #expect(String(localized: TimeFrameWidgetConfigurationIntent.title) == "Time Frame Widget")
    }

    @Test("Each parameter enum exposes a human type name")
    func typeDisplayRepresentations() {
        #expect(String(localized: WidgetContentOption.typeDisplayRepresentation.name) == "Widget Content")
        #expect(String(localized: WidgetDestinationOption.typeDisplayRepresentation.name) == "Open When Tapped")
        #expect(String(localized: WidgetCountdownOption.typeDisplayRepresentation.name) == "Countdown")
    }

    // MARK: Case display representations (no raw enum names leak to users)

    @Test("Content options present friendly titles, one per case")
    func contentDisplayRepresentations() {
        let reps = WidgetContentOption.caseDisplayRepresentations
        #expect(Set(reps.keys) == Set(WidgetContentOption.allCases))
        #expect(title(reps[.currentTimer]) == "Current Timer")
        #expect(title(reps[.todaysFocus]) == "Today's Focus")
        #expect(title(reps[.statistics]) == "Statistics")
    }

    @Test("Destination options present friendly titles, one per case")
    func destinationDisplayRepresentations() {
        let reps = WidgetDestinationOption.caseDisplayRepresentations
        #expect(Set(reps.keys) == Set(WidgetDestinationOption.allCases))
        #expect(title(reps[.timer]) == "Timer")
        #expect(title(reps[.today]) == "Today")
        #expect(title(reps[.statistics]) == "Statistics")
        #expect(title(reps[.history]) == "History")
    }

    @Test("Countdown options present Show / Hide, not a raw boolean")
    func countdownDisplayRepresentations() {
        let reps = WidgetCountdownOption.caseDisplayRepresentations
        #expect(Set(reps.keys) == Set(WidgetCountdownOption.allCases))
        #expect(title(reps[.show]) == "Show Countdown")
        #expect(title(reps[.hide]) == "Hide Countdown")
    }

    // MARK: Choice → pure configuration mapping

    @Test("Every choice combination maps to the matching pure configuration")
    func mapsToConfiguration() {
        for content in WidgetContentOption.allCases {
            for destination in WidgetDestinationOption.allCases {
                for countdown in WidgetCountdownOption.allCases {
                    let intent = TimeFrameWidgetConfigurationIntent(
                        content: content, destination: destination, countdown: countdown
                    )
                    let config = intent.configuration
                    #expect(config.displayMode == content.displayMode)
                    #expect(config.destination == destination.destination)
                    #expect(config.showsCountdown == countdown.showsCountdown)
                }
            }
        }
    }

    @Test("Content options map to the pure display modes")
    func contentMapping() {
        #expect(WidgetContentOption.currentTimer.displayMode == .timer)
        #expect(WidgetContentOption.todaysFocus.displayMode == .today)
        #expect(WidgetContentOption.statistics.displayMode == .statistics)
    }

    @Test("Countdown options map to the correct boolean")
    func countdownMapping() {
        #expect(WidgetCountdownOption.show.showsCountdown == true)
        #expect(WidgetCountdownOption.hide.showsCountdown == false)
    }

    // MARK: Helpers

    private func title(_ representation: DisplayRepresentation?) -> String? {
        guard let representation else { return nil }
        return String(localized: representation.title)
    }
}
