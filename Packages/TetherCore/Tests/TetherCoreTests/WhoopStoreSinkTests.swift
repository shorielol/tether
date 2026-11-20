import Foundation
import Testing
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore
@testable import TetherCore

@Suite("WhoopStore sink")
struct WhoopStoreSinkTests {
    @Test func writtenSamplesReadBackFromTheStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tether-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = WhoopStoreSink(path: dir.appendingPathComponent("tether.sqlite").path)
        let streams = Streams(hr: [HRSample(ts: 1_000, bpm: 58), HRSample(ts: 1_001, bpm: 59)],
                              rr: [RRInterval(ts: 1_000, rrMs: 1_030, ord: 0, seq: 0)])
        try await sink.write(SampleBatch(streams))
        let back = try await sink.readBack(from: 0, to: 2_000).streams
        #expect(back.hr.map(\.bpm) == [58, 59])
        #expect(back.rr.map(\.rrMs) == [1_030])
    }
}
