import Foundation
import Testing
@preconcurrency import WhoopProtocol
import TetherCore
@testable import TetherFiles

/// Holds what the exporter read and wrote, so the closures don't capture mutable locals.
private final class ExportLog: @unchecked Sendable {
    var reads: [ClosedRange<Int>] = []
    var files: [String: String] = [:]
}

@Suite("Mac inbox export")
struct InboxExportTests {
    private let hr = [HRSample(ts: 101, bpm: 60), HRSample(ts: 150, bpm: 62)]
    private let rr = [RRInterval(ts: 101, rrMs: 1_000, ord: 0, seq: 0), RRInterval(ts: 150, rrMs: 968, ord: 0, seq: 1)]

    @Test func writesOneFileForNewSamplesAndAdvancesTheCursor() async throws {
        let log = ExportLog()
        let batch = SampleBatch(Streams(hr: hr, rr: rr))
        let cursor = try await InboxExporter.export(after: 100, now: 260,
                                                    read: { from, to in log.reads.append(from...to); return batch },
                                                    write: { text, path in log.files[path] = text })
        #expect(cursor == 200)
        #expect(log.reads == [101...200])
        #expect(Array(log.files.keys) == ["inbox/mac/101-150.csv"])
        let back = try InboxFile.read(try #require(log.files["inbox/mac/101-150.csv"]))
        #expect(back.hr == hr)
        #expect(back.rr == rr)
    }

    @Test func nothingIsReadAgainBeforeANewMinuteHasSettled() async throws {
        let log = ExportLog()
        let cursor = try await InboxExporter.export(after: 200, now: 250,
                                                    read: { from, to in log.reads.append(from...to); return SampleBatch(Streams()) },
                                                    write: { text, path in log.files[path] = text })
        #expect(cursor == 200)
        #expect(log.reads.isEmpty)
        #expect(log.files.isEmpty)
    }

    @Test func anEmptyRangeWritesNoFileButMovesOn() async throws {
        let log = ExportLog()
        let cursor = try await InboxExporter.export(after: 100, now: 400,
                                                    read: { _, _ in SampleBatch(Streams()) },
                                                    write: { text, path in log.files[path] = text })
        #expect(cursor == 340)
        #expect(log.files.isEmpty)
    }

    @Test func samplesOutsideTheRangeAreLeftOut() async throws {
        let log = ExportLog()
        let stray = SampleBatch(Streams(hr: [HRSample(ts: 90, bpm: 58)] + hr + [HRSample(ts: 230, bpm: 64)], rr: rr))
        _ = try await InboxExporter.export(after: 100, now: 260,
                                           read: { _, _ in stray },
                                           write: { text, path in log.files[path] = text })
        let text = try #require(log.files.values.first)
        #expect(try InboxFile.read(text).hr == hr)
    }
}

@Suite("Pairing details in the shared files")
struct SharedDetailsTests {
    @Test func profileCarriesTheStrapName() throws {
        let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male)
        let text = ProfileFile.write(profile: profile, pairedAt: 1_795_300_000, strapName: "WHOOP NAKV")
        #expect(text.contains("strap_name: WHOOP NAKV"))
        #expect(try ProfileFile.read(text).strapName == "WHOOP NAKV")
        #expect(try ProfileFile.read(ProfileFile.write(profile: profile, pairedAt: nil)).strapName == nil)
    }

    @Test func dayFilesKeepTheMinutesTheMacRecorded() throws {
        let record = DayRecord(day: "2026-11-22", savedAt: 1_795_300_000, strapBatteryPct: nil, today: nil, night: nil,
                               macSpans: [1_795_250_000...1_795_260_000, 1_795_270_000...1_795_271_000])
        let text = DayFile.write(record)
        #expect(text.contains("mac_spans: 1795250000-1795260000;1795270000-1795271000"))
        #expect(try DayFile.read(text) == record)
    }

    @Test func olderDayFilesWithoutMacSpansStillRead() throws {
        let record = DayRecord(day: "2026-11-21", savedAt: 1_795_200_000, strapBatteryPct: 61, today: nil, night: nil)
        let text = DayFile.write(record)
        #expect(!text.contains("mac_spans"))
        #expect(try DayFile.read(text).macSpans.isEmpty)
    }
}

/// A store that already has heart rate for some seconds, as the phone's does after its own recording.
private actor StoreWithSeconds: SampleSink {
    let existing: Set<Int>
    private(set) var written: [Streams] = []
    init(existing: Set<Int>) { self.existing = existing }
    func write(_ batch: SampleBatch) async throws { written.append(batch.streams) }
    func erase(from: Int) async throws {}
    func hrSeconds(from: Int, to: Int) async throws -> Set<Int> { existing.filter { $0 >= from && $0 <= to } }
}

@Suite("Inbox import from the Mac")
struct MacImportTests {
    @Test func secondsThePhoneAlreadyHasAreSkipped() async throws {
        let text = InboxFile.write(hr: [HRSample(ts: 200, bpm: 70), HRSample(ts: 201, bpm: 71)],
                                   rr: [RRInterval(ts: 200, rrMs: 857, ord: 0, seq: 0),
                                        RRInterval(ts: 201, rrMs: 845, ord: 0, seq: 1)])
        let sink = StoreWithSeconds(existing: [200])
        let result = try await InboxImporter.importFile(text, into: sink, notBefore: 0)
        let written = await sink.written
        #expect(written.flatMap(\.hr).map(\.ts) == [201])
        #expect(written.flatMap(\.rr).map(\.ts) == [201])
        #expect(result.samples == 2)
    }

    @Test func importReportsTheSpanItCovered() async throws {
        let text = InboxFile.write(hr: [HRSample(ts: 300, bpm: 70), HRSample(ts: 420, bpm: 72)], rr: [])
        let result = try await InboxImporter.importFile(text, into: StoreWithSeconds(existing: []), notBefore: 0)
        #expect(result.span == 300...420)
    }
}

@Suite("Mac spans kept by the phone")
struct MacSpanTests {
    @Test func touchingOrNearbySpansMerge() {
        let merged = MacSpans.adding(600...700, to: [100...200, 250...300])
        #expect(merged == [100...300, 600...700])
        #expect(MacSpans.adding(150...260, to: [100...200, 250...300]) == [100...300])
    }

    @Test func spansAreClippedToADay() {
        let spans = [100...200, 900...1_100]
        #expect(MacSpans.within(spans, day: 150...1_000) == [150...200, 900...1_000])
        #expect(MacSpans.within(spans, day: 300...800).isEmpty)
    }

    @Test func oldSpansAreDropped() {
        #expect(MacSpans.dropping([100...200, 300...400], before: 250) == [300...400])
    }
}
