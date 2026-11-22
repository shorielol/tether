import Foundation
@preconcurrency import WhoopProtocol

/// The strap's own silent alarm: the frames that set its clock and its alarm, the one that cancels it, and
/// how to read the strap's answer. The strap keeps the time itself and buzzes even if the phone is away.
/// Only the commands `StrapCommandPolicy` allows are built here.
public enum StrapAlarm {
    /// What the strap said to an alarm command.
    public enum Result: Equatable, Sendable {
        case accepted, refused, pending, unsupported
    }

    public struct Reply: Equatable, Sendable {
        public let command: UInt8
        public let result: Result

        public init(command: UInt8, result: Result) {
            self.command = command
            self.result = result
        }
    }

    /// Command replies arrive as COMMAND_RESPONSE (36) or the WHOOP 5 response type (38).
    static let replyTypes: Set<UInt8> = [36, UInt8(PuffinPacketType.puffinCommandResponse)]
    static let typeIndex = 8
    static let commandIndex = 10
    /// After the echo of our sequence number at byte 11.
    static let resultIndex = 12
    static let alarmCommands: Set<UInt8> = [
        StrapCommandPolicy.setClock, StrapCommandPolicy.setAlarm,
        StrapCommandPolicy.readAlarm, StrapCommandPolicy.cancelAlarm,
    ]

    /// The next time the clock reads `hour:minute`, strictly after `now`.
    public static func nextWake(hour: Int, minute: Int, after now: Int, calendar: Calendar = .current) -> Int {
        let moment = Date(timeIntervalSince1970: TimeInterval(now))
        var parts = calendar.dateComponents([.year, .month, .day], from: moment)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        let today = calendar.date(from: parts) ?? moment
        let wake = today > moment ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        return Int(wake.timeIntervalSince1970)
    }

    /// SET_CLOCK's body: the time in seconds, little-endian, then four zero bytes.
    public static func clockPayload(now: Int) -> [UInt8] {
        let seconds = UInt32(clamping: now)
        return [UInt8(seconds & 0xFF), UInt8((seconds >> 8) & 0xFF),
                UInt8((seconds >> 16) & 0xFF), UInt8((seconds >> 24) & 0xFF), 0, 0, 0, 0]
    }

    /// Sets the strap's clock to `now`, then its alarm for `wakeAt`. A strap alarm is only as good as its
    /// clock, so the clock always goes first.
    public static func armFrames(wakeAt: Int, now: Int, clockSeq: UInt8, alarmSeq: UInt8) -> [[UInt8]] {
        [
            puffinCommandFrame(cmd: StrapCommandPolicy.setClock, seq: clockSeq, payload: clockPayload(now: now)),
            puffinCommandFrame(cmd: StrapCommandPolicy.setAlarm, seq: alarmSeq,
                               payload: AlarmPayload.setAlarmRev4(wakeEpochMs: Int64(wakeAt) * 1_000)),
        ]
    }

    public static func cancelFrame(seq: UInt8) -> [UInt8] {
        puffinCommandFrame(cmd: StrapCommandPolicy.cancelAlarm, seq: seq, payload: AlarmPayload.disableRev2())
    }

    /// The strap's answer to one of the alarm or clock commands, or nil for any other frame.
    public static func reply(_ frame: [UInt8]) -> Reply? {
        guard frame.count > resultIndex, frame[0] == 0xAA, replyTypes.contains(frame[typeIndex]),
              alarmCommands.contains(frame[commandIndex]) else { return nil }
        let result: Result
        switch frame[resultIndex] {
        case 0: result = .refused
        case 1: result = .accepted
        case 2: result = .pending
        case 3: result = .unsupported
        default: return nil
        }
        return Reply(command: frame[commandIndex], result: result)
    }
}
