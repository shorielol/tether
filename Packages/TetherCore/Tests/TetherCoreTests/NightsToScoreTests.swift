import Foundation
import Testing
@testable import TetherCore

/// Which days get scored: any not scored yet, today and yesterday always (their nights may still be filling
/// in), and every day the strap's history has just reached back into.
@Suite("Which nights to score")
struct NightsToScoreTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    /// 2026-11-22 00:00 UTC.
    private let midnight = 1_795_305_600
    private func day(_ offset: Int) -> Int { midnight + offset * 86_400 }
    private func key(_ offset: Int) -> String { DayScorer.dayKey(dayStart: day(offset), timeZone: calendar.timeZone) }

    @Test func aFreshPhoneScoresEveryDaySincePairing() {
        let days = NightsToScore.days(pairedAt: day(-3) + 3_600, now: day(0) + 9 * 3_600, scored: [],
                                      historyFrom: nil, calendar: calendar)
        #expect(days == [day(-3), day(-2), day(-1), day(0)])
    }

    @Test func scoredDaysAreLeftAloneExceptTodayAndYesterday() {
        let scored = Set((-5...0).map(key))
        let days = NightsToScore.days(pairedAt: day(-5), now: day(0) + 9 * 3_600, scored: scored,
                                      historyFrom: nil, calendar: calendar)
        #expect(days == [day(-1), day(0)])
    }

    @Test func historyFromAWeekendAwayRescoresTheDaysItReaches() {
        let scored = Set((-5...0).map(key))
        let days = NightsToScore.days(pairedAt: day(-5), now: day(0) + 9 * 3_600, scored: scored,
                                      historyFrom: day(-3) + 20 * 3_600, calendar: calendar)
        #expect(days == [day(-3), day(-2), day(-1), day(0)])
    }

    @Test func historyNeverReachesBeforePairing() {
        let scored = Set((-2...0).map(key))
        let days = NightsToScore.days(pairedAt: day(-2) + 3_600, now: day(0) + 9 * 3_600, scored: scored,
                                      historyFrom: day(-9), calendar: calendar)
        #expect(days == [day(-2), day(-1), day(0)])
    }
}
