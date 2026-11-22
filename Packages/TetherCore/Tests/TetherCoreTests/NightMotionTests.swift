import Foundation
import Testing
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore
@testable import TetherCore

/// The strap's motion joins sleep staging: a restless stretch reads as awake even when heart rate stays low,
/// and a night with no motion data is staged from heart rate exactly as before.
@Suite("Motion in sleep stages")
struct NightMotionTests {
    private let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    /// 03:00–03:20, tossing and turning while heart rate stays at its sleeping level.
    static let restless = (SyntheticNight.dayStart + 3 * 3_600)..<(SyntheticNight.dayStart + 3 * 3_600 + 20 * 60)

    /// One reading a second: near-still in bed, moving while up and during the restless stretch.
    static func gravity() -> [GravitySample] {
        stride(from: SyntheticNight.dayStart - 4 * 3_600, to: SyntheticNight.dayStart + 10 * 3_600, by: 1).map { ts in
            let up = ts < SyntheticNight.bedtime || ts >= SyntheticNight.wake
            let moving = up || restless.contains(ts)
            let wobble = moving ? sin(Double(ts) / 3) * 0.4 : sin(Double(ts) / 7) * 0.002
            return GravitySample(ts: ts, x: wobble, y: 0.1, z: 0.99)
        }
    }

    /// Minutes of the night's wake stages that fall inside `window`.
    static func wakeMinutes(_ night: NightSummary, in window: Range<Int>) -> Int {
        night.stages.filter { $0.kind == .wake }.reduce(0) { total, stage in
            total + max(0, min(stage.end, window.upperBound) - max(stage.start, window.lowerBound))
        } / 60
    }

    @Test func aRestlessStretchReadsAsAwake() {
        let (hr, rr) = SyntheticNight.streams()
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, gravity: Self.gravity(),
                                    profile: profile, history: [], tzOffsetSeconds: 0)
        #expect(Self.wakeMinutes(night, in: Self.restless) >= 10)
    }

    @Test func heartRateAloneDoesNotSeeIt() {
        let (hr, rr) = SyntheticNight.streams()
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, profile: profile,
                                    history: [], tzOffsetSeconds: 0)
        #expect(Self.wakeMinutes(night, in: Self.restless) <= 5)
    }

    @Test func aStillNightStaysAsleepWithMotion() throws {
        let (hr, rr) = SyntheticNight.streams()
        let still = Self.gravity().map { sample in
            Self.restless.contains(sample.ts)
                ? GravitySample(ts: sample.ts, x: sin(Double(sample.ts) / 7) * 0.002, y: 0.1, z: 0.99) : sample
        }
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, gravity: still,
                                    profile: profile, history: [], tzOffsetSeconds: 0)
        #expect(Self.wakeMinutes(night, in: Self.restless) <= 5)
        #expect((night.totalSleepMin ?? 0) > 360)
    }
}
