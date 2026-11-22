import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// The smart window's cue: heart rate lifting off the night's low, the way it does as you surface.
@Suite("Smart wake")
struct SmartWakeTests {
    private let now = 1_000_000

    private func hr(baseline: Int, lastThreeMinutes: Int, seconds: Int = 3_600) -> [HRSample] {
        (now - seconds + 1...now).map { HRSample(ts: $0, bpm: $0 > now - 180 ? lastThreeMinutes : baseline) }
    }

    @Test func aSteadyNightIsNotSurfacing() {
        #expect(!SmartWake.surfacing(hr(baseline: 54, lastThreeMinutes: 56), now: now))
    }

    @Test func heartRateLiftingOffTheLowIsSurfacing() {
        #expect(SmartWake.surfacing(hr(baseline: 54, lastThreeMinutes: 64), now: now))
    }

    @MainActor
    @Test func theCollectorMovesTheAlarmWhenLiveHeartRateLifts() {
        final class Clock { var now = 0 }
        let clock = Clock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let evening = Int(calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_795_305_600))!
            .timeIntervalSince1970)
        clock.now = evening
        let source = FakeDataLinkSource()
        let defaults = UserDefaults(suiteName: "smart-\(UUID().uuidString)")!
        let pairing = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { evening - 3_600 })
        pairing.pair(with: UUID())
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { clock.now })
        source.send(.dataLink(.ready))
        collector.historyWentQuiet()
        collector.alarm.set(hour: 7, minute: 0)
        collector.alarm.setWindow(30)
        source.send(.strapFrame(puffinCommandFrame(cmd: StrapCommandPolicy.setAlarm, seq: 40, payload: [1, 1], type: 38)))
        guard case .set(let wake) = collector.alarm.status else { Issue.record("alarm not set"); return }
        source.commands.removeAll()
        let start = wake - 80 * 60
        for ts in start..<(wake - 20 * 60) {
            clock.now = ts
            let lifted = ts >= wake - 20 * 60 - 180
            source.send(.measurement(HeartRateMeasurement(bpm: lifted ? 66 : 54, rrMs: [], contact: .detected), at: ts))
        }
        #expect(source.commands.map { $0[10] }.contains(StrapCommandPolicy.setAlarm))
        guard case .sending(let early) = collector.alarm.status else { Issue.record("no early alarm sent"); return }
        #expect(early < wake && early >= wake - 30 * 60)
    }

    @Test func tooLittleHeartRateDecidesNothing() {
        #expect(!SmartWake.surfacing(hr(baseline: 54, lastThreeMinutes: 70, seconds: 400), now: now))
    }
}
