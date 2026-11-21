import Foundation
import Testing
@preconcurrency import WhoopProtocol
import TetherCore
@testable import TetherFiles

@Suite("Shared folder")
struct FolderTests {
    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tether-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesNestedFilesAndReadsThemBack() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let shared = SharedFolder(url: folder)
        try shared.write("hello", to: "days/2026/11/2026-11-22.md")
        #expect(try shared.read("days/2026/11/2026-11-22.md") == "hello")
        try shared.write("again", to: "days/2026/11/2026-11-22.md")
        #expect(try shared.read("days/2026/11/2026-11-22.md") == "again")
        #expect(shared.dayFiles().map(\.lastPathComponent) == ["2026-11-22.md"])
    }

    @Test func inboxFilesAreListedAndMovedToDoneAfterImport() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let shared = SharedFolder(url: folder)
        let text = InboxFile.write(hr: [HRSample(ts: 10, bpm: 60)], rr: [])
        try shared.write(text, to: InboxFile.relativePath(from: 10, to: 20))
        let pending = shared.pendingInbox()
        #expect(pending.map(\.lastPathComponent) == ["10-20.csv"])
        try shared.markImported(pending[0])
        #expect(shared.pendingInbox().isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("inbox/done/10-20.csv").path))
    }

    @Test func profileFileRoundTrips() throws {
        let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68.5, restingHR: nil, sex: .male)
        let text = ProfileFile.write(profile: profile, pairedAt: 1_795_300_000)
        #expect(text.contains("age: 17"))
        let back = try ProfileFile.read(text)
        #expect(back.profile == profile)
        #expect(back.pairedAt == 1_795_300_000)
    }
}

actor RecordingSink: SampleSink {
    private(set) var written: [Streams] = []
    func write(_ batch: SampleBatch) async throws { written.append(batch.streams) }
    func erase(from: Int) async throws {}
}

@Suite("Inbox import")
struct InboxImportTests {
    @Test func importKeepsOnlySamplesFromTheHistoryStart() async throws {
        let text = InboxFile.write(hr: [HRSample(ts: 90, bpm: 70), HRSample(ts: 110, bpm: 72)],
                                   rr: [RRInterval(ts: 95, rrMs: 850, ord: 0, seq: 0),
                                        RRInterval(ts: 111, rrMs: 830, ord: 0, seq: 1)])
        let sink = RecordingSink()
        let result = try await InboxImporter.importFile(text, into: sink, notBefore: 100)
        #expect(result.samples == 2)
        let written = await sink.written
        #expect(written.flatMap(\.hr).map(\.ts) == [110])
        #expect(written.flatMap(\.rr).map(\.ts) == [111])
    }

    @Test func aFileWithNothingNewWritesNothing() async throws {
        let sink = RecordingSink()
        let result = try await InboxImporter.importFile(InboxFile.write(hr: [HRSample(ts: 5, bpm: 60)], rr: []),
                                                        into: sink, notBefore: 100)
        #expect(result.samples == 0)
        #expect(result.span == nil)
        #expect(await sink.written.isEmpty)
    }
}
