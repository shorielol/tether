import XCTest
import WhoopProtocol
@testable import WhoopStore

// tether: Tether's own policy tests. A WHOOP 5 window is read hour by hour from whichever scoring
// transport banked more beats in that hour, so a night recorded only over the live link still scores
// after the strap's history (a sparser channel) arrives for a later hour.
final class TetherHourlySourceTests: XCTestCase {
    private let id = "tether-strap"

    private func beats(_ range: Range<Int>, ms: Int, _ channel: RRSourceChannel?) -> [RRInterval] {
        range.map { RRInterval(ts: $0, rrMs: ms, srcChannel: channel) }
    }

    private func read(_ store: WhoopStore, from: Int, to: Int) async throws -> [RRInterval] {
        try await store.rrIntervals(deviceId: id, from: from, to: to, limit: 100_000)
    }

    func testANightOfLiveBeatsStillScoresAfterHistoryArrivesForALaterHour() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.insert(Streams(rr: beats(0..<3_600, ms: 1_000, .whoop5Standard)), deviceId: id)
        _ = try await store.insert(Streams(rr: beats(18_000..<18_060, ms: 990, .whoop5Historical)), deviceId: id)
        let night = try await read(store, from: 0, to: 3_599)
        XCTAssertEqual(night.count, 3_600)
        let day = try await read(store, from: 0, to: 20_000)
        XCTAssertEqual(day.count, 3_660, "each hour keeps its own source")
    }

    func testEachHourUsesTheSourceWithMoreBeats() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.insert(Streams(rr: beats(0..<100, ms: 1_000, .whoop5Standard)
                                         + beats(100..<110, ms: 990, .whoop5Historical)
                                         + beats(3_600..<3_605, ms: 1_000, .whoop5Standard)
                                         + beats(3_605..<3_655, ms: 990, .whoop5Historical)), deviceId: id)
        let rows = try await read(store, from: 0, to: 7_199)
        XCTAssertEqual(rows.filter { $0.ts < 3_600 }.map(\.srcChannel), Array(repeating: .whoop5Standard, count: 100))
        XCTAssertEqual(rows.filter { $0.ts >= 3_600 }.map(\.srcChannel), Array(repeating: .whoop5Historical, count: 50))
    }

    func testATiedHourGoesToTheStrapsHistory() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.insert(Streams(rr: beats(0..<10, ms: 1_000, .whoop5Standard)
                                         + beats(10..<20, ms: 990, .whoop5Historical)), deviceId: id)
        let rows = try await read(store, from: 0, to: 3_599)
        XCTAssertEqual(Set(rows.map(\.srcChannel)), [.whoop5Historical])
    }

    func testOldUnlabelledLiveBeatsAreLabelledAsTheStandardLink() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.insert(Streams(rr: beats(0..<30, ms: 1_000, nil)), deviceId: id)
        _ = try await store.insert(Streams(rr: beats(18_000..<18_010, ms: 990, .whoop5Historical)), deviceId: id)
        var night = try await read(store, from: 0, to: 3_599)
        XCTAssertTrue(night.isEmpty, "the bug: unlabelled beats are dropped once history exists")
        let labelled = try await store.labelLegacyRR(deviceId: id, as: .whoop5Standard)
        XCTAssertEqual(labelled, 30)
        night = try await read(store, from: 0, to: 3_599)
        XCTAssertEqual(night.count, 30)
        let again = try await store.labelLegacyRR(deviceId: id, as: .whoop5Standard)
        XCTAssertEqual(again, 0, "running it twice changes nothing")
        let other = try await store.labelLegacyRR(deviceId: "someone-else", as: .whoop5Standard)
        XCTAssertEqual(other, 0)
    }
}
