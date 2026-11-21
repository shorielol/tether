import WhoopProtocol

/// The strap had an owner before. Nothing timestamped before Tether's pairing is ever stored.
public struct OwnershipCutoff: Equatable, Sendable {
    public let pairedAt: Int

    public init(pairedAt: Int) {
        self.pairedAt = pairedAt
    }

    public func admits(_ ts: Int) -> Bool {
        ts >= pairedAt
    }
}

/// Collects live measurements between store writes and hands them over as NOOP `Streams`.
public struct SampleBatcher {
    private let cutoff: OwnershipCutoff
    private var hrBySecond: [Int: Int] = [:]
    private var rr: [RRInterval] = []
    private var seqInSecond: [Int: Int] = [:]

    public init(cutoff: OwnershipCutoff) {
        self.cutoff = cutoff
    }

    public var isEmpty: Bool { hrBySecond.isEmpty && rr.isEmpty }

    /// One notification at wall-clock second `ts`. A later heart rate in the same second replaces the earlier one.
    public mutating func append(_ measurement: HeartRateMeasurement, at ts: Int) {
        guard cutoff.admits(ts) else { return }
        hrBySecond[ts] = measurement.bpm
        for (order, rrMs) in measurement.rrMs.enumerated() {
            let seq = seqInSecond[ts, default: 0]
            seqInSecond[ts] = seq + 1
            rr.append(RRInterval(ts: ts, rrMs: rrMs, ord: order, seq: seq))
        }
    }

    /// Everything collected since the last drain, in time order. Leaves the batcher empty.
    public mutating func drain() -> Streams {
        let hr = hrBySecond.keys.sorted().map { HRSample(ts: $0, bpm: hrBySecond[$0]!) }
        let streams = Streams(hr: hr, rr: rr)
        hrBySecond = [:]
        rr = []
        seqInSecond = [:]
        return streams
    }
}

/// How much of a time window has heart-rate samples, and where the holes are.
public struct CoverageReport: Equatable, Sendable {
    public let window: ClosedRange<Int>
    public let capturedSeconds: Int
    public let gaps: [ClosedRange<Int>]

    public var fraction: Double {
        Double(capturedSeconds) / Double(window.count)
    }

    public init(window: ClosedRange<Int>, capturedSeconds: Int, gaps: [ClosedRange<Int>]) {
        self.window = window
        self.capturedSeconds = capturedSeconds
        self.gaps = gaps
    }
}

public enum Coverage {
    /// A dropout longer than `maxGapSeconds` counts as lost time. Shorter ones are normal Bluetooth jitter.
    public static func compute(timestamps: [Int], window: ClosedRange<Int>, maxGapSeconds: Int = 5) -> CoverageReport {
        let inside = Array(Set(timestamps.filter { window.contains($0) })).sorted()
        guard let first = inside.first, let last = inside.last else {
            return CoverageReport(window: window, capturedSeconds: 0, gaps: [window])
        }
        var gaps: [ClosedRange<Int>] = []
        if first - window.lowerBound > maxGapSeconds {
            gaps.append(window.lowerBound...(first - 1))
        }
        for (a, b) in zip(inside, inside.dropFirst()) where b - a > maxGapSeconds {
            gaps.append((a + 1)...(b - 1))
        }
        if window.upperBound - last > maxGapSeconds {
            gaps.append((last + 1)...window.upperBound)
        }
        let lost = gaps.reduce(0) { $0 + $1.count }
        return CoverageReport(window: window, capturedSeconds: window.count - lost, gaps: gaps)
    }
}
