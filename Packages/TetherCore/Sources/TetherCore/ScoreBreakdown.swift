import Foundation
import StrandAnalytics
@preconcurrency import WhoopStore

/// Everything one night's Charge was worked out from: the night's own measures and the averages they were
/// compared with. `charge()` runs the real scorer, so changing a value here is a true what-if.
public struct ChargeInputs: Sendable, Equatable {
    /// A running average and how much it usually varies, as the scorer keeps it.
    public struct Normal: Sendable, Equatable {
        public let mean: Double
        public let spread: Double

        public init(mean: Double, spread: Double) {
            self.mean = mean
            self.spread = spread
        }
    }

    public var hrv: Double
    public var restingHR: Double
    public var resp: Double?
    /// The night's sleep quality, 0–100.
    public var rest: Double?
    public var skinTempDevC: Double?
    public let hrvNormal: Normal
    public let restingHRNormal: Normal?
    public let respNormal: Normal?

    public init(hrv: Double, restingHR: Double, resp: Double?, rest: Double?, skinTempDevC: Double?,
                hrvNormal: Normal, restingHRNormal: Normal?, respNormal: Normal?) {
        self.hrv = hrv
        self.restingHR = restingHR
        self.resp = resp
        self.rest = rest
        self.skinTempDevC = skinTempDevC
        self.hrvNormal = hrvNormal
        self.restingHRNormal = restingHRNormal
        self.respNormal = respNormal
    }

    /// Sleep quality that neither adds to Charge nor takes from it.
    public static let levelRest = RecoveryScorer.sleepPerfCenter * 100

    /// Charge (0–100) from these values, through the same scorer the night was scored with.
    public func charge() -> Double? {
        RecoveryScorer.recovery(
            hrv: hrv, rhr: restingHR, resp: resp,
            hrvBaseline: .init(mean: hrvNormal.mean, spread: hrvNormal.spread),
            rhrBaseline: restingHRNormal.map { .init(mean: $0.mean, spread: $0.spread) },
            respBaseline: respNormal.map { .init(mean: $0.mean, spread: $0.spread) },
            sleepPerf: rest.map { $0 / 100 }, skinTempDev: skinTempDevC)
    }

    /// The inputs as the scorer saw them for a scored night, or nil when the night had no Charge.
    static func from(daily: DailyMetric, rest: Double?, baselines: AnalyticsEngine.ProfileBaselines) -> ChargeInputs? {
        guard let hrv = daily.avgHrv, let restingHR = daily.restingHr, let hrvBase = baselines.hrv, hrvBase.usable,
              daily.recovery != nil else { return nil }
        func normal(_ state: BaselineState?) -> Normal? {
            state.flatMap { $0.usable ? Normal(mean: $0.baseline, spread: $0.spread) : nil }
        }
        return ChargeInputs(hrv: hrv, restingHR: Double(restingHR), resp: daily.respRateBpm, rest: rest,
                            skinTempDevC: daily.skinTempDevC,
                            hrvNormal: Normal(mean: hrvBase.baseline, spread: hrvBase.spread),
                            restingHRNormal: normal(baselines.restingHR), respNormal: normal(baselines.resp))
    }
}

/// How a score was worked out, as a running total: where a night exactly at your normal lands, then the
/// points each measure added or took away, ending on the real score.
public struct ScoreBreakdown: Sendable, Equatable {
    public struct Step: Sendable, Equatable, Identifiable {
        public let name: String
        public let valueText: String
        public let compareText: String
        /// Share of the score this measure carries, in percent.
        public let weightPercent: Int
        /// Points this step added, already rounded to the breakdown's `decimals`.
        public let points: Double
        public var id: String { name }
    }

    public let start: Double
    public let steps: [Step]
    public let total: Double
    /// Decimal places the score is shown with: 0 for Charge, 1 for Effort.
    public let decimals: Int

    /// Rounds the way the score is shown, so the steps add up to the number on screen.
    static func shown(_ value: Double, decimals: Int) -> Double {
        let scale = pow(10, Double(decimals))
        return (value * scale).rounded() / scale
    }

