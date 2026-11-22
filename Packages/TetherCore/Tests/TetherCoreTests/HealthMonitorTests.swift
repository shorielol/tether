import Foundation
import Testing
@testable import TetherCore

/// Phase 3: each vital flagged against your own normal, and a gentle early warning when several drift
/// the illness-ward way together.
@Suite("Health monitor and early warning")
struct HealthMonitorTests {
    static func night(_ index: Int, hrv: Double, rhr: Int, resp: Double, skin: Double) -> NightSummary {
        let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: index,
                                                         to: Date(timeIntervalSince1970: 1_793_000_000))!
        let key = DayScorer.dayKey(dayStart: Int(day.timeIntervalSince1970), timeZone: TimeZone(secondsFromGMT: 0)!)
        return NightSummary(day: key, sleepStart: 0, sleepEnd: 1, totalSleepMin: 420, efficiency: 0.9, deepMin: nil,
                            remMin: nil, lightMin: nil, disturbances: nil, restingHR: rhr, hrv: hrv, respRate: resp,
                            charge: nil, rest: nil, drivers: [], stages: [], skinTempC: skin)
    }

    /// `count` ordinary nights with a little night-to-night wobble.
    static func usual(_ count: Int) -> [NightSummary] {
        (0..<count).map { i in
            let wobble = Double([-1, 0, 1, 0][i % 4])
            return night(i, hrv: 60 + 3 * wobble, rhr: 52 + Int(wobble), resp: 15 + 0.3 * wobble, skin: 33.2 + 0.1 * wobble)
        }
    }

    @Test func anOrdinaryNightIsAllClear() throws {
        let history = Self.usual(20)
        let latest = Self.night(20, hrv: 61, rhr: 52, resp: 15.1, skin: 33.2)
        let report = try #require(HealthMonitor.check(latest: latest, history: history))
        #expect(report.flags.allSatisfy { !$0.outOfRange })
        #expect(report.flags.allSatisfy { $0.personal })
        #expect(report.warning == .clear)
    }

    @Test func severalSignalsOffTogetherRaiseTheWarning() throws {
        let history = Self.usual(20)
        let latest = Self.night(20, hrv: 36, rhr: 63, resp: 17.2, skin: 34.3)
        let report = try #require(HealthMonitor.check(latest: latest, history: history))
        guard case .raised(let signals) = report.warning else {
            Issue.record("expected raised, got \(report.warning)"); return
        }
        #expect(signals.count >= 2)
        #expect(report.flags.first { $0.name == "Resting HR" }?.outOfRange == true)
        #expect(report.flags.first { $0.name == "HRV" }?.outOfRange == true)
    }

    @Test func aFewSignalsSlightlyOffIsMildNotANotification() throws {
        let report = try #require(HealthMonitor.check(latest: Self.night(20, hrv: 42, rhr: 59, resp: 16.6, skin: 33.9),
                                                      history: Self.usual(20)))
        guard case .mild = report.warning else { Issue.record("expected mild, got \(report.warning)"); return }
        #expect(HealthMonitor.notification(for: report.warning, day: "2026-11-23", lastNotifiedDay: nil) == nil)
    }

    @Test func oneSignalAloneNeverRaisesIt() throws {
        let history = Self.usual(20)
        let latest = Self.night(20, hrv: 60, rhr: 60, resp: 15, skin: 33.2)
        let report = try #require(HealthMonitor.check(latest: latest, history: history))
        #expect(report.flags.first { $0.name == "Resting HR" }?.outOfRange == true)
        if case .raised = report.warning { Issue.record("one signal must not raise the warning") }
    }

    @Test func itStaysQuietWhileItIsStillLearningYourNormal() throws {
        let history = Self.usual(5)
        let latest = Self.night(5, hrv: 42, rhr: 59, resp: 16.6, skin: 33.9)
        let report = try #require(HealthMonitor.check(latest: latest, history: history))
        #expect(report.warning == .learning(nightsToGo: HealthMonitor.trustedNights - 5))
        #expect(report.flags.allSatisfy { !$0.personal }, "typical adult ranges until your own normal is trusted")
        #expect(report.flags.first { $0.name == "HRV" }?.outOfRange == false, "42 ms is inside the typical range")
    }

    @Test func theMorningNotificationGoesOnceADayAndOnlyWhenRaised() {
        let raised = HealthMonitor.Warning.raised(["resting HR +7 bpm", "HRV −30%"])
        let note = HealthMonitor.notification(for: raised, day: "2026-11-23", lastNotifiedDay: "2026-11-22")
        #expect(note?.body.contains("resting HR +7 bpm") == true)
        #expect(HealthMonitor.notification(for: raised, day: "2026-11-23", lastNotifiedDay: "2026-11-23") == nil)
        #expect(HealthMonitor.notification(for: .mild(["HRV −15%"]), day: "2026-11-23", lastNotifiedDay: nil) == nil)
        #expect(HealthMonitor.notification(for: .clear, day: "2026-11-23", lastNotifiedDay: nil) == nil)
    }

    @Test func noNightNoReport() {
        #expect(HealthMonitor.check(latest: nil, history: []) == nil)
    }
}
