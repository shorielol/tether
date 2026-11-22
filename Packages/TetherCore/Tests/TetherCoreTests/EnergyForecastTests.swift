import Foundation
import Testing
@testable import TetherCore

/// The energy forecast: sleep pressure building through the day against your body clock.
@Suite("Energy forecast")
struct EnergyForecastTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let base = 1_794_268_800   // 2026-11-10 00:00 UTC

    private func nights(bed: Double, wake: Double, count: Int = 5, asleepFraction: Double = 0.93) -> [NightSummary] {
        (0..<count).map { index in
            let dayStart = base + index * 86_400
            let start = dayStart + Int(bed * 3_600) - (bed > 12 ? 86_400 : 0), end = dayStart + Int(wake * 3_600)
            return NightSummary(day: DayScorer.dayKey(dayStart: dayStart, timeZone: utc), sleepStart: start, sleepEnd: end,
                                totalSleepMin: Double(end - start) / 60 * asleepFraction, efficiency: asleepFraction,
                                deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHR: nil, hrv: nil,
                                respRate: nil, charge: nil, rest: nil, drivers: [], stages: [])
        }
    }

    private func forecast(_ nights: [NightSummary], owed: Double = 0) -> EnergyForecast? {
        EnergyForecast.compute(nights: nights, owedSleepMin: owed, timeZone: utc)
    }

    @Test func aLaterScheduleShiftsTheDayLater() throws {
        let early = try #require(forecast(nights(bed: 22, wake: 6)))
        let late = try #require(forecast(nights(bed: 1, wake: 9)))
        #expect(late.bestWindow.lowerBound > early.bestWindow.lowerBound)
        #expect(late.dipMinute > early.dipMinute)
    }

    @Test func shortNightsLowerTheCurveAndOpenANapWindow() throws {
        let rested = try #require(forecast(nights(bed: 22, wake: 7)))
        let short = try #require(forecast(nights(bed: 1.5, wake: 6.5), owed: 150))
        let mean = { (f: EnergyForecast) in f.points.map(\.level).reduce(0, +) / Double(f.points.count) }
        #expect(mean(short) < mean(rested))
        #expect(rested.napWindow == nil)
        let nap = try #require(short.napWindow)
        #expect(nap.contains(short.dipMinute))
    }

    @Test func theCoffeeCutOffIsEightHoursBeforeYourUsualSleep() throws {
        let plan = try #require(forecast(nights(bed: 23, wake: 7)))
        #expect(plan.coffeeCutoffMinute == 15 * 60)
    }

    @Test func theBestWindowIsWhereTheCurveIsHighest() throws {
        let plan = try #require(forecast(nights(bed: 22.5, wake: 6.5)))
        let inside = plan.points.filter { plan.bestWindow.contains($0.minute) }.map(\.level)
        let outside = plan.points.filter { !plan.bestWindow.contains($0.minute) }.map(\.level)
        #expect(inside.reduce(0, +) / Double(inside.count) > outside.reduce(0, +) / Double(outside.count))
        #expect(plan.points.allSatisfy { (0...100).contains($0.level) })
    }

    @Test func theDipIsEarlyAfternoonForAUsualSchedule() throws {
        let plan = try #require(forecast(nights(bed: 23, wake: 7)))
        #expect((13 * 60...15 * 60).contains(plan.dipMinute))
    }

    @Test func withoutHistoryItSaysNothing() {
        #expect(forecast(nights(bed: 22, wake: 6, count: 2)) == nil)
    }
}
