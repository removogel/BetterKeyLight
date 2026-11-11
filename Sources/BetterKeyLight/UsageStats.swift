import Foundation
import SwiftUI

struct DayUsage: Identifiable {
    let date: Date
    let seconds: Double
    var id: Date { date }
}

/// Records how long the light was on per day. Only counts while the app is running.
/// Kept separate from `LightStore` so its frequent updates only redraw the usage view.
@MainActor
final class UsageStats: ObservableObject {
    @Published private(set) var secondsByDay: [String: Double]

    private static let key = "usageSecondsByDay"
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var lastStamp = Date()
    private var wasOn = false

    init() {
        secondsByDay = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    /// Adds the time since the last call if the light was on, then remembers the new state.
    func record(isOn: Bool) {
        let now = Date()
        if wasOn {
            let elapsed = now.timeIntervalSince(lastStamp)
            // Longer gaps mean the Mac was asleep or the app was suspended: don't count them.
            if elapsed > 0 && elapsed < 120 {
                secondsByDay[Self.formatter.string(from: now), default: 0] += elapsed
                prune()
                UserDefaults.standard.set(secondsByDay, forKey: Self.key)
            }
        }
        wasOn = isOn
        lastStamp = now
    }

    func seconds(on date: Date) -> Double {
        secondsByDay[Self.formatter.string(from: date)] ?? 0
    }

    /// The last `count` days, oldest first, ending today.
    func lastDays(_ count: Int) -> [DayUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset -> DayUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayUsage(date: date, seconds: seconds(on: date))
        }
    }

    func reset() {
        secondsByDay = [:]
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// Keeps roughly the last four months.
    private func prune() {
        guard secondsByDay.count > 130 else { return }
        let keep = Set(secondsByDay.keys.sorted().suffix(120))
        secondsByDay = secondsByDay.filter { keep.contains($0.key) }
    }

    static func format(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
