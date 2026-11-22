import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

@Suite("Strap alarm commands")
struct StrapAlarmTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    /// 2026-11-22 00:00 UTC.
    private let midnight = 1_795_305_600

    @Test func theNextWakeIsTomorrowOnceTodaysTimeHasPassed() {
        let lateEvening = midnight + 22 * 3_600
        #expect(StrapAlarm.nextWake(hour: 7, minute: 0, after: lateEvening, calendar: calendar)
                == midnight + 86_400 + 7 * 3_600)
        let early = midnight + 6 * 3_600
        #expect(StrapAlarm.nextWake(hour: 7, minute: 30, after: early, calendar: calendar)
                == midnight + 7 * 3_600 + 30 * 60)
        #expect(StrapAlarm.nextWake(hour: 7, minute: 0, after: midnight + 7 * 3_600, calendar: calendar)
                == midnight + 86_400 + 7 * 3_600)
    }

    @Test func armingSetsTheStrapsClockThenTheAlarm() {
        let now = midnight + 22 * 3_600
        let wake = midnight + 86_400 + 7 * 3_600
        let frames = StrapAlarm.armFrames(wakeAt: wake, now: now, clockSeq: 5, alarmSeq: 6)
        #expect(frames.count == 2)
        #expect(frames.allSatisfy(StrapCommandPolicy.allows))
        #expect(frames[0] == puffinCommandFrame(cmd: StrapCommandPolicy.setClock, seq: 5,
                                                payload: StrapAlarm.clockPayload(now: now)))
        #expect(frames[1] == puffinCommandFrame(cmd: StrapCommandPolicy.setAlarm, seq: 6,
                                                payload: AlarmPayload.setAlarmRev4(wakeEpochMs: Int64(wake) * 1_000)))
    }

    @Test func theClockIsTheTimeInSecondsLittleEndian() {
        #expect(StrapAlarm.clockPayload(now: 0x0102_0304) == [0x04, 0x03, 0x02, 0x01, 0, 0, 0, 0])
    }

    @Test func cancellingUsesTheCancelCommand() {
        let frame = StrapAlarm.cancelFrame(seq: 9)
        #expect(StrapCommandPolicy.allows(frame))
        #expect(frame == puffinCommandFrame(cmd: StrapCommandPolicy.cancelAlarm, seq: 9,
                                            payload: AlarmPayload.disableRev2()))
    }

    private func reply(_ cmd: UInt8, result: UInt8, type: UInt8 = 38) -> [UInt8] {
        puffinCommandFrame(cmd: cmd, seq: 40, payload: [6, result], type: type)
    }

    @Test func theStrapsReplySaysWhetherItTookTheAlarm() {
        #expect(StrapAlarm.reply(reply(66, result: 1)) == .init(command: 66, result: .accepted))
        #expect(StrapAlarm.reply(reply(66, result: 0)) == .init(command: 66, result: .refused))
        #expect(StrapAlarm.reply(reply(66, result: 2)) == .init(command: 66, result: .pending))
        #expect(StrapAlarm.reply(reply(69, result: 3, type: 36)) == .init(command: 69, result: .unsupported))
    }

    @Test func otherFramesAreNotAlarmReplies() {
        #expect(StrapAlarm.reply(reply(22, result: 1)) == nil)                 // a history reply
        #expect(StrapAlarm.reply(reply(66, result: 1, type: 35)) == nil)       // our own command
        #expect(StrapAlarm.reply(reply(66, result: 9)) == nil)                 // unknown result
        #expect(StrapAlarm.reply([0xAA, 1, 2]) == nil)
    }
}
