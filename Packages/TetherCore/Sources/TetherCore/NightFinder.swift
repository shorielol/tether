import Foundation
@preconcurrency import WhoopProtocol

/// Finds the whole night in heart rate alone, so a night isn't cut into fragments.
///
/// NOOP's heart-rate-only finder counts a minute as sleep when it sits within 5% of the window's
/// lowest readings. That works for a night spent near the floor, but early sleep often runs 10–20%
/// above it, so a real night came back as three pieces and only the longest one was counted
/// (2 h 23 m of a 6½ h night). This looks at 10-minute medians instead, counts anything within
/// 20% of the night's own low as asleep, and bridges wakes of half an hour or less. The span it
/// returns is then staged as usual, so time awake inside it still counts as awake.
public enum NightFinder {
    static let epochSeconds = 600
    /// An epoch needs at least two minutes of readings to be judged at all.
    static let minSamplesPerEpoch = 120
    static let anchorPercentile = 0.10
    static let bandMultiplier = 1.20
    /// The night has to stand out from the day: the busiest tenth of the window sits at least this far
    /// above the sleep band. A day spent awake has no such contrast, and gets no night.
    static let contrastMultiplier = 1.15
    /// Up to three epochs (30 minutes) awake or without readings stay inside the night.
    static let bridgeEpochs = 3
    static let minNightSeconds = 2 * 3_600

    struct Epoch {
        let index: Int
        let median: Double
        let first: Int
        let last: Int
    }

    /// The longest night that ends on the day starting at `dayStart`, or nil.
    public static func night(hr: [HRSample], dayStart: Int) -> ClosedRange<Int>? {
        let epochs = epochs(hr)
        guard epochs.count >= 12 else { return nil }
        let values = epochs.map(\.median).sorted()
        let band = percentile(values, anchorPercentile) * bandMultiplier
        guard percentile(values, 0.90) >= band * contrastMultiplier else { return nil }
        return blocks(epochs, band: band)
            .filter { $0.upperBound - $0.lowerBound >= minNightSeconds }
            .filter { $0.upperBound >= dayStart && $0.upperBound < dayStart + 86_400 }
            .max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }
    }

    static func epochs(_ hr: [HRSample]) -> [Epoch] {
        Dictionary(grouping: hr) { $0.ts / epochSeconds }
            .compactMap { index, samples -> Epoch? in
                guard samples.count >= minSamplesPerEpoch else { return nil }
                let sorted = samples.map { Double($0.bpm) }.sorted()
                let times = samples.map(\.ts)
                return Epoch(index: index, median: sorted[sorted.count / 2],
                             first: times.min() ?? 0, last: times.max() ?? 0)
            }
            .sorted { $0.index < $1.index }
    }

    /// Runs of sleepy epochs, joined across short wakes and short gaps in the data.
    static func blocks(_ epochs: [Epoch], band: Double) -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        var open: (start: Epoch, last: Epoch)?
        for epoch in epochs where epoch.median <= band {
            if let current = open, epoch.index - current.last.index - 1 <= bridgeEpochs {
                open = (current.start, epoch)
            } else {
                if let current = open { spans.append(current.start.first...current.last.last) }
                open = (epoch, epoch)
            }
        }
        if let current = open { spans.append(current.start.first...current.last.last) }
        return spans
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }
}