    /// Charge as a running total. Each measure is brought from your normal to the night's value in turn,
    /// and every total along the way is a real run of the scorer, so the steps add up exactly.
    public static func charge(_ inputs: ChargeInputs) -> ScoreBreakdown? {
        typealias Move = (name: String, value: String, compare: String, weight: Double,
                          apply: (inout ChargeInputs) -> Void)
        var level = inputs
        var moves: [Move] = []

        level.hrv = inputs.hrvNormal.mean
        moves.append(("HRV", "\(whole(inputs.hrv)) ms", "your average \(whole(inputs.hrvNormal.mean)) ms",
                      RecoveryScorer.wHRV, { $0.hrv = inputs.hrv }))
        if let normal = inputs.restingHRNormal {
            level.restingHR = normal.mean
            moves.append(("Resting HR", "\(whole(inputs.restingHR)) bpm", "your average \(whole(normal.mean)) bpm",
                          RecoveryScorer.wRHR, { $0.restingHR = inputs.restingHR }))
        }
        if let rest = inputs.rest {
            level.rest = ChargeInputs.levelRest
            moves.append(("Sleep", "quality \(whole(rest)) of 100",
                          "level at \(whole(ChargeInputs.levelRest))", RecoveryScorer.wSleep, { $0.rest = rest }))
        }
        if let resp = inputs.resp, let normal = inputs.respNormal {
            level.resp = normal.mean
            moves.append(("Breathing", "\(tenth(resp)) /min", "your average \(tenth(normal.mean)) /min",
                          RecoveryScorer.wResp, { $0.resp = resp }))
        }
        if let deviation = inputs.skinTempDevC {
            level.skinTempDevC = 0
            moves.append(("Skin temp", "\(deviation >= 0 ? "+" : "")\(tenth(deviation)) °C from normal",
                          "any drift either way counts against", RecoveryScorer.wSkinTemp,
                          { $0.skinTempDevC = deviation }))
        }

        guard let startScore = level.charge() else { return nil }
        let totalWeight = moves.reduce(0) { $0 + $1.weight }
        var running = level
        var previous = shown(startScore, decimals: 0)
        var steps: [Step] = []
        for move in moves {
            move.apply(&running)
            guard let score = running.charge() else { return nil }
            let rounded = shown(score, decimals: 0)
            steps.append(Step(name: move.name, valueText: move.value, compareText: move.compare,
                              weightPercent: Int((move.weight / totalWeight * 100).rounded()),
                              points: rounded - previous))
            previous = rounded
        }
        return ScoreBreakdown(start: shown(startScore, decimals: 0), steps: steps, total: previous, decimals: 0)
    }

    /// Time asleep (minutes) as a running total: time in bed, minus the stretches awake, plus any sleep
    /// outside the main stretch. Each subtotal is rounded to the minute so the lines add up.
    public static func sleep(_ night: NightSummary) -> ScoreBreakdown? {
        guard let start = night.sleepStart, let end = night.sleepEnd, end > start,
              let asleep = night.totalSleepMin else { return nil }
        let inBed = Double(end - start) / 60
        let awake = Double(night.stages.filter { $0.kind == .wake }.reduce(0) { $0 + $1.end - $1.start }) / 60
        let staged = Double(night.stages.reduce(0) { $0 + $1.end - $1.start }) / 60
        let unstaged = max(0, inBed - staged)
        let moves: [(name: String, value: String, compare: String, subtotal: Double)] = [
            ("Awake in the night", "\(night.stages.filter { $0.kind == .wake }.count) times", "taken off",
             inBed - awake),
            ("Not read", "gaps with no heart rate", "taken off", inBed - awake - unstaged),
            ("Other sleep that night", "a separate stretch", "added on", asleep),
        ]
        var previous = inBed.rounded()
        var steps: [Step] = []
        for move in moves {
            let rounded = move.subtotal.rounded()
            let points = rounded - previous
            if points != 0 || (move.name == "Awake in the night" && awake > 0) {
                // Only the last line can go either way: sleep the scorer found outside the main stretch adds
                // on; a total below the stretch (it trimmed something) is said as such, not as "added".
                let trimmed = move.name == "Other sleep that night" && points < 0
                steps.append(Step(name: trimmed ? "Trimmed by the scorer" : move.name,
                                  valueText: trimmed ? "not counted as sleep" : move.value,
                                  compareText: trimmed ? "taken off" : move.compare,
                                  weightPercent: 0, points: points))
            }
            previous = rounded
        }
        return ScoreBreakdown(start: inBed.rounded(), steps: steps, total: previous, decimals: 0)
    }

