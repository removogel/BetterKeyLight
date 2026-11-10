import Foundation

/// Ein Eintrag der zeitbasierten Steuerung.
struct ScheduleEntry: Codable, Identifiable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case on, off
        var id: String { rawValue }
        var label: String { self == .on ? "Einschalten" : "Ausschalten" }
    }

    var id = UUID()
    var enabled = true
    var hour = 8
    var minute = 0
    /// Calendar-Wochentage: 1 = Sonntag ... 7 = Samstag
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var action: Action = .on
    var brightness: Int = 50
    var setBrightness = true

    var timeString: String { String(format: "%02d:%02d", hour, minute) }

    var summary: String {
        var s = "\(timeString) – \(action.label)"
        if action == .on && setBrightness { s += " (\(brightness) %)" }
        return s
    }

    /// Nächster Auslösezeitpunkt ab `date`.
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, !weekdays.isEmpty else { return nil }
        return weekdays.compactMap { wd in
            calendar.nextDate(after: date,
                              matching: DateComponents(hour: hour, minute: minute, weekday: wd),
                              matchingPolicy: .nextTime)
        }.min()
    }
}

enum Weekday {
    /// Reihenfolge Mo–So mit Calendar-Wochentagsnummern
    static let ordered: [(id: Int, short: String)] = [
        (2, "Mo"), (3, "Di"), (4, "Mi"), (5, "Do"), (6, "Fr"), (7, "Sa"), (1, "So")
    ]
}
