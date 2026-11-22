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

    @Test func savedHistoryMarksHowFarBackTheNightsNeedRescoring() async {
        let source = FakeDataLinkSource()
        let defaults = makeDefaults()
        let sink = FakeSink()
        let collector = pairedCollector(source, sink, defaults: defaults)
        #expect(collector.historyRescoreFrom == nil)
        source.send(.dataLink(.ready))
        await collector.receiveStrapFrames([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        #expect(collector.historyRescoreFrom == HistoryFrames.recordTs)
        let relaunched = LiveCollector(source: source, sink: sink, defaults: defaults, now: { now })
        #expect(relaunched.historyRescoreFrom == HistoryFrames.recordTs)
        relaunched.historyRescored(from: HistoryFrames.recordTs)
        #expect(relaunched.historyRescoreFrom == nil)
        #expect(LiveCollector(source: source, sink: sink, defaults: defaults, now: { now }).historyRescoreFrom == nil)
    }

    /// A rescore that began from a later point didn't cover older history that arrived meanwhile.
    @Test func olderHistoryThanTheRescoreCoveredIsNotForgotten() async {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.ready))
        await collector.receiveStrapFrames([HistoryFrames.start, HistoryFrames.record, HistoryFrames.end])
        collector.historyRescored(from: HistoryFrames.recordTs + 86_400)
        #expect(collector.historyRescoreFrom == HistoryFrames.recordTs)
        collector.historyRescored(from: HistoryFrames.recordTs - 60)
        #expect(collector.historyRescoreFrom == nil)
    }

    @Test func theAlarmGoesOutOverTheDataLinkAndTheStrapsAnswerLands() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.ready))
        collector.alarm.set(hour: 7, minute: 0)
        let sent = source.commands.map { $0[10] }
        #expect(sent.contains(StrapCommandPolicy.setClock))
        #expect(sent.last == StrapCommandPolicy.setAlarm)
        source.send(.strapFrame(puffinCommandFrame(cmd: StrapCommandPolicy.setAlarm, seq: 3, payload: [1, 1], type: 38)))
        guard case .set = collector.alarm.status else {
            Issue.record("expected the alarm to be set, got \(collector.alarm.status)")
            return
        }
        source.send(.dataLink(.unavailable))
        collector.alarm.turnOff()
        #expect(source.commands.last?[10] != StrapCommandPolicy.cancelAlarm)
        source.send(.dataLink(.ready))
        #expect(source.commands.contains { $0[10] == StrapCommandPolicy.cancelAlarm })
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

    /// While the strap stays connected, history keeps coming without pressing Sync now.
    @Test func whileConnectedASyncStartsOnItsOwnOnceTheLastIsHalfAnHourOld() {
        final class Clock { var now = 0 }
        let clock = Clock()
        clock.now = now
        let source = FakeDataLinkSource()
        let defaults = makeDefaults()
        let pairing = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { now - 3_600 })
        pairing.pair(with: UUID())
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { clock.now })
        source.send(.dataLink(.ready))
        collector.historyWentQuiet()
        #expect(source.historyRequests == 1)
        clock.now += 10 * 60
        collector.historyHeartbeat()
        #expect(source.historyRequests == 1, "ten minutes on, nothing new is asked")
        clock.now += LiveCollector.historySyncInterval
        collector.historyHeartbeat()
        #expect(source.historyRequests == 2)
        #expect(LiveCollector.historySyncInterval == 30 * 60)
    }

    /// A collector that last synced `minutesAgo` before its clock, with the link down.
    private func syncedEarlier(_ source: FakeDataLinkSource, minutesAgo: Int) -> LiveCollector {
        final class Clock { var now = 0 }
        let clock = Clock()
        clock.now = now - minutesAgo * 60
        let defaults = makeDefaults()
        let pairing = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { now - 3_600 })
        pairing.pair(with: UUID())
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { clock.now })
        source.send(.dataLink(.ready))
        collector.historyWentQuiet()
        source.send(.dataLink(.unavailable))
        clock.now = now
        return collector
    }

    @Test func openingTheAppSyncsEvenWhenTheLastSyncWasRecent() {
        let source = FakeDataLinkSource()
        let collector = syncedEarlier(source, minutesAgo: 10)
        source.send(.dataLink(.ready))
        #expect(source.historyRequests == 1, "ten minutes on, the link coming back alone asks nothing")
        collector.appOpened()
        #expect(source.historyRequests == 2)
        #expect(collector.isSyncingHistory)
    }

    @Test func openingTheAppWhileTheStrapIsAwaySyncsOnceItConnects() {
        let source = FakeDataLinkSource()
        let collector = syncedEarlier(source, minutesAgo: 10)
        collector.appOpened()
        #expect(source.historyRequests == 1)
        source.send(.dataLink(.ready))
        #expect(source.historyRequests == 2)
        collector.historyWentQuiet()
        source.send(.dataLink(.unavailable))
        source.send(.dataLink(.ready))
        #expect(source.historyRequests == 2, "one open, one sync")
    }

    @Test func switchingBackAndForthDoesNotRereadTheStrap() {
        let source = FakeDataLinkSource()
        let collector = syncedEarlier(source, minutesAgo: 1)
        source.send(.dataLink(.ready))
        collector.appOpened()
        #expect(source.historyRequests == 1, "synced a minute ago, nothing new to ask for")
        #expect(LiveCollector.openSyncInterval == 2 * 60)
    }

    @Test func openingDuringASyncLeavesItRunning() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.ready))
        collector.appOpened()
        #expect(source.historyRequests == 1)
        #expect(collector.isSyncingHistory)
    }

    @Test func theHeartbeatAsksNothingWhileTheLinkIsDown() {
        let source = FakeDataLinkSource()
        let collector = pairedCollector(source, FakeSink(), defaults: makeDefaults())
        source.send(.dataLink(.unavailable))
        collector.historyHeartbeat()
        #expect(source.historyRequests == 0)
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
