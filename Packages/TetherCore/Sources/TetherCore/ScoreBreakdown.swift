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
        public let points: Int
        public var id: String { name }
    }

    public let start: Int
    public let steps: [Step]
    public let total: Int

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
        var previous = Int(startScore.rounded())
        var steps: [Step] = []
        for move in moves {
            move.apply(&running)
            guard let score = running.charge() else { return nil }
            let rounded = Int(score.rounded())
            steps.append(Step(name: move.name, valueText: move.value, compareText: move.compare,
                              weightPercent: Int((move.weight / totalWeight * 100).rounded()),
                              points: rounded - previous))
            previous = rounded
        }
        return ScoreBreakdown(start: Int(startScore.rounded()), steps: steps, total: previous)
    }

    private static func whole(_ value: Double) -> String { String(Int(value.rounded())) }
    private static func tenth(_ value: Double) -> String { String(format: "%.1f", value) }
}
