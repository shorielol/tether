import Foundation
import TetherCore
@preconcurrency import WhoopProtocol

/// Hands what the Mac recorded to the phone: everything after a saved cursor goes into one
/// `inbox/mac/<start>-<end>.csv`, and the cursor moves past it so nothing is sent twice.
public enum InboxExporter {
    /// The newest minute is left alone, so a second still being written is never split across files.
    public static let settleSeconds = 60

    /// Returns the new cursor. `read` gets an inclusive range; `write` gets the file text and its
    /// path relative to the shared folder. An empty range writes nothing but still moves the cursor.
    nonisolated(nonsending) public static func export(after cursor: Int, now: Int,
                              read: (Int, Int) async throws -> SampleBatch,
                              write: (String, String) throws -> Void) async throws -> Int {
        let end = now - settleSeconds
        guard end > cursor else { return cursor }
        let range = (cursor + 1)...end
        let streams = try await read(range.lowerBound, range.upperBound).streams
        let hr = streams.hr.filter { range.contains($0.ts) }
        let rr = streams.rr.filter { range.contains($0.ts) }
        let stamps = hr.map(\.ts) + rr.map(\.ts)
        if let first = stamps.min(), let last = stamps.max() {
            try write(InboxFile.write(hr: hr, rr: rr), InboxFile.relativePath(from: first, to: last))
        }
        return end
    }
}
