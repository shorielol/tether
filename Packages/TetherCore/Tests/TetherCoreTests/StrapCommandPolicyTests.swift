import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// Tether may send the strap a hello, history requests and acks, the clock, and the alarm. Nothing else.
@Suite("Strap command allowlist")
struct StrapCommandPolicyTests {
    @Test func theHelloIsAllowed() {
        #expect(StrapCommandPolicy.allows(WhoopCommandCode.clientHello))
    }

    @Test func historyRequestAndAckAreAllowed() {
        #expect(StrapCommandPolicy.allows(puffinCommandFrame(cmd: WhoopCommandCode.sendHistoricalData, seq: 1)))
        #expect(StrapCommandPolicy.allows(puffinCommandFrame(cmd: WhoopCommandCode.historicalDataResult, seq: 2,
                                                             payload: [0x01] + Array(repeating: 0, count: 8))))
    }

    @Test func clockAndAlarmAreAllowed() {
        for cmd: UInt8 in [10, 66, 67, 69] {
            #expect(StrapCommandPolicy.allows(puffinCommandFrame(cmd: cmd, seq: 3)))
        }
    }

    @Test func anythingElseIsRefused() {
        // 68 buzzes the strap right now; 7 asks for version info; 150 is outside the set entirely.
        for cmd: UInt8 in [68, 7, 150, 0] {
            #expect(!StrapCommandPolicy.allows(puffinCommandFrame(cmd: cmd, seq: 4)))
        }
    }

    @Test func aMalformedFrameIsRefused() {
        #expect(!StrapCommandPolicy.allows([]))
        #expect(!StrapCommandPolicy.allows([0xAA, 0x01, 0x08]))
        var notACommand = puffinCommandFrame(cmd: WhoopCommandCode.sendHistoricalData, seq: 1)
        notACommand[8] = 0x24
        #expect(!StrapCommandPolicy.allows(notACommand))
    }
}
