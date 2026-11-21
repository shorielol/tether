import TetherCore

/// Everything one day file carries: what Today showed and the night that ended on that day.
/// Nil parts were not measured, and are left out of the file rather than written as zero.
public struct DayRecord: Sendable, Equatable {
    public let day: String
    public let savedAt: Int
    public let strapBatteryPct: Int?
    public let today: TodaySnapshot?
    public let night: NightSummary?

    public init(day: String, savedAt: Int, strapBatteryPct: Int?, today: TodaySnapshot?, night: NightSummary?) {
        self.day = day
        self.savedAt = savedAt
        self.strapBatteryPct = strapBatteryPct
        self.today = today
        self.night = night
    }
}