    /// One hour's stress (0–3) as a running total: an hour exactly at the day's calm level reads 1.5, then
    /// heart rate and HRV move it along the scorer's own curve.
    static func stressHour(meanHR: Double, rmssd: Double?, reference: DaytimeStress.Reference) -> ScoreBreakdown {
        let hrOnly = DaytimeStress.rawScore(hr: meanHR, meanHR: reference.hr, sdHR: reference.sdHR,
                                            rmssd: nil, meanRMSSD: nil, sdRMSSD: 0)
        let both = DaytimeStress.rawScore(hr: meanHR, meanHR: reference.hr, sdHR: reference.sdHR,
                                          rmssd: rmssd, meanRMSSD: reference.rmssd, sdRMSSD: reference.sdRMSSD)
        let start = shown(DaytimeStress.squash(0), decimals: 1)
        let afterHR = shown(DaytimeStress.squash(hrOnly), decimals: 1)
        let total = shown(DaytimeStress.squash(both), decimals: 1)
        var steps = [Step(name: "Heart rate", valueText: "\(whole(meanHR)) bpm",
                          compareText: "your calm \(whole(reference.hr)) bpm", weightPercent: 0,
                          points: shown(afterHR - start, decimals: 1))]
        if let rmssd, let calm = reference.rmssd, reference.sdRMSSD > 0.0001 {
            steps.append(Step(name: "HRV", valueText: "\(whole(rmssd)) ms", compareText: "your calm \(whole(calm)) ms",
                              weightPercent: 0, points: shown(total - afterHR, decimals: 1)))
        }
        return ScoreBreakdown(start: start, steps: steps, total: total, decimals: 1)
    }

    /// Names for Effort's five heart-rate bands, easiest first.
    public static let effortBandNames = ["Light", "Moderate", "Hard", "Very hard", "Flat out"]

    /// Effort (0–100) from minutes per band, through the scorer's own curve. Each minute in band n is
    /// worth n; time below band 1 is worth nothing.
    public static func effortScore(bandMinutes: [Double]) -> Double {
        StrainScorer.trimpToStrain(points(bandMinutes))
    }

    /// Effort as a running total, easiest band first. Every total is a real run of the curve, so the
    /// steps add up exactly.
    public static func effort(bandMinutes: [Double]) -> ScoreBreakdown? {
        let floors = StrainScorer.edwardsBandFloors
        guard bandMinutes.count == floors.count + 1 else { return nil }
        let totalPoints = points(bandMinutes)
        var previous = 0.0
        var steps: [Step] = []
        for band in 1...floors.count {
            let minutes = bandMinutes[band]
            let rounded = shown(effortScore(bandMinutes: Array(bandMinutes.prefix(band + 1))), decimals: 1)
            let top = band < floors.count ? "\(whole(floors[band]))" : "100"
            steps.append(Step(name: effortBandNames[band - 1],
                              valueText: "\(whole(minutes)) min at \(whole(floors[band - 1]))–\(top)% of your range",
                              compareText: "each minute worth \(band)",
                              weightPercent: totalPoints > 0 ? Int((minutes * Double(band) / totalPoints * 100).rounded()) : 0,
                              points: shown(rounded - previous, decimals: 1)))
            previous = rounded
        }
        return ScoreBreakdown(start: 0, steps: steps, total: previous, decimals: 1)
    }

    private static func points(_ bandMinutes: [Double]) -> Double {
        bandMinutes.enumerated().reduce(0) { $0 + $1.element * Double($1.offset) }
    }

    private static func whole(_ value: Double) -> String { String(Int(value.rounded())) }
    private static func tenth(_ value: Double) -> String { String(format: "%.1f", value) }
}
