import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

@MainActor
@Suite("Keeping the strap's alarm set")
struct AlarmKeeperTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    /// 2026-11-22 00:00 UTC.
    private let midnight = 1_795_305_600
    private var tomorrowSeven: Int { midnight + 86_400 + 7 * 3_600 }

    final class Harness {
        var clock: Int
        var sent: [[UInt8]] = []
        let defaults = UserDefaults(suiteName: "alarm-\(UUID().uuidString)")!
        init(clock: Int) { self.clock = clock }
        var commands: [UInt8] { sent.map { $0[10] } }
    }

    private func keeper(_ harness: Harness) -> AlarmKeeper {
        AlarmKeeper(defaults: harness.defaults, now: { harness.clock }, calendar: calendar) { harness.sent.append($0) }
    }

    private func reply(_ cmd: UInt8, _ result: UInt8) -> [UInt8] {
        puffinCommandFrame(cmd: cmd, seq: 40, payload: [1, result], type: 38)
    }

    @Test func settingItWhileConnectedSendsTheClockThenTheAlarm() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        #expect(harness.commands == [StrapCommandPolicy.setClock, StrapCommandPolicy.setAlarm])
        #expect(alarm.status == .sending(wake: tomorrowSeven))
        #expect(alarm.receive(reply(StrapCommandPolicy.setAlarm, 1)))
        #expect(alarm.status == .set(wake: tomorrowSeven))
    }

    @Test func itWaitsForTheStrapWhenNotConnected() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.set(hour: 7, minute: 0)
        #expect(harness.sent.isEmpty)
        #expect(alarm.status == .waitingForStrap(wake: tomorrowSeven))
        alarm.linkChanged(ready: true)
        #expect(harness.commands == [StrapCommandPolicy.setClock, StrapCommandPolicy.setAlarm])
    }

    @Test func aSetAlarmSurvivesARelaunchAndIsNotSentAgain() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 1))
        harness.sent.removeAll()
        let relaunched = keeper(harness)
        #expect(relaunched.setting == .init(hour: 7, minute: 0, isOn: true))
        #expect(relaunched.status == .set(wake: tomorrowSeven))
        relaunched.linkChanged(ready: true)
        relaunched.tick()
        #expect(harness.sent.isEmpty)
    }

    @Test func afterItGoesOffItIsSetForTheNextMorning() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 1))
        harness.sent.removeAll()
        harness.clock = tomorrowSeven + 600
        alarm.tick()
        #expect(harness.commands == [StrapCommandPolicy.setClock, StrapCommandPolicy.setAlarm])
        #expect(alarm.status == .sending(wake: tomorrowSeven + 86_400))
    }

    @Test func aRefusalIsAcceptedAndNotRetriedOnItsOwn() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 0))
        #expect(alarm.status == .refused(wake: tomorrowSeven))
        harness.sent.removeAll()
        alarm.tick()
        alarm.linkChanged(ready: false)
        alarm.linkChanged(ready: true)
        #expect(harness.sent.isEmpty)
        #expect(keeper(harness).status == .refused(wake: tomorrowSeven))
        alarm.set(hour: 7, minute: 0)   // the person asks again
        #expect(harness.commands.last == StrapCommandPolicy.setAlarm)
    }

    @Test func anUnsupportedAnswerAlsoStops() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 6, minute: 45)
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 3))
        #expect(alarm.status == .refused(wake: midnight + 86_400 + 6 * 3_600 + 45 * 60))
    }

    @Test func turningItOffCancelsOnTheStrapNowOrOnTheNextConnection() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.set(hour: 7, minute: 0)
        alarm.turnOff()
        #expect(alarm.status == .off)
        #expect(alarm.setting?.isOn == false)
        #expect(harness.sent.isEmpty)
        alarm.linkChanged(ready: true)
        #expect(harness.commands == [StrapCommandPolicy.cancelAlarm])
        _ = alarm.receive(reply(StrapCommandPolicy.cancelAlarm, 1))
        alarm.linkChanged(ready: false)
        alarm.linkChanged(ready: true)
        #expect(harness.commands == [StrapCommandPolicy.cancelAlarm])
    }

    @Test func losingTheLinkMidSendWaitsToSendAgain() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        alarm.linkChanged(ready: false)
        #expect(alarm.status == .waitingForStrap(wake: tomorrowSeven))
        harness.sent.removeAll()
        alarm.linkChanged(ready: true)
        #expect(harness.commands == [StrapCommandPolicy.setClock, StrapCommandPolicy.setAlarm])
    }

    // MARK: Smart wake window

    @Test func insideTheWindowSurfacingMovesTheAlarmToAMinuteFromNow() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        alarm.setWindow(30)
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 1))
        harness.sent.removeAll()
        harness.clock = tomorrowSeven - 20 * 60
        #expect(alarm.inSmartWindow)
        alarm.wakeEarly()
        #expect(harness.commands == [StrapCommandPolicy.setClock, StrapCommandPolicy.setAlarm])
        #expect(alarm.status == .sending(wake: harness.clock + 60))
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 1))
        #expect(alarm.status == .set(wake: harness.clock + 60))
        #expect(alarm.wokeEarly)
        harness.sent.removeAll()
        harness.clock += 5 * 60
        alarm.tick()
        #expect(harness.sent.isEmpty, "the early alarm stands until the window's end has passed")
        harness.clock = tomorrowSeven + 600
        alarm.tick()
        #expect(alarm.status == .sending(wake: tomorrowSeven + 86_400), "then tomorrow's goes out as usual")
    }

    @Test func outsideTheWindowOrWithNoWindowNothingMoves() {
        let harness = Harness(clock: midnight + 22 * 3_600)
        let alarm = keeper(harness)
        alarm.linkChanged(ready: true)
        alarm.set(hour: 7, minute: 0)
        _ = alarm.receive(reply(StrapCommandPolicy.setAlarm, 1))
        harness.sent.removeAll()
        harness.clock = tomorrowSeven - 10 * 60
        #expect(!alarm.inSmartWindow, "no window chosen")
        alarm.wakeEarly()
        alarm.setWindow(15)
        harness.clock = tomorrowSeven - 40 * 60
        #expect(!alarm.inSmartWindow, "too early for a 15-minute window")
        alarm.wakeEarly()
        #expect(harness.sent.isEmpty)
    }

    @Test func aSavedAlarmFromBeforeWindowsStillLoads() throws {
        let harness = Harness(clock: midnight)
        harness.defaults.set(Data(#"{"hour":6,"minute":30,"isOn":true}"#.utf8), forKey: "tether.alarm.setting")
        let alarm = keeper(harness)
        #expect(alarm.setting == .init(hour: 6, minute: 30, isOn: true))
        #expect(alarm.setting?.windowMinutes == 0)
    }

    @Test func otherFramesAreLeftForHistory() {
        let alarm = keeper(Harness(clock: midnight))
        #expect(!alarm.receive(reply(WhoopCommandCode.sendHistoricalData, 1)))
    }
}
