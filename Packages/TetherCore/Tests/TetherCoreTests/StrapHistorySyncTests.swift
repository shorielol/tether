import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// A source that also has the strap's data link, recording every command written to the strap.
@MainActor
final class FakeDataLinkSource: HeartDataSource {
    var onEvent: ((HeartSourceEvent) -> Void)?
    var rememberedStrap: UUID?
    var commands: [[UInt8]] = []
    func startScan() {}
    func stopScan() {}
    func connect(to strap: UUID) { rememberedStrap = strap }
    func forget() { rememberedStrap = nil }
    func sendStrapCommand(_ frame: [UInt8]) { commands.append(frame) }
    var retries = 0
    func retryDataLink() { retries += 1 }
    func send(_ event: HeartSourceEvent) { onEvent?(event) }

    var historyRequests: Int { commands.filter { $0[10] == WhoopCommandCode.sendHistoricalData }.count }
    var acks: Int { commands.filter { $0[10] == WhoopCommandCode.historicalDataResult }.count }
}

@MainActor
@Suite("Strap history sync")
struct StrapHistorySyncTests {
    private let now = HistoryFrames.recordTs + 600

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "history-\(UUID().uuidString)")!
    }

    /// Paired an hour before `now`, so the fixture record (10 minutes before `now`) is the owner's.
    private func pairedCollector(_ source: FakeDataLinkSource, _ sink: FakeSink,
                                 defaults: UserDefaults) -> LiveCollector {
        let pairing = LiveCollector(source: source, sink: sink, defaults: defaults, now: { now - 3_600 })
        pairing.pair(with: UUID())
        return LiveCollector(source: source, sink: sink, defaults: defaults, now: { now })
    }

    @Test func aReadyDataLinkStartsASyncWhenOneIsDue() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.ready))
        #expect(collector.dataLink == .ready)
        #expect(collector.isSyncingHistory)
        #expect(source.historyRequests == 1)
    }

    @Test func historyFramesAreSavedThenAcknowledged() async {
        let source = FakeDataLinkSource()
        let sink = FakeSink()
        let collector = pairedCollector(source, sink, defaults: makeDefaults())
        source.send(.dataLink(.ready))
        await collector.receiveStrapFrames([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        #expect(await sink.written.flatMap(\.hr).map(\.bpm) == [102])
        #expect(await sink.written.flatMap(\.skinTemp).count == 1)
        #expect(source.acks == 1)
    }

    @Test func finishingRemembersWhenItSyncedAcrossARelaunch() {
        let source = FakeDataLinkSource()
        let defaults = makeDefaults()
        let collector = pairedCollector(source, FakeSink(), defaults: defaults)
        var reported: [StrapHistoryOutcome] = []
        collector.onHistorySynced = { reported.append($0) }
        source.send(.dataLink(.ready))
        collector.historyWentQuiet()
        #expect(reported == [.timedOut(rows: 0)])
        #expect(!collector.isSyncingHistory)
        #expect(collector.lastHistorySync == now)
        #expect(collector.lastHistoryOutcome == .timedOut(rows: 0))
        let relaunched = LiveCollector(source: FakeDataLinkSource(), sink: FakeSink(), defaults: defaults, now: { now })
        #expect(relaunched.lastHistorySync == now)
    }

    @Test func aRecentSyncIsNotRepeatedUnlessAsked() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.ready))
        collector.historyWentQuiet()
        source.send(.dataLink(.ready))
        #expect(source.historyRequests == 1)
        collector.syncHistoryNow()
        #expect(source.historyRequests == 2)
    }

    @Test func nothingIsAskedBeforePairing() {
        let source = FakeDataLinkSource()
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: makeDefaults(), now: { now })
        source.send(.dataLink(.ready))
        collector.syncHistoryNow()
        #expect(source.commands.isEmpty)
    }

    @Test func aDeclinedLinkAsksNothing() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.declined(reason: "Encryption is insufficient.")))
        collector.syncHistoryNow()
        #expect(collector.dataLink == .declined(reason: "Encryption is insufficient."))
        #expect(source.commands.isEmpty)
    }

    @Test func tryingAgainAsksTheSourceToReopenTheLink() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.declined(reason: "Encryption is insufficient.")))
        collector.retryDataLink()
        #expect(source.retries == 1)
    }
}
