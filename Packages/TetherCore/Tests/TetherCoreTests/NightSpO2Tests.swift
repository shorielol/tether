import Foundation
import Testing
@testable import TetherCore

@Suite("Blood oxygen from the strap's own nightly reading")
struct NightSpO2Tests {
    private let start = 1_795_420_000
    private var end: Int { start + 6 * 3_600 }

    /// One reading every 40 s from the start of sleep, as the strap sends them.
    private func night(_ values: [Int], from first: Int? = nil) -> [(ts: Int, value: Int)] {
        values.enumerated().map { (ts: (first ?? start) + $0.offset * 40, value: $0.element) }
    }

    @Test func lastNightsRealValuesGiveAMedianOf95() throws {
        let counts = [95: 147, 96: 137, 94: 61, 97: 34, 93: 31, 92: 5]
        let values = counts.flatMap { Array(repeating: $0.key, count: $0.value) }.shuffled()
        let reading = try #require(NightSpO2.compute(day: "2026-11-23", readings: night(values), sleepStart: start, sleepEnd: end))
        #expect(reading.median == 95)
        #expect(reading.low == 93)
        #expect(reading.minutesBelow90 == 0)
        #expect(reading.readings == 415)
    }

    @Test func codesAndZerosAreNotReadings() throws {
        let values = Array(repeating: 96, count: 70) + [0, 0, 2, 4, 32, 128, 160, 255]
        let reading = try #require(NightSpO2.compute(day: "d", readings: night(values), sleepStart: start, sleepEnd: end))
        #expect(reading.readings == 70)
        #expect(reading.median == 96)
    }

    @Test func dipsBelow90CountAsMinutes() throws {
        let values = Array(repeating: 95, count: 60) + Array(repeating: 88, count: 9)   // 9 × 40 s = 6 min
        let reading = try #require(NightSpO2.compute(day: "d", readings: night(values), sleepStart: start, sleepEnd: end))
        #expect(reading.minutesBelow90 == 6)
        #expect(reading.low == 88)
    }

    @Test func onlyReadingsInsideSleepCount() {
        let before = night(Array(repeating: 97, count: 100), from: start - 10_000)
        let inside = night(Array(repeating: 95, count: 30))
        #expect(NightSpO2.compute(day: "d", readings: before + inside, sleepStart: start, sleepEnd: end) == nil,
                "30 readings inside sleep is under the 60 needed")
    }

    @Test func nightsAreKeptAfterTheRawRowsAreGone() {
        let defaults = UserDefaults(suiteName: "spo2-\(UUID().uuidString)")!
        let one = NightSpO2(day: "2026-11-22", median: 95, low: 93, minutesBelow90: 0, readings: 400)
        let two = NightSpO2(day: "2026-11-23", median: 96, low: 94, minutesBelow90: 1, readings: 410)
        NightSpO2.save([two, one], defaults: defaults)
        NightSpO2.save([NightSpO2(day: "2026-11-23", median: 97, low: 95, minutesBelow90: 0, readings: 420)], defaults: defaults)
        #expect(NightSpO2.load(defaults: defaults).map(\.day) == ["2026-11-22", "2026-11-23"])
        #expect(NightSpO2.load(defaults: defaults).last?.median == 97, "a rescored night replaces the old one")
    }
}
