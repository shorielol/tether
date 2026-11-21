import Foundation
@preconcurrency import WhoopProtocol

/// Heart rate and R-R the Mac recorded itself, waiting in `inbox/mac/` for the phone to import.
/// Lines are `h,ts,bpm` and `r,ts,rr_ms,ord,seq` under a `tether-inbox: 1` first line.
public enum InboxFile {
    public static let version = 1

    public enum ReadError: Error, Equatable { case unsupported, badLine(Int) }

    public static func write(hr: [HRSample], rr: [RRInterval]) -> String {
        var out = "tether-inbox: \(version)\n"
        for sample in hr { out += "h,\(sample.ts),\(sample.bpm)\n" }
        for beat in rr { out += "r,\(beat.ts),\(beat.rrMs),\(beat.ord ?? 0),\(beat.seq)\n" }
        return out
    }

    public static func read(_ text: String) throws -> (hr: [HRSample], rr: [RRInterval]) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.first == "tether-inbox: \(version)" else { throw ReadError.unsupported }
        lines.removeFirst()
        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        for (index, line) in lines.enumerated() {
            let parts = line.split(separator: ",").map(String.init)
            switch parts.first {
            case "h" where parts.count == 3:
                guard let ts = Int(parts[1]), let bpm = Int(parts[2]) else { throw ReadError.badLine(index + 2) }
                hr.append(HRSample(ts: ts, bpm: bpm))
            case "r" where parts.count == 5:
                guard let ts = Int(parts[1]), let ms = Int(parts[2]), let ord = Int(parts[3]), let seq = Int(parts[4]) else {
                    throw ReadError.badLine(index + 2)
                }
                rr.append(RRInterval(ts: ts, rrMs: ms, ord: ord, seq: seq))
            default:
                throw ReadError.badLine(index + 2)
            }
        }
        return (hr, rr)
    }

    /// `inbox/mac/<start>-<end>.csv`
    public static func relativePath(from start: Int, to end: Int) -> String { "inbox/mac/\(start)-\(end).csv" }
}
