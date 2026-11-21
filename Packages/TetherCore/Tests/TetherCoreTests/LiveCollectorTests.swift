import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

@MainActor
final class FakeSource: HeartDataSource {
    var onEvent: ((HeartSourceEvent) -> Void)?
    var rememberedStrap: UUID?
    var scanning = false
    var connectedTo: UUID?
    func startScan() { scanning = true }
    func stopScan() { scanning = false }
    func connect(to strap: UUID) { connectedTo = strap; rememberedStrap = strap }
    func forget() { rememberedStrap = nil }
    var released = false
    func releaseStrap() { released = true }
    func reclaimStrap() { released = false }
    func send(_ event: HeartSourceEvent) { onEvent?(event) }
}

actor FakeSink: SampleSink {
    private(set) var written: [Streams] = []
    private(set) var erasedFrom: [Int] = []
    func write(_ batch: SampleBatch) async throws { written.append(batch.streams) }
    func erase(from: Int) async throws { erasedFrom.append(from) }
}

@MainActor
@Suite("Live collector")
struct LiveCollectorTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "tether.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func pairingRecordsTheCutoffAndConnects() {
        let source = FakeSource()
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: makeDefaults(), now: { 5_000 })
        let strap = UUID()
        collector.pair(with: strap)
        #expect(source.connectedTo == strap)
        #expect(collector.pairedAt == 5_000)
    }

    @Test func handingTheStrapOverSavesFirstAndKeepsThePairing() async {
        let source = FakeSource()
        let sink = FakeSink()
        let collector = LiveCollector(source: source, sink: sink, defaults: makeDefaults(), now: { 0 })
        collector.pair(with: UUID())
        source.send(.link(.connected))
        source.send(.measurement(HeartRateMeasurement(bpm: 64, rrMs: [], contact: .detected), at: 20))
        await collector.release()
        #expect(source.released)
        #expect(collector.isReleased)
        #expect(collector.isPaired)
        #expect(collector.heartRate == nil)
        #expect(await sink.written.flatMap(\.hr).map(\.bpm) == [64])
        collector.reclaim()
        #expect(!source.released)
        #expect(!collector.isReleased)
    }

    @Test func liveStateFollowsSourceEvents() {
        let source = FakeSource()
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: makeDefaults(), now: { 0 })
        collector.pair(with: UUID())
        source.send(.link(.connected))
        source.send(.measurement(HeartRateMeasurement(bpm: 58, rrMs: [1030], contact: .detected), at: 10))
        source.send(.battery(percent: 61))
        source.send(.firmware("50.43.2.0"))
        #expect(collector.link == .connected)
        #expect(collector.heartRate == 58)
        #expect(collector.batteryPercent == 61)
        #expect(collector.firmware == "50.43.2.0")
        #expect(collector.lastSampleAt == 10)
    }

    @Test func flushWritesEverythingSinceTheLastFlush() async {
        let source = FakeSource()
        let sink = FakeSink()
        let collector = LiveCollector(source: source, sink: sink, defaults: makeDefaults(), now: { 100 })
        collector.pair(with: UUID())
        source.send(.measurement(HeartRateMeasurement(bpm: 60, rrMs: [1000], contact: .detected), at: 100))
        source.send(.measurement(HeartRateMeasurement(bpm: 61, rrMs: [990], contact: .detected), at: 101))
        await collector.flush()
        await collector.flush()
        let written = await sink.written
        #expect(written.count == 1)
        #expect(written.first?.hr.map(\.bpm) == [60, 61])
    }

    @Test func samplesBeforePairingAreNeverWritten() async {
        let source = FakeSource()
        let sink = FakeSink()
        let collector = LiveCollector(source: source, sink: sink, defaults: makeDefaults(), now: { 1_000 })
        collector.pair(with: UUID())
        source.send(.measurement(HeartRateMeasurement(bpm: 60, rrMs: [], contact: .detected), at: 999))
        await collector.flush()
        #expect(await sink.written.isEmpty)
    }

    @Test func nothingIsCollectedBeforeAStrapIsPaired() async {
        let source = FakeSource()
        let sink = FakeSink()
        let collector = LiveCollector(source: source, sink: sink, defaults: makeDefaults(), now: { 0 })
        source.send(.measurement(HeartRateMeasurement(bpm: 60, rrMs: [], contact: .detected), at: 50))
        await collector.flush()
        #expect(await sink.written.isEmpty)
        #expect(collector.heartRate == 60)
    }

    @Test func pairingSurvivesARelaunch() {
        let defaults = makeDefaults()
        let source = FakeSource()
        let first = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { 7_000 })
        first.pair(with: UUID())
        let second = LiveCollector(source: FakeSource(), sink: FakeSink(), defaults: defaults, now: { 9_000 })
        #expect(second.pairedAt == 7_000)
    }

    @Test func discoveredStrapsAreListedOnceEach() {
        let source = FakeSource()
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: makeDefaults(), now: { 0 })
        let id = UUID()
        collector.startScan()
        source.send(.discovered(DiscoveredStrap(id: id, name: "WHOOP 4C0", rssi: -60)))
        source.send(.discovered(DiscoveredStrap(id: id, name: "WHOOP 4C0", rssi: -55)))
        #expect(collector.discovered.count == 1)
        #expect(collector.discovered.first?.rssi == -55)
    }

    @Test func forgettingEndsThePairingAndSurvivesRelaunch() async {
        let defaults = makeDefaults()
        let source = FakeSource()
        let collector = LiveCollector(source: source, sink: FakeSink(), defaults: defaults, now: { 500 })
        collector.pair(with: UUID())
        source.send(.measurement(HeartRateMeasurement(bpm: 70, rrMs: [], contact: .detected), at: 501))
        await collector.forgetStrap(erase: true)
        #expect(!collector.isPaired)
        #expect(collector.heartRate == nil)
        #expect(collector.lastSampleAt == nil)
        #expect(source.rememberedStrap == nil)
        let relaunched = LiveCollector(source: FakeSource(), sink: FakeSink(), defaults: defaults, now: { 600 })
        #expect(!relaunched.isPaired)
    }

    @Test func eraseRemovesWhatThePairingRecordedAndSavesNothingPending() async {
        let source = FakeSource()
        let sink = FakeSink()
        let collector = LiveCollector(source: source, sink: sink, defaults: makeDefaults(), now: { 500 })
        collector.pair(with: UUID())
        source.send(.measurement(HeartRateMeasurement(bpm: 70, rrMs: [850], contact: .detected), at: 501))
        await collector.forgetStrap(erase: true)
        source.send(.measurement(HeartRateMeasurement(bpm: 71, rrMs: [], contact: .detected), at: 502))
        await collector.flush()
        #expect(await sink.erasedFrom == [500])
        #expect(await sink.written.isEmpty)
    }

    @Test func keepSavesUnsavedSamplesBeforeForgetting() async {
        let source = FakeSource()
        let sink = FakeSink()
        let collector = LiveCollector(source: source, sink: sink, defaults: makeDefaults(), now: { 500 })
        collector.pair(with: UUID())
        source.send(.measurement(HeartRateMeasurement(bpm: 70, rrMs: [850], contact: .detected), at: 501))
        await collector.forgetStrap(erase: false)
        #expect(!collector.isPaired)
        #expect(await sink.erasedFrom.isEmpty)
        #expect(await sink.written.flatMap(\.hr).map(\.bpm) == [70])
    }
}
