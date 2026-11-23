import Foundation

/// Last night's numbers for the lock-screen widgets. Written by the phone app once the night is scored,
/// read by the widget extension. A nil value means "not measured" and shows as a dash, never as zero.
public struct MorningSnapshot: Codable, Sendable, Equatable {
    /// Nights the baseline needs before Charge scores (NOOP's `Baselines.minNightsSeed`).
    public static let chargeNightsNeeded = 4

    /// The wake day this snapshot belongs to ("yyyy-MM-dd"); see `WakeDay`.
    public let wakeDay: String
    public let savedAt: Int
    public let sleepMin: Double?
    /// Rest score, 0–100.
    public let rest: Double?
    /// Charge, 0–100. Nil until the baseline has `chargeNightsNeeded` nights.
    public let charge: Double?
    public let baselineNights: Int
    public let restingHR: Int?
    /// Last night's skin temperature against your normal, in °C. Nil before there's a normal.
    public let skinTempDevC: Double?

    public init(wakeDay: String, savedAt: Int, sleepMin: Double?, rest: Double?, charge: Double?,
                baselineNights: Int, restingHR: Int?, skinTempDevC: Double? = nil) {
        self.wakeDay = wakeDay
        self.savedAt = savedAt
        self.sleepMin = sleepMin
        self.rest = rest
        self.charge = charge
        self.baselineNights = max(0, baselineNights)
        self.restingHR = restingHR
        self.skinTempDevC = skinTempDevC
    }

    /// True only on the wake day it was written for, so yesterday's numbers never pass as today's.
    public func isFresh(at date: Date, calendar: Calendar = .current) -> Bool {
        wakeDay == WakeDay.key(for: date, calendar: calendar)
    }

    /// How far the baseline is towards Charge, 0…1.
    public var chargeProgress: Double {
        min(1, Double(baselineNights) / Double(Self.chargeNightsNeeded))
    }
}

/// A "wake day" runs from 04:00 to 04:00 local, so a number from this morning stays up through the evening
/// and clears before the next night could have finished.
public enum WakeDay {
    public static let boundaryHour = 4

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-TimeInterval(boundaryHour * 3_600))
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The first 04:00 strictly after `date`.
    public static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        let match = DateComponents(hour: boundaryHour, minute: 0, second: 0)
        return calendar.nextDate(after: date, matching: match, matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }
}

/// The snapshot in shared UserDefaults (the App Group both targets carry, ADR-005).
public struct SnapshotStore: @unchecked Sendable {
    public static let appGroup = "group.com.shorielol.tether"
    static let key = "tether.morningSnapshot"
    static let planKey = "tether.dayPlan"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The App Group store, or nil if the entitlement is missing from this build.
    public static func shared() -> SnapshotStore? {
        UserDefaults(suiteName: appGroup).map(SnapshotStore.init(defaults:))
    }

    public func read() -> MorningSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(MorningSnapshot.self, from: data)
    }

    public func write(_ snapshot: MorningSnapshot) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.key)
    }

    public func readPlan() -> DayPlan? {
        guard let data = defaults.data(forKey: Self.planKey) else { return nil }
        return try? JSONDecoder().decode(DayPlan.self, from: data)
    }

    /// Saves today's plan. True when what the widget shows changed, so the caller reloads only then.
    @discardableResult
    public func writePlan(_ plan: DayPlan) throws -> Bool {
        if let current = readPlan(), current.sameShown(as: plan) { return false }
        defaults.set(try JSONEncoder().encode(plan), forKey: Self.planKey)
        return true
    }
}
