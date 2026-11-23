import Foundation
import Testing
@testable import TetherCore

/// Fitness age: NOOP's Nes-model estimate from resting heart rate and how active your week was.
@Suite("Fitness age")
struct FitnessAgeTests {
    private func week(rhr: Int, effort: Double, count: Int = 7) -> [NightSummary] {
        (0..<count).map { index in
            NightSummary(day: String(format: "2026-11-%02d", 10 + index), sleepStart: 0, sleepEnd: 1, totalSleepMin: 420,
                         efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHR: rhr,
                         hrv: nil, respRate: nil, charge: nil, rest: nil, drivers: [], stages: [], effort: effort)
        }
    }

    @Test func aFitActiveAdultReadsYounger() throws {
        guard case .estimate(let years, let band, let actual) = FitnessAge.compute(nights: week(rhr: 50, effort: 70), age: 35, sex: "male") else {
            Issue.record("expected an estimate"); return
        }
        #expect(years < actual)
        #expect(band == 5)
    }

    @Test func aHigherRestingHeartRateAndQuietWeekReadsOlder() throws {
        guard case .estimate(let years, _, let actual) = FitnessAge.compute(nights: week(rhr: 78, effort: 10), age: 35, sex: "male") else {
            Issue.record("expected an estimate"); return
        }
        #expect(years > actual)
    }

    @Test func itWaitsUntilTheFormulaFitsYourAge() {
        #expect(FitnessAge.compute(nights: week(rhr: 50, effort: 70), age: 17, sex: "male") == .tooYoung(startsAt: 20))
    }

    @Test func itNeedsMostOfAWeek() {
        #expect(FitnessAge.compute(nights: week(rhr: 50, effort: 70, count: 3), age: 35, sex: "male") == .needsMoreDays(have: 3, need: 4))
    }
}
