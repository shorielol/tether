import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// Real WHOOP 5 offload frames (v18 layout), from WhoopProtocol's hardware-verified fixtures.
enum HistoryFrames {
    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    static let start = bytes("aa012c0001002cd1312c0184a3266ad7230d0000005200000000000000320000002600000001000000000000000b010034497926")
    /// unix 1780916150, 102 bpm, R-R 602 and 613 ms, one gravity and one skin-temperature sample.
    static let record = bytes("aa01740001003fb12f1280733d8401b69f266a66460066025a0265020000000000007b0a8d656463ff0012163cf6a439bf2924fd3ed763fe3e3200aa000000000000000000f7000901f10b0007010c020c00000000000000000000000000000000000000000000000100656f1e1e0000009d61a7c00000003e862817")
    /// trim 112193; its end data is 41 b6 01 00 10 00 00 00.
    static let end = bytes("aa011c00010023d1316a0284a3266a0a373d00000041b601001000000000000044d21e3d")
    static let endData: [UInt8] = [0x41, 0xb6, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00]
    static let recordTs = 1_780_916_150
}

/// Stands in for the strap's command characteristic and the store, recording the order things happen.
@MainActor
final class FakeStrapLink {
    var log: [String] = []
    var written: [[UInt8]] = []
    var saved: [Streams] = []
    var failSaves = false
    var outcomes: [StrapHistoryOutcome] = []

    func session(cutoff: Int = 0,
                 classify: (([UInt8]) -> HistoricalMeta)? = nil) -> StrapHistorySession {
        let session = StrapHistorySession(
            cutoff: OwnershipCutoff(pairedAt: cutoff),
            write: { [unowned self] frame in
                self.written.append(frame)
                self.log.append(frame.count > 10 && frame[10] == 23 ? "ack" : "write \(frame.count > 10 ? frame[10] : 0)")
            },
            save: { [unowned self] streams in
                if self.failSaves { throw CocoaError(.fileWriteUnknown) }
                self.saved.append(streams)
                self.log.append("save")
                return streams.hr.count + streams.rr.count + streams.gravity.count + streams.skinTemp.count
            },
            now: { HistoryFrames.recordTs + 600 },
            classify: classify)
        session.onFinish = { [unowned self] in self.outcomes.append($0) }
        return session
    }
}

@MainActor
@Suite("Strap history session")
struct StrapHistorySessionTests {
    @Test func startingAsksTheStrapForItsHistory() throws {
        let link = FakeStrapLink()
        link.session().start()
        let request = try #require(link.written.first)
        #expect(request[10] == WhoopCommandCode.sendHistoricalData)
        #expect(request[11] == 0x00)
        #expect(verifyFrame(request, family: .whoop5).ok)
    }

    @Test func aChunkIsSavedBeforeItIsAcknowledged() async {
        let link = FakeStrapLink()
        let session = link.session()
        session.start()
        await session.receiveAll([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        #expect(link.log == ["write 22", "save", "ack"])
        #expect(link.saved.first?.hr.map(\.bpm) == [102])
        #expect(link.saved.first?.rr.map(\.rrMs) == [602, 613])
        #expect(link.saved.first?.gravity.count == 1)
        #expect(link.saved.first?.skinTemp.count == 1)
        let ack = link.written.last ?? []
        #expect(Array(ack[12..<20]) == HistoryFrames.endData)
        #expect(verifyFrame(ack, family: .whoop5).ok)
    }

    @Test func recordsFromBeforePairingAreDroppedButStillAcknowledged() async {
        let link = FakeStrapLink()
        let session = link.session(cutoff: HistoryFrames.recordTs + 1)
        session.start()
        await session.receiveAll([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        #expect(link.saved.first?.hr.isEmpty == true)
        #expect(link.saved.first?.gravity.isEmpty == true)
        #expect(link.log.last == "ack")
    }

    @Test func aFailedSaveIsNeverAcknowledged() async {
        let link = FakeStrapLink()
        link.failSaves = true
        let session = link.session()
        session.start()
        await session.receiveAll([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        #expect(!link.log.contains("ack"))
        #expect(link.outcomes == [.saveFailed])
    }

    @Test func liveFramesAreIgnored() async {
        let link = FakeStrapLink()
        let session = link.session()
        session.start()
        var live = HistoryFrames.record
        live[8] = 40   // REALTIME_DATA
        await session.receiveAll([HistoryFrames.start, live, HistoryFrames.end])
        #expect(link.saved.first?.hr.isEmpty == true)
    }

    @Test func silenceEndsTheSessionWithWhatWasSaved() async {
        let link = FakeStrapLink()
        let session = link.session()
        session.start()
        await session.receiveAll([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        session.idleTimeout()
        #expect(link.outcomes == [.timedOut(rows: 5)])
    }

    /// The fixtures have no HISTORY_COMPLETE frame, so a marker frame stands in for one.
    @Test func completeAfterNewRowsAsksAgainThenFinishesWhenNothingIsLeft() async {
        let link = FakeStrapLink()
        var marker = HistoryFrames.start
        marker[marker.count - 1] ^= 0xFF
        let session = link.session { frame in
            frame == marker ? .complete : classifyHistoricalMeta(parseFrame(frame, family: .whoop5))
        }
        session.start()
        await session.receiveAll([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end, marker])
        #expect(link.written.filter { $0[10] == WhoopCommandCode.sendHistoricalData }.count == 2)
        #expect(link.outcomes.isEmpty)
        await session.receiveAll([marker])
        #expect(link.outcomes == [.caughtUp(rows: 5)])
    }
}
