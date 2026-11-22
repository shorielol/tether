import Foundation
import Testing
@testable import TetherCore

/// Phase 6 trends: each measure over 7, 30 or 90 days, its average, and which way it's heading.
@Suite("Trends")
struct TrendsTests {
    private func nights(_ count: Int, hrv: (Int) -> Double, charge: (Int) -> Double? = { _ in 60 }) -> [NightSummary] {
        (0..<count).map { index in
            let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: index - count + 1,
                                                             to: Date(timeIntervalSince1970: 1_795_305_600))!
            return NightSummary(day: DayScorer.dayKey(dayStart: Int(day.timeIntervalSince1970), timeZone: TimeZone(secondsFromGMT: 0)!),
                                sleepStart: 0, sleepEnd: 1, totalSleepMin: 420, efficiency: 0.9, deepMin: nil, remMin: nil,
                                lightMin: nil, disturbances: nil, restingHR: 52, hrv: hrv(index), respRate: 15,
                                charge: charge(index), rest: 80, drivers: [], stages: [], effort: 40)
        }
    }

    private let today = "2026-11-22"

    @Test func aRangeKeepsOnlyItsDays() throws {
        let all = nights(40, hrv: { _ in 60 })
        let series = try #require(Trends.compute(nights: all, days: 7, today: today).first { $0.name == "HRV" })
        #expect(series.points.count == 7)
        #expect(series.average == 60)
    }

    @Test func aRisingMeasureSaysSo() throws {
        let rising = nights(30, hrv: { 50 + Double($0) })
        let series = try #require(Trends.compute(nights: rising, days: 30, today: today).first { $0.name == "HRV" })
        #expect(try #require(series.change) > 10)
        #expect(series.isBetter == true)
    }

    @Test func missingValuesAreSkippedNotZeroed() throws {
        let gaps = nights(10, hrv: { _ in 60 }, charge: { $0.isMultiple(of: 2) ? 70 : nil })
        let charge = try #require(Trends.compute(nights: gaps, days: 30, today: today).first { $0.name == "Charge" })
        #expect(charge.points.count == 5)
        #expect(charge.average == 70)
    }

    @Test func theWeekIsComparedWithTheOneBefore() {
        let weeks = nights(14, hrv: { $0 < 7 ? 50 : 65 })
        let digest = Trends.weekly(nights: weeks, today: today)
        let hrv = digest.metrics.first { $0.metric.label == "HRV" }
        #expect(hrv != nil)
    }
}
