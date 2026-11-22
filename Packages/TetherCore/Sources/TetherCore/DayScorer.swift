import Foundation
import StrandAnalytics
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore

/// One scored night, in Tether's own Sendable shape. Nil means "not measured", never zero.
public struct NightSummary: Sendable, Equatable, Identifiable {
    public struct Driver: Sendable, Equatable, Identifiable {
        public let label: String
        public let valueText: String
        public let deltaPoints: Int
        public var id: String { label }

        public init(label: String, valueText: String, deltaPoints: Int) {
            self.label = label
            self.valueText = valueText
            self.deltaPoints = deltaPoints
        }
    }

    /// One stretch of the hypnogram.
    public struct Stage: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, CaseIterable { case wake, rem, light, deep }
        public let start: Int
        public let end: Int
        public let kind: Kind
        public var id: Int { start }

        public init(start: Int, end: Int, kind: Kind) {
            self.start = start
            self.end = end
            self.kind = kind
        }
    }

    public let day: String
    public let sleepStart: Int?
    public let sleepEnd: Int?
    public let totalSleepMin: Double?
    public let efficiency: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let lightMin: Double?
    public let disturbances: Int?
    public let restingHR: Int?
    public let hrv: Double?
    public let respRate: Double?
    /// Charge (0–100). Nil until the baseline has `Baselines.minNightsSeed` nights.
    public let charge: Double?
    public let rest: Double?
    public let drivers: [Driver]
    /// Estimated from heart rate alone until motion data exists.
    public let stages: [Stage]
    public var id: String { day }

    public init(day: String, sleepStart: Int?, sleepEnd: Int?, totalSleepMin: Double?, efficiency: Double?,
                deepMin: Double?, remMin: Double?, lightMin: Double?, disturbances: Int?, restingHR: Int?,
                hrv: Double?, respRate: Double?, charge: Double?, rest: Double?, drivers: [Driver], stages: [Stage]) {
        self.day = day
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.totalSleepMin = totalSleepMin
        self.efficiency = efficiency
        self.deepMin = deepMin
        self.remMin = remMin
        self.lightMin = lightMin
        self.disturbances = disturbances
        self.restingHR = restingHR
        self.hrv = hrv
        self.respRate = respRate
        self.charge = charge
        self.rest = rest
        self.drivers = drivers
        self.stages = stages
    }
}

/// Scores the night that ends on a given day with NOOP's `AnalyticsEngine`, the way NOOP's own app does
/// when there is no motion data: find sleep from heart rate, then analyse the day against baselines
/// folded from earlier nights.
public enum DayScorer {
    /// NOOP reads 30 h before the day's midnight so the night that ends on it is fully inside.
    public static let lookbackSeconds = StreamReadCap.lookbackSeconds

    public static func window(dayStart: Int, now: Int) -> ClosedRange<Int> {
        (dayStart - lookbackSeconds)...max(dayStart - lookbackSeconds, min(dayStart + 86_400, now))
    }

