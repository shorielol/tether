import Foundation
import Testing
@testable import TetherCore

@Suite("On-device coach: brief and written answers")
struct CoachTests {
    private func night(_ day: Int, sleep: Double = 420, charge: Double? = 58, hrv: Double? = 52, rhr: Int? = 54,
                       drivers: [NightSummary.Driver] = []) -> NightSummary {
        NightSummary(day: String(format: "2026-11-%02d", day), sleepStart: 0, sleepEnd: 1, totalSleepMin: sleep,
                     efficiency: 0.9, deepMin: 80, remMin: 90, lightMin: 250, disturbances: 3, restingHR: rhr,
                     hrv: hrv, respRate: 14.5, charge: charge, rest: 80,
                     drivers: drivers, stages: [], skinTempDevC: 0.3, effort: 40)
    }

    private var input: Coach.Input {
        let drivers = [NightSummary.Driver(label: "HRV", valueText: "44 ms", deltaPoints: -9),
                       NightSummary.Driver(label: "Sleep", valueText: "6h 10m", deltaPoints: -4),
                       NightSummary.Driver(label: "Resting HR", valueText: "52", deltaPoints: 2)]
        let week = (16...22).map { night($0, sleep: Double(400 + $0)) }
        return Coach.Input(lastNight: night(23, sleep: 370, charge: 41, hrv: 44, drivers: drivers), week: week,
                           effortToday: 22, sleepNeedMin: 560, bedtimeMinute: 22 * 60, warning: .clear,
                           journal: ["Alcohol: Charge 8 lower the next morning."])
    }

    @Test func theBriefCarriesLastNightAndTheWeekInPlainLines() {
        let brief = Coach.brief(input)
        #expect(brief.contains("Charge 41%"))
        #expect(brief.contains("HRV 44 ms"))
        #expect(brief.contains("Skin temperature +0.3"))
        #expect(brief.contains("HRV (44 ms) took 9 points off Charge"), "biggest drivers, in Charge points")
        #expect(brief.contains("Average sleep over the last 7 nights: 6h 59m"))
        #expect(brief.contains("Alcohol"))
        #expect(!brief.contains("nil"))
    }

    @Test func questionsRouteToATopic() {
        #expect(Coach.topic(for: "Why is my Charge low?") == .charge)
        #expect(Coach.topic(for: "how did I sleep this week") == .sleep)
        #expect(Coach.topic(for: "Should I train hard today?") == .effort)
        #expect(Coach.topic(for: "am i getting sick") == .health)
        #expect(Coach.topic(for: "hello") == .overview)
    }

    @Test func theWrittenChargeAnswerNamesWhatPulledItDown() {
        let answer = Coach.writtenAnswer(to: "Why is my Charge low?", input)
        #expect(answer.contains("41%"))
        #expect(answer.contains("HRV"))
        #expect(answer.contains("9 points"))
    }

    @Test func theWrittenEffortAnswerUsesTodaysTargetBand() {
        let answer = Coach.writtenAnswer(to: "How hard should I push today?", input)
        #expect(answer.contains("35–55"), "Charge 41 is the yellow zone")
    }

    @Test func withNoNightsItSaysSoInsteadOfGuessing() {
        let empty = Coach.Input(lastNight: nil, week: [], effortToday: nil, sleepNeedMin: nil, bedtimeMinute: nil,
                                warning: nil, journal: [])
        #expect(!Coach.hasData(empty))
        #expect(Coach.writtenAnswer(to: "Why is my Charge low?", empty).contains("no nights"))
    }
}
