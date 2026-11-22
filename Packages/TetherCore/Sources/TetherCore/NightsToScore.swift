import Foundation

/// Picks the days whose nights need scoring: any day since pairing that has no score yet, today and
/// yesterday always (their nights can still be filling in), and every day the strap's history has just
/// reached back into, so minutes the phone missed count once the strap hands them over.
public enum NightsToScore {
    /// Today and yesterday are always rescored.
    static let alwaysRecentDays = 1

    /// Day starts (local midnight, unix seconds), oldest first.
    public static func days(pairedAt: Int, now: Int, scored: Set<String>, historyFrom: Int?,
                            calendar: Calendar = .current) -> [Int] {
        let today = calendar.startOfDay(for: date(now))
        let firstDay = calendar.startOfDay(for: date(pairedAt))
        let historyDay = historyFrom.map { max(calendar.startOfDay(for: date($0)), firstDay) }
        var picked: [Int] = []
        var day = firstDay
        while day <= today {
            let start = Int(day.timeIntervalSince1970)
            let isRecent = (calendar.dateComponents([.day], from: day, to: today).day ?? 0) <= alwaysRecentDays
            let historyReached = historyDay.map { day >= $0 } ?? false
            let unscored = !scored.contains(DayScorer.dayKey(dayStart: start, timeZone: calendar.timeZone))
            if isRecent || historyReached || unscored { picked.append(start) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return picked
    }

    private static func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
}
