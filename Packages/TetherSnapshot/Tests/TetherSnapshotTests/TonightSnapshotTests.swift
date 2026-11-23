import Foundation
import Testing
@testable import TetherSnapshot

@Suite("Tonight snapshot and skin temp for the widgets")
struct TonightSnapshotTests {
    private func store() -> SnapshotStore { SnapshotStore(defaults: UserDefaults(suiteName: "tonight-\(UUID().uuidString)")!) }

    @Test func tonightRoundTripsAndOnlyReportsAChangeWhenSomethingMoved() throws {
        let store = store()
        let tonight = TonightSnapshot(savedAt: 1, needMin: 560, bedtimeMinute: 22 * 60 + 15,
                                      alarmMinute: 7 * 60, alarmConfirmed: true)
        #expect(try store.writeTonight(tonight))
        #expect(store.readTonight() == tonight)
        let later = TonightSnapshot(savedAt: 99, needMin: 560, bedtimeMinute: 22 * 60 + 15,
                                    alarmMinute: 7 * 60, alarmConfirmed: true)
        #expect(try !store.writeTonight(later), "same numbers, later time: no widget reload")
        let moved = TonightSnapshot(savedAt: 120, needMin: 560, bedtimeMinute: 22 * 60 + 15,
                                    alarmMinute: nil, alarmConfirmed: false)
        #expect(try store.writeTonight(moved))
    }

    @Test func clockTimesReadAsHoursAndMinutes() {
        #expect(TonightSnapshot.clock(22 * 60 + 5) == "22:05")
        #expect(TonightSnapshot.clock(-30) == "23:30")
        #expect(TonightSnapshot.clock(24 * 60 + 10) == "00:10")
    }

    @Test func skinTempShowsAsASignedChange() {
        #expect(MorningSnapshot.signedDelta(0.34) == "+0.3°")
        #expect(MorningSnapshot.signedDelta(-0.26) == "−0.3°")
        #expect(MorningSnapshot.signedDelta(0.02) == "0.0°")
    }

    @Test func aMorningSavedBeforeSkinTempStillLoads() throws {
        let defaults = UserDefaults(suiteName: "old-\(UUID().uuidString)")!
        let old = #"{"wakeDay":"2026-11-22","savedAt":1,"sleepMin":420,"rest":80,"charge":60,"baselineNights":5,"restingHR":50}"#
        defaults.set(Data(old.utf8), forKey: SnapshotStore.key)
        let read = SnapshotStore(defaults: defaults).read()
        #expect(read?.charge == 60)
        #expect(read?.skinTempDevC == nil)
    }
}
