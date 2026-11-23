import Foundation
import Testing
@preconcurrency import WhoopStore
@testable import TetherCore

/// Phase 6 journal: a few taps each morning about yesterday, and after enough mornings, what moves Charge.
@Suite("Journal")
struct JournalTests {
    private func day(_ index: Int) -> String { String(format: "2026-10-%02d", index + 1) }

    private func night(_ index: Int, charge: Double) -> NightSummary {
        NightSummary(day: day(index), sleepStart: 0, sleepEnd: 1, totalSleepMin: 420, efficiency: 0.9, deepMin: nil,
                     remMin: nil, lightMin: nil, disturbances: nil, restingHR: nil, hrv: nil, respRate: nil,
                     charge: charge, rest: nil, drivers: [], stages: [])
    }

    /// 20 mornings; alcohol on every fourth, with Charge about 15 lower the morning after.
    private var month: (entries: [JournalEntry], nights: [NightSummary]) {
        var entries: [JournalEntry] = []
        var nights: [NightSummary] = []
        for i in 0..<20 {
            let drank = i % 4 == 0
            entries += JournalDay.entries(day: day(i), yes: drank ? [.alcohol] : [])
            nights.append(night(i, charge: (drank ? 50 : 65) + Double(i % 3)))
        }
        return (entries, nights)
    }

    @Test func aMorningSavesEveryQuestionYesOrNo() {
        let entries = JournalDay.entries(day: "2026-11-23", yes: [.alcohol, .screensInBed])
        #expect(entries.count == JournalQuestion.allCases.count)
        #expect(entries.filter(\.answeredYes).map(\.question).sorted() == [JournalQuestion.alcohol.rawValue, JournalQuestion.screensInBed.rawValue].sorted())
    }

    @Test func enoughMorningsShowWhatMovesCharge() throws {
        let insights = JournalInsights.compute(entries: month.entries, nights: month.nights)
        let alcohol = try #require(insights.first { $0.question == .alcohol })
        #expect(alcohol.difference < -10)
        #expect(alcohol.clear)
        #expect(alcohol.sentence.contains("Alcohol"))
        #expect(insights.allSatisfy { $0.question != .nap }, "never logged: nothing to compare")
    }

    @Test func tooFewMorningsSayNothingYet() {
        let few = (month.entries.filter { $0.day <= day(5) }, month.nights)
        #expect(JournalInsights.compute(entries: few.0, nights: few.1).isEmpty)
        #expect(JournalInsights.morningsLogged(few.0) == 6)
    }

    @Test func aMorningIsSavedAndReadBack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sink = WhoopStoreSink(path: directory.appendingPathComponent("tether.sqlite").path)
        try await sink.saveJournal(day: "2026-11-23", yes: [.caffeineLate])
        try await sink.saveJournal(day: "2026-11-23", yes: [.nap])
        let read = try await sink.journal(from: "2026-11-01", to: "2026-11-30")
        #expect(read.filter(\.answeredYes).map(\.question) == [JournalQuestion.nap.rawValue], "a re-save replaces the morning")
    }
}
