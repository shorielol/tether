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

/// Motion one reading a second: still keeps the wrist where it is, moving shifts it every second.
enum Wrist {
    static func samples(_ pieces: [(Double, Double, Bool)]) -> [GravitySample] {
        pieces.flatMap { from, to, still in
            stride(from: LateNight.hour(from), to: LateNight.hour(to), by: 1).map { ts in
                let wobble = still ? 0.002 * sin(Double(ts)) : 0.2 * sin(Double(ts) * 1.7)
                return GravitySample(ts: ts, x: 0.1 + wobble, y: 0.2, z: 0.9 - wobble, dynAccel: still ? 0.006 : 0.09)
            }
        }
    }
}

@Suite("Finding the night from motion")
struct NightFromMotionTests {
    private let tolerance = 15 * 60
    private let profile = UserProfile(age: 17, heightCm: 167, weightKg: 60, restingHR: nil, sex: .male)

    /// After a hard evening the heart stays high for hours of real sleep. Lying still is the night.
    private var hardEvening: (hr: [HRSample], gravity: [GravitySample]) {
        let hr = LateNight.samples([(-8, -1, 135), (-1, 1.25, 108), (1.25, 4, 97), (4, 6, 86), (6, 10.6, 68),
                                    (10.6, 12, 84)])
        let gravity = Wrist.samples([(-8, 1.25, false), (1.25, 10.6, true), (10.6, 12, false)])
        return (hr, gravity)
    }

    @Test func aStillNightWithAHighHeartIsStillANight() throws {
        let (hr, gravity) = hardEvening
        let span = try #require(NightFinder.night(hr: hr, gravity: gravity, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(1.25)) <= tolerance)
        #expect(abs(span.upperBound - LateNight.hour(10.6)) <= tolerance)
    }

    @Test func movingAgainEndsTheNightEvenWithACalmHeart() throws {
        // Asleep 03:00–11:35, then up and about with a heart rate as low as the night's.
        let hr = LateNight.samples([(-8, 3, 95), (3, 11.6, 58), (11.6, 14, 64), (14, 16, 95)])
        let gravity = Wrist.samples([(-8, 3, false), (3, 11.6, true), (11.6, 16, false)])
        let span = try #require(NightFinder.night(hr: hr, gravity: gravity, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(3)) <= tolerance)
        #expect(abs(span.upperBound - LateNight.hour(11.6)) <= tolerance)
    }

    @Test func stillWithAnExerciseHeartIsNotSleep() throws {
        // A long still stretch at 150 bpm (a spin class, arms on the bars) next to a real night.
        let hr = LateNight.samples([(-8, -4, 90), (-4, -1, 150), (-1, 0, 90), (0, 7, 58), (7, 9, 85)])
        let gravity = Wrist.samples([(-8, -4, false), (-4, -1, true), (-1, 0, false), (0, 7, true), (7, 9, false)])
        let span = try #require(NightFinder.night(hr: hr, gravity: gravity, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(0)) <= tolerance)
    }

    @Test func aSteadyWristThatIsAcceleratingIsNotSleep() throws {
        // A three-hour night, then four hours in the afternoon with a fixed wrist angle and real
        // acceleration (cycling, hands on the bars) at a heart rate under the still ceiling.
        let busy = stride(from: LateNight.hour(12), to: LateNight.hour(16), by: 1).map { ts in
            GravitySample(ts: ts, x: 0.1, y: 0.2, z: 0.9, dynAccel: 0.35)
        }
        let hr = LateNight.samples([(-8, 0, 100), (0, 3, 58), (3, 12, 95), (12, 16, 85), (16, 18, 100)])
        let gravity = Wrist.samples([(-8, 0, false), (0, 3, true), (3, 12, false)]) + busy
            + Wrist.samples([(16, 18, false)])
        let span = try #require(NightFinder.night(hr: hr, gravity: gravity, dayStart: LateNight.dayStart))
        #expect(abs(span.lowerBound - LateNight.hour(0)) <= tolerance)
        #expect(abs(span.upperBound - LateNight.hour(3)) <= tolerance)
    }

    @Test func withoutMotionTheHeartStillFindsTheNight() throws {
        let span = try #require(NightFinder.night(hr: LateNight.samples(LateNight.pieces), gravity: [],
                                                  dayStart: LateNight.dayStart))
        #expect(abs(span.upperBound - LateNight.hour(10.33)) <= tolerance)
    }

    @Test func theScoreUsesTheStillNightAfterAHardEvening() {
        let (hr, gravity) = hardEvening
        let night = DayScorer.score(day: LateNight.day, hr: hr, rr: LateNight.beats(hr), gravity: gravity,
                                    profile: profile, history: [], tzOffsetSeconds: 0)
        #expect(abs((night.sleepStart ?? 0) - LateNight.hour(1.25)) <= tolerance)
        #expect(abs((night.sleepEnd ?? 0) - LateNight.hour(10.6)) <= tolerance)
        #expect((night.totalSleepMin ?? 0) >= 420)
    }

    @Test func theScoreEndsTheNightWhenTheWristMoves() {
        let hr = LateNight.samples([(-8, 3, 95), (3, 11.6, 58), (11.6, 14, 64), (14, 16, 95)])
        let gravity = Wrist.samples([(-8, 3, false), (3, 11.6, true), (11.6, 16, false)])
        let night = DayScorer.score(day: LateNight.day, hr: hr, rr: LateNight.beats(hr), gravity: gravity,
                                    profile: profile, history: [], tzOffsetSeconds: 0)
        #expect(abs((night.sleepEnd ?? 0) - LateNight.hour(11.6)) <= tolerance)
    }
}
