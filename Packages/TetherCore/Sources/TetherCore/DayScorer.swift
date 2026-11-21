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
    public let stages: [StageSegment]
    public var id: String { day }
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
        let sleep = SleepStager.hrOnlySessions(day: day, hr: sortedHR, rr: sortedRR, resp: [])
        return AnalyticsEngine.analyzeDay(
            day: day, hr: sortedHR, rr: sortedRR,
            profile: .init(weightKg: profile.weightKg, heightCm: Double(profile.heightCm),
                           age: Double(profile.age), sex: profile.sex.rawValue),
            baselines: baselines(history: history),
            maxHROverride: Double(profile.maxHR),
            tzOffsetSeconds: tzOffsetSeconds,
            providedSleep: sleep)
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
            stages: main?.stages ?? [])
    }

    /// A stored night, rebuilt from the daily row and its saved sleep session. Charge drivers aren't stored.
    static func summary(of daily: DailyMetric, session: CachedSleepSession?) -> NightSummary {
        let stages = session?.stagesJSON.flatMap { try? JSONDecoder().decode([StageSegment].self, from: Data($0.utf8)) } ?? []
        return NightSummary(
            day: daily.day, sleepStart: session?.startTs, sleepEnd: session?.endTs,
            totalSleepMin: daily.totalSleepMin, efficiency: daily.efficiency, deepMin: daily.deepMin,
            remMin: daily.remMin, lightMin: daily.lightMin, disturbances: daily.disturbances,
            restingHR: daily.restingHr, hrv: daily.avgHrv, respRate: daily.respRateBpm,
            charge: daily.recovery, rest: nil, drivers: [], stages: stages)
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
