import Foundation

/// Today's plan for the Now widget, written by the phone app: this morning's Charge, the energy forecast's
/// times, tonight's bedtime and the strap alarm. The widget schedules its own changes from these times, so
/// it stays right without the app running. A nil means "not known" and is never shown as zero.
public struct DayPlan: Codable, Sendable, Equatable {
    /// The wake day this plan is for ("yyyy-MM-dd"); see `WakeDay`.
    public let day: String
    /// Local midnight at the start of `day`.
    public let dayStart: Int
    public let chargePercent: Int?
    public let zoneName: String?
    public let advice: String?
    public let sleepMin: Double?
    public let targetLow: Int?
    public let targetHigh: Int?
    /// Minutes after midnight.
    public let sharpest: ClosedRange<Int>?
    public let dipMinute: Int?
    public let coffeeByMinute: Int?
    public let napWindow: ClosedRange<Int>?
    /// Forecast alertness 0–100, hourly from 06:00 to midnight (19 values), for the home-screen curve.
    public let energy: [Int]
    public let bedtimeAt: Int?
    public let needMin: Double?
    public let alarmAt: Int?
    public let alarmConfirmed: Bool

    public init(day: String, dayStart: Int, chargePercent: Int?, zoneName: String?, advice: String?, sleepMin: Double?,
                targetLow: Int?, targetHigh: Int?, sharpest: ClosedRange<Int>?, dipMinute: Int?, coffeeByMinute: Int?,
                napWindow: ClosedRange<Int>?, energy: [Int], bedtimeAt: Int?, needMin: Double?, alarmAt: Int?,
                alarmConfirmed: Bool) {
        self.day = day
        self.dayStart = dayStart
        self.chargePercent = chargePercent
        self.zoneName = zoneName
        self.advice = advice
        self.sleepMin = sleepMin
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.sharpest = sharpest
        self.dipMinute = dipMinute
        self.coffeeByMinute = coffeeByMinute
        self.napWindow = napWindow
        self.energy = energy
        self.bedtimeAt = bedtimeAt
        self.needMin = needMin
        self.alarmAt = alarmAt
        self.alarmConfirmed = alarmConfirmed
    }

    /// Everything the widget shows, so an unchanged plan doesn't spend a widget reload.
    func sameShown(as other: DayPlan) -> Bool {
        var a = self, b = other
        a = a.with(energy: []); b = b.with(energy: [])
        return a == b && zip(energy, other.energy).allSatisfy { abs($0 - $1) < 5 } && energy.count == other.energy.count
    }

    private func with(energy: [Int]) -> DayPlan {
        DayPlan(day: day, dayStart: dayStart, chargePercent: chargePercent, zoneName: zoneName, advice: advice,
                sleepMin: sleepMin, targetLow: targetLow, targetHigh: targetHigh, sharpest: sharpest, dipMinute: dipMinute,
                coffeeByMinute: coffeeByMinute, napWindow: napWindow, energy: energy, bedtimeAt: bedtimeAt, needMin: needMin,
                alarmAt: alarmAt, alarmConfirmed: alarmConfirmed)
    }

    func time(_ minute: Int) -> Int { dayStart + minute * 60 }
}

/// What the Now widget shows at a moment: Charge in the morning, the next thing on the plan through the day,
/// bedtime for the two hours before it, then the alarm.
public enum NowView: Equatable, Sendable {
    public struct Event: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case sharpestFrom, sharpestTill, dip, coffee, napFrom, napTill }
        public let kind: Kind
        public let at: Int
    }

    case morning
    /// The next thing on today's plan, or nil when nothing's left (the widget shows the Effort target).
    case day(Event?)
    case evening
    case night
    case empty

    public static let morningEndsHour = 12
    public static let eveningLeadSeconds = 2 * 3_600
    /// After an old plan's alarm, it keeps showing for this long before going quiet.
    static let alarmGraceSeconds = 3_600

    public static func at(_ now: Int, plan: DayPlan?, calendar: Calendar = .current) -> NowView {
        guard let plan else { return .empty }
        let fresh = plan.day == WakeDay.key(for: Date(timeIntervalSince1970: TimeInterval(now)), calendar: calendar)
        if let bed = plan.bedtimeAt, now >= bed {
            return now < (plan.alarmAt.map { $0 + alarmGraceSeconds } ?? WakeDay.boundaryAfter(bed, calendar)) ? .night : .empty
        }
        guard fresh else { return .empty }
        if let bed = plan.bedtimeAt, now >= bed - eveningLeadSeconds { return .evening }
        if plan.chargePercent != nil, now < plan.dayStart + morningEndsHour * 3_600 { return .morning }
        return .day(events(plan).first { $0.at > now })
    }

    /// The moments the view changes after `now`, for the widget's timeline.
    public static func changes(after now: Int, plan: DayPlan?, calendar: Calendar = .current) -> [Int] {
        guard let plan else { return [] }
        var times = events(plan).map(\.at) + [plan.dayStart + morningEndsHour * 3_600]
        if let bed = plan.bedtimeAt {
            times += [bed - eveningLeadSeconds, bed, WakeDay.boundaryAfter(bed, calendar)]
        }
        if let alarm = plan.alarmAt { times.append(alarm + alarmGraceSeconds) }
        return Array(Set(times.filter { $0 > now })).sorted()
    }

    /// Today's plan as events in time order. Inside the sharpest window the next event is its end.
    static func events(_ plan: DayPlan) -> [Event] {
        var list: [Event] = []
        if let sharp = plan.sharpest {
            list += [Event(kind: .sharpestFrom, at: plan.time(sharp.lowerBound)),
                     Event(kind: .sharpestTill, at: plan.time(sharp.upperBound))]
        }
        if let nap = plan.napWindow {
            list += [Event(kind: .napFrom, at: plan.time(nap.lowerBound)), Event(kind: .napTill, at: plan.time(nap.upperBound))]
        }
        if let dip = plan.dipMinute { list.append(Event(kind: .dip, at: plan.time(dip))) }
        if let coffee = plan.coffeeByMinute { list.append(Event(kind: .coffee, at: plan.time(coffee))) }
        return list.sorted { $0.at < $1.at }
    }
}

extension WakeDay {
    /// The first 04:00 after an epoch time.
    static func boundaryAfter(_ time: Int, _ calendar: Calendar) -> Int {
        Int(nextBoundary(after: Date(timeIntervalSince1970: TimeInterval(time)), calendar: calendar).timeIntervalSince1970)
    }
}
