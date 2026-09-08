//
//  CalendarPickerView.swift
//  time_frame
//
//  A calendar chooser over pure CalendarDescriptors. Selection is the stable
//  calendar identifier (nil = the system default), never the title (§20). Only
//  writable calendars are offered (the coordinator already filters them — §19).
//

import SwiftUI

struct CalendarPickerView: View {
    let calendars: [CalendarDescriptor]
    /// The chosen calendar identifier, or nil for the system default calendar.
    @Binding var selection: String?

    var body: some View {
        Picker("Calendar", selection: $selection) {
            Text("System Default").tag(String?.none)
            ForEach(calendars) { calendar in
                Label {
                    Text(calendar.title)
                } icon: {
                    Circle()
                        .fill(swatchColor(calendar.colorHex))
                        .frame(width: 10, height: 10)
                }
                .tag(Optional(calendar.id))
            }
        }
        .accessibilityIdentifier("calendar.picker")
    }

    private func swatchColor(_ hex: String?) -> Color {
        guard let hex, let color = Color(hex: hex) else { return .secondary }
        return color
    }
}

extension Color {
    /// Builds a colour from a `#RRGGBB` string, or nil if it can't be parsed. Kept
    /// local to the calendar UI, where EventKit hands out hex colour hints.
    init?(hex: String) {
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b)
    }
}
