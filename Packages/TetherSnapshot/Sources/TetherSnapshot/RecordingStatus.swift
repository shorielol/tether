import Foundation

/// What the lock-screen "Recording your night" card shows. It's the Live Activity's content state, so it
/// stays small and Codable; the app builds it every minute from the collector and the stored samples.
public struct RecordingStatus: Codable, Hashable, Sendable {
    public enum Link: String, Codable, Hashable, Sendable {
        case solid, reconnecting, lost
    }

    /// The card's own lifetime: iOS ends a Live Activity after 8 hours.
    public static let cardHours = 8
    /// The first sample and the collector's 30 s flush lag aren't missed data.
    static let graceSeconds = 60
    /// Evening and morning hours count as "your night" in the title.
    static let nightHours: Set<Int> = Set(20...23).union(0..<10)

    public let heartRate: Int?
    public let link: Link
    public let missedMinutes: Int
    /// Share of the time since the card started with heart rate stored; nil for the first minute.
    public let coveragePercent: Int?
    public let strapBattery: Int?
    public let isNight: Bool

    public init(heartRate: Int?, link: Link, missedMinutes: Int, coveragePercent: Int?, strapBattery: Int?,
                isNight: Bool) {
        self.heartRate = heartRate
        self.link = link
        self.missedMinutes = max(0, missedMinutes)
        self.coveragePercent = coveragePercent
        self.strapBattery = strapBattery
        self.isNight = isNight
    }

    public static func make(heartRate: Int?, link: Link, startedAt: Date, now: Date, capturedSeconds: Int,
                            strapBattery: Int?, calendar: Calendar = .current) -> RecordingStatus {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let missed = max(0, elapsed - min(capturedSeconds, elapsed) - graceSeconds)
        let coverage = elapsed < 60 ? nil : Int((Double(elapsed - missed) / Double(elapsed) * 100).rounded())
        return RecordingStatus(heartRate: heartRate, link: link, missedMinutes: missed / 60,
                               coveragePercent: coverage, strapBattery: strapBattery,
                               isNight: nightHours.contains(calendar.component(.hour, from: now)))
    }

    public var title: String { isNight ? "Recording your night" : "Recording" }

    public var subtitle: String {
        let missed = missedMinutes == 0 ? nil : "\(Self.duration(minutes: missedMinutes)) missed"
        switch link {
        case .solid: return "Link solid · " + (missed ?? "nothing missed")
        case .reconnecting: return missed.map { "Reconnecting · " + $0 } ?? "Reconnecting…"
        case .lost: return "Strap not linked" + (missed.map { " · " + $0 } ?? "")
        }
    }

    /// 6 → "6 min", 75 → "1 h 15 min", 120 → "2 h".
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// The Live Activity both the app (starts and updates it) and the widget extension (draws it) share.
public struct RecordingAttributes: ActivityAttributes, Sendable {
    public typealias ContentState = RecordingStatus
    public let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}
#endif
