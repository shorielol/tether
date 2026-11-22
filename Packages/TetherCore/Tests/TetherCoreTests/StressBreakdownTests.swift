import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// "Show the maths" for Stress: each hour starts at 1.5 (exactly your calm level for the day), then heart
/// rate and HRV move it up or down the 0–3 curve.
@Suite("How an hour's stress was worked out")
struct StressBreakdownTests {
    private let day = SyntheticDay.streams(SyntheticDay.calmThenTense)

    @Test func everyScoredHourAddsUpToItsLevel() throws {
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, tzOffsetSeconds: 0)
        let scored = detail.hours.filter { $0.level != nil }
        #expect(!scored.isEmpty)
        for hour in scored {
            let breakdown = try #require(hour.breakdown)
            let level = try #require(hour.level)
            #expect(breakdown.start == 1.5)
            #expect(breakdown.total == (level * 10).rounded() / 10)
            #expect(abs(breakdown.start + breakdown.steps.map(\.points).reduce(0, +) - breakdown.total) < 0.001)
        }
    }

    @Test func aTenseHourIsPushedUpByHeartRateAndHRV() throws {
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, tzOffsetSeconds: 0)
        let tense = try #require(detail.hours.first { $0.hour == 15 }?.breakdown)
        #expect(tense.steps.map(\.name) == ["Heart rate", "HRV"])
        #expect(tense.steps.allSatisfy { $0.points > 0 })
        let calm = try #require(detail.hours.first { $0.hour == 7 }?.breakdown)
        #expect(calm.steps.allSatisfy { $0.points <= 0 })
    }

    @Test func theDaysCalmLevelIsShown() throws {
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, tzOffsetSeconds: 0)
        let calm = try #require(detail.calm)
        #expect(calm.heartRate <= 64)
        #expect((calm.hrv ?? 0) >= 40)
    }

    @Test func anHourSpentMovingHasNothingToBreakDown() throws {
        let day = SyntheticDay.streams([(7, 9, 54, 70), (9, 13, 64, 40), (13, 14, 96, 4), (14, 17, 64, 40)])
        let gravity = stride(from: SyntheticDay.at(7), to: SyntheticDay.at(17), by: 1).map { ts in
            let walking = ts >= SyntheticDay.at(13) && ts < SyntheticDay.at(14)
            return GravitySample(ts: ts, x: walking ? (ts.isMultiple(of: 2) ? 0.3 : -0.3) : 0, y: 0.1, z: 0.99)
        }
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, gravity: gravity, tzOffsetSeconds: 0)
        let walk = try #require(detail.hours.first { $0.hour == 13 })
        #expect(walk.wasMoving)
        #expect(walk.breakdown == nil)
    }
}
