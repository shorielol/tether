import Foundation
import Testing
@testable import TetherCore

/// Stress alerts: a sustained HRV dip at rest, from live R-R, at most once every 15 minutes.
@Suite("Stress alerts")
struct StressNudgerTests {
    /// One beat around 860 ms, alternating up and down by `wobble` (beat-to-beat variation, i.e. HRV).
    private func beat(at ts: Int, wobble: Int) -> [Int] {
        [860 + (ts.isMultiple(of: 2) ? wobble : -wobble)]
    }

    /// Feeds `minutes` of beats, one batch per second.
    private func run(_ nudger: inout StressNudger, from start: Int, minutes: Int, wobble: Int) -> [Int] {
        var fired: [Int] = []
        for second in 0..<(minutes * 60) {
            let ts = start + second
            if nudger.add(rr: beat(at: ts, wobble: wobble), heartRate: 70, at: ts, tzOffsetSeconds: 0) { fired.append(ts) }
        }
        return fired
    }

    private let noon = 1_700_006_400 + 12 * 3_600 - (1_700_006_400 % 86_400)

    @Test func aSustainedDipAtRestFiresOnce() {
        var nudger = StressNudger(enabled: true)
        #expect(run(&nudger, from: noon, minutes: 20, wobble: 40).isEmpty, "calm: steady high HRV")
        let fired = run(&nudger, from: noon + 20 * 60, minutes: 6, wobble: 6)
        #expect(fired.count == 1)
    }

    @Test func itStaysQuietWhenTurnedOff() {
        var nudger = StressNudger(enabled: false)
        _ = run(&nudger, from: noon, minutes: 20, wobble: 40)
        #expect(run(&nudger, from: noon + 20 * 60, minutes: 6, wobble: 6).isEmpty)
    }

    @Test func itNeverFiresAtNight() {
        var nudger = StressNudger(enabled: true)
        let night = noon + 11 * 3_600   // 23:00
        _ = run(&nudger, from: night, minutes: 20, wobble: 40)
        #expect(run(&nudger, from: night + 20 * 60, minutes: 6, wobble: 6).isEmpty)
    }
}
