import Foundation

/// A saved combination of brightness and color temperature.
struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var brightness: Int   // 3...100
    var kelvin: Int       // 2900...7000

    static let defaults: [Preset] = [
        Preset(name: "Video Call", brightness: 35, kelvin: 4800),
        Preset(name: "Bright", brightness: 80, kelvin: 5600),
        Preset(name: "Warm", brightness: 25, kelvin: 3200),
    ]
}

/// One rule of the time-based schedule.
struct ScheduleEntry: Codable, Identifiable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case on, off
        var id: String { rawValue }
        var label: String { self == .on ? "Turn on" : "Turn off" }
    }

    var id = UUID()
    var enabled = true
    var hour = 8
    var minute = 0
    /// Calendar weekdays: 1 = Sunday ... 7 = Saturday
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var action: Action = .on
    var brightness: Int = 50
    var setBrightness = true

    /// Next time this rule fires after `date`.
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
    /// Monday to Sunday with their Calendar weekday numbers.
    static let ordered: [(id: Int, short: String)] = [
        (2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa"), (1, "Su")
    ]
}
