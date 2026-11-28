import Foundation

/// Your usual range for a measure: the middle half of your earlier nights (25th to 75th percentile).
/// None until there are enough nights to say what's usual.
public struct NormalBand: Sendable, Equatable {
    public let low: Double
    public let high: Double

    /// The same three earlier nights the Recovery normal needs.
    public static let minNights = RecoveryDetail.minNightsForNormal

    /// `minWidth` keeps a band visible when every night read alike, widened evenly around the middle.
    public init?(past: [Double], minNights: Int = NormalBand.minNights, minWidth: Double = 0) {
        guard past.count >= minNights, !past.isEmpty else { return nil }
        let sorted = past.sorted()
        var low = Self.percentile(sorted, 0.25)
        var high = Self.percentile(sorted, 0.75)
        if high - low < minWidth {
            let middle = Self.percentile(sorted, 0.5)
            low = middle - minWidth / 2
            high = middle + minWidth / 2
        }
        self.low = low
        self.high = high
    }

    public init(low: Double, high: Double) {
        self.low = min(low, high)
        self.high = max(low, high)
    }

    public func contains(_ value: Double) -> Bool { value >= low && value <= high }

    /// Linear interpolation between neighbouring nights.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let below = Int(position.rounded(.down))
        let above = min(below + 1, sorted.count - 1)
        let fraction = position - Double(below)
        return sorted[below] + (sorted[above] - sorted[below]) * fraction
    }
}

/// Where a value and its normal band sit on a bar, as fractions (0–1) of the bar's width.
public struct RangePlacement: Sendable, Equatable {
    public let value: Double
    public let band: ClosedRange<Double>?
    /// Whether the value is inside your normal, or nil when there is no normal yet.
    public let isInsideBand: Bool?

    public init(value: Double, band: NormalBand?, domain: ClosedRange<Double>) {
        let span = domain.upperBound - domain.lowerBound
        func place(_ v: Double) -> Double {
            guard span > 0 else { return 0.5 }
            return min(1, max(0, (v - domain.lowerBound) / span))
        }
        self.value = place(value)
        self.band = band.map { place($0.low)...place($0.high) }
        self.isInsideBand = band?.contains(value)
    }

    /// A bar wide enough to show the band with room either side, and the value even when it's far out.
    public static func domain(around band: NormalBand, value: Double) -> ClosedRange<Double> {
        let pad = max(band.high - band.low, abs(band.high) * 0.05, 1) * 1.5
        return min(band.low - pad, value)...max(band.high + pad, value)
    }
}

/// The line under the Recovery card: which measure, if any, sits outside your normal.
public enum RecoveryNote {
    public static func text(_ measures: [RecoveryDetail.Measure]) -> String? {
        guard !measures.isEmpty else { return nil }
        let banded = measures.filter { $0.band != nil }
        guard !banded.isEmpty else { return "Your normal shows after \(NormalBand.minNights) nights." }
        guard let off = banded.first(where: { !($0.band?.contains($0.value) ?? true) }), let band = off.band else {
            return "Everything is in your normal range."
        }
        let side = off.value < band.low ? "below" : "above"
        let worse = off.higherIsBetter.map { $0 != (off.value > band.high) } ?? false
        return worse ? "\(off.name) is \(side) your normal, which pulls Charge down." : "\(off.name) is \(side) your normal."
    }
}

/// The one sentence at the top of Today: what Charge and last night mean for the day.
public enum DayLine {
    /// Without your own normal yet, a night under seven hours counts as short.
    public static let shortNightMinutes = 420.0
    /// Effort at or above this, on a red day, means you've already pushed.
    public static let hardEffort = 40.0

    public static func sentence(zone: ChargeZone?, nightsUntilCharge: Int, sleptMinutes: Double?,
                                sleepBand: NormalBand?, effort: Double?) -> String {
        let short = sleptMinutes.map { isShort($0, band: sleepBand) } ?? false
        guard let zone else { return learning(nightsUntilCharge: nightsUntilCharge, sleptMinutes: sleptMinutes) }
        switch zone {
        case .red:
            if let effort, effort >= hardEffort {
                return "Charge is red and you've already pushed today. Ease off and get to bed early."
            }
            return "Charge is red. Rest today and get to bed early."
        case .yellow:
            return short ? "A short night and a yellow Charge. Keep today steady, and an early night helps most."
                         : "Charge is yellow. Keep today steady."
        case .green:
            return short ? "Charge is green, even after a short night. A good day to push."
                         : "Charge is green. A good day to push."
        }
    }

    static func isShort(_ minutes: Double, band: NormalBand?) -> Bool {
        if let band { return minutes < band.low }
        return minutes < shortNightMinutes
    }

    private static func learning(nightsUntilCharge: Int, sleptMinutes: Double?) -> String {
        guard let sleptMinutes else {
            if nightsUntilCharge == 0 { return "No sleep found last night, so there's no Charge today." }
            return "Wear the strap tonight. Your first night shows here in the morning."
        }
        let slept = "You slept \(duration(sleptMinutes))."
        switch nightsUntilCharge {
        case 0: return slept
        case 1: return "\(slept) Charge starts after one more night."
        case let n: return "\(slept) Charge starts in \(n) more nights."
        }
    }

    /// "6h 36m", or "45m" under an hour.
    public static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let rest = total % 60
        return hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
    }
}
