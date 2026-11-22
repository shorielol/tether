import Foundation

/// How alert you're likely to feel through the day, from the two-process model of sleep (Borbély):
/// sleep pressure that builds while you're awake and drains while you sleep, against a body clock timed
/// from your usual wake. An estimate from your sleep times, not a measurement.
public struct EnergyForecast: Sendable, Equatable {
    public struct Point: Sendable, Equatable, Identifiable {
        /// Minutes after midnight.
        public let minute: Int
        /// 0–100, higher is more alert. Relative within your day, not a score.
        public let level: Double
        public var id: Int { minute }
    }

    public let points: [Point]
    /// The two hours you're likely to be sharpest.
    public let bestWindow: ClosedRange<Int>
    /// The bottom of the afternoon dip.
    public let dipMinute: Int
    /// About 8 hours before your usual sleep, so caffeine has mostly cleared by bedtime.
    public let coffeeCutoffMinute: Int
    /// A short nap fits here when you're owed sleep.
    public let napWindow: ClosedRange<Int>?

    // Two-process constants (Daan, Beersma & Borbély 1984).
    static let riseHours = 18.2
    static let fallHours = 4.2
    static let clockAmplitude = 0.5
    static let dipAmplitude = 0.12
    /// Core body temperature bottoms out about this long before your usual wake.
    static let tempMinBeforeWakeHours = 2.5
    static let caffeineHours = 8
    static let napOwedMin = 60.0
    static let nightsNeeded = 3
    static let stepMinutes = 15
    static let bestWindowMinutes = 120

    public static func compute(nights: [NightSummary], owedSleepMin: Double, timeZone: TimeZone = .current) -> EnergyForecast? {
        let slept = nights.filter { $0.sleepStart != nil && $0.sleepEnd != nil }.sorted { $0.day < $1.day }.suffix(7)
        guard slept.count >= nightsNeeded, let last = slept.last, let wakeTs = last.sleepEnd else { return nil }
        let wakes = slept.compactMap { $0.sleepEnd.map { Double(SleepCoach.minuteOfDay($0, timeZone)) } }
        let beds = slept.compactMap { $0.sleepStart.map { Double((SleepCoach.minuteOfDay($0, timeZone) + 720) % 1_440 - 720) } }
        let usualWake = SleepCoach.median(wakes) / 60
        let usualBed = SleepCoach.median(beds) / 60

        // Sleep pressure, carried night to night so short sleep leaves more of it.
        var pressure = 0.5
        var awakeSince: Int?
        for night in slept {
            guard let start = night.sleepStart, let end = night.sleepEnd else { continue }
            if let awakeSince { pressure = rise(pressure, hours: Double(start - awakeSince) / 3_600) }
            let asleepHours = (night.totalSleepMin ?? Double(end - start) / 60) / 60
            pressure = fall(pressure, hours: asleepHours)
            awakeSince = end
        }
        let wakeMinute = SleepCoach.minuteOfDay(wakeTs, timeZone)
        let clockPeak = usualWake - tempMinBeforeWakeHours + 12
        let dipCentre = usualWake - tempMinBeforeWakeHours + 9.5

        var points: [Point] = []
        var minute = (wakeMinute / stepMinutes + 1) * stepMinutes
        while minute <= 24 * 60 {
            let hour = Double(minute) / 60
            let awake = Double(minute - wakeMinute) / 60
            let clock = clockAmplitude * cos(2 * .pi * (hour - clockPeak) / 24)
                - dipAmplitude * cos(2 * .pi * (hour - dipCentre) / 12)
            let raw = clock - rise(pressure, hours: awake)
            points.append(Point(minute: minute, level: min(100, max(0, (raw + 1.2) / 1.9 * 100))))
            minute += stepMinutes
        }
        guard points.count >= bestWindowMinutes / stepMinutes else { return nil }

        let span = bestWindowMinutes / stepMinutes
        let eligible = points.indices.dropLast(span - 1).filter { points[$0].minute <= 20 * 60 }
        let bestStart = eligible.max { mean(points[$0..<$0 + span]) < mean(points[$1..<$1 + span]) } ?? 0
        // The dip is the low point around the body clock's own post-lunch trough.
        let centre = Int((dipCentre * 60).rounded())
        let troughs = points.indices.dropFirst().dropLast().filter { index in
            abs(points[index].minute - centre) <= 120
                && points[index].level <= points[index - 1].level && points[index].level <= points[index + 1].level
        }
        let dip = troughs.min { points[$0].level < points[$1].level }.map { points[$0].minute }
            ?? (centre / stepMinutes) * stepMinutes
        let cutoff = ((Int((usualBed * 60).rounded()) - caffeineHours * 60) % 1_440 + 1_440) % 1_440
        return EnergyForecast(points: points,
                              bestWindow: points[bestStart].minute...points[bestStart + span - 1].minute,
                              dipMinute: dip, coffeeCutoffMinute: cutoff,
                              napWindow: owedSleepMin >= napOwedMin ? (dip - 30)...(dip + 10) : nil)
    }

    static func rise(_ pressure: Double, hours: Double) -> Double { 1 - (1 - pressure) * exp(-max(0, hours) / riseHours) }
    static func fall(_ pressure: Double, hours: Double) -> Double { pressure * exp(-max(0, hours) / fallHours) }

    private static func mean(_ slice: ArraySlice<Point>) -> Double {
        slice.map(\.level).reduce(0, +) / Double(max(slice.count, 1))
    }
}
