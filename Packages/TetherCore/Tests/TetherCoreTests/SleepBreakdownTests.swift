import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// "Show the maths" for Sleep: time in bed, minus the time awake, is the time asleep.
@Suite("How Sleep was worked out")
struct SleepBreakdownTests {
    private let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    private func night(stages: [(NightSummary.Stage.Kind, Int)], totalSleepMin: Double? = nil) -> NightSummary {
        var at = 1_000_000
        let built = stages.map { kind, minutes in
            defer { at += minutes * 60 }
            return NightSummary.Stage(start: at, end: at + minutes * 60, kind: kind)
        }
        let asleep = Double(stages.filter { $0.0 != .wake }.reduce(0) { $0 + $1.1 })
        return NightSummary(day: "2026-11-22", sleepStart: 1_000_000, sleepEnd: at,
                            totalSleepMin: totalSleepMin ?? asleep, efficiency: nil, deepMin: nil, remMin: nil,
                            lightMin: nil, disturbances: nil, restingHR: nil, hrv: nil, respRate: nil, charge: nil,
                            rest: nil, drivers: [], stages: built)
    }

    @Test func inBedMinusAwakeIsAsleep() throws {
        let breakdown = try #require(ScoreBreakdown.sleep(night(stages: [(.wake, 10), (.light, 200), (.wake, 15),
                                                                         (.deep, 90), (.rem, 100), (.wake, 5)])))
        #expect(breakdown.start == 420)
        #expect(breakdown.steps.map(\.name) == ["Awake in the night"])
        #expect(breakdown.steps.first?.points == -30)
        #expect(breakdown.total == 390)
    }

    @Test func sleepOutsideTheMainStretchIsItsOwnLine() throws {
        let breakdown = try #require(ScoreBreakdown.sleep(night(stages: [(.light, 300), (.wake, 20)], totalSleepMin: 345)))
        #expect(breakdown.steps.map(\.name) == ["Awake in the night", "Other sleep that night"])
        #expect(breakdown.steps.last?.points == 45)
        #expect(breakdown.start + breakdown.steps.map(\.points).reduce(0, +) == breakdown.total)
        #expect(breakdown.total == 345)
    }

    @Test func aTotalBelowTheStretchIsCalledTrimmedNotAdded() throws {
        let breakdown = try #require(ScoreBreakdown.sleep(night(stages: [(.light, 300), (.wake, 20)], totalSleepMin: 290)))
        #expect(breakdown.steps.last?.name == "Trimmed by the scorer")
        #expect(breakdown.steps.last?.points == -10)
        #expect(breakdown.total == 290)
    }

    @Test func aNightWithoutSleepHasNothingToBreakDown() {
        let empty = NightSummary(day: "2026-11-22", sleepStart: nil, sleepEnd: nil, totalSleepMin: nil, efficiency: nil,
                                 deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHR: nil, hrv: nil,
                                 respRate: nil, charge: nil, rest: nil, drivers: [], stages: [])
        #expect(ScoreBreakdown.sleep(empty) == nil)
    }

    @Test func aScoredNightAddsUpToItsTimeAsleep() throws {
        let (hr, rr) = SyntheticNight.streams()
        let scored = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, profile: profile, history: [],
                                     tzOffsetSeconds: 0)
        let asleep = try #require(scored.totalSleepMin)
        let breakdown = try #require(ScoreBreakdown.sleep(scored))
        #expect(breakdown.total == asleep.rounded())
        #expect(breakdown.start + breakdown.steps.map(\.points).reduce(0, +) == breakdown.total)
    }
}
