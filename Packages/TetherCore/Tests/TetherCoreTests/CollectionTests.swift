import Testing
import WhoopProtocol
@testable import TetherCore

@Suite("Ownership cutoff")
struct OwnershipCutoffTests {
    @Test func admitsOnlySamplesFromThePairingTimeOn() {
        let cutoff = OwnershipCutoff(pairedAt: 1_000)
        #expect(!cutoff.admits(999))
        #expect(cutoff.admits(1_000))
        #expect(cutoff.admits(5_000))
    }
}

@Suite("Sample batcher")
struct SampleBatcherTests {
    private func m(_ bpm: Int, _ rr: [Int] = []) -> HeartRateMeasurement {
        HeartRateMeasurement(bpm: bpm, rrMs: rr, contact: .detected)
    }

    @Test func turnsMeasurementsIntoStreams() {
        var batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: 0))
        batcher.append(m(60, [1000]), at: 100)
        batcher.append(m(61, [980, 990]), at: 101)
        let streams = batcher.drain()
        #expect(streams.hr == [HRSample(ts: 100, bpm: 60), HRSample(ts: 101, bpm: 61)])
        #expect(streams.rr.map(\.rrMs) == [1000, 980, 990])
        #expect(streams.rr.map(\.ts) == [100, 101, 101])
    }

    @Test func liveBeatsAreLabelledAsTheStrapsStandardHeartRateLink() {
        var batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: 0))
        batcher.append(m(60, [1000, 990]), at: 100)
        #expect(batcher.drain().rr.map(\.srcChannel) == [.whoop5Standard, .whoop5Standard])
    }

    @Test func beatsInTheSameSecondGetDistinctOrderAndSequence() {
        var batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: 0))
        batcher.append(m(70, [850, 850]), at: 200)
        let rr = batcher.drain().rr
        #expect(rr.map(\.ord) == [0, 1])
        #expect(rr.map(\.seq) == [0, 1])
    }

    @Test func keepsOneHeartRatePerSecond() {
        var batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: 0))
        batcher.append(m(60), at: 300)
        batcher.append(m(62), at: 300)
        #expect(batcher.drain().hr == [HRSample(ts: 300, bpm: 62)])
    }

    @Test func dropsEverythingBeforeTheCutoff() {
        var batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: 500))
        batcher.append(m(60, [1000]), at: 499)
        batcher.append(m(61, [990]), at: 500)
        let streams = batcher.drain()
        #expect(streams.hr.map(\.ts) == [500])
        #expect(streams.rr.map(\.ts) == [500])
    }

    @Test func drainEmptiesTheBatch() {
        var batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: 0))
        batcher.append(m(60), at: 1)
        _ = batcher.drain()
        #expect(batcher.isEmpty)
        #expect(batcher.drain().hr.isEmpty)
    }
}

@Suite("Coverage")
struct CoverageTests {
    @Test func fullyCapturedWindowIsOneHundredPercent() {
        let report = Coverage.compute(timestamps: Array(0...99), window: 0...99)
        #expect(report.capturedSeconds == 100)
        #expect(report.gaps.isEmpty)
        #expect(report.fraction == 1)
    }

    @Test func shortDropoutsUnderTheThresholdDoNotCount() {
        let ts = Array(0...10) + Array(14...20)
        let report = Coverage.compute(timestamps: ts, window: 0...20, maxGapSeconds: 5)
        #expect(report.gaps.isEmpty)
        #expect(report.fraction == 1)
    }

    @Test func longGapsAreReportedAndSubtracted() {
        let ts = Array(0...9) + Array(70...99)
        let report = Coverage.compute(timestamps: ts, window: 0...99, maxGapSeconds: 5)
        #expect(report.gaps == [10...69])
        #expect(report.capturedSeconds == 40)
        #expect(report.fraction == 0.4)
    }

    @Test func missingStartAndEndOfTheWindowAreGaps() {
        let report = Coverage.compute(timestamps: Array(20...79), window: 0...99, maxGapSeconds: 5)
        #expect(report.gaps == [0...19, 80...99])
        #expect(report.capturedSeconds == 60)
    }

    @Test func emptyWindowHasNoCoverage() {
        let report = Coverage.compute(timestamps: [], window: 0...59)
        #expect(report.capturedSeconds == 0)
        #expect(report.gaps == [0...59])
        #expect(report.fraction == 0)
    }
}
