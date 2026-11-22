import Testing
@testable import TetherCore

@Suite("Health tab vitals")
struct HealthVitalTests {
    private func night(_ day: Int, hrv: Double?, resting: Int?, resp: Double?) -> NightSummary {
        NightSummary(day: String(format: "2026-11-%02d", day), sleepStart: 0, sleepEnd: 1, totalSleepMin: 420,
                     efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                     restingHR: resting, hrv: hrv, respRate: resp, charge: nil, rest: nil, drivers: [], stages: [])
    }

    @Test func listsHrvRestingAndBreathingInOrder() {
        let vitals = HealthVital.compute(latest: night(22, hrv: 50, resting: 56, resp: 14.5), history: [])
        #expect(vitals.map(\.name) == ["HRV", "Resting HR", "Breathing", "Skin temp"])
    }

    @Test func skinTemperatureReadsInDegreesToOneDecimal() throws {
        let plain = night(22, hrv: 50, resting: 56, resp: 14.5)
        let latest = NightSummary(day: plain.day, sleepStart: 0, sleepEnd: 1, totalSleepMin: 420, efficiency: 0.9,
                                  deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHR: 56,
                                  hrv: 50, respRate: 14.5, charge: nil, rest: nil, drivers: [], stages: [],
                                  skinTempC: 33.42, skinTempDevC: 0.3)
        let skin = try #require(HealthVital.compute(latest: latest, history: []).first { $0.name == "Skin temp" })
        #expect(skin.value == 33.42)
        #expect(skin.unit == "°C")
        #expect(skin.decimals == 1)
        #expect(skin.higherIsBetter == nil)
    }

    @Test func aMeasureMissingLastNightKeepsItsRowWithNoValue() throws {
        let vitals = HealthVital.compute(latest: night(22, hrv: nil, resting: 56, resp: nil), history: [])
        let hrv = try #require(vitals.first { $0.name == "HRV" })
        #expect(hrv.value == nil)
        #expect(hrv.isOutsideNormal == false)
    }

    @Test func bandComesFromEarlierNightsOnly() throws {
        let earlier = (18...21).map { night($0, hrv: 50, resting: 56, resp: 14) }
        let latest = night(22, hrv: 30, resting: 56, resp: 14)
        let vitals = HealthVital.compute(latest: latest, history: earlier + [latest])
        let hrv = try #require(vitals.first { $0.name == "HRV" })
        let band = try #require(hrv.band)
        #expect(band.contains(50))
        #expect(!band.contains(30))
        #expect(hrv.isOutsideNormal)
        #expect(hrv.isWorse)
    }

    @Test func recentShowsUpToSevenNightsEndingLastNight() throws {
        let nights = (10...22).map { night($0, hrv: Double($0), resting: 50, resp: 14) }
        let vitals = HealthVital.compute(latest: nights.last, history: nights)
        let hrv = try #require(vitals.first { $0.name == "HRV" })
        #expect(hrv.recent.count == 7)
        #expect(hrv.recent.first?.day == "2026-11-16")
        #expect(hrv.recent.last?.value == 22)
    }

    @Test func noNightsMeansNoVitals() {
        #expect(HealthVital.compute(latest: nil, history: []).isEmpty)
    }

    @Test func summaryCountsMeasuresInsideTheirNormal() {
        let earlier = (18...21).map { night($0, hrv: 50, resting: 56, resp: 14) }
        let latest = night(22, hrv: 30, resting: 56, resp: 14)
        let vitals = HealthVital.compute(latest: latest, history: earlier + [latest])
        #expect(HealthVital.summary(vitals) == "2 of 3 in your normal")
        #expect(HealthVital.summary(HealthVital.compute(latest: latest, history: [])) == "Your normal shows after 3 nights")
    }
}
