import Foundation
import StrandAnalytics
@preconcurrency import WhoopStore

/// The morning journal's questions, about the day before. Stored by their raw value.
public enum JournalQuestion: String, CaseIterable, Sendable, Identifiable {
    case caffeineLate = "Caffeine after 2 PM"
    case alcohol = "Alcohol"
    case lateMeal = "Ate within 2 hours of bed"
    case screensInBed = "Screens in bed"
    case hardWorkout = "A hard workout"
    case stressfulDay = "A stressful day"
    case nap = "A nap"

    public var id: String { rawValue }
}

/// One morning's answers: each question yes or no, saved under the day the night ended.
public enum JournalDay {
    public static func entries(day: String, yes: Set<JournalQuestion>) -> [JournalEntry] {
        JournalQuestion.allCases.map { JournalEntry(day: day, question: $0.rawValue, answeredYes: yes.contains($0), notes: nil) }
    }
}

/// What a journal answer does to the next morning's Charge, from NOOP's `BehaviorInsights`
/// (Welch's t-test between mornings after "yes" and mornings after "no").
public struct JournalInsight: Sendable, Equatable, Identifiable {
    public let question: JournalQuestion
    /// Average Charge after "yes" minus after "no".
    public let difference: Double
    public let averageWith: Double
    public let averageWithout: Double
    public let mornings: Int
    /// True when the difference is unlikely to be chance.
    public let clear: Bool
    public var id: String { question.rawValue }

    public var sentence: String {
        let size = Int(abs(difference).rounded())
        let direction = difference >= 0 ? "higher" : "lower"
        return "After ‘\(question.rawValue)’, Charge averaged \(Int(averageWith.rounded()))% against \(Int(averageWithout.rounded()))% without: \(size) points \(direction)."
    }
}

public enum JournalInsights {
    /// Each side of a comparison needs this many mornings.
    public static let minimumEach = 3

    public static func morningsLogged(_ entries: [JournalEntry]) -> Int { Set(entries.map(\.day)).count }

    public static func compute(entries: [JournalEntry], nights: [NightSummary]) -> [JournalInsight] {
        let charge = Dictionary(nights.compactMap { night in night.charge.map { (night.day, $0) } }) { first, _ in first }
        var behaviors: [String: Set<String>] = [:]
        var controls: [String: Set<String>] = [:]
        for entry in entries {
            if entry.answeredYes { behaviors[entry.question, default: []].insert(entry.day) }
            else { controls[entry.question, default: []].insert(entry.day) }
        }
        return BehaviorInsights.rank(behaviors: behaviors, controls: controls, outcomeByDay: charge, outcome: "Charge")
            .compactMap { effect in
                guard effect.nWith >= minimumEach, effect.nWithout >= minimumEach,
                      let question = JournalQuestion(rawValue: effect.behavior) else { return nil }
                return JournalInsight(question: question, difference: effect.delta, averageWith: effect.meanWith,
                                      averageWithout: effect.meanWithout, mornings: effect.nWith + effect.nWithout,
                                      clear: effect.significant)
            }
    }
}

extension WhoopStoreSink {
    public func journal(from: String, to: String) async throws -> [JournalEntry] {
        try await openStore().journalEntries(deviceId: Self.deviceId, from: from, to: to)
            .filter { JournalQuestion(rawValue: $0.question) != nil }
    }

    /// Saves a morning, replacing any earlier answers for it.
    public func saveJournal(day: String, yes: Set<JournalQuestion>) async throws {
        try await openStore().upsertJournal(JournalDay.entries(day: day, yes: yes), deviceId: Self.deviceId)
    }
}
