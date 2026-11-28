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
///
/// Where the strap's motion covers an epoch, stillness decides instead of heart rate. Heart rate alone
/// failed both ways on real nights: after a hard evening it stayed in the 90s for hours of still sleep
/// (no night found), and a calm late morning in the 60s kept a night going for two hours after the
/// wrist started moving. A still epoch counts as asleep unless its heart rate is at exercise level.
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
    /// A wrist that shifts by more than this between two readings a second apart has moved.
    static let movedG = 0.02
    /// An epoch is still when the wrist moved in at most this share of its seconds. Real sleep on the
    /// strap ran 0–11%; awake, even sitting, ran 27% and up.
    static let stillShare = 0.15
    /// A steady wrist angle with more than this average acceleration (g) is busy, not still: cycling
    /// or rowing hold the wrist's angle while it shakes. Real sleep on the strap averaged 0.006–0.044.
    static let stillAccel = 0.05
    /// Still but with a heart rate this far above the sleep band is effort, not sleep.
    static let stillHRCeiling = 1.6

    struct Epoch {
        let index: Int
        let median: Double
        let first: Int
        let last: Int
    }

    /// The longest night that ends on the day starting at `dayStart`, or nil. Motion, where there is
    /// any, decides which epochs are asleep; heart rate decides the rest.
    public static func night(hr: [HRSample], gravity: [GravitySample] = [], dayStart: Int) -> ClosedRange<Int>? {
        let epochs = epochs(hr)
        guard epochs.count >= 12 else { return nil }
        let values = epochs.map(\.median).sorted()
        let band = percentile(values, anchorPercentile) * bandMultiplier
        guard percentile(values, 0.90) >= band * contrastMultiplier else { return nil }
        let still = stillness(gravity)
        let asleep = epochs.filter { epoch in
            if let isStill = still[epoch.index] { return isStill && epoch.median <= band * stillHRCeiling }
            return epoch.median <= band
        }
        return blocks(asleep)
            .filter { $0.upperBound - $0.lowerBound >= minNightSeconds }
            .filter { $0.upperBound >= dayStart && $0.upperBound < dayStart + 86_400 }
            .max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }
    }

    /// Whether each 10-minute epoch with enough motion readings was still. Epochs without them are absent.
    static func stillness(_ gravity: [GravitySample]) -> [Int: Bool] {
        Dictionary(grouping: gravity) { $0.ts / epochSeconds }
            .compactMapValues { samples -> Bool? in
                guard samples.count >= minSamplesPerEpoch else { return nil }
                let sorted = samples.sorted { $0.ts < $1.ts }
                var pairs = 0, moved = 0
                for (a, b) in zip(sorted, sorted.dropFirst()) where b.ts - a.ts <= 2 {
                    pairs += 1
                    let shift = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z)).squareRoot()
                    if shift > movedG { moved += 1 }
                }
                guard pairs > 0 else { return nil }
                let accel = sorted.compactMap(\.dynAccel)
                let busy = !accel.isEmpty && accel.reduce(0, +) / Double(accel.count) > stillAccel
                return !busy && Double(moved) / Double(pairs) <= stillShare
            }
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

    /// Runs of asleep epochs, joined across short wakes and short gaps in the data.
    static func blocks(_ epochs: [Epoch]) -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        var open: (start: Epoch, last: Epoch)?
        for epoch in epochs {
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
