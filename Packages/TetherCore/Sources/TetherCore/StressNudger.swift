import Foundation
import StrandAnalytics

/// Stress alerts from live R-R, using NOOP's `StressOnsetDetector`: an HRV dip below 60% of your running
/// level, held for a minute, while heart rate looks like rest (so a workout doesn't count). At most once
/// every 15 minutes, never in quiet hours (22:00–07:00). Off unless you turn it on.
public struct StressNudger: Sendable {
    public var enabled: Bool
    private var state = StressOnsetDetector.State.initial
    private var buffer: [Int] = []
    private var lastCheck = 0

    /// Beats kept for the detector, a little more than its fast window.
    static let bufferBeats = 240
    /// How often to ask the detector, in seconds.
    static let checkSeconds = 10
    static let quietStart = 22 * 60
    static let quietEnd = 7 * 60

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    /// Adds live beats; true when this is the moment to suggest a breather.
    public mutating func add(rr: [Int], heartRate: Int?, at ts: Int, tzOffsetSeconds: Int) -> Bool {
        buffer.append(contentsOf: rr)
        if buffer.count > Self.bufferBeats { buffer.removeFirst(buffer.count - Self.bufferBeats) }
        guard ts - lastCheck >= Self.checkSeconds else { return false }
        lastCheck = ts
        let config = StressOnsetDetector.Config(enabled: enabled, autoNudge: enabled, quietHoursEnabled: true,
                                                quietStartMinutes: Self.quietStart, quietEndMinutes: Self.quietEnd)
        let decision = StressOnsetDetector.evaluate(rrBuffer: buffer, currentHR: heartRate.map(Double.init),
                                                    recentMotionG: nil, sessionActive: false, state: state,
                                                    config: config, nowSec: ts, tzOffsetSec: tzOffsetSeconds)
        state = decision.nextState
        return decision.shouldNudge
    }
}
