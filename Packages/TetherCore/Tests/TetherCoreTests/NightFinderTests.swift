import Foundation
import Testing
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore
@testable import TetherCore

/// Heart rate shaped like a real late night: awake and high until 03:40, asleep in the 60s and
/// then the high 50s, one 10-minute wake at 08:50, up at 10:20. All in UTC.
enum LateNight {
    static let dayStart = SyntheticNight.dayStart
    static let day = SyntheticNight.day

    static func hour(_ h: Double) -> Int { dayStart + Int(h * 3_600) }

    /// Piecewise heart rate, each piece `(from hour, to hour, bpm)`, with a small wobble.
    static func samples(_ pieces: [(Double, Double, Int)]) -> [HRSample] {
        pieces.flatMap { from, to, bpm in
            stride(from: hour(from), to: hour(to), by: 1).map { ts in
                HRSample(ts: ts, bpm: bpm + Int((sin(Double(ts) / 37) * 2).rounded()))
            }
        }
    }

    static let pieces: [(Double, Double, Int)] = [
        (-1, 3.67, 95), (3.67, 7, 64), (7, 8.83, 57), (8.83, 9, 70), (9, 10.33, 57), (10.33, 11, 82),
    ]

    /// One beat per heartbeat, timed by the heart rate, the way the strap reports them.
    static func beats(_ hr: [HRSample]) -> [RRInterval] {
        var out: [RRInterval] = []
        var seq = 0
        for sample in hr where sample.ts.isMultiple(of: 2) {
            let ms = 60_000 / max(sample.bpm, 30)
            out.append(RRInterval(ts: sample.ts, rrMs: ms + (seq.isMultiple(of: 2) ? 25 : -25), ord: 0, seq: seq))
            seq += 1
        }
        return out
    }
}

@Suite("Finding the whole night")
struct NightFinderTests {
    private let tolerance = 15 * 60

    @Test func findsTheWholeLateNight() throws {
        let span = try #require(NightFinder.night(hr: LateNight.samples(LateNight.pieces), dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(3.67)) <= tolerance)
        #expect(abs(span.upperBound - LateNight.hour(10.33)) <= tolerance)
    }

    @Test func aLongWakeSplitsTheNightAndTheLongerPartWins() throws {
        let hr = LateNight.samples([(-1, 0, 90), (0, 2, 55), (2, 3, 90), (3, 8, 55), (8, 9, 88)])
        let span = try #require(NightFinder.night(hr: hr, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(3)) <= tolerance)
        #expect(abs(span.upperBound - LateNight.hour(8)) <= tolerance)
    }

    @Test func aLongStretchWithNoDataEndsTheNight() throws {
        let hr = LateNight.samples([(-1, 0, 90), (0, 2, 55), (4, 8, 55), (8, 9, 88)])
        let span = try #require(NightFinder.night(hr: hr, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(4)) <= tolerance)
    }

    @Test func aDayAwakeHasNoNight() {
        let hr = LateNight.samples([(-1, 11, 92)])
        #expect(NightFinder.night(hr: hr, dayStart: LateNight.dayStart) == nil)
    }

    @Test func aCalmEveningIsNotSleep() throws {
        let hr = LateNight.samples([(-4, -1, 74), (-1, 7, 52), (7, 9, 80)])
        let span = try #require(NightFinder.night(hr: hr, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(-1)) <= tolerance)
    }

    @Test func aNightEndingTheDayBeforeIsNotThisDaysNight() {
        let hr = LateNight.samples([(-30, -24, 52), (-24, 11, 90)])
        #expect(NightFinder.night(hr: hr, dayStart: LateNight.dayStart) == nil)
    }

    @Test func rescoringADayDropsItsOldFragments() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tether-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = WhoopStoreSink(path: dir.appendingPathComponent("tether.sqlite").path)
        let hr = LateNight.samples(LateNight.pieces)
        try await sink.write(SampleBatch(Streams(hr: hr, rr: LateNight.beats(hr))))
        // A fragment an earlier pass saved for the same night.
        let stale = CachedSleepSession(startTs: LateNight.hour(7.4), endTs: LateNight.hour(8.7), efficiency: 1,
                                       restingHr: nil, avgHrv: nil, stagesJSON: nil)
        _ = try await sink.openStore().upsertSleepSessions([stale], deviceId: WhoopStoreSink.deviceId)
        let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)
        _ = try await sink.scoreDay(dayStart: LateNight.dayStart, now: LateNight.hour(12), profile: profile,
                                   tzOffsetSeconds: 0)
        let saved = try await sink.openStore().sleepSessions(deviceId: WhoopStoreSink.deviceId, from: 0,
                                                             to: Int.max / 2, limit: 100)
        #expect(!saved.contains { $0.startTs == stale.startTs })
        #expect(saved.count == 1)
    }

    @Test func theScoreCountsTheWholeNightNotOneFragment() {
        let hr = LateNight.samples(LateNight.pieces)
        let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)
        let night = DayScorer.score(day: LateNight.day, hr: hr, rr: LateNight.beats(hr), profile: profile,
                                    history: [], tzOffsetSeconds: 0)
        #expect((night.totalSleepMin ?? 0) >= 300)
        #expect(abs((night.sleepStart ?? 0) - LateNight.hour(3.67)) <= tolerance)
    }
}
