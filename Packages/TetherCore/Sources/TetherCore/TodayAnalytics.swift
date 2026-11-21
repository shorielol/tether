import Foundation
import StrandAnalytics
@preconcurrency import WhoopProtocol

/// Everything Today can honestly show from the heart rate and R-R stored so far today.
/// Each number is nil (not zero) when there isn't enough data behind it.
public struct TodaySnapshot: Sendable, Equatable {
    public enum RestingSource: Sendable, Equatable { case profile, lowestFiveMinutes, defaultValue }

    /// One minute's average heart rate. `segment` changes after a gap, so charts break the line there.
    public struct MinutePoint: Sendable, Equatable, Identifiable {
        public let ts: Int
        public let bpm: Double
        public let segment: Int
        public var id: Int { ts }
    }

    public struct StressHour: Sendable, Equatable, Identifiable {
        public let hour: Int
        /// 0–3 stress proxy, nil when the hour had too little signal.
        public let level: Double?
        /// The hour was left unscored because it looked like exercise.
        public let wasActive: Bool
        public var id: Int { hour }
    }

    public let window: ClosedRange<Int>
    public let maxHR: Int
    public let minuteSeries: [MinutePoint]
    public let minBPM: Int?
    public let avgBPM: Int?
    public let maxBPM: Int?
    /// Minutes in zones 1–5.
    public let zoneMinutes: [Int]
    public let restingHR: Int
    public let restingSource: RestingSource
    /// 0–100, nil until the scorer has enough data.
    public let effort: Double?
    public let caloriesTotal: Int?
    public let caloriesActive: Int?
    /// RMSSD over the last five minutes of beats.
    public let hrvNow: Double?
    public let stressHours: [StressHour]
    public let coverage: CoverageReport?

    public var isEmpty: Bool { minuteSeries.isEmpty }
}

public enum TodayAnalytics {
    public static let hrvWindowSeconds = 300
    public static let restingWindowMinutes = 5
    public static let defaultRestingHR = 60
    /// A pause longer than this between minutes breaks the chart line.
    public static let chartGapSeconds = 120
    private static let fallbackAge = 30.0

    public static func compute(hr: [HRSample], rr: [RRInterval], profile: UserProfile?,
                               window: ClosedRange<Int>, now: Int,
                               tzOffsetSeconds: Int = TimeZone.current.secondsFromGMT()) -> TodaySnapshot {
        let samples = hr.filter { window.contains($0.ts) }.sorted { $0.ts < $1.ts }
        let beats = rr.filter { window.contains($0.ts) }
        let maxHR = profile?.maxHR ?? Int(HRZones.tanakaMaxHR(age: fallbackAge).rounded())
        let minutes = minuteSeries(samples)
        let (resting, source) = restingHR(profile: profile, minutes: minutes)
        guard !samples.isEmpty else {
            return TodaySnapshot(window: window, maxHR: maxHR, minuteSeries: [], minBPM: nil, avgBPM: nil,
                                 maxBPM: nil, zoneMinutes: Array(repeating: 0, count: 5), restingHR: resting,
                                 restingSource: source, effort: nil, caloriesTotal: nil, caloriesActive: nil,
                                 hrvNow: nil, stressHours: [], coverage: nil)
        }
        let bpms = samples.map(\.bpm)
        let zones = HRZones.timeInZone(samples, zoneSet: HRZones.zones(maxHR: Double(maxHR)))
        let energy = profile.map { person in
            Calories.estimateDayEnergy(samples,
                                       profile: .init(weightKg: person.weightKg, heightCm: Double(person.heightCm),
                                                      age: Double(person.age), sex: person.sex.rawValue),
                                       hrmax: Double(maxHR), restingHR: Double(resting))
        }
        let hrvNow = HRVAnalyzer.analyze(beats, windowStart: now - hrvWindowSeconds + 1, windowEnd: now).rmssd
        let stress = DaytimeStress.analyze(hr: samples, rr: beats, tzOffsetSeconds: tzOffsetSeconds).hours.map {
            TodaySnapshot.StressHour(hour: $0.hour, level: $0.level, wasActive: $0.maskedForActivity)
        }
        let coverageEnd = max(window.lowerBound, min(now, window.upperBound))
        return TodaySnapshot(
            window: window, maxHR: maxHR, minuteSeries: minutes,
            minBPM: bpms.min(), avgBPM: Int((Double(bpms.reduce(0, +)) / Double(bpms.count)).rounded()),
            maxBPM: bpms.max(), zoneMinutes: zones.seconds.map { Int(($0 / 60).rounded()) },
            restingHR: resting, restingSource: source,
            effort: StrainScorer.strain(samples, maxHR: Double(maxHR), restingHR: Double(resting),
                                        sex: profile?.sex.rawValue ?? "male"),
            caloriesTotal: energy.map { Int($0.totalKcal.rounded()) },
            caloriesActive: energy.map { Int($0.activeKcal.rounded()) },
            hrvNow: hrvNow, stressHours: stress,
            coverage: Coverage.compute(timestamps: samples.map(\.ts), window: window.lowerBound...coverageEnd))
    }

    /// Zone 1–5 for a heart rate, 0 when below zone 1.
    public static func zone(bpm: Int, maxHR: Int) -> Int {
        let set = HRZones.zones(maxHR: Double(maxHR))
        guard Double(bpm) >= set.zones[0].lower else { return 0 }
        return set.zoneNumber(forBPM: Double(bpm))
    }

    static func minuteSeries(_ samples: [HRSample]) -> [TodaySnapshot.MinutePoint] {
        var buckets: [(ts: Int, sum: Int, count: Int)] = []
        for sample in samples {
            let minute = sample.ts - sample.ts % 60
            if let last = buckets.last, last.ts == minute {
                buckets[buckets.count - 1] = (minute, last.sum + sample.bpm, last.count + 1)
            } else {
                buckets.append((minute, sample.bpm, 1))
            }
        }
        var segment = 0
        var previous: Int?
        return buckets.map { bucket in
            if let previous, bucket.ts - previous > chartGapSeconds { segment += 1 }
            previous = bucket.ts
            return TodaySnapshot.MinutePoint(ts: bucket.ts, bpm: Double(bucket.sum) / Double(bucket.count),
                                             segment: segment)
        }
    }

    /// Profile value, else the lowest 5-minute average so far, else the scorer's default.
    static func restingHR(profile: UserProfile?,
                          minutes: [TodaySnapshot.MinutePoint]) -> (Int, TodaySnapshot.RestingSource) {
        if let resting = profile?.restingHR { return (resting, .profile) }
        var lowest: Double?
        if minutes.count >= restingWindowMinutes {
            for end in (restingWindowMinutes - 1)..<minutes.count {
                let run = minutes[(end - restingWindowMinutes + 1)...end]
                guard run.first?.segment == run.last?.segment else { continue }
                let mean = run.map(\.bpm).reduce(0, +) / Double(restingWindowMinutes)
                lowest = min(lowest ?? mean, mean)
            }
        }
        if let lowest { return (Int(lowest.rounded()), .lowestFiveMinutes) }
        return (defaultRestingHR, .defaultValue)
    }
}