    public static func dayKey(dayStart: Int, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(dayStart)))
    }

    public static func score(day: String, hr: [HRSample], rr: [RRInterval], profile: UserProfile,
                             history: [DailyMetric], tzOffsetSeconds: Int) -> NightSummary {
        summary(of: analyze(day: day, hr: hr, rr: rr, profile: profile, history: history,
                            tzOffsetSeconds: tzOffsetSeconds), day: day)
    }

    static func analyze(day: String, hr: [HRSample], rr: [RRInterval], profile: UserProfile,
                        history: [DailyMetric], tzOffsetSeconds: Int) -> AnalyticsEngine.DayResult {
        let sortedHR = hr.sorted { $0.ts < $1.ts }
        let sortedRR = rr.sorted { $0.ts < $1.ts }
        let fragments = SleepStager.hrOnlySessions(day: day, hr: sortedHR, rr: sortedRR, resp: [])
        let sleep = joiningTheNight(fragments, day: day, hr: sortedHR, rr: sortedRR, tzOffsetSeconds: tzOffsetSeconds)
        return AnalyticsEngine.analyzeDay(
            day: day, hr: sortedHR, rr: sortedRR,
            profile: .init(weightKg: profile.weightKg, heightCm: Double(profile.heightCm),
                           age: Double(profile.age), sex: profile.sex.rawValue),
            baselines: baselines(history: history),
            maxHROverride: Double(profile.maxHR),
            tzOffsetSeconds: tzOffsetSeconds,
            providedSleep: sleep)
    }

    /// Swaps the fragments of one night for the whole night when `NightFinder` sees a longer span
    /// than any single fragment. The span is staged from heart rate and R-R like any other night, so
    /// wakes inside it still count as awake; resting HR and HRV are left for the engine to fill.
    static func joiningTheNight(_ fragments: [SleepSession], day: String, hr: [HRSample], rr: [RRInterval],
                                tzOffsetSeconds: Int) -> [SleepSession] {
        guard let dayStart = dayStart(day, tzOffsetSeconds: tzOffsetSeconds),
              let span = NightFinder.night(hr: hr, dayStart: dayStart) else { return fragments }
        let longest = fragments.map { $0.end - $0.start }.max() ?? 0
        guard span.upperBound - span.lowerBound > longest else { return fragments }
        let stages = SleepStagerV2.stageSession(start: span.lowerBound, end: span.upperBound, grav: [],
                                                hr: hr, rr: rr, resp: [])
        guard !stages.isEmpty else { return fragments }
        let awake = stages.filter { $0.stage == "wake" }.reduce(0) { $0 + $1.end - $1.start }
        let inBed = span.upperBound - span.lowerBound
        let night = SleepSession(start: span.lowerBound, end: span.upperBound,
                                 efficiency: Double(inBed - awake) / Double(inBed), stages: stages,
                                 restingHR: nil, avgHRV: nil, hrOnly: true)
        let others = fragments.filter { $0.end <= span.lowerBound || $0.start >= span.upperBound }
        return others + [night]
    }

    /// Local midnight for a "yyyy-MM-dd" key, as unix seconds.
    static func dayStart(_ day: String, tzOffsetSeconds: Int) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let utcMidnight = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        return Int(utcMidnight.timeIntervalSince1970) - tzOffsetSeconds
    }

    /// Personal HRV and resting-HR baselines from earlier nights, oldest first.
    static func baselines(history: [DailyMetric]) -> AnalyticsEngine.ProfileBaselines {
        let nights = history.sorted { $0.day < $1.day }
        guard let hrvCfg = Baselines.metricCfg["hrv"], let rhrCfg = Baselines.metricCfg["resting_hr"] else {
            return AnalyticsEngine.ProfileBaselines()
        }
        return AnalyticsEngine.ProfileBaselines(
            hrv: Baselines.foldHistory(nights.map(\.avgHrv), cfg: hrvCfg),
            restingHR: Baselines.foldHistory(nights.map { $0.restingHr.map(Double.init) }, cfg: rhrCfg))
    }

    static func summary(of result: AnalyticsEngine.DayResult, day: String) -> NightSummary {
        let main = result.sleepSessions.max { ($0.end - $0.start) < ($1.end - $1.start) }
        let daily = result.daily
        return NightSummary(
            day: day, sleepStart: main?.start, sleepEnd: main?.end,
            totalSleepMin: main == nil ? nil : daily.totalSleepMin, efficiency: daily.efficiency,
            deepMin: daily.deepMin, remMin: daily.remMin, lightMin: daily.lightMin,
            disturbances: daily.disturbances, restingHR: daily.restingHr, hrv: daily.avgHrv,
            respRate: daily.respRateBpm, charge: result.recovery, rest: result.restScore,
            drivers: result.chargeDrivers.map {
                NightSummary.Driver(label: $0.label, valueText: $0.valueText, deltaPoints: $0.deltaPoints)
            },
            stages: stages(main?.stages ?? []))
    }

    static func stages(_ segments: [StageSegment]) -> [NightSummary.Stage] {
        segments.compactMap { segment in
            NightSummary.Stage.Kind(rawValue: segment.stage).map {
                NightSummary.Stage(start: segment.start, end: segment.end, kind: $0)
            }
        }
    }

    /// A stored night, rebuilt from the daily row and its saved sleep session. Charge drivers aren't stored.
    static func summary(of daily: DailyMetric, session: CachedSleepSession?) -> NightSummary {
        let stages = session?.stagesJSON.flatMap { try? JSONDecoder().decode([StageSegment].self, from: Data($0.utf8)) } ?? []
        return NightSummary(
            day: daily.day, sleepStart: session?.startTs, sleepEnd: session?.endTs,
            totalSleepMin: daily.totalSleepMin, efficiency: daily.efficiency, deepMin: daily.deepMin,
            remMin: daily.remMin, lightMin: daily.lightMin, disturbances: daily.disturbances,
            restingHR: daily.restingHr, hrv: daily.avgHrv, respRate: daily.respRateBpm,
            charge: daily.recovery, rest: nil, drivers: [], stages: Self.stages(stages))
    }
}

