import Testing
@testable import TetherCore

@Suite("Your normal band")
struct NormalBandTests {
    @Test func needsThreeEarlierNights() {
        #expect(NormalBand(past: [50, 60]) == nil)
        #expect(NormalBand(past: [50, 60, 70]) != nil)
    }

    @Test func isTheMiddleHalfOfEarlierNights() throws {
        let band = try #require(NormalBand(past: [40, 50, 60, 70, 80]))
        #expect(band.low == 50)
        #expect(band.high == 70)
        #expect(band.contains(60))
        #expect(!band.contains(45))
    }

    @Test func widensAroundTheMiddleWhenNightsAreAllAlike() throws {
        let band = try #require(NormalBand(past: [56, 56, 56], minWidth: 4))
        #expect(band.low == 54)
        #expect(band.high == 58)
    }
}

@Suite("Where a value sits on its bar")
struct RangePlacementTests {
    @Test func placesValueAndBandAsFractionsOfTheBar() throws {
        let band = try #require(NormalBand(past: [40, 50, 60, 70, 80]))
        let place = RangePlacement(value: 25, band: band, domain: 0...100)
        #expect(place.value == 0.25)
        #expect(place.band == 0.5...0.7)
        #expect(place.isInsideBand == false)
    }

    @Test func clampsValuesOffTheEnds() {
        #expect(RangePlacement(value: 140, band: nil, domain: 0...100).value == 1)
        #expect(RangePlacement(value: -5, band: nil, domain: 0...100).value == 0)
    }

    @Test func withoutABandThereIsNoVerdict() {
        let place = RangePlacement(value: 50, band: nil, domain: 0...100)
        #expect(place.band == nil)
        #expect(place.isInsideBand == nil)
    }

    @Test func domainAroundABandKeepsTheValueOnTheBar() throws {
        let band = try #require(NormalBand(past: [50, 55, 60]))
        let domain = RangePlacement.domain(around: band, value: 20)
        #expect(domain.lowerBound <= 20)
        #expect(domain.upperBound > band.high)
        let place = RangePlacement(value: 20, band: band, domain: domain)
        #expect(place.value == 0)
    }
}

@Suite("The day's sentence")
struct DayLineTests {
    @Test func redChargeSaysRest() {
        let line = DayLine.sentence(zone: .red, nightsUntilCharge: 0, sleptMinutes: 480, sleepBand: nil, effort: 5)
        #expect(line.contains("Rest"))
    }

    @Test func redChargeAfterAHardDaySaysEaseOff() {
        let line = DayLine.sentence(zone: .red, nightsUntilCharge: 0, sleptMinutes: 480, sleepBand: nil, effort: 55)
        #expect(line.contains("Ease off"))
    }

    @Test func shortNightWithYellowSaysSteady() {
        let line = DayLine.sentence(zone: .yellow, nightsUntilCharge: 0, sleptMinutes: 396, sleepBand: nil, effort: 15)
        #expect(line == "A short night and a yellow Charge. Keep today steady, and an early night helps most.")
    }

    @Test func shortIsJudgedAgainstYourNormalWhenThereIsOne() throws {
        let band = try #require(NormalBand(past: [360, 370, 380]))
        let line = DayLine.sentence(zone: .yellow, nightsUntilCharge: 0, sleptMinutes: 372, sleepBand: band, effort: 15)
        #expect(line == "Charge is yellow. Keep today steady.")
    }

    @Test func greenAfterAShortNightStillSaysPush() {
        let line = DayLine.sentence(zone: .green, nightsUntilCharge: 0, sleptMinutes: 380, sleepBand: nil, effort: 0)
        #expect(line == "Charge is green, even after a short night. A good day to push.")
    }

    @Test func whileLearningItCountsTheNightsLeft() {
        let line = DayLine.sentence(zone: nil, nightsUntilCharge: 3, sleptMinutes: 396, sleepBand: nil, effort: nil)
        #expect(line == "You slept 6h 36m. Charge starts in 3 more nights.")
        let last = DayLine.sentence(zone: nil, nightsUntilCharge: 1, sleptMinutes: 396, sleepBand: nil, effort: nil)
        #expect(last == "You slept 6h 36m. Charge starts after one more night.")
    }

