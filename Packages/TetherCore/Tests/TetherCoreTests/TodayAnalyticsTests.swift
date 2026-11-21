import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

@Suite("Today analytics")
struct TodayAnalyticsTests {
    private let t0 = 1_699_999_980   // on a minute boundary
    private let teen = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    private func steady(_ bpm: Int, from start: Int, seconds: Int) -> [HRSample] {
        (0..<seconds).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    @Test func restThenHardBlockFillsZonesEffortAndCalories() throws {
        let hr = steady(60, from: t0, seconds: 3_600) + steady(150, from: t0 + 3_600, seconds: 1_200)
        let now = t0 + 4_799
        let day = TodayAnalytics.compute(hr: hr, rr: [], profile: teen, window: t0...now, now: now)
        #expect(day.maxHR == 196)
        #expect(day.minuteSeries.count == 80)
        #expect(Set(day.minuteSeries.map(\.segment)).count == 1)
        #expect(day.minBPM == 60)
        #expect(day.maxBPM == 150)
        #expect(day.avgBPM == 83)
        #expect(day.zoneMinutes == [0, 0, 20, 0, 0])
        let effort = try #require(day.effort)
        let restOnly = TodayAnalytics.compute(hr: Array(hr.prefix(3_600)), rr: [], profile: teen,
                                              window: t0...(t0 + 3_599), now: t0 + 3_599)
        #expect(effort > (restOnly.effort ?? 0))
        #expect((day.caloriesTotal ?? 0) > 0)
        #expect((day.caloriesActive ?? 0) > 0)
    }

    @Test func aTenMinuteHoleBreaksTheChartAndCountsAsAGap() throws {
        let hr = steady(70, from: t0, seconds: 1_800) + steady(72, from: t0 + 2_400, seconds: 1_800)
        let now = t0 + 4_199
        let day = TodayAnalytics.compute(hr: hr, rr: [], profile: teen, window: t0...now, now: now)
        #expect(Set(day.minuteSeries.map(\.segment)).count == 2)
        let coverage = try #require(day.coverage)
        #expect(coverage.gaps.count == 1)
    }

    @Test func hrvNowUsesTheLastFiveMinutesOfBeats() throws {
        let now = t0 + 600
        let rr = (0..<300).map { i in RRInterval(ts: now - 299 + i, rrMs: i.isMultiple(of: 2) ? 800 : 850, ord: 0, seq: 0) }
        let hr = steady(72, from: now - 299, seconds: 300)
        let day = TodayAnalytics.compute(hr: hr, rr: rr, profile: teen, window: t0...now, now: now)
        let hrv = try #require(day.hrvNow)
        #expect(abs(hrv - 50) < 1)
    }

    @Test func noSamplesMeansNothingIsShownNotZeros() {
        let day = TodayAnalytics.compute(hr: [], rr: [], profile: teen, window: t0...(t0 + 600), now: t0 + 600)
        #expect(day.isEmpty)
        #expect(day.effort == nil)
        #expect(day.caloriesTotal == nil)
        #expect(day.hrvNow == nil)
        #expect(day.minBPM == nil)
    }

    @Test func restingHRComesFromProfileThenLowestFiveMinutesThenDefault() {
        let hr = steady(55, from: t0, seconds: 600) + steady(90, from: t0 + 600, seconds: 600)
        let now = t0 + 1_199
        let withProfile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: 52, sex: .male)
        let a = TodayAnalytics.compute(hr: hr, rr: [], profile: withProfile, window: t0...now, now: now)
        #expect(a.restingHR == 52 && a.restingSource == .profile)
        let b = TodayAnalytics.compute(hr: hr, rr: [], profile: teen, window: t0...now, now: now)
        #expect(b.restingHR == 55 && b.restingSource == .lowestFiveMinutes)
        let short = steady(80, from: t0, seconds: 120)
        let c = TodayAnalytics.compute(hr: short, rr: [], profile: teen, window: t0...(t0 + 119), now: t0 + 119)
        #expect(c.restingHR == 60 && c.restingSource == .defaultValue)
    }

    @Test func liveZoneFromBPM() {
        #expect(TodayAnalytics.zone(bpm: 150, maxHR: 196) == 3)
        #expect(TodayAnalytics.zone(bpm: 60, maxHR: 196) == 0)
        #expect(TodayAnalytics.zone(bpm: 190, maxHR: 196) == 5)
    }
}
