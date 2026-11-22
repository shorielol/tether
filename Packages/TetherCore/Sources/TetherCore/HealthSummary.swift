import Foundation

/// One vital on the Health tab: last night's value, your normal band and the last week of nights.
/// A vital the strap didn't give last night keeps its row with no value, so the screen can say so.
public struct HealthVital: Sendable, Equatable, Identifiable {
    public struct Night: Sendable, Equatable, Identifiable {
        public let day: String
        public let value: Double?
        public var id: String { day }
    }

    public let name: String
    public let unit: String
    public let decimals: Int
    public let value: Double?
    public let band: NormalBand?
    /// Up to a week, oldest first, ending with last night.
    public let recent: [Night]
    /// Whether a higher value is the better direction, or nil when neither is.
    public let higherIsBetter: Bool?
    public var id: String { name }

    public static let recentNights = 7

    public var isOutsideNormal: Bool {
        guard let value, let band else { return false }
        return !band.contains(value)
    }

    /// Outside your normal on the side that counts against you.
    public var isWorse: Bool {
        guard isOutsideNormal, let value, let band, let higherIsBetter else { return false }
        return higherIsBetter ? value < band.low : value > band.high
    }

    public static func compute(latest: NightSummary?, history: [NightSummary]) -> [HealthVital] {
        guard let latest else { return [] }
        let earlier = history.filter { $0.day < latest.day }.sorted { $0.day < $1.day }
        let week = (earlier + [latest]).suffix(recentNights)
        func vital(_ name: String, _ unit: String, decimals: Int = 0, higherIsBetter: Bool?,
                   _ read: (NightSummary) -> Double?) -> HealthVital {
            HealthVital(name: name, unit: unit, decimals: decimals, value: read(latest),
                        band: NormalBand(past: earlier.compactMap(read)),
                        recent: week.map { Night(day: $0.day, value: read($0)) }, higherIsBetter: higherIsBetter)
        }
        return [
            vital("HRV", "ms", higherIsBetter: true) { $0.hrv },
            vital("Resting HR", "bpm", higherIsBetter: false) { $0.restingHR.map(Double.init) },
            vital("Breathing", "/min", decimals: 1, higherIsBetter: nil) { $0.respRate },
        ]
    }

    /// The line under the Health title: how many measured vitals sit inside your normal.
    public static func summary(_ vitals: [HealthVital]) -> String {
        let judged = vitals.filter { $0.value != nil && $0.band != nil }
        guard !judged.isEmpty else { return "Your normal shows after \(NormalBand.minNights) nights" }
        return "\(judged.filter { !$0.isOutsideNormal }.count) of \(judged.count) in your normal"
    }
}
