import Foundation
import TetherSnapshot

/// Decides when last night is done and what the lock-screen widgets should show.
/// Run every 15 minutes through the morning; it publishes whenever this wake day's numbers change, so an
/// early wake followed by more sleep is replaced by the fuller night.
public enum MorningCheck {
    /// Awake time after the scored sleep end before the night counts as over.
    public static let awakeMinutes = 20

    public enum Decision: Equatable, Sendable {
        case publish(MorningSnapshot)
        /// Not ready: still asleep, no sleep found, not awake long enough, or before 04:00.
        case wait
        /// Already showing these numbers.
        case skip
    }

    public static func decide(night: NightSummary?, baselineNights: Int, now: Date, published: MorningSnapshot?,
                              calendar: Calendar = .current) -> Decision {
        let wakeDay = WakeDay.key(for: now, calendar: calendar)
        guard let night, night.day == wakeDay, let sleepEnd = night.sleepEnd else { return .wait }
        let awakeSeconds = Int(now.timeIntervalSince1970) - sleepEnd
        guard awakeSeconds >= awakeMinutes * 60 else { return .wait }

        let snapshot = MorningSnapshot(wakeDay: wakeDay, savedAt: Int(now.timeIntervalSince1970),
                                       sleepMin: night.totalSleepMin, rest: night.rest, charge: night.charge,
                                       baselineNights: baselineNights, restingHR: night.restingHR)
        if let published, sameNumbers(published, snapshot) { return .skip }
        return .publish(snapshot)
    }

    private static func sameNumbers(_ a: MorningSnapshot, _ b: MorningSnapshot) -> Bool {
        a.wakeDay == b.wakeDay && a.sleepMin == b.sleepMin && a.rest == b.rest && a.charge == b.charge
            && a.baselineNights == b.baselineNights && a.restingHR == b.restingHR
    }
}
