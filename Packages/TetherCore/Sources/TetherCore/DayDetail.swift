import Foundation
import StrandAnalytics
@preconcurrency import WhoopProtocol

/// The shared 0–3 stress scale read as three words. The scale is relative to your own day: an
/// ordinary hour for you scores about 1.5, so the middle band is "Usual", Calm is below it and High
/// starts where DaytimeStress's high band does. Same cut-offs as NOOP's Stress screen.
public enum StressBand: String, Sendable, Equatable, CaseIterable {
    case calm, usual, high

    public init(level: Double) {
        if level >= DaytimeStress.highBandFloor {
            self = .high
        } else if level >= 1 {
            self = .usual
        } else {
            self = .calm
        }
    }

    public var name: String {
        switch self {
        case .calm: "Calm"
        case .usual: "Usual"
        case .high: "High"
        }
    }
}

/// Today's stress in depth: every waking hour with its heart rate and HRV, a half-hourly line, and
/// how long you spent in each band. Read from heart rate and R-R against the rest of your own day.
public struct StressDetail: Sendable, Equatable {
    public struct Point: Sendable, Equatable, Identifiable {
        public let ts: Int
        public let level: Double
        public var band: StressBand { StressBand(level: level) }
        public var id: Int { ts }
    }

    public struct Hour: Sendable, Equatable, Identifiable {
        public let hour: Int
        public let startTs: Int
        /// 0–3, nil when the hour had too little signal or you were moving.
        public let level: Double?
        public let meanHR: Int?
        /// RMSSD over the hour's clean beats, in ms.
        public let hrv: Int?
        /// Left unscored because heart rate looked like movement rather than stress.
        public let wasMoving: Bool
        /// Minutes in the hour that have heart rate.
        public let recordedMinutes: Int
        public var band: StressBand? { level.map(StressBand.init(level:)) }
        public var id: Int { hour }
    }

    public let timeline: [Point]
    public let hours: [Hour]
    public let calmMinutes: Int
    public let usualMinutes: Int
    public let highMinutes: Int
    /// Mean level across the scored hours.
    public let dayLevel: Double?
    public let peak: Hour?
    /// How many of the latest scored hours in a row were high, when that run is long enough to flag.
    public let sustainedHighHours: Int
    public let movingHours: Int

    public var dayBand: StressBand? { dayLevel.map(StressBand.init(level:)) }

    public static let empty = StressDetail(timeline: [], hours: [], calmMinutes: 0, usualMinutes: 0,
                                           highMinutes: 0, dayLevel: nil, peak: nil, sustainedHighHours: 0,
                                           movingHours: 0)

    public static func compute(hr: [HRSample], rr: [RRInterval], tzOffsetSeconds: Int) -> StressDetail {
        guard !hr.isEmpty else { return .empty }
        let result = DaytimeStress.analyze(hr: hr, rr: rr, tzOffsetSeconds: tzOffsetSeconds, includeTimeline: true)
        let minutesByHour = recordedMinutes(hr)
        let hours = result.hours.map { point in
            Hour(hour: point.hour, startTs: point.startTs, level: point.level,
                 meanHR: point.meanHR.map { Int($0.rounded()) }, hrv: point.rmssd.map { Int($0.rounded()) },
                 wasMoving: point.maskedForActivity,
                 recordedMinutes: minutesByHour[point.startTs / DaytimeStress.bucketSeconds] ?? 0)
        }
        func minutes(in band: StressBand) -> Int {
            hours.filter { $0.band == band }.reduce(0) { $0 + $1.recordedMinutes }
        }
        return StressDetail(
            timeline: result.timeline.compactMap { point in point.level.map { Point(ts: point.startTs, level: $0) } },
            hours: hours,
            calmMinutes: minutes(in: .calm), usualMinutes: minutes(in: .usual), highMinutes: minutes(in: .high),
            dayLevel: result.dayMean,
            peak: result.peak.flatMap { peak in hours.first { $0.startTs == peak.startTs } },
            sustainedHighHours: result.sustainedHigh ? result.sustainedRun : 0,
            movingHours: result.activityMaskedHours)
    }

    /// Distinct minutes with a reading, keyed by hour bucket.
    static func recordedMinutes(_ hr: [HRSample]) -> [Int: Int] {
        let minutes = Set(hr.map { $0.ts / 60 })
        return Dictionary(grouping: minutes) { $0 * 60 / DaytimeStress.bucketSeconds }.mapValues(\.count)
    }
}

