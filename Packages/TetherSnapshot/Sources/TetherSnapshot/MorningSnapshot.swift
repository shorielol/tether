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

    /// 0.34 → "+0.3°", rounded to a tenth; a change that rounds to nothing shows no sign.
    public static func signedDelta(_ celsius: Double) -> String {
        let tenths = (celsius * 10).rounded() / 10
        let text = String(format: "%.1f°", abs(tenths))
        return tenths > 0 ? "+" + text : tenths < 0 ? "−" + text : text
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
    static let tonightKey = "tether.tonightSnapshot"

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

    public func readTonight() -> TonightSnapshot? {
        guard let data = defaults.data(forKey: Self.tonightKey) else { return nil }
        return try? JSONDecoder().decode(TonightSnapshot.self, from: data)
    }

    /// Saves tonight's numbers. True when they changed, so the caller reloads the widgets only then.
    @discardableResult
    public func writeTonight(_ tonight: TonightSnapshot) throws -> Bool {
        if let current = readTonight(), current.sameNumbers(as: tonight) { return false }
        defaults.set(try JSONEncoder().encode(tonight), forKey: Self.tonightKey)
        return true
    }
}

/// Tonight's plan for the widgets: how much sleep you need, when to be in bed, and the strap's alarm.
/// Changes through the day, so it's kept apart from the morning's numbers.
public struct TonightSnapshot: Codable, Sendable, Equatable {
    public let savedAt: Int
    public let needMin: Double
    /// Minutes after midnight.
    public let bedtimeMinute: Int
    /// Minutes after midnight, or nil when the alarm is off.
    public let alarmMinute: Int?
    /// True once the strap has said it has the alarm.
    public let alarmConfirmed: Bool

    public init(savedAt: Int, needMin: Double, bedtimeMinute: Int, alarmMinute: Int?, alarmConfirmed: Bool) {
        self.savedAt = savedAt
        self.needMin = needMin
        self.bedtimeMinute = bedtimeMinute
        self.alarmMinute = alarmMinute
        self.alarmConfirmed = alarmConfirmed
    }

    func sameNumbers(as other: TonightSnapshot) -> Bool {
        Int(needMin.rounded()) == Int(other.needMin.rounded()) && bedtimeMinute == other.bedtimeMinute
            && alarmMinute == other.alarmMinute && alarmConfirmed == other.alarmConfirmed
    }

    /// Minutes after midnight as a 24-hour clock, wrapping past midnight either way.
    public static func clock(_ minute: Int) -> String {
        let wrapped = ((minute % 1_440) + 1_440) % 1_440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }
}
