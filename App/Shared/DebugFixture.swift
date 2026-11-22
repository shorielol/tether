#if DEBUG
import Foundation
import TetherCore
@preconcurrency import WhoopProtocol

/// Simulator-only sample day for screenshots, switched on with `-tether.fixture day`.
/// Compiled out of Release (the build on the phone) and never written to the store.
enum DebugFixture {
    static var isOn: Bool { UserDefaults.standard.string(forKey: "tether.fixture") == "day" }

    static var liveHeartRate: Int? { isOn ? 74 : nil }

    static func today(profile: UserProfile?) -> TodaySnapshot? {
        guard isOn else { return nil }
        let day = dayStreams()
        return TodayAnalytics.compute(hr: day.hr, rr: day.rr, profile: profile, window: day.window, now: day.window.upperBound)
    }

    /// The sample day's heart rate and beats: a calm late morning, a tense mid-afternoon, a run at 6 PM.
    static func dayStreams() -> (hr: [HRSample], rr: [RRInterval], window: ClosedRange<Int>) {
        let midnight = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        let end = midnight + 21 * 3_600
        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        for ts in stride(from: midnight, through: end, by: 1) {
            let hour = Double(ts - midnight) / 3_600
            guard !(13.0..<13.4).contains(hour) else { continue }   // a dropout, to show a gap
            let bpm = Int(base(hour) + 3 * sin(Double(ts) / 97) + 2 * sin(Double(ts) / 13))
            hr.append(HRSample(ts: ts, bpm: bpm))
            let beat = 60_000 / max(bpm, 40)
            let spread = spread(hour)
            rr.append(RRInterval(ts: ts, rrMs: beat + (ts.isMultiple(of: 2) ? spread : -spread), ord: 0, seq: 0))
        }
        return (hr, rr, midnight...end)
    }

    /// The sample day's steps: a walk to school, a slow afternoon, the 6 PM run. The counter resets once at
    /// noon, as the real strap's does, so the screen shows the same handling.
    static func steps() -> DailySteps {
        let midnight = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        var counter = 0
        var samples: [StepSample] = []
        for minute in 0..<(21 * 60) {
            let perMinute = stepsPerMinute(Double(minute) / 60)
            if minute == 12 * 60 { counter = 0 }
            counter += perMinute
            samples.append(StepSample(ts: midnight + minute * 60, counter: counter,
                                      activityClass: perMinute >= 60 ? 1 : 0))
        }
        return DailySteps.compute(samples: samples, dayStart: midnight, dayEnd: midnight + 86_400)
    }

    private static func stepsPerMinute(_ hour: Double) -> Int {
        switch hour {
        case 7..<8: 55
        case 15..<16: 20
        case 18..<18.6: 150
        case 8..<21: 3
        default: 0
        }
    }

    /// Beat-to-beat spread: wide when relaxed, narrow when tense.
    private static func spread(_ hour: Double) -> Int {
        switch hour {
        case 10..<12: 40
        case 15..<17: 6
        default: 18
        }
    }

    /// Six sample nights ending last night; Charge appears from the fourth, as it would for real.
    static func nights() -> [NightSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<6).map { index in
            let day = calendar.date(byAdding: .day, value: index - 5, to: today) ?? today
            let dayStart = Int(day.timeIntervalSince1970)
            let bed = dayStart - 3_600 + index * 600, wake = dayStart + 7 * 3_600 - index * 300
            let pattern: [(NightSummary.Stage.Kind, Int)] = [(.wake, 12), (.light, 25), (.deep, 50), (.light, 30),
                (.rem, 22), (.light, 35), (.deep, 35), (.rem, 30), (.wake, 6), (.light, 40), (.rem, 35),
                (.light, 45), (.rem, 30), (.wake, 8)]
            var at = bed
            var stages: [NightSummary.Stage] = []
            for (kind, minutes) in pattern where at < wake {
                stages.append(.init(start: at, end: min(wake, at + minutes * 60), kind: kind))
                at += minutes * 60
            }
            let hasCharge = index >= 3
            let inputs = index == 5 ? fixtureChargeInputs : nil
            return NightSummary(
                day: DayScorer.dayKey(dayStart: dayStart), sleepStart: bed, sleepEnd: wake,
                totalSleepMin: Double(stages.filter { $0.kind != .wake }.reduce(0) { $0 + $1.end - $1.start }) / 60,
                efficiency: 0.92, deepMin: 85, remMin: 117,
                lightMin: 175, disturbances: 3, restingHR: 52 - index % 2, hrv: 54 + Double(index * 2),
                respRate: 14.6, charge: inputs?.charge() ?? (hasCharge ? [58, 71, 64][index - 3] : nil),
                rest: hasCharge ? 78 : nil,
                drivers: index == 5 ? [.init(label: "HRV", valueText: "6 ms above your average", deltaPoints: 7),
                                       .init(label: "Sleep", valueText: "58 min short of your need", deltaPoints: -5),
                                       .init(label: "Resting HR", valueText: "1 bpm below your average", deltaPoints: 2)] : [],
                stages: stages, skinTempC: [33.1, 33.3, 32.9, 33.2, 33.0, 33.6][index],
                skinTempDevC: index >= 3 ? [0.1, -0.1, 0.5][index - 3] : nil, chargeInputs: inputs)
        }
    }

    struct FixtureMark {
        let ts: Int
        let label: String?
        let window: MarkWindow?
    }

    /// Four mornings of coffee before today, coffee this morning, and an unnamed mark this afternoon.
    static func marks() -> [FixtureMark] {
        let today = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        let earlier = (1...4).reversed().map { day in
            FixtureMark(ts: today - day * 86_400 + 8 * 3_600 + 600, label: "Coffee",
                        window: MarkWindow(before: 62 + day % 2, after: 71 + day % 3))
        }
        return earlier + [
            FixtureMark(ts: today + 8 * 3_600 + 900, label: "Coffee", window: MarkWindow(before: 63, after: 72)),
            FixtureMark(ts: today + 15 * 3_600 + 1_200, label: nil, window: MarkWindow(before: 80, after: 92)),
        ]
    }

    /// Last night's Charge inputs, matching the sample night above.
    private static let fixtureChargeInputs = ChargeInputs(
        hrv: 64, restingHR: 51, resp: 14.6, rest: 78, skinTempDevC: 0.5,
        hrvNormal: .init(mean: 58, spread: 5), restingHRNormal: .init(mean: 52, spread: 2),
        respNormal: .init(mean: 14.8, spread: 0.5))

    private static func base(_ hour: Double) -> Double {
        switch hour {
        case ..<7: 52
        case ..<9: 78
        case 15..<17: 86
        case 18..<18.7: 156
        case 18.7..<19: 120
        default: 74
        }
    }
}
#endif
