import Foundation
import StrandAnalytics

/// Phase 4's sleep coach: tonight's need, a bedtime that meets it, and how last night measured up.
/// Sleep debt is NOOP's `SleepDebt` ledger; the rest is plain arithmetic on your own nights.
public struct SleepCoach: Sendable, Equatable {
    public struct Need: Sendable, Equatable {
        /// Recommended for your age: 9 h from 13 to 17, 8 h for adults.
        public let baseMin: Double
        /// Catching up on recent short nights: tonight's share, at most `maxCatchUpMin`.
        public let debtMin: Double
        /// All the catching up owed; it's paid back over several nights.
        public let owedMin: Double
        /// A little extra after a hard day.
        public let effortMin: Double
        public var totalMin: Double { baseMin + debtMin + effortMin }
    }

    public struct LastNight: Sendable, Equatable {
        /// Time asleep against the need going into that night, capped at 1.
        public let performance: Double
        /// Deep plus REM.
        public let restorativeMin: Double
        public let restorativeShare: Double
    }

    public let need: Need
    /// Minutes after midnight you're aiming to wake.
    public let wakeMinute: Int
    /// True when the wake time is your alarm, false when it's your usual wake time.
    public let wakeFromAlarm: Bool
    /// Minutes after midnight to be in bed by.
    public let bedtimeMinute: Int
    /// 0–100: how steady your bed and wake times have been this week. Nil with fewer than 4 nights.
    public let consistency: Int?
    public let lastNight: LastNight?

    /// The most catch-up asked of one night: debt is paid back over several nights, not in one go.
    public static let maxCatchUpMin = 60.0
    /// Allowance for falling asleep.
    public static let fallAsleepMin = 15
    static let nightsNeeded = 3
    static let consistencyNights = 7
    /// Standard deviation (minutes) of bed and wake times that scores zero consistency.
    static let scatterForZero = 120.0

    public static func baseNeedHours(age: Int) -> Double { age < 18 ? 9 : AnalyticsEngine.Rest.defaultNeedHours }

    public static func effortExtraMin(_ effort: Double?) -> Double {
        guard let effort else { return 0 }
        return effort >= 70 ? 20 : effort >= 50 ? 10 : 0
    }

    public static func compute(nights: [NightSummary], effortYesterday: Double?, age: Int,
                               wakeTarget: (hour: Int, minute: Int)?, timeZone: TimeZone = .current) -> SleepCoach? {
        let slept = nights.filter { $0.sleepStart != nil && $0.sleepEnd != nil && ($0.totalSleepMin ?? 0) > 0 }
            .sorted { $0.day < $1.day }
        guard slept.count >= nightsNeeded else { return nil }
        let needHours = baseNeedHours(age: age)
        let ledger = SleepDebt.ledger(series: slept.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) },
                                      needHours: needHours)
        let owed = max(0, -ledger.balanceMin)
        let need = Need(baseMin: needHours * 60, debtMin: min(owed, maxCatchUpMin), owedMin: owed,
                        effortMin: effortExtraMin(effortYesterday))

        let wakes = slept.suffix(consistencyNights).compactMap { $0.sleepEnd.map { minuteOfDay($0, timeZone) } }
        let wakeMinute = wakeTarget.map { $0.hour * 60 + $0.minute } ?? Int(median(wakes.map(Double.init)).rounded())
        let bedtime = ((wakeMinute - Int(need.totalMin.rounded()) - fallAsleepMin) % 1_440 + 1_440) % 1_440

        let recent = slept.suffix(consistencyNights)
        var consistency: Int?
        if recent.count >= 4 {
            // Bedtimes are measured from noon so 23:30 and 00:30 sit an hour apart, not 23 hours.
            let beds = recent.compactMap { $0.sleepStart.map { Double((minuteOfDay($0, timeZone) + 720) % 1_440) } }
            let ends = recent.compactMap { $0.sleepEnd.map { Double(minuteOfDay($0, timeZone)) } }
            let scatter = (deviation(beds) + deviation(ends)) / 2
            consistency = Int((100 * max(0, 1 - scatter / scatterForZero)).rounded())
        }

        var last: LastNight?
        if let night = slept.last, let asleep = night.totalSleepMin {
            let before = Array(slept.dropLast())
            let debtBefore = before.isEmpty ? 0 : max(0, -SleepDebt.ledger(
                series: before.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }, needHours: needHours).balanceMin)
            let restorative = (night.deepMin ?? 0) + (night.remMin ?? 0)
            last = LastNight(performance: min(1, asleep / (needHours * 60 + min(debtBefore, maxCatchUpMin))),
                             restorativeMin: restorative, restorativeShare: restorative / asleep)
        }
        return SleepCoach(need: need, wakeMinute: wakeMinute, wakeFromAlarm: wakeTarget != nil,
                          bedtimeMinute: bedtime, consistency: consistency, lastNight: last)
    }

    static func minuteOfDay(_ ts: Int, _ timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func deviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
}
