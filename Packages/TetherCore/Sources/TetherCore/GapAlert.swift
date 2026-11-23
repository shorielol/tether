import Foundation

/// A one-off "Tether hasn't heard from your strap" notification. While samples arrive the alert keeps being
/// pushed two hours ahead, so it only goes off if the strap really has gone quiet, even with the app
/// suspended. A gap that runs into the night waits until 07:00 instead of waking anyone.
public enum GapAlert {
    public enum Action: Equatable, Sendable {
        case schedule(fireAt: Int)
        case keep
        case cancel
    }

    public static let gapSeconds = 2 * 3_600
    /// Don't reschedule the notification for every beat: only when it moves by this much.
    static let moveSeconds = 5 * 60
    static let quietStartHour = 23
    static let quietEndHour = 7

    public static func plan(lastSampleAt: Int?, scheduledFor: Int?, enabled: Bool,
                            calendar: Calendar = .current) -> Action {
        guard enabled, let lastSampleAt else { return scheduledFor == nil ? .keep : .cancel }
        let fireAt = outsideQuietHours(lastSampleAt + gapSeconds, calendar: calendar)
        if let scheduledFor, abs(fireAt - scheduledFor) < moveSeconds { return .keep }
        return .schedule(fireAt: fireAt)
    }

    static func outsideQuietHours(_ time: Int, calendar: Calendar) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let hour = calendar.component(.hour, from: date)
        guard hour >= quietStartHour || hour < quietEndHour else { return time }
        let morning = calendar.nextDate(after: date, matching: DateComponents(hour: quietEndHour, minute: 0, second: 0),
                                        matchingPolicy: .nextTime) ?? date
        return Int(morning.timeIntervalSince1970)
    }
}
