import Foundation
import Testing
@testable import TetherSnapshot

@Suite("Recording card")
struct RecordingStatusTests {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }()

    static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: hour, minute: minute))!
    }

    static func status(link: RecordingStatus.Link = .solid, start: Date = at(23), now: Date = at(23, 30),
                       captured: Int, hr: Int? = 57, battery: Int? = 58) -> RecordingStatus {
        RecordingStatus.make(heartRate: hr, link: link, startedAt: start, now: now, capturedSeconds: captured,
                             strapBattery: battery, calendar: calendar)
    }

    @Test func aFullRecordingMissesNothing() {
        let s = Self.status(captured: 1_800)
        #expect(s.subtitle == "Link solid · nothing missed")
        #expect(s.coveragePercent == 100 && s.missedMinutes == 0)
    }

    @Test func aMinuteOfStartupLagIsNotAGap() {
        // The first sample and the 30 s flush lag shouldn't read as missing data.
        let s = Self.status(captured: 1_800 - 50)
        #expect(s.missedMinutes == 0 && s.coveragePercent == 100)
    }

    @Test func gapsAreCountedInWholeMinutes() {
        let s = Self.status(captured: 1_800 - 60 - 6 * 60 - 20)
        #expect(s.missedMinutes == 6)
        #expect(s.subtitle == "Link solid · 6 min missed")
        #expect(s.coveragePercent == 79)
    }

    @Test func longGapsReadInHours() {
        let s = Self.status(start: Self.at(22), now: Self.at(23, 30), captured: 5_400 - 60 - 75 * 60)
        #expect(s.subtitle == "Link solid · 1 h 15 min missed")
    }

    @Test func reconnectingAndLostSayWhatIsHappening() {
        #expect(Self.status(link: .reconnecting, captured: 1_800).subtitle == "Reconnecting…")
        #expect(Self.status(link: .reconnecting, captured: 1_000).subtitle == "Reconnecting · 12 min missed")
        #expect(Self.status(link: .lost, captured: 1_000, hr: nil).subtitle == "Strap not linked · 12 min missed")
    }

    @Test func coverageWaitsForAMinute() {
        #expect(Self.status(now: Self.at(23, 0) + 30, captured: 30).coveragePercent == nil)
    }

    @Test func theTitleFollowsTheClock() {
        #expect(Self.status(start: Self.at(23), now: Self.at(23, 30), captured: 1_800).title == "Recording your night")
        #expect(Self.status(start: Self.at(9), now: Self.at(9, 30), captured: 1_800).title == "Recording your night")
        #expect(Self.status(start: Self.at(13), now: Self.at(13, 30), captured: 1_800).title == "Recording")
    }

    @Test func itRoundTripsAsActivityContent() throws {
        let s = Self.status(captured: 1_200)
        #expect(try JSONDecoder().decode(RecordingStatus.self, from: JSONEncoder().encode(s)) == s)
    }
}
