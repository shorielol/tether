import Foundation
import TetherCore
@preconcurrency import WhoopProtocol

/// Brings the Mac's recordings into the phone's store. The ownership cutoff applies here too:
/// nothing timestamped before the history start is kept.
public enum InboxImporter {
    /// Returns how many samples (heart rate plus R-R) were written.
    public static func importFile(_ text: String, into sink: any SampleSink, notBefore cutoff: Int) async throws -> Int {
        let parsed = try InboxFile.read(text)
        let hr = parsed.hr.filter { $0.ts >= cutoff }
        let rr = parsed.rr.filter { $0.ts >= cutoff }
        guard !hr.isEmpty || !rr.isEmpty else { return 0 }
        try await sink.write(SampleBatch(Streams(hr: hr, rr: rr)))
        return hr.count + rr.count
    }
}
