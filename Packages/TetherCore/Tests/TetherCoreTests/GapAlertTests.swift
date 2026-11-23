import Foundation
import Testing
@testable import TetherCore

@Suite("Out-of-touch alert")
struct GapAlertTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    /// 2026-11-22 00:00 UTC.
    private let midnight = 1_795_305_600

    private func plan(last: Int?, scheduled: Int?, enabled: Bool = true) -> GapAlert.Action {
        GapAlert.plan(lastSampleAt: last, scheduledFor: scheduled, enabled: enabled, calendar: calendar)
    }

    @Test func aFreshSampleSetsTheAlertTwoHoursOut() {
        let last = midnight + 14 * 3_600
        #expect(plan(last: last, scheduled: nil) == .schedule(fireAt: last + 2 * 3_600))
    }

    @Test func itIsOnlyMovedOnceTheNewTimeIsFiveMinutesLater() {
        let last = midnight + 14 * 3_600
        let scheduled = last + 2 * 3_600
        #expect(plan(last: last + 60, scheduled: scheduled) == .keep)
        #expect(plan(last: last + 6 * 60, scheduled: scheduled) == .schedule(fireAt: last + 6 * 60 + 2 * 3_600))
    }

    @Test func aGapRunningIntoTheNightWaitsForTheMorning() {
        let last = midnight + 22 * 3_600     // 22:00, two hours later is midnight
        #expect(plan(last: last, scheduled: nil) == .schedule(fireAt: midnight + 86_400 + 7 * 3_600))
    }

    @Test func offOrNeverHeardMeansNoAlert() {
        #expect(plan(last: midnight + 14 * 3_600, scheduled: midnight, enabled: false) == .cancel)
        #expect(plan(last: nil, scheduled: midnight) == .cancel)
        #expect(plan(last: nil, scheduled: nil) == .keep)
    }
}