/// Effort and heart-rate zones in depth: your own bpm range for each zone, the stretches you spent
/// working hard and how fast your heart came down after them, the hourly average, and Effort as it built.
public struct EffortDetail: Sendable, Equatable {
    public struct Zone: Sendable, Equatable, Identifiable {
        public let number: Int
        public let lowerBPM: Int
        public let upperBPM: Int
        public let minutes: Int
        public var id: Int { number }
    }

    /// Five minutes or more in Zone 3 or above, with short dips of up to two minutes kept inside.
    public struct Stretch: Sendable, Equatable, Identifiable {
        public let start: Int
        /// Start of the last hard minute.
        public let end: Int
        public let averageBPM: Int
        public let peakBPM: Int
        public let topZone: Int
        /// How far heart rate fell one and two minutes after the last hard minute, when recorded.
        public let dropAfterOneMinute: Int?
        public let dropAfterTwoMinutes: Int?
        public var minutes: Int { (end - start) / 60 + 1 }
        public var id: Int { start }
    }

    public struct HourAverage: Sendable, Equatable, Identifiable {
        public let hour: Int
        public let startTs: Int
        public let averageBPM: Int
        public var id: Int { startTs }
    }

    public struct EffortPoint: Sendable, Equatable, Identifiable {
        public let ts: Int
        public let effort: Double
        public var id: Int { ts }
    }

    public let zones: [Zone]
    public let stretches: [Stretch]
    public let hourly: [HourAverage]
    public let effortCurve: [EffortPoint]

    static let hardZone = 3
    static let minStretchSeconds = 300
    static let maxDipSeconds = 180

    public static func compute(hr: [HRSample], maxHR: Int, restingHR: Int, sex: String,
                               tzOffsetSeconds: Int) -> EffortDetail {
        let samples = hr.sorted { $0.ts < $1.ts }
        let set = HRZones.zones(maxHR: Double(maxHR))
        let seconds = samples.isEmpty ? Array(repeating: 0.0, count: 5) : HRZones.timeInZone(samples, zoneSet: set).seconds
        let zones = set.zones.enumerated().map { index, zone in
            Zone(number: index + 1, lowerBPM: Int(zone.lower.rounded()), upperBPM: Int(zone.upper.rounded()),
                 minutes: Int((seconds[index] / 60).rounded()))
        }
        let minutes = TodayAnalytics.minuteSeries(samples)
        return EffortDetail(zones: zones, stretches: stretches(minutes, maxHR: maxHR),
                            hourly: hourly(minutes, tzOffsetSeconds: tzOffsetSeconds),
                            effortCurve: effortCurve(samples, maxHR: maxHR, restingHR: restingHR, sex: sex))
    }

