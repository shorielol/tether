import Foundation
import Testing
@testable import TetherSnapshot

@Suite("Morning snapshot")
struct SnapshotTests {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }()

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func snapshot(wakeDay: String = "2026-11-22", charge: Double? = 64, nights: Int = 6) -> MorningSnapshot {
        MorningSnapshot(wakeDay: wakeDay, savedAt: 1_795_400_000, sleepMin: 432, rest: 78, charge: charge,
                        baselineNights: nights, restingHR: 51)
    }

    @Test func theWakeDayTurnsOverAtFourInTheMorning() {
        #expect(WakeDay.key(for: Self.date(22, 3, 59), calendar: Self.calendar) == "2026-11-21")
        #expect(WakeDay.key(for: Self.date(22, 4, 0), calendar: Self.calendar) == "2026-11-22")
        #expect(WakeDay.key(for: Self.date(22, 23, 30), calendar: Self.calendar) == "2026-11-22")
    }

    @Test func theNextBoundaryIsTheComingFourOClock() {
        #expect(WakeDay.nextBoundary(after: Self.date(22, 3, 0), calendar: Self.calendar) == Self.date(22, 4))
        #expect(WakeDay.nextBoundary(after: Self.date(22, 4, 0), calendar: Self.calendar) == Self.date(23, 4))
        #expect(WakeDay.nextBoundary(after: Self.date(22, 9, 15), calendar: Self.calendar) == Self.date(23, 4))
    }

    @Test func aSnapshotIsFreshOnlyOnItsOwnWakeDay() {
        let snap = Self.snapshot()
        #expect(snap.isFresh(at: Self.date(22, 7), calendar: Self.calendar))
        #expect(snap.isFresh(at: Self.date(23, 3, 59), calendar: Self.calendar))
        #expect(!snap.isFresh(at: Self.date(23, 4), calendar: Self.calendar))
        #expect(!snap.isFresh(at: Self.date(22, 3), calendar: Self.calendar))
    }

    @Test func chargeWaitsForTheBaseline() {
        #expect(Self.snapshot(charge: nil, nights: 2).chargeProgress == 0.5)
        #expect(Self.snapshot(charge: nil, nights: 7).chargeProgress == 1)
        #expect(MorningSnapshot.chargeNightsNeeded == 4)
    }

    @Test func itRoundTripsThroughTheStore() throws {
        let suite = "tether.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SnapshotStore(defaults: defaults)
        #expect(store.read() == nil)
        try store.write(Self.snapshot())
        #expect(store.read() == Self.snapshot())
    }

    @Test func missingValuesStayMissing() throws {
        let empty = MorningSnapshot(wakeDay: "2026-11-22", savedAt: 1, sleepMin: nil, rest: nil, charge: nil,
                                    baselineNights: 0, restingHR: nil)
        let data = try JSONEncoder().encode(empty)
        let back = try JSONDecoder().decode(MorningSnapshot.self, from: data)
        #expect(back == empty)
        #expect(back.sleepMin == nil && back.restingHR == nil)
    }

    @Test func aCorruptStoredValueReadsAsNothing() throws {
        let suite = "tether.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: SnapshotStore.key)
        #expect(SnapshotStore(defaults: defaults).read() == nil)
    }
}
