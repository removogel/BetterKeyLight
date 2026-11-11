import Foundation

/// Color temperature that follows the time of day: cool during the day, warm at night,
/// with a gradual transition before each of the two set times.
enum DayCycle {
    /// Length of each transition in minutes.
    static let rampMinutes = 120

    /// - Parameters:
    ///   - dayStart: minute of the day at which the light is fully cool
    ///   - nightStart: minute of the day at which the light is fully warm
    static func kelvin(at date: Date, day: Int, night: Int,
                       dayStart: Int, nightStart: Int,
                       calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        func wrap(_ minutes: Int) -> Int { ((minutes % 1440) + 1440) % 1440 }

        let ramp = rampMinutes
        let intoMorning = wrap(now - (dayStart - ramp))
        let intoEvening = wrap(now - (nightStart - ramp))
        let value: Double
        if intoMorning < ramp {
            value = Double(night) + Double(day - night) * Double(intoMorning) / Double(ramp)
        } else if intoEvening < ramp {
            value = Double(day) + Double(night - day) * Double(intoEvening) / Double(ramp)
        } else if wrap(now - dayStart) < wrap(nightStart - ramp - dayStart) {
            value = Double(day)
        } else {
            value = Double(night)
        }
        let rounded = Int((value / 50).rounded()) * 50
        return min(7000, max(2900, rounded))
    }
}