    static func stretches(_ minutes: [TodaySnapshot.MinutePoint], maxHR: Int) -> [Stretch] {
        var runs: [[TodaySnapshot.MinutePoint]] = []
        for point in minutes where TodayAnalytics.zone(bpm: Int(point.bpm.rounded()), maxHR: maxHR) >= hardZone {
            if let last = runs.last?.last, point.ts - last.ts <= maxDipSeconds {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        let byTime = Dictionary(minutes.map { ($0.ts, $0.bpm) }, uniquingKeysWith: { first, _ in first })
        return runs.compactMap { run in
            guard let first = run.first, let last = run.last, last.ts - first.ts + 60 >= minStretchSeconds else { return nil }
            let bpms = run.map(\.bpm)
            let peak = Int((bpms.max() ?? 0).rounded())
            let endBPM = last.bpm
            func drop(after seconds: Int) -> Int? {
                byTime[last.ts + seconds].map { Int((endBPM - $0).rounded()) }
            }
            return Stretch(start: first.ts, end: last.ts,
                           averageBPM: Int((bpms.reduce(0, +) / Double(bpms.count)).rounded()), peakBPM: peak,
                           topZone: TodayAnalytics.zone(bpm: peak, maxHR: maxHR),
                           dropAfterOneMinute: drop(after: 60), dropAfterTwoMinutes: drop(after: 120))
        }
    }

    static func hourly(_ minutes: [TodaySnapshot.MinutePoint], tzOffsetSeconds: Int) -> [HourAverage] {
        Dictionary(grouping: minutes) { ($0.ts + tzOffsetSeconds) / 3_600 }
            .map { bucket, points in
                HourAverage(hour: bucket % 24, startTs: bucket * 3_600 - tzOffsetSeconds,
                            averageBPM: Int((points.map(\.bpm).reduce(0, +) / Double(points.count)).rounded()))
            }
            .sorted { $0.startTs < $1.startTs }
    }

    /// Effort over everything up to each hour boundary, then up to the latest reading.
    static func effortCurve(_ samples: [HRSample], maxHR: Int, restingHR: Int, sex: String) -> [EffortPoint] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var boundaries = Array(stride(from: (first.ts / 3_600 + 1) * 3_600, through: last.ts, by: 3_600))
        if boundaries.last != last.ts + 1 { boundaries.append(last.ts + 1) }
        var index = 0
        return boundaries.compactMap { boundary in
            while index < samples.count, samples[index].ts < boundary { index += 1 }
            guard let effort = StrainScorer.strain(Array(samples[..<index]), maxHR: Double(maxHR),
                                                   restingHR: Double(restingHR), sex: sex) else { return nil }
            return EffortPoint(ts: boundary, effort: effort)
        }
    }
}

/// Last night against your own normal: Charge and its zone, what moved it, and each measure beside
/// the median of your earlier nights. No normal is shown until there are enough nights to have one.
public struct RecoveryDetail: Sendable, Equatable {
    public struct Measure: Sendable, Equatable, Identifiable {
        public let name: String
        public let unit: String
        public let value: Double
        /// Median of earlier nights, once there are enough of them.
        public let normal: Double?
        public let decimals: Int
        /// Whether a higher value is the better direction, or nil when neither is.
        let higherIsBetter: Bool?
        public var delta: Double? { normal.map { value - $0 } }
        /// True when the night moved the good way, false the other way, nil when level or unknown.
        public var isBetter: Bool? {
            guard let delta, let higherIsBetter, delta != 0 else { return nil }
            return (delta > 0) == higherIsBetter
        }
        public var id: String { name }
    }

    public struct TrendNight: Sendable, Equatable, Identifiable {
        public let day: String
        public let hrv: Double?
        public let restingHR: Int?
        public var id: String { day }
    }

    public let night: NightSummary
    public let zone: ChargeZone?
    public let drivers: [NightSummary.Driver]
    public let measures: [Measure]
    public let nightsUntilCharge: Int
    public let recent: [TrendNight]

    /// Charge needs four nights; the normal needs the three before tonight.
    public static let minNightsForNormal = BaselineProgress.chargeNights - 1
    static let trendNights = 7

    public static func compute(latest: NightSummary?, history: [NightSummary]) -> RecoveryDetail? {
        guard let latest else { return nil }
        let earlier = history.filter { $0.day < latest.day }.sorted { $0.day < $1.day }
        let all = earlier + [latest]
        func measure(_ name: String, _ unit: String, decimals: Int = 0, higherIsBetter: Bool?,
                     _ read: (NightSummary) -> Double?) -> Measure? {
            guard let value = read(latest) else { return nil }
            let past = earlier.compactMap(read)
            return Measure(name: name, unit: unit, value: value,
                           normal: past.count >= minNightsForNormal ? median(past) : nil,
                           decimals: decimals, higherIsBetter: higherIsBetter)
        }
        let measures = [
            measure("HRV", "ms", higherIsBetter: true) { $0.hrv },
            measure("Resting HR", "bpm", higherIsBetter: false) { $0.restingHR.map(Double.init) },
            measure("Breathing", "/min", decimals: 1, higherIsBetter: nil) { $0.respRate },
            measure("Asleep", "h", decimals: 1, higherIsBetter: true) { $0.totalSleepMin.map { $0 / 60 } },
            measure("Efficiency", "%", higherIsBetter: true) { $0.efficiency.map { $0 * 100 } },
        ].compactMap { $0 }
        let scored = all.filter { $0.hrv != nil }.count
        return RecoveryDetail(
            night: latest, zone: latest.charge.map(ChargeZone.init(charge:)), drivers: latest.drivers,
            measures: measures,
            nightsUntilCharge: BaselineProgress(scoredNights: scored).nightsUntilCharge,
            recent: all.suffix(trendNights).map { TrendNight(day: $0.day, hrv: $0.hrv, restingHR: $0.restingHR) })
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
