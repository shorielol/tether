import Foundation
@preconcurrency import WhoopProtocol

// tether: a lean port of NOOP's WHOOP 5 offload flow (Strand/BLE/BLEManager.swift beginBackfill /
// ackHistoricalChunk, Strand/Collect/Backfiller.swift ingest / finishChunk). PolyForm NC, notice kept.

/// The command numbers Tether sends to a WHOOP 5 strap's command characteristic.
public enum WhoopCommandCode {
    public static let sendHistoricalData: UInt8 = 22
    public static let historicalDataResult: UInt8 = 23
    /// The static WHOOP 5 CLIENT_HELLO that opens the data link (WhoopProtocol's
    /// `DeviceFamily.whoop5ClientHello`, which the package keeps internal).
    public static let clientHello: [UInt8] = [0xaa, 0x01, 0x08, 0x00, 0x00, 0x01, 0xe6, 0x71,
                                              0x23, 0x01, 0x91, 0x01, 0x36, 0x3e, 0x5c, 0x8d]
}

public enum StrapHistoryOutcome: Equatable, Sendable {
    /// The strap said it has nothing more to hand over.
    case caughtUp(rows: Int)
    /// The strap went quiet; what was saved stays saved, and the next sync carries on from there.
    case timedOut(rows: Int)
    /// A chunk couldn't be stored. It was not acknowledged, so the strap keeps it for next time.
    case saveFailed
}

/// One history sync with a WHOOP 5 strap: ask for the stored history, then for every chunk decode
/// it, drop anything from before this phone paired, save it, and only then acknowledge it, which
/// lets the strap delete it. Never acknowledges a chunk that wasn't saved.
@MainActor
public final class StrapHistorySession {
    /// How long the strap may stay silent mid-sync before the session ends.
    public static let idleTimeoutSeconds = 60
    /// Each request drains one stretch of history; keep asking while chunks keep coming, up to this many.
    static let maxRequests = 30
    /// Offload frame types at the WHOOP 5 inner-record start: history, event, metadata, console logs.
    static let offloadTypes: Set<UInt8> = [47, 48, 49, 50, 56]
    static let typeIndex = 8
    /// A WHOOP 5 HISTORY_END carries the 8-byte block the acknowledgement echoes back here.
    static let endDataRange = 21..<29

    public var onFinish: ((StrapHistoryOutcome) -> Void)?
    public private(set) var isRunning = false
    public private(set) var rowsSaved = 0

    private let cutoff: OwnershipCutoff
    private let write: ([UInt8]) -> Void
    private let save: (Streams) async throws -> Int
    private let now: () -> Int
    private let classify: ([UInt8]) -> HistoricalMeta
    private var seq: UInt8 = 0
    private var requests = 0
    private var chunksSinceRequest = 0
    private var chunk: [[UInt8]] = []
    private var chunkOpen = false
    private var queue: [[UInt8]] = []
    private var drain: Task<Void, Never>?

    public init(cutoff: OwnershipCutoff,
                write: @escaping ([UInt8]) -> Void,
                save: @escaping (Streams) async throws -> Int,
                now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
                classify: (([UInt8]) -> HistoricalMeta)? = nil) {
        self.cutoff = cutoff
        self.write = write
        self.save = save
        self.now = now
        self.classify = classify ?? { classifyHistoricalMeta(parseFrame($0, family: .whoop5)) }
    }

    public func start() {
        isRunning = true
        rowsSaved = 0
        requests = 0
        request()
    }

    /// Feed every complete frame from the strap's data characteristics. Live frames are ignored.
    public func receive(_ frame: [UInt8]) {
        guard isRunning, Self.isOffloadFrame(frame) else { return }
        queue.append(frame)
        guard drain == nil else { return }
        drain = Task { [weak self] in await self?.drainQueue() }
    }

    /// The strap has been silent for `idleTimeoutSeconds`.
    public func idleTimeout() {
        guard isRunning else { return }
        finish(.timedOut(rows: rowsSaved))
    }

    static func isOffloadFrame(_ frame: [UInt8]) -> Bool {
        frame.count > typeIndex && offloadTypes.contains(frame[typeIndex])
    }

    /// Feeds frames and waits until they've been handled. For tests and replays.
    func receiveAll(_ frames: [[UInt8]]) async {
        frames.forEach(receive)
        await drain?.value
    }

    private func request() {
        requests += 1
        chunksSinceRequest = 0
        chunk.removeAll()
        chunkOpen = true
        // The payload must be [0x00]: an empty payload gets no history back (NOOP, verified on hardware).
        write(puffinCommandFrame(cmd: WhoopCommandCode.sendHistoricalData, seq: nextSeq(), payload: [0x00]))
    }

    private func drainQueue() async {
        while isRunning, !queue.isEmpty {
            await handle(queue.removeFirst())
        }
        queue.removeAll()
        drain = nil
    }

    private func handle(_ frame: [UInt8]) async {
        switch classify(frame) {
        case .start:
            chunk.removeAll()
            chunkOpen = true
        case .other:
            if chunkOpen { chunk.append(frame) }
        case .end:
            await finishChunk(endFrame: frame)
        case .complete:
            chunk.removeAll()
            chunkOpen = false
            if chunksSinceRequest > 0, requests < Self.maxRequests {
                request()
            } else {
                finish(.caughtUp(rows: rowsSaved))
            }
        }
    }

    private func finishChunk(endFrame: [UInt8]) async {
        guard endFrame.count >= Self.endDataRange.upperBound else { return }
        let endData = Array(endFrame[Self.endDataRange])
        let frames = chunk
        chunk.removeAll()
        // A WHOOP 5 record carries real unix time, so the clock reference is identity.
        let clock = now()
        let parsed = frames.map { parseFrame($0, family: .whoop5) }
        let streams = extractHistoricalStreams(parsed, deviceClockRef: clock, wallClockRef: clock, family: .whoop5)
        do {
            rowsSaved += try await save(cutoff.admitting(streams))
        } catch {
            finish(.saveFailed)
            return
        }
        guard isRunning else { return }
        chunksSinceRequest += 1
        write(whoop5HistoricalAckFrame(endData: endData, seq: nextSeq()))
    }

    private func finish(_ outcome: StrapHistoryOutcome) {
        guard isRunning else { return }
        isRunning = false
        queue.removeAll()
        chunk.removeAll()
        onFinish?(outcome)
    }

    private func nextSeq() -> UInt8 {
        seq &+= 1
        return seq
    }
}

extension OwnershipCutoff {
    /// The same streams with everything from before this phone paired removed. Waveforms and raw
    /// optical channels are dropped too: Tether scores none of them.
    func admitting(_ streams: Streams) -> Streams {
        var owned = streams
        owned.hr = streams.hr.filter { admits($0.ts) }
        owned.rr = streams.rr.filter { admits($0.ts) }
        owned.spo2 = streams.spo2.filter { admits($0.ts) }
        owned.skinTemp = streams.skinTemp.filter { admits($0.ts) }
        owned.resp = streams.resp.filter { admits($0.ts) }
        owned.gravity = streams.gravity.filter { admits($0.ts) }
        owned.steps = streams.steps.filter { admits($0.ts) }
        owned.sleepState = streams.sleepState.filter { admits($0.ts) }
        owned.v18Aux = streams.v18Aux.filter { admits($0.ts) }
        owned.events = streams.events.filter { admits($0.ts) }
        owned.battery = streams.battery.filter { admits($0.ts) }
        owned.ppgHr = []
        owned.ppgWaveform = []
        owned.ecgWaveform = []
        return owned
    }
}
