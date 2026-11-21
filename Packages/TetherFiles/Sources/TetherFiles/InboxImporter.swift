import Foundation
import TetherCore
@preconcurrency import WhoopProtocol

/// Brings the Mac's recordings into the phone's store. The ownership cutoff applies here too:
/// nothing timestamped before the history start is kept. Seconds the phone recorded itself are
/// skipped, so if both devices heard the strap at once its R-R isn't counted twice.
public enum InboxImporter {
    public struct Result: Equatable, Sendable {
        /// Heart-rate plus R-R samples written.
        public let samples: Int
        /// First to last second the Mac recorded in this file, after the cutoff. Nil when nothing was new.
        public let span: ClosedRange<Int>?
    }

    public static func importFile(_ text: String, into sink: any SampleSink, notBefore cutoff: Int) async throws -> Result {
        let parsed = try InboxFile.read(text)
        let hr = parsed.hr.filter { $0.ts >= cutoff }
        let rr = parsed.rr.filter { $0.ts >= cutoff }
        let stamps = hr.map(\.ts) + rr.map(\.ts)
        guard let first = stamps.min(), let last = stamps.max() else { return Result(samples: 0, span: nil) }
        let own = try await sink.hrSeconds(from: first, to: last)
        let newHR = hr.filter { !own.contains($0.ts) }
        let newRR = rr.filter { !own.contains($0.ts) }
        if !newHR.isEmpty || !newRR.isEmpty {
            try await sink.write(SampleBatch(Streams(hr: newHR, rr: newRR)))
        }
        return Result(samples: newHR.count + newRR.count, span: first...last)
    }
}
