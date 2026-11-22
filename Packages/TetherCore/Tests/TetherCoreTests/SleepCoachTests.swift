import Foundation
import Testing
@testable import TetherCore

/// Phase 4: how much sleep you need tonight, when to go to bed, and how last night measured up.
@Suite("Sleep coach")
struct SleepCoachTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-11-10 00:00 UTC.
    private let base = 1_794_268_800

    /// A night ending on day `index`, asleep from `bed` to `wake` (hours, `bed` on the evening before).
    private func night(_ index: Int, bed: Double = 22.5, wake: Double = 7, asleep: Double? = nil,
                       deep: Double = 90, rem: Double = 100) -> NightSummary {
        let dayStart = base + index * 86_400
        let start = dayStart - Int((24 - bed) * 3_600), end = dayStart + Int(wake * 3_600)
        return NightSummary(day: DayScorer.dayKey(dayStart: dayStart, timeZone: utc), sleepStart: start, sleepEnd: end,
                            totalSleepMin: asleep ?? Double(end - start) / 60 - 20, efficiency: 0.95, deepMin: deep,
                            remMin: rem, lightMin: 200, disturbances: nil, restingHR: nil, hrv: nil, respRate: nil,
                            charge: nil, rest: nil, drivers: [], stages: [])
    }

    private func coach(_ nights: [NightSummary], effort: Double? = nil, age: Int = 17,
                       wake: (hour: Int, minute: Int)? = nil) -> SleepCoach? {
        SleepCoach.compute(nights: nights, effortYesterday: effort, age: age, wakeTarget: wake, timeZone: utc)
    }

    @Test func aTeenNeedsNineHoursAndAnAdultEight() throws {
        let rested = (0..<5).map { night($0, bed: 21.5, wake: 7, asleep: 560) }
        #expect(try #require(coach(rested)).need.baseMin == 540)
        #expect(try #require(coach(rested, age: 30)).need.baseMin == 480)
        #expect(try #require(coach(rested)).need.debtMin == 0)
    }

    @Test func shortNightsAddCatchUp() throws {
        let short = (0..<5).map { night($0, asleep: 380) }
        let need = try #require(coach(short)).need
        #expect(need.owedMin > 60)
        #expect(need.debtMin == SleepCoach.maxCatchUpMin, "paid back an hour a night at most")
        #expect(need.totalMin == need.baseMin + need.debtMin + need.effortMin)
    }

    @Test func aHardDayAddsALittle() throws {
        let nights = (0..<5).map { night($0, asleep: 560) }
        #expect(try #require(coach(nights, effort: 75)).need.effortMin == 20)
        #expect(try #require(coach(nights, effort: 55)).need.effortMin == 10)
        #expect(try #require(coach(nights, effort: 30)).need.effortMin == 0)
    }

    @Test func bedtimeCountsBackFromTheAlarm() throws {
        let rested = (0..<5).map { night($0, bed: 21.5, wake: 7, asleep: 560) }
        let plan = try #require(coach(rested, wake: (7, 0)))
        #expect(plan.wakeMinute == 7 * 60)
        #expect(plan.bedtimeMinute == (7 * 60 - 540 - SleepCoach.fallAsleepMin + 1_440) % 1_440)
        #expect(plan.wakeFromAlarm)
    }

    @Test func withoutAnAlarmItUsesYourUsualWakeTime() throws {
        let nights = (0..<5).map { night($0, wake: 6.5) }
        let plan = try #require(coach(nights))
        #expect(plan.wakeMinute == 6 * 60 + 30)
        #expect(!plan.wakeFromAlarm)
    }

    @Test func steadyTimesAreConsistentAndScatteredOnesAreNot() throws {
        let steady = (0..<7).map { night($0, bed: 22.5, wake: 7) }
        let scattered = (0..<7).map { night($0, bed: [21.0, 23.5, 0.0 + 24, 22.0, 1.0 + 24, 21.5, 23.0][$0] - ($0 == 2 || $0 == 4 ? 24 : 0),
                                           wake: [6, 9, 7.5, 5.5, 10, 6.5, 8][$0]) }
        let calm = try #require(coach(steady)).consistency
        let messy = try #require(coach(scattered)).consistency
        #expect(calm == 100)
        #expect(try #require(messy) < 70)
    }

    @Test func lastNightIsMeasuredAgainstItsNeed() throws {
        let nights = (0..<4).map { night($0, asleep: 560) } + [night(4, asleep: 405, deep: 80, rem: 95)]
        let plan = try #require(coach(nights))
        let last = try #require(plan.lastNight)
        #expect(last.restorativeMin == 175)
        #expect(last.performance > 0.6 && last.performance < 0.9)
    }

    @Test func tooFewNightsMeansNoCoachYet() {
        #expect(coach([night(0)]) == nil)
    }
}
