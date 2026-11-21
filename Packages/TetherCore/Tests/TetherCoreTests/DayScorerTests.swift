import Foundation
import Testing
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore
@testable import TetherCore

/// A night scored in UTC so the windows are easy to reason about.
enum SyntheticNight {
    /// 2026-11-22 00:00 UTC: the night of 21→22 November belongs to this day.
    static let dayStart = 1_795_305_600
    static let day = "2026-11-22"
    static let bedtime = dayStart - 3_600        // 23:00
    static let wake = dayStart + 7 * 3_600       // 07:00

    static func bpm(at ts: Int) -> Int {
        let asleep = ts >= bedtime && ts < wake
        // Sleeping heart rate is steady minute to minute (±1); awake it moves more.
        let wobble = Int((sin(Double(ts) / 41) * (asleep ? 1 : 3)).rounded())
        return (asleep ? 52 : 76) + wobble
    }

    static func streams() -> (hr: [HRSample], rr: [RRInterval]) {
        let from = dayStart - 4 * 3_600, to = dayStart + 10 * 3_600
        let hr = stride(from: from, to: to, by: 1).map { HRSample(ts: $0, bpm: bpm(at: $0)) }
        // Beats follow their own durations, the way the strap reports them.
        var rr: [RRInterval] = []
        var t = Double(from)
        var beat = 0
        var lastSecond = -1
        var ordInSecond = 0
        while t < Double(to) {
            let second = Int(t)
            let asleep = second >= bedtime && second < wake
            let spread = asleep ? 30 : 12
            let ms = 60_000 / bpm(at: second) + (beat.isMultiple(of: 2) ? spread : -spread)
            ordInSecond = second == lastSecond ? ordInSecond + 1 : 0
            rr.append(RRInterval(ts: second, rrMs: ms, ord: ordInSecond, seq: beat))
            lastSecond = second
            t += Double(ms) / 1_000
            beat += 1
        }
        return (hr, rr)
    }
}

@Suite("Night scoring")
struct DayScorerTests {
    private let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    @Test func windowCoversTheNightEndingOnThatDay() {
        let window = DayScorer.window(dayStart: SyntheticNight.dayStart, now: SyntheticNight.dayStart + 200_000)
        #expect(window.lowerBound == SyntheticNight.dayStart - 30 * 3_600)
        #expect(window.upperBound == SyntheticNight.dayStart + 86_400)
        let early = DayScorer.window(dayStart: SyntheticNight.dayStart, now: SyntheticNight.dayStart + 3_600)
        #expect(early.upperBound == SyntheticNight.dayStart + 3_600)
    }

    @Test func aClearNightIsFoundAndSummarised() throws {
        let (hr, rr) = SyntheticNight.streams()
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, profile: profile,
                                    history: [], tzOffsetSeconds: 0)
        let start = try #require(night.sleepStart)
        let end = try #require(night.sleepEnd)
        #expect(abs(start - SyntheticNight.bedtime) <= 3_600)
        #expect(abs(end - SyntheticNight.wake) <= 3_600)
        #expect((night.totalSleepMin ?? 0) > 300)
        #expect(!night.stages.isEmpty)
        let resting = try #require(night.restingHR)
        #expect((45...60).contains(resting))
        #expect((night.hrv ?? 0) > 0)
        #expect(night.charge == nil)   // no baseline yet
    }

    @Test func anEmptyNightHasNoSleep() {
        let night = DayScorer.score(day: SyntheticNight.day, hr: [], rr: [], profile: profile,
                                    history: [], tzOffsetSeconds: 0)
        #expect(night.sleepStart == nil)
        #expect(night.totalSleepMin == nil || night.totalSleepMin == 0)
        #expect(night.stages.isEmpty)
    }

    @Test func storeScoresOnceAndCountsBaselineNights() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tether-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = WhoopStoreSink(path: dir.appendingPathComponent("tether.sqlite").path)
        let (hr, rr) = SyntheticNight.streams()
        try await sink.write(SampleBatch(Streams(hr: hr, rr: rr)))
        let now = SyntheticNight.dayStart + 12 * 3_600
        let first = try await sink.scoreDay(dayStart: SyntheticNight.dayStart, now: now, profile: profile, tzOffsetSeconds: 0)
        _ = try await sink.scoreDay(dayStart: SyntheticNight.dayStart, now: now, profile: profile, tzOffsetSeconds: 0)
        #expect(first.sleepStart != nil)
        #expect(try await sink.scoredDays(from: "2026-11-01", to: "2026-11-30") == [SyntheticNight.day])
        #expect(try await sink.baselineNightCount() == 1)
        let saved = try await sink.nights(from: "2026-11-01", to: "2026-11-30")
        #expect(saved.map(\.day) == [SyntheticNight.day])
        #expect(saved.first?.restingHR == first.restingHR)
    }
}