    @Test func withNothingYetItSaysWhatToDo() {
        let line = DayLine.sentence(zone: nil, nightsUntilCharge: 4, sleptMinutes: nil, sleepBand: nil, effort: nil)
        #expect(line == "Wear the strap tonight. Your first night shows here in the morning.")
    }
}

@Suite("A morning with no night found")
struct NoNightLineTests {
    @Test func afterLearningAMissingNightIsSaidPlainly() {
        let line = DayLine.sentence(zone: nil, nightsUntilCharge: 0, sleptMinutes: nil, sleepBand: nil, effort: 20)
        #expect(line == "No sleep found last night, so there's no Charge today.")
    }

    @Test func beforeAnyNightTheFirstNightIsAskedFor() {
        let line = DayLine.sentence(zone: nil, nightsUntilCharge: 4, sleptMinutes: nil, sleepBand: nil, effort: nil)
        #expect(line == "Wear the strap tonight. Your first night shows here in the morning.")
    }
}

@Suite("Why Charge is where it is")
struct RecoveryNoteTests {
    private func measure(_ name: String, _ value: Double, band: NormalBand?, higherIsBetter: Bool?) -> RecoveryDetail.Measure {
        RecoveryDetail.Measure(name: name, unit: "", value: value, normal: band.map { ($0.low + $0.high) / 2 },
                               band: band, decimals: 0, higherIsBetter: higherIsBetter)
    }

    @Test func namesTheFirstMeasureOffYourNormal() {
        let note = RecoveryNote.text([
            measure("HRV", 40, band: NormalBand(low: 50, high: 60), higherIsBetter: true),
            measure("Resting HR", 56, band: NormalBand(low: 54, high: 58), higherIsBetter: false),
        ])
        #expect(note == "HRV is below your normal, which pulls Charge down.")
    }

    @Test func aGoodDirectionIsNotBlamed() {
        let note = RecoveryNote.text([measure("HRV", 70, band: NormalBand(low: 50, high: 60), higherIsBetter: true)])
        #expect(note == "HRV is above your normal.")
    }

    @Test func allInsideSaysSo() {
        let note = RecoveryNote.text([measure("HRV", 55, band: NormalBand(low: 50, high: 60), higherIsBetter: true)])
        #expect(note == "Everything is in your normal range.")
    }

    @Test func withoutBandsItSaysWhenTheyArrive() {
        #expect(RecoveryNote.text([measure("HRV", 55, band: nil, higherIsBetter: true)]) == "Your normal shows after 3 nights.")
        #expect(RecoveryNote.text([]) == nil)
    }
}

@Suite("Recovery measures carry their band")
struct RecoveryBandTests {
    private func night(_ day: Int, hrv: Double, resting: Int) -> NightSummary {
        NightSummary(day: String(format: "2026-11-%02d", day), sleepStart: 0, sleepEnd: 1, totalSleepMin: 420,
                     efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                     restingHR: resting, hrv: hrv, respRate: nil, charge: nil, rest: nil, drivers: [], stages: [])
    }

    @Test func measuresGetABandFromEarlierNights() throws {
        let nights = (1...4).map { night($0, hrv: Double(40 + $0 * 5), resting: 55 + $0) }
        let detail = try #require(RecoveryDetail.compute(latest: nights.last, history: nights))
        let hrv = try #require(detail.measures.first { $0.name == "HRV" })
        let band = try #require(hrv.band)
        #expect(band.low <= 50 && band.high >= 50)
        #expect(hrv.band?.contains(hrv.value) == false)
    }

    @Test func noBandBeforeThreeEarlierNights() throws {
        let nights = (1...3).map { night($0, hrv: 50, resting: 56) }
        let detail = try #require(RecoveryDetail.compute(latest: nights.last, history: nights))
        #expect(detail.measures.allSatisfy { $0.band == nil })
    }
}