extension WhoopStoreSink {
    /// Scores the night ending on the day that starts at `dayStart`, saves it, and returns the summary.
    /// Re-scoring a day replaces its rows.
    public func scoreDay(dayStart: Int, now: Int, profile: UserProfile,
                         tzOffsetSeconds: Int = TimeZone.current.secondsFromGMT()) async throws -> NightSummary {
        let store = try await openStore()
        let window = DayScorer.window(dayStart: dayStart, now: now)
        let timeZone = TimeZone(secondsFromGMT: tzOffsetSeconds) ?? .current
        let day = DayScorer.dayKey(dayStart: dayStart, timeZone: timeZone)
        let hr = try await store.hrSamples(deviceId: Self.deviceId, from: window.lowerBound, to: window.upperBound,
                                           limit: Self.scoringReadLimit)
        let rr = try await store.rrIntervals(deviceId: Self.deviceId, from: window.lowerBound, to: window.upperBound,
                                             limit: Self.scoringReadLimit)
        let history = try await store.dailyMetrics(deviceId: Self.deviceId, from: "0000-01-01", to: day)
            .filter { $0.day < day }
        let result = DayScorer.analyze(day: day, hr: hr, rr: rr, profile: profile, history: history,
                                       tzOffsetSeconds: tzOffsetSeconds)
        _ = try await store.upsertDailyMetrics([result.daily], deviceId: Self.deviceId)
        // Sessions are keyed by their start, so a re-score that finds a different start would leave the
        // old one behind. Clear this day's earlier sessions first; hand-edited ones stay.
        let fresh = Set(result.cachedSleep.map(\.startTs))
        let earlier = try await store.sleepSessions(deviceId: Self.deviceId, from: window.lowerBound,
                                                    to: window.upperBound + 86_400, limit: 1_000)
        for session in earlier where !session.userEdited && !fresh.contains(session.startTs)
            && DayScorer.dayKey(dayStart: session.endTs, timeZone: timeZone) == day {
            _ = try await store.deleteSleepSession(deviceId: Self.deviceId, startTs: session.startTs)
        }
        if !result.cachedSleep.isEmpty {
            _ = try await store.upsertSleepSessions(result.cachedSleep, deviceId: Self.deviceId)
        }
        return DayScorer.summary(of: result, day: day)
    }

    /// Days that already have a scored row.
    public func scoredDays(from: String, to: String) async throws -> [String] {
        try await openStore().dailyMetrics(deviceId: Self.deviceId, from: from, to: to).map(\.day).sorted()
    }

    /// Nights that count toward the personal baseline (they produced an HRV reading).
    public func baselineNightCount() async throws -> Int {
        try await openStore().dailyMetrics(deviceId: Self.deviceId, from: "0000-01-01", to: "9999-12-31")
            .filter { $0.avgHrv != nil }.count
    }

    /// Stored nights, oldest first, with each night's main sleep session.
    public func nights(from: String, to: String) async throws -> [NightSummary] {
        let store = try await openStore()
        let days = try await store.dailyMetrics(deviceId: Self.deviceId, from: from, to: to).sorted { $0.day < $1.day }
        guard !days.isEmpty else { return [] }
        let sessions = try await store.sleepSessions(deviceId: Self.deviceId, from: 0, to: Int.max / 2, limit: 4_000)
        return days.map { daily in
            let session = sessions.filter { DayScorer.dayKey(dayStart: $0.endTs) == daily.day }
                .max { ($0.endTs - $0.startTs) < ($1.endTs - $1.startTs) }
            return DayScorer.summary(of: daily, session: session)
        }
    }

    static let scoringReadLimit = 400_000
}
