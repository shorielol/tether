import Foundation
import StrandAnalytics

/// One measure over a stretch of days: the values, their average, and the change from the first half
/// of the stretch to the second.
public struct TrendSeries: Sendable, Equatable, Identifiable {
    public struct Point: Sendable, Equatable, Identifiable {
        public let day: String
        public let value: Double
        public var id: String { day }
    }

    public let name: String
    public let unit: String
    public let decimals: Int
    public let points: [Point]
    public let average: Double?
    /// Second-half average minus first-half average; nil with fewer than 4 points.
    public let change: Double?
    let higherIsBetter: Bool?
    public var id: String { name }

    /// True when the change went the good way, false the other way, nil when neither or too small.
    public var isBetter: Bool? {
        guard let change, let higherIsBetter, abs(change) > 0 else { return nil }
        return (change > 0) == higherIsBetter
    }
}

public enum Trends {
    public static let ranges = [7, 30, 90]
    public static var longestRange: Int { ranges.max() ?? 90 }

    private struct Measure: Sendable {
        let name: String
        let unit: String
        let decimals: Int
        let higherIsBetter: Bool?
        let read: @Sendable (NightSummary) -> Double?
    }

    private static let measures: [Measure] = [
        Measure(name: "Charge", unit: "%", decimals: 0, higherIsBetter: true) { $0.charge },
        Measure(name: "Asleep", unit: "h", decimals: 1, higherIsBetter: true) { $0.totalSleepMin.map { $0 / 60 } },
        Measure(name: "HRV", unit: "ms", decimals: 0, higherIsBetter: true) { $0.hrv },
        Measure(name: "Resting HR", unit: "bpm", decimals: 0, higherIsBetter: false) { $0.restingHR.map(Double.init) },
        Measure(name: "Effort", unit: "", decimals: 1, higherIsBetter: nil) { $0.effort },
        Measure(name: "Breathing", unit: "/min", decimals: 1, higherIsBetter: nil) { $0.respRate },
        Measure(name: "Skin temp", unit: "°C", decimals: 1, higherIsBetter: nil) { $0.skinTempC },
    ]

    /// Every measure over the `days` ending `today` ("yyyy-MM-dd"). Missing nights are left out.
    public static func compute(nights: [NightSummary], days: Int, today: String) -> [TrendSeries] {
        let first = WeeklyDigestEngine.addDays(today, -(days - 1))
        let inRange = nights.filter { $0.day >= first && $0.day <= today }.sorted { $0.day < $1.day }
        return measures.map { measure in
            let points = inRange.compactMap { night in measure.read(night).map { TrendSeries.Point(day: night.day, value: $0) } }
            let values = points.map(\.value)
            let half = values.count / 2
            let change = values.count >= 4
                ? mean(Array(values.suffix(values.count - half))) - mean(Array(values.prefix(half))) : nil
            return TrendSeries(name: measure.name, unit: measure.unit, decimals: measure.decimals, points: points,
                               average: values.isEmpty ? nil : mean(values), change: change,
                               higherIsBetter: measure.higherIsBetter)
        }
    }

    /// This week against last, with NOOP's weekly digest.
    public static func weekly(nights: [NightSummary], today: String) -> WeeklyDigest {
        func byDay(_ read: (NightSummary) -> Double?) -> [String: Double] {
            Dictionary(nights.compactMap { night in read(night).map { (night.day, $0) } }) { first, _ in first }
        }
        return WeeklyDigestEngine.build(byMetric: [
            .charge: byDay(\.charge), .effort: byDay(\.effort), .rest: byDay(\.rest),
            .rhr: byDay { $0.restingHR.map(Double.init) }, .hrv: byDay(\.hrv),
        ], anchorDay: today)
    }

    private static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }
}
