import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// A day in UTC built from pieces of steady heart rate, each with its own beat-to-beat spread.
enum SyntheticDay {
    static let dayStart = SyntheticNight.dayStart

    static func at(_ hour: Double) -> Int { dayStart + Int(hour * 3_600) }

    /// `(from hour, to hour, bpm, R-R spread in ms)`. A wide spread reads as relaxed, a narrow one as tense.
    static func streams(_ pieces: [(Double, Double, Int, Int)]) -> (hr: [HRSample], rr: [RRInterval]) {
        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        var seq = 0
        for (from, to, bpm, spread) in pieces {
            var t = Double(at(from))
            let end = Double(at(to))
            while t < end {
                let second = Int(t)
                if hr.last?.ts != second { hr.append(HRSample(ts: second, bpm: bpm)) }
                let ms = 60_000 / bpm + (seq.isMultiple(of: 2) ? spread : -spread)
                rr.append(RRInterval(ts: second, rrMs: ms, ord: 0, seq: seq))
                seq += 1
                t += Double(ms) / 1_000
            }
        }
        return (hr, rr)
    }

    /// Relaxed 07:00–09:00, an ordinary morning 09:00–12:00, tense 13:00–17:00.
    static let calmThenTense: [(Double, Double, Int, Int)] = [(7, 9, 54, 70), (9, 12, 64, 40), (13, 17, 86, 4)]
}

@Suite("Stress in depth")
struct StressDetailTests {
    private let day = SyntheticDay.streams(SyntheticDay.calmThenTense)

    @Test func calmMorningAndTenseAfternoonLandInTheirBands() throws {
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, tzOffsetSeconds: 0)
        let early = try #require(detail.hours.first { $0.hour == 7 })
        let morning = try #require(detail.hours.first { $0.hour == 10 })
        let afternoon = try #require(detail.hours.first { $0.hour == 15 })
        #expect(early.band == .calm)
        #expect(morning.band == .usual)
        #expect(afternoon.band == .high)
        #expect(morning.meanHR == 64)
        #expect(afternoon.meanHR == 86)
        #expect((morning.hrv ?? 0) > (afternoon.hrv ?? 0))
    }

    @Test func minutesInEachBandCountWhatWasRecorded() {
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, tzOffsetSeconds: 0)
        #expect(detail.calmMinutes == 120)
        #expect(detail.usualMinutes == 180)
        #expect(detail.highMinutes == 240)
    }

    @Test func thePeakIsInTheAfternoonAndTheTimelineIsHalfHourly() throws {
        let detail = StressDetail.compute(hr: day.hr, rr: day.rr, tzOffsetSeconds: 0)
        let peak = try #require(detail.peak)
        #expect((13...16).contains(peak.hour))
        #expect(detail.timeline.count > detail.hours.filter { $0.level != nil }.count)
        let steps = zip(detail.timeline.dropFirst(), detail.timeline).map { $0.ts - $1.ts }
        #expect(steps.allSatisfy { $0 >= 1_800 })
        #expect(detail.dayBand != nil)
    }

    @Test func anEmptyDayHasNothingToSay() {
        let detail = StressDetail.compute(hr: [], rr: [], tzOffsetSeconds: 0)
        #expect(detail.hours.isEmpty)
        #expect(detail.dayBand == nil)
        #expect(detail.peak == nil)
    }

    @Test(arguments: [(0.4, StressBand.calm), (1.0, .usual), (1.99, .usual), (2.0, .high), (3, .high)])
    func bandsFollowTheSharedScale(level: Double, band: StressBand) {
        #expect(StressBand(level: level) == band)
    }
}

@Suite("Effort and zones in depth")
struct EffortDetailTests {
    private let maxHR = 196
    private let minute = 1.0 / 60

    /// Rest, a 30-minute run at 160 bpm, a known drop after it, a 3-minute burst later on.
    private var day: (hr: [HRSample], rr: [RRInterval]) {
        SyntheticDay.streams([
            (8, 10, 60, 30), (10, 10.5, 160, 3), (10.5, 10.5 + minute, 130, 5),
            (10.5 + minute, 10.5 + 2 * minute, 115, 8), (10.5 + 2 * minute, 12, 70, 25),
            (12, 12 + 3 * minute, 180, 3), (12 + 3 * minute, 13, 68, 25),
        ])
    }

