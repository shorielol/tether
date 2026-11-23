import Foundation
import Testing
@testable import TetherSnapshot

@Suite("Now widget: what shows when")
struct DayPlanTests {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }()
    /// 2026-11-23 00:00 IST.
    static let midnight = Int(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!.timeIntervalSince1970)
    static func at(_ hour: Int, _ minute: Int = 0) -> Int { midnight + hour * 3_600 + minute * 60 }

    static func plan(charge: Int? = 76, bed: Int? = at(22, 15), alarm: Int? = at(31)) -> DayPlan {
        DayPlan(day: "2026-11-23", dayStart: midnight, chargePercent: charge, zoneName: "Green", advice: "Ready for a harder day",
                sleepMin: 377, targetLow: 55, targetHigh: 75,
                sharpest: 16 * 60 + 30...18 * 60 + 15, dipMinute: 13 * 60 + 45, coffeeByMinute: 15 * 60 + 25, napWindow: nil,
                energy: Array(repeating: 50, count: 19), bedtimeAt: bed, needMin: 560, alarmAt: alarm, alarmConfirmed: true)
    }

    private func view(_ time: Int, _ plan: DayPlan? = plan()) -> NowView {
        NowView.at(time, plan: plan, calendar: Self.calendar)
    }

    @Test func theMorningLeadsWithCharge() {
        #expect(view(Self.at(8)) == .morning)
    }

    @Test func theDayShowsTheNextThingOnThePlan() {
        #expect(view(Self.at(12, 30)) == .day(.init(kind: .dip, at: Self.at(13, 45))))
        #expect(view(Self.at(14)) == .day(.init(kind: .coffee, at: Self.at(15, 25))))
        #expect(view(Self.at(16)) == .day(.init(kind: .sharpestFrom, at: Self.at(16, 30))))
        #expect(view(Self.at(17)) == .day(.init(kind: .sharpestTill, at: Self.at(18, 15))))
        #expect(view(Self.at(19)) == .day(nil), "nothing left: the Effort target")
    }

    @Test func twoHoursBeforeBedItTurnsToBedtimeThenTheAlarm() {
        #expect(view(Self.at(20, 15)) == .evening)
        #expect(view(Self.at(23)) == .night)
        #expect(view(Self.at(26)) == .night, "02:00 the next day, still yesterday's plan")
    }

    @Test func anOldPlanOnlyKeepsTheAlarmThenGoesQuiet() {
        #expect(view(Self.at(29)) == .night, "05:00, alarm at 07:00 still ahead")
        #expect(view(Self.at(33)) == .empty, "09:00 next day without a new plan")
        #expect(view(Self.at(8), nil) == .empty)
    }

    @Test func withoutChargeTheMorningIsTheDayView() {
        #expect(view(Self.at(8), Self.plan(charge: nil)) == .day(.init(kind: .dip, at: Self.at(13, 45))))
    }

    @Test func theTimelineChangesExactlyWhenTheViewDoes() {
        let changes = NowView.changes(after: Self.at(8), plan: Self.plan(), calendar: Self.calendar)
        #expect(changes == [Self.at(12), Self.at(13, 45), Self.at(15, 25), Self.at(16, 30), Self.at(18, 15),
                            Self.at(20, 15), Self.at(22, 15), Self.at(28), Self.at(32)])
    }
}
