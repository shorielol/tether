import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// Tap to mark: a double-tap on the strap bookmarks the moment; you name it, and after a few marks with
/// the same name Tether shows what that usually does to your heart rate.
@MainActor
@Suite("Tap to mark")
struct MarksTests {
    /// A real DOUBLE_TAP(14) EVENT frame from a WHOOP 5 strap, tapped at 1780910464.
    static let tapFrame = bytes("aa0110000100208130340e008089266a3d2a000030b8df92")
    static let tapTs = 1_780_910_464
    /// A real BATTERY_LEVEL event: not a tap.
    static let batteryFrame = bytes("aa01240001002eb130350300a589266a5118140002f3010000f90e00000000340806003500000000358eb56f")

    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "marks-\(UUID().uuidString)")! }

    @Test func aDoubleTapFrameGivesTheMomentItWasTapped() {
        #expect(StrapTap.timestamp(of: Self.tapFrame) == Self.tapTs)
        #expect(StrapTap.timestamp(of: Self.batteryFrame) == nil)
        #expect(StrapTap.timestamp(of: [0xAA, 1, 2]) == nil)
    }

    private func collector(now: Int, pairedAt: Int, sink: FakeSink, defaults: UserDefaults) -> (LiveCollector, FakeSource) {
        let source = FakeSource()
        let pairing = LiveCollector(source: source, sink: sink, defaults: defaults, now: { pairedAt })
        pairing.pair(with: UUID())
        return (LiveCollector(source: source, sink: sink, defaults: defaults, now: { now }), source)
    }

    @Test func aTapIsSavedAndTheAppIsToldWhileItIsFresh() async {
        let sink = FakeSink()
        let (collector, source) = collector(now: Self.tapTs + 20, pairedAt: Self.tapTs - 3_600, sink: sink,
                                            defaults: defaults())
        var told: [(Int, Bool)] = []
        collector.onMark = { told.append(($0, $1)) }
        source.send(.strapFrame(Self.tapFrame))
        await collector.flush()
        #expect(told.map(\.0) == [Self.tapTs])
        #expect(told.first?.1 == true)
        #expect(await sink.written.flatMap(\.events).map(\.ts) == [Self.tapTs])
        #expect(await sink.written.flatMap(\.events).first?.kind == StrapTap.kind)
    }

    @Test func aTapThatArrivesLateIsSavedQuietly() async {
        let sink = FakeSink()
        let (collector, source) = collector(now: Self.tapTs + 3 * 3_600, pairedAt: Self.tapTs - 3_600, sink: sink,
                                            defaults: defaults())
        var told: [(Int, Bool)] = []
        collector.onMark = { told.append(($0, $1)) }
        source.send(.strapFrame(Self.tapFrame))
        await collector.flush()
        #expect(told.first?.1 == false)
        #expect(await sink.written.flatMap(\.events).count == 1)
    }

    @Test func aTapFromBeforePairingIsDropped() async {
        let sink = FakeSink()
        let (collector, source) = collector(now: Self.tapTs + 20, pairedAt: Self.tapTs + 10, sink: sink,
                                            defaults: defaults())
        var told = 0
        collector.onMark = { _, _ in told += 1 }
        source.send(.strapFrame(Self.tapFrame))
        await collector.flush()
        #expect(told == 0)
        #expect(await sink.written.flatMap(\.events).isEmpty)
    }

    @Test func labelsAreKeptAndTheRecentOnesOfferedFirst() {
        let store = MarkLabels(defaults: defaults())
        store.set("Coffee", for: 100)
        store.set("Exam", for: 200)
        store.set("Coffee", for: 300)
        #expect(store.label(for: 100) == "Coffee")
        #expect(store.label(for: 999) == nil)
        #expect(store.recent == ["Coffee", "Exam"])
        store.set("  ", for: 200)
        #expect(store.label(for: 200) == nil, "a blank name clears the label")
        #expect(MarkLabels(defaults: store.defaults).label(for: 300) == "Coffee", "labels survive a relaunch")
    }

    /// Heart rate at 62 for 15 minutes before each mark, 71 for the half hour after.
    private func hrAround(_ marks: [Int], before: Int = 62, after: Int = 71) -> [HRSample] {
        marks.flatMap { mark in
            (mark - 900..<mark).map { HRSample(ts: $0, bpm: before) }
                + (mark..<mark + 1_800).map { HRSample(ts: $0, bpm: after) }
        }
    }

    @Test func aLabelsTypicalEffectNeedsThreeMarks() throws {
        let marks = [10_000, 100_000, 200_000]
        let hr = hrAround(marks)
        #expect(MarkEffect.compute(label: "Coffee", marks: Array(marks.prefix(2)), hr: hr) == nil)
        let effect = try #require(MarkEffect.compute(label: "Coffee", marks: marks, hr: hr))
        #expect(effect.bpmChange == 9)
        #expect(effect.marks == 3)
    }

    @Test func marksWithoutHeartRateAroundThemDontCount() {
        let marks = [10_000, 100_000, 200_000]
        let hr = hrAround(Array(marks.prefix(2)))
        #expect(MarkEffect.compute(label: "Coffee", marks: marks, hr: hr) == nil)
    }

    @Test func aTapIsStoredAndReadBackWithItsHeartRate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("marks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sink = WhoopStoreSink(path: directory.appendingPathComponent("tether.sqlite").path)
        let defaults = defaults()
        let pairing = LiveCollector(source: FakeSource(), sink: sink, defaults: defaults, now: { Self.tapTs - 3_600 })
        pairing.pair(with: UUID())
        let source = FakeSource()
        let collector = LiveCollector(source: source, sink: sink, defaults: defaults, now: { Self.tapTs + 20 })
        source.send(.strapFrame(Self.tapFrame))
        await collector.flush()
        var around = Streams(hr: hrAround([Self.tapTs]), rr: [])
        around.events = []
        try await sink.write(SampleBatch(around))
        #expect(try await sink.marks(from: Self.tapTs - 60, to: Self.tapTs + 60) == [Self.tapTs])
        #expect(try await sink.window(around: Self.tapTs)?.change == 9)
    }

    @Test func oneMarksWindowShowsBeforeAndAfter() throws {
        let window = try #require(MarkWindow.compute(mark: 10_000, hr: hrAround([10_000])))
        #expect(window.before == 62)
        #expect(window.after == 71)
    }
}