    private func detail() -> EffortDetail {
        EffortDetail.compute(hr: day.hr, maxHR: maxHR, restingHR: 60, sex: "male", tzOffsetSeconds: 0)
    }

    @Test func oneHardStretchWithItsRecovery() throws {
        let stretches = detail().stretches
        #expect(stretches.count == 1)
        let run = try #require(stretches.first)
        #expect(run.start == SyntheticDay.at(10))
        #expect(run.minutes == 30)
        #expect(run.averageBPM == 160)
        #expect(run.peakBPM == 160)
        #expect(run.topZone == 4)
        #expect(run.dropAfterOneMinute == 30)
        #expect(run.dropAfterTwoMinutes == 45)
    }

    @Test func zonesCarryYourOwnBPMRanges() throws {
        let zones = detail().zones
        #expect(zones.map(\.number) == [1, 2, 3, 4, 5])
        #expect(zones[0].lowerBPM == 98)
        #expect(zones[2].lowerBPM == 137)
        #expect(zones[3].minutes == 30)
    }

    @Test func hourlyAveragesAndAnEffortCurveThatOnlyClimbs() throws {
        let effort = detail()
        let eight = try #require(effort.hourly.first { $0.hour == 8 })
        #expect(eight.averageBPM == 60)
        #expect(effort.effortCurve.count >= 4)
        let values = effort.effortCurve.map(\.effort)
        #expect(zip(values.dropFirst(), values).allSatisfy { $0 >= $1 })
        #expect((values.last ?? 0) > (values.first ?? 0))
    }

    @Test func anEmptyDayHasNoStretchesOrCurve() {
        let effort = EffortDetail.compute(hr: [], maxHR: maxHR, restingHR: 60, sex: "male", tzOffsetSeconds: 0)
        #expect(effort.stretches.isEmpty)
        #expect(effort.effortCurve.isEmpty)
        #expect(effort.zones.count == 5)
    }
}

@Suite("Recovery in depth")
struct RecoveryDetailTests {
    private func night(_ day: Int, hrv: Double?, resting: Int?, charge: Double? = nil,
                       asleep: Double = 400) -> NightSummary {
        NightSummary(day: String(format: "2026-11-%02d", day), sleepStart: 0, sleepEnd: 1, totalSleepMin: asleep,
                     efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil, disturbances: 1, restingHR: resting,
                     hrv: hrv, respRate: 14.5, charge: charge, rest: nil,
                     drivers: [NightSummary.Driver(label: "HRV", valueText: "6 ms above your normal", deltaPoints: 8)],
                     stages: [])
    }

    @Test func theFirstNightHasValuesButNoNormalYet() throws {
        let detail = try #require(RecoveryDetail.compute(latest: night(22, hrv: 77, resting: 56), history: []))
        let hrv = try #require(detail.measures.first { $0.name == "HRV" })
        #expect(hrv.value == 77)
        #expect(hrv.normal == nil)
        #expect(hrv.delta == nil)
        #expect(detail.zone == nil)
        #expect(detail.nightsUntilCharge == 3)
    }

    @Test func aBaselineGivesANormalAndTheDifference() throws {
        let earlier = [60.0, 62, 64, 66, 68].enumerated().map { night(15 + $0.offset, hrv: $0.element, resting: 55) }
        let latest = night(22, hrv: 70, resting: 52, charge: 72)
        let detail = try #require(RecoveryDetail.compute(latest: latest, history: earlier + [latest]))
        let hrv = try #require(detail.measures.first { $0.name == "HRV" })
        #expect(hrv.normal == 64)
        #expect(hrv.delta == 6)
        let resting = try #require(detail.measures.first { $0.name == "Resting HR" })
        #expect(resting.delta == -3)
        #expect(resting.isBetter == true)
        #expect(detail.zone == .green)
        #expect(detail.nightsUntilCharge == 0)
        #expect(detail.drivers.count == 1)
    }

    @Test func theTrendShowsTheLastSevenNightsInOrder() {
        let nights = (10...21).map { night($0, hrv: Double($0), resting: 50) }
        let latest = night(22, hrv: 22, resting: 50)
        let detail = RecoveryDetail.compute(latest: latest, history: nights + [latest])
        #expect(detail?.recent.map(\.day) == (16...22).map { String(format: "2026-11-%02d", $0) })
    }

    @Test func noNightMeansNoRecovery() {
        #expect(RecoveryDetail.compute(latest: nil, history: []) == nil)
    }
}
