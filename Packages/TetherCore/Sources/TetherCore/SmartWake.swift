import Foundation
@preconcurrency import WhoopProtocol

/// The smart wake window's cue. Inside the window, a heart rate lifting clearly off the night's low is
/// the sign of surfacing from deep sleep, the easiest moment to wake. If it never comes, the alarm goes
/// at the end of the window as usual.
public enum SmartWake {
    /// Window lengths offered, in minutes. 0 is off.
    public static let windowChoices = [0, 15, 30]
    /// How far above the night's low the last few minutes must sit.
    static let riseBpm = 8.0
    static let recentSeconds = 180
    static let lookbackSeconds = 3_600
    static let lowWindowSeconds = 300
    /// Enough readings to trust: two minutes of the last three, a quarter hour of the hour before.
    static let recentMinimum = 120
    static let lookbackMinimum = 900

    public static func surfacing(_ hr: [HRSample], now: Int) -> Bool {
        let recent = hr.filter { $0.ts > now - recentSeconds && $0.ts <= now }
        let earlier = hr.filter { $0.ts > now - lookbackSeconds && $0.ts <= now - recentSeconds }.sorted { $0.ts < $1.ts }
        guard recent.count >= recentMinimum, earlier.count >= lookbackMinimum, let low = lowest(earlier) else { return false }
        return mean(recent) - low >= riseBpm
    }

    /// Lowest five-minute average, stepping a minute at a time.
    private static func lowest(_ samples: [HRSample]) -> Double? {
        guard let first = samples.first?.ts, let last = samples.last?.ts else { return nil }
        var low: Double?
        var start = first
        while start + lowWindowSeconds <= last + 1 {
            let inside = samples.filter { $0.ts >= start && $0.ts < start + lowWindowSeconds }
            if inside.count >= lowWindowSeconds / 2 {
                let value = mean(inside)
                low = min(low ?? value, value)
            }
            start += 60
        }
        return low
    }

    private static func mean(_ samples: [HRSample]) -> Double {
        Double(samples.reduce(0) { $0 + $1.bpm }) / Double(max(samples.count, 1))
    }
}
