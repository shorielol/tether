import Foundation
import Testing
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore
@testable import TetherCore

/// "Show the maths" for Charge: a running total from a night exactly at your normal to the real score,
/// and a what-if that re-runs the real scorer.
@Suite("How Charge was worked out")
struct ScoreBreakdownTests {
    private let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    private func inputs(hrv: Double = 62, restingHR: Double = 50, resp: Double? = 15.4, rest: Double? = 78,
                        skinTempDevC: Double? = 0.3) -> ChargeInputs {
        ChargeInputs(hrv: hrv, restingHR: restingHR, resp: resp, rest: rest, skinTempDevC: skinTempDevC,
                     hrvNormal: .init(mean: 55, spread: 6), restingHRNormal: .init(mean: 52, spread: 2),
                     respNormal: .init(mean: 15.0, spread: 0.6))
    }

    @Test func theStepsAddUpExactlyToTheScore() throws {
        let charge = try #require(inputs().charge())
        let breakdown = try #require(ScoreBreakdown.charge(inputs()))
        #expect(breakdown.total == charge.rounded())
        #expect(breakdown.start + breakdown.steps.map(\.points).reduce(0, +) == breakdown.total)
    }

    @Test func itStartsFromANightAtYourNormal() throws {
        let level = inputs(hrv: 55, restingHR: 52, resp: 15.0, rest: 85, skinTempDevC: 0)
        let breakdown = try #require(ScoreBreakdown.charge(level))
        #expect(breakdown.steps.allSatisfy { $0.points == 0 })
        #expect(breakdown.total == breakdown.start)
    }

    @Test func eachMeasureMovesTheWayItShould() throws {
        let breakdown = try #require(ScoreBreakdown.charge(inputs()))
        func points(_ name: String) -> Double? { breakdown.steps.first { $0.name == name }?.points }
        #expect((points("HRV") ?? 0) > 0)           // above normal
        #expect((points("Resting HR") ?? 0) > 0)    // below normal is good
        #expect((points("Sleep") ?? 0) < 0)         // Rest 78 is under the steady point
        #expect((points("Skin temp") ?? 0) <= 0)    // any drift costs a little
        #expect(breakdown.steps.map(\.name) == ["HRV", "Resting HR", "Sleep", "Breathing", "Skin temp"])
    }

    @Test func missingMeasuresAreLeftOutNotFaked() throws {
        let breakdown = try #require(ScoreBreakdown.charge(inputs(resp: nil, rest: nil, skinTempDevC: nil)))
        #expect(breakdown.steps.map(\.name) == ["HRV", "Resting HR"])
        #expect(breakdown.start + breakdown.steps.map(\.points).reduce(0, +) == breakdown.total)
    }

    @Test func aWhatIfWithNothingChangedIsTheRealScore() throws {
        let real = try #require(inputs().charge())
        var whatIf = inputs()
        #expect(whatIf.charge() == real)
        whatIf.hrv += 10
        #expect(try #require(whatIf.charge()) > real)
        whatIf = inputs()
        whatIf.rest = 95
        #expect(try #require(whatIf.charge()) > real)
    }

    @Test func aScoredNightCarriesTheInputsItsChargeCameFrom() throws {
        let (hr, rr) = SyntheticNight.streams()
        let history = (0..<6).map { index in
            DailyMetric(day: String(format: "2026-11-%02d", 10 + index), totalSleepMin: 420, efficiency: 0.9,
                        deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                        restingHr: 50 + index % 3, avgHrv: 60 + Double(index * 3), recovery: nil, strain: nil,
                        exerciseCount: nil)
        }
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, profile: profile,
                                    history: history, tzOffsetSeconds: 0)
        let charge = try #require(night.charge)
        let carried = try #require(night.chargeInputs)
        #expect(carried.charge() == charge)
        #expect(try #require(ScoreBreakdown.charge(carried)).total == charge.rounded())
    }

    @Test func aNightWithoutChargeHasNothingToBreakDown() {
        let (hr, rr) = SyntheticNight.streams()
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, profile: profile,
                                    history: [], tzOffsetSeconds: 0)
        #expect(night.chargeInputs == nil)
    }
}
