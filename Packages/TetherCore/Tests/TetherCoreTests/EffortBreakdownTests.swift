import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// "Show the maths" for Effort: minutes in each heart-rate band, each worth its band number, added up
/// and put on the Effort curve.
@Suite("How Effort was worked out")
struct EffortBreakdownTests {
    private let t0 = 1_699_999_980
    private let teen = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    private func steady(_ bpm: Int, from start: Int, seconds: Int) -> [HRSample] {
        (0..<seconds).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    private func day() -> TodaySnapshot {
        let hr = steady(60, from: t0, seconds: 3_600) + steady(150, from: t0 + 3_600, seconds: 1_200)
            + steady(185, from: t0 + 4_800, seconds: 600)
        let now = t0 + 5_399
        return TodayAnalytics.compute(hr: hr, rr: [], profile: teen, window: t0...now, now: now)
    }

    @Test func theTodayNumbersCarryTheMinutesEffortCounted() throws {
        let today = day()
        #expect(today.effortBandMinutes.count == 6)
        #expect(today.effortBandMinutes[0] > 55)                       // the resting hour counts nothing
        #expect(abs(today.effortBandMinutes.dropFirst().reduce(0, +) - 30) < 1)
    }

    @Test func theStepsAddUpToTodaysEffort() throws {
        let today = day()
        let effort = try #require(today.effort)
        let breakdown = try #require(ScoreBreakdown.effort(bandMinutes: today.effortBandMinutes))
        #expect(breakdown.start == 0)
        #expect(breakdown.total == (effort * 10).rounded() / 10)
        #expect(abs(breakdown.steps.map(\.points).reduce(0, +) - breakdown.total) < 0.001)
        #expect(breakdown.steps.count == 5)
        #expect(breakdown.steps.filter { $0.points > 0 }.count == 2)   // two bands were used
    }

    @Test func aWhatIfWithNothingAddedIsTheRealEffort() throws {
        let today = day()
        let effort = try #require(today.effort)
        #expect(abs(ScoreBreakdown.effortScore(bandMinutes: today.effortBandMinutes) - effort) < 0.01)
        var more = today.effortBandMinutes
        more[4] += 20
        #expect(ScoreBreakdown.effortScore(bandMinutes: more) > effort)
    }

    @Test func aRestingDayAddsNothing() throws {
        let breakdown = try #require(ScoreBreakdown.effort(bandMinutes: [600, 0, 0, 0, 0, 0]))
        #expect(breakdown.total == 0)
        #expect(breakdown.steps.allSatisfy { $0.points == 0 })
        #expect(ScoreBreakdown.effort(bandMinutes: []) == nil)
    }
}
