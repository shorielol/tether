import Foundation
import StrandAnalytics

/// Fitness age with NOOP's `FitnessAgeEngine` (the Nes 2011 model): your last week's resting heart rate
/// and how active it was, against an average adult. A fitness comparison, not a biological age. The
/// formula is for adults 20–80, so younger people get a plain "starts at 20" instead of a guess.
public enum FitnessAge {
    public enum Reading: Sendable, Equatable {
        case tooYoung(startsAt: Int)
        case needsMoreDays(have: Int, need: Int)
        case estimate(years: Int, band: Int, actualAge: Int)
    }

    static let daysNeeded = 4
    /// An Effort this high counts the day as active (the engine maps Effort 30 to light-moderate).
    static let activeEffort = 30.0

    public static func compute(nights: [NightSummary], age: Int, sex: String) -> Reading {
        guard Double(age) >= FitnessAgeEngine.minAge else { return .tooYoung(startsAt: Int(FitnessAgeEngine.minAge)) }
        let week = nights.sorted { $0.day < $1.day }.suffix(7)
        let resting = week.compactMap(\.restingHR).map(Double.init).sorted()
        guard resting.count >= daysNeeded else { return .needsMoreDays(have: resting.count, need: daysNeeded) }
        let medianRHR = resting[resting.count / 2]
        let active = week.compactMap(\.effort).filter { $0 >= activeEffort }
        let pai = FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: active.count,
            meanActiveStrain: active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count))
        guard let result = FitnessAgeEngine.compute(age: Double(age), sex: sex, restingHR: medianRHR, paIndex: pai) else {
            return .needsMoreDays(have: resting.count, need: daysNeeded)
        }
        return .estimate(years: Int(result.fitnessAge.rounded()), band: Int(result.bandYears), actualAge: age)
    }
}
