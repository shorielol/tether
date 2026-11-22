import Foundation
import Testing
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore
@testable import TetherCore

/// Skin temperature from the strap's history joins each night's score: the night's own value, then the
/// difference from your normal once there are enough earlier nights to have one.
@Suite("Skin temperature in the night's score")
struct NightSkinTempTests {
    private let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)

    /// One reading a minute, warmer while asleep, the way skin is at night. WHOOP 5 stores centidegrees.
    static func skin(asleepC: Double, awakeC: Double) -> [SkinTempSample] {
        stride(from: SyntheticNight.dayStart - 4 * 3_600, to: SyntheticNight.dayStart + 10 * 3_600, by: 60).map { ts in
            let asleep = ts >= SyntheticNight.bedtime && ts < SyntheticNight.wake
            return SkinTempSample(ts: ts, raw: Int(((asleep ? asleepC : awakeC) * 100).rounded()))
        }
    }

    static func earlierNight(_ index: Int, skinC: Double) -> DailyMetric {
        DailyMetric(day: String(format: "2026-11-%02d", 10 + index), totalSleepMin: 420, efficiency: 0.9,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52, avgHrv: 70,
                    recovery: nil, strain: nil, exerciseCount: nil, skinTempC: skinC)
    }

    @Test func theNightsSkinTemperatureIsTakenWhileAsleep() throws {
        let (hr, rr) = SyntheticNight.streams()
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr,
                                    skinTemp: Self.skin(asleepC: 33.4, awakeC: 31.0),
                                    profile: profile, history: [], tzOffsetSeconds: 0)
        let skin = try #require(night.skinTempC)
        #expect(abs(skin - 33.4) < 0.25)
        #expect(night.skinTempDevC == nil)   // no normal yet
    }

    @Test func itIsComparedWithYourNormalOnceThereIsOne() throws {
        let (hr, rr) = SyntheticNight.streams()
        let history = (0..<6).map { Self.earlierNight($0, skinC: $0.isMultiple(of: 2) ? 33.05 : 32.95) }
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr,
                                    skinTemp: Self.skin(asleepC: 33.4, awakeC: 31.0),
                                    profile: profile, history: history, tzOffsetSeconds: 0)
        let deviation = try #require(night.skinTempDevC)
        #expect(abs(deviation - 0.4) < 0.25)
    }

    @Test func aNightWithoutSkinTemperatureScoresAsBefore() {
        let (hr, rr) = SyntheticNight.streams()
        let night = DayScorer.score(day: SyntheticNight.day, hr: hr, rr: rr, profile: profile,
                                    history: [], tzOffsetSeconds: 0)
        #expect(night.skinTempC == nil)
        #expect(night.skinTempDevC == nil)
        #expect((night.totalSleepMin ?? 0) > 300)
    }

    @Test func aStoredNightKeepsItsSkinTemperature() {
        let daily = DailyMetric(day: "2026-11-22", totalSleepMin: 400, efficiency: 0.9, deepMin: nil, remMin: nil,
                                lightMin: nil, disturbances: nil, restingHr: 52, avgHrv: 70, recovery: 60,
                                strain: nil, exerciseCount: nil, skinTempDevC: 0.3, skinTempC: 33.3)
        let night = DayScorer.summary(of: daily, session: nil)
        #expect(night.skinTempC == 33.3)
        #expect(night.skinTempDevC == 0.3)
    }
}
