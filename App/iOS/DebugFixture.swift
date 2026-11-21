#if DEBUG
import Foundation
import TetherCore
@preconcurrency import WhoopProtocol

/// Simulator-only sample day for screenshots, switched on with `-tether.fixture day`.
/// Compiled out of Release (the build on the phone) and never written to the store.
enum DebugFixture {
    static var isOn: Bool { UserDefaults.standard.string(forKey: "tether.fixture") == "day" }

    static var liveHeartRate: Int? { isOn ? 74 : nil }

    static func today(profile: UserProfile?) -> TodaySnapshot? {
        guard isOn else { return nil }
        let midnight = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        let end = midnight + 21 * 3_600
        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        for ts in stride(from: midnight, through: end, by: 1) {
            let hour = Double(ts - midnight) / 3_600
            guard !(13.0..<13.4).contains(hour) else { continue }   // a dropout, to show a gap
            let bpm = Int(base(hour) + 3 * sin(Double(ts) / 97) + 2 * sin(Double(ts) / 13))
            hr.append(HRSample(ts: ts, bpm: bpm))
            let beat = 60_000 / max(bpm, 40)
            rr.append(RRInterval(ts: ts, rrMs: beat + (ts.isMultiple(of: 2) ? 18 : -18), ord: 0, seq: 0))
        }
        return TodayAnalytics.compute(hr: hr, rr: rr, profile: profile, window: midnight...end, now: end)
    }

    private static func base(_ hour: Double) -> Double {
        switch hour {
        case ..<7: 52
        case ..<9: 78
        case 18..<18.7: 156
        case 18.7..<19: 120
        default: 74
        }
    }
}
#endif
