import Foundation
import Testing
import TetherSnapshot
@testable import TetherCore

@Suite("Morning check")
struct MorningCheckTests {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }()

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func night(day: String = "2026-11-22", end: Date? = at(22, 7), sleepMin: Double? = 432,
                      charge: Double? = 64) -> NightSummary {
        NightSummary(day: day, sleepStart: end.map { Int($0.timeIntervalSince1970) - 27_000 },
                     sleepEnd: end.map { Int($0.timeIntervalSince1970) }, totalSleepMin: sleepMin, efficiency: 0.9,
                     deepMin: 80, remMin: 100, lightMin: 252, disturbances: 3, restingHR: 51, hrv: 55,
                     respRate: 14.5, charge: charge, rest: 78, drivers: [], stages: [])
    }

    static func decide(_ night: NightSummary?, now: Date, published: MorningSnapshot? = nil,
                       nights: Int = 6) -> MorningCheck.Decision {
        MorningCheck.decide(night: night, baselineNights: nights, now: now, published: published, calendar: calendar)
    }

    static func published(_ decision: MorningCheck.Decision) -> MorningSnapshot? {
        if case let .publish(snap) = decision { return snap }
        return nil
    }

    @Test func waitsWhileStillAsleep() {
        #expect(Self.decide(Self.night(end: nil), now: Self.at(22, 6)) == .wait)
    }

    @Test func waitsUntilTwentyMinutesAwake() {
        #expect(Self.decide(Self.night(), now: Self.at(22, 7, 10)) == .wait)
    }

    @Test func publishesOnceAwakeLongEnough() throws {
        let snap = try #require(Self.published(Self.decide(Self.night(), now: Self.at(22, 7, 25))))
        #expect(snap.wakeDay == "2026-11-22")
        #expect(snap.sleepMin == 432 && snap.rest == 78 && snap.charge == 64 && snap.restingHR == 51)
        #expect(snap.baselineNights == 6)
        #expect(snap.savedAt == Int(Self.at(22, 7, 25).timeIntervalSince1970))
    }

    @Test func waitsWhenNoNightWasFound() {
        #expect(Self.decide(nil, now: Self.at(22, 9)) == .wait)
    }

    @Test func waitsBeforeFourEvenIfAwake() {
        // 02:00 still belongs to yesterday's wake day, and the night scored is today's.
        #expect(Self.decide(Self.night(end: Self.at(22, 1)), now: Self.at(22, 2)) == .wait)
    }

    @Test func ignoresAnOldNight() {
        #expect(Self.decide(Self.night(day: "2026-11-21", end: Self.at(21, 7)), now: Self.at(22, 9)) == .wait)
    }

    @Test func skipsWhenNothingChanged() throws {
        let first = try #require(Self.published(Self.decide(Self.night(), now: Self.at(22, 7, 30))))
        #expect(Self.decide(Self.night(), now: Self.at(22, 7, 45), published: first) == .skip)
    }

    @Test func republishesWhenSleepWentOn() throws {
        // Woke at 05:00 for a while, slept again until 07:30: the later score replaces the early one.
        let early = try #require(Self.published(Self.decide(Self.night(end: Self.at(22, 5), sleepMin: 300),
                                                            now: Self.at(22, 5, 30))))
        let later = Self.decide(Self.night(end: Self.at(22, 7, 30), sleepMin: 410), now: Self.at(22, 8), published: early)
        #expect(Self.published(later)?.sleepMin == 410)
    }

    @Test func carriesBaselineProgressBeforeCharge() throws {
        let snap = try #require(Self.published(Self.decide(Self.night(charge: nil), now: Self.at(22, 8), nights: 2)))
        #expect(snap.charge == nil && snap.chargeProgress == 0.5)
    }
}
