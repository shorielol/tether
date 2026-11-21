import Foundation
import Testing
@preconcurrency import WhoopProtocol
import TetherCore
@testable import TetherFiles

@Suite("Day files")
struct DayFileTests {
    static let start = 1_795_305_600

    static let today = TodaySnapshot(
        window: start...(start + 3_600), maxHR: 196,
        minuteSeries: [.init(ts: start, bpm: 61.25, segment: 0), .init(ts: start + 60, bpm: 63.5, segment: 0),
                       .init(ts: start + 900, bpm: 70, segment: 1)],
        minBPM: 58, avgBPM: 64, maxBPM: 74, zoneMinutes: [3, 1, 0, 0, 0], restingHR: 55,
        restingSource: .lowestFiveMinutes, effort: 12.75, caloriesTotal: 210, caloriesActive: 40, hrvNow: 48.3,
        stressHours: [.init(hour: 9, level: 1.5, wasActive: false), .init(hour: 10, level: nil, wasActive: true)],
        coverage: CoverageReport(window: start...(start + 3_600), capturedSeconds: 3_100,
                                 gaps: [(start + 300)...(start + 800)]))

    static let night = NightSummary(
        day: "2026-11-22", sleepStart: start - 3_600, sleepEnd: start + 25_200, totalSleepMin: 452.5,
        efficiency: 0.91, deepMin: 80, remMin: 110, lightMin: 262.5, disturbances: 4, restingHR: 51, hrv: 57.2,
        respRate: 14.6, charge: 64, rest: 78,
        drivers: [.init(label: "HRV", valueText: "6 ms above your average, really", deltaPoints: 7)],
        stages: [.init(start: start - 3_600, end: start - 1_800, kind: .light),
                 .init(start: start - 1_800, end: start, kind: .deep)])

    @Test func aFullDayRoundTrips() throws {
        let record = DayRecord(day: "2026-11-22", savedAt: Self.start + 4_000, strapBatteryPct: 61,
                               today: Self.today, night: Self.night)
        let text = DayFile.write(record)
        #expect(text.hasPrefix("---\ntether: 1\n"))
        #expect(text.contains("charge: 64"))
        #expect(try DayFile.read(text) == record)
    }

    @Test func aNewerFormatIsRefused() {
        let text = DayFile.write(DayRecord(day: "2026-11-22", savedAt: 1, strapBatteryPct: nil, today: nil, night: nil))
            .replacingOccurrences(of: "tether: 1", with: "tether: 9")
        #expect(throws: DayFile.ReadError.unsupportedVersion(9)) { try DayFile.read(text) }
    }

    @Test func missingKeysMeanNotMeasured() throws {
        let bare = DayRecord(day: "2026-11-22", savedAt: 5, strapBatteryPct: nil, today: nil, night: nil)
        let back = try DayFile.read(DayFile.write(bare))
        #expect(back == bare)
        #expect(!DayFile.write(bare).contains("charge:"))
    }

    @Test func inboxSamplesRoundTrip() throws {
        let hr = [HRSample(ts: 100, bpm: 58), HRSample(ts: 101, bpm: 59)]
        let rr = [RRInterval(ts: 100, rrMs: 1_030, ord: 0, seq: 0), RRInterval(ts: 101, rrMs: 1_010, ord: 1, seq: 1)]
        let back = try InboxFile.read(InboxFile.write(hr: hr, rr: rr))
        #expect(back.hr == hr)
        #expect(back.rr.map(\.rrMs) == [1_030, 1_010])
        #expect(back.rr.map(\.ts) == [100, 101])
    }

    @Test func pathsFollowTheFolderLayout() {
        #expect(DayFile.relativePath(day: "2026-11-22") == "days/2026/11/2026-11-22.md")
    }
}
