import Foundation
import Observation
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore

/// Where collected samples go. Production writes to NOOP's `WhoopStore`; tests use a fake.
public protocol SampleSink: Sendable {
    func write(_ batch: SampleBatch) async throws
    /// Removes every stored sample timestamped at or after `from`.
    func erase(from: Int) async throws
}

/// NOOP's `Streams` predates Swift 6 and isn't marked Sendable, but it is a struct of arrays of plain
/// value structs with no reference state, so handing a copy across actors is safe.
public struct SampleBatch: @unchecked Sendable {
    public let streams: Streams
    public init(_ streams: Streams) { self.streams = streams }
}

/// Writes into NOOP's SQLite store under one fixed device id: Tether only ever has one strap.
/// The database opens on the first write, so the app can create this without waiting.
public actor WhoopStoreSink: SampleSink {
    public static let deviceId = "tether-strap"
    private let path: String
    private var store: WhoopStore?

    public init(path: String) {
        self.path = path
    }

    public func openStore() async throws -> WhoopStore {
        if let store { return store }
        let opened = try await WhoopStore(path: path)
        try await opened.upsertDevice(id: Self.deviceId, mac: nil, name: "WHOOP 5.0")
        store = opened
        return opened
    }

    public func write(_ batch: SampleBatch) async throws {
        try await openStore().insert(batch.streams, deviceId: Self.deviceId)
    }

    public func erase(from: Int) async throws {
        try await openStore().deleteLiveSamples(deviceId: Self.deviceId, from: from)
    }

    /// Reads HR and R-R for a time range back out, wrapped so it can leave the actor.
    public func readBack(from: Int, to: Int, limit: Int = 100_000) async throws -> SampleBatch {
        let store = try await openStore()
        let hr = try await store.hrSamples(deviceId: Self.deviceId, from: from, to: to, limit: limit)
        let rr = try await store.rrIntervals(deviceId: Self.deviceId, from: from, to: to, limit: limit)
        return SampleBatch(Streams(hr: hr, rr: rr))
    }
}

/// The live link the screens watch, and the bridge from the source to storage.
@MainActor
@Observable
public final class LiveCollector {
    public private(set) var link: LinkState = .idle
    public private(set) var heartRate: Int?
    public private(set) var batteryPercent: Int?
    public private(set) var firmware: String?
    public private(set) var lastSampleAt: Int?
    public private(set) var discovered: [DiscoveredStrap] = []
    public private(set) var pairedAt: Int?
    public private(set) var lastWriteError: String?

    @ObservationIgnored private let source: any HeartDataSource
    @ObservationIgnored private let sink: any SampleSink
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Int
    @ObservationIgnored private var batcher: SampleBatcher?
    @ObservationIgnored private var pending: [Streams] = []
    @ObservationIgnored private var autoFlush: Task<Void, Never>?

    private static let pairedAtKey = "tether.pairedAt"

    public init(source: any HeartDataSource, sink: any SampleSink, defaults: UserDefaults = .standard,
                now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.source = source
        self.sink = sink
        self.defaults = defaults
        self.now = now
        if defaults.object(forKey: Self.pairedAtKey) != nil {
            let saved = defaults.integer(forKey: Self.pairedAtKey)
            pairedAt = saved
            batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: saved))
        }
        source.onEvent = { [weak self] event in self?.handle(event) }
    }

    public var isPaired: Bool { pairedAt != nil }

    public func startScan() {
        discovered = []
        source.startScan()
    }

    public func stopScan() {
        source.stopScan()
    }

    /// Pairing starts the owner's history: nothing timestamped before this moment is ever stored.
    public func pair(with strap: UUID) {
        let start = now()
        defaults.set(start, forKey: Self.pairedAtKey)
        pairedAt = start
        batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: start))
        source.connect(to: strap)
    }

    /// Ends the pairing: drops the strap, stops recording and clears the history start, so the next
    /// pairing begins fresh. `erase` also deletes what this pairing recorded (a strap picked by
    /// mistake); otherwise anything not yet saved is written first.
    public func forgetStrap(erase: Bool) async {
        let start = pairedAt
        source.forget()
        if erase {
            pending = []
        } else {
            await flush()
        }
        batcher = nil
        pairedAt = nil
        defaults.removeObject(forKey: Self.pairedAtKey)
        heartRate = nil
        batteryPercent = nil
        firmware = nil
        lastSampleAt = nil
        guard erase, let start else { return }
        do {
            try await sink.erase(from: start)
        } catch {
            lastWriteError = "Couldn't erase the forgotten strap's samples: \(error)"
        }
    }

    /// Writes everything collected since the last flush. A failed write is kept and retried next time.
    public func flush() async {
        if var batch = batcher, !batch.isEmpty {
            pending.append(batch.drain())
            batcher = batch
        }
        while let next = pending.first {
            do {
                try await sink.write(SampleBatch(next))
                pending.removeFirst()
                lastWriteError = nil
            } catch {
                lastWriteError = String(describing: error)
                return
            }
        }
    }

    public func startAutoFlush(every seconds: Int = 30) {
        autoFlush?.cancel()
        autoFlush = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                await self?.flush()
            }
        }
    }

    private func handle(_ event: HeartSourceEvent) {
        switch event {
        case .link(let state):
            link = state
        case .discovered(let strap):
            if let i = discovered.firstIndex(where: { $0.id == strap.id }) { discovered[i] = strap }
            else { discovered.append(strap) }
        case .measurement(let measurement, let ts):
            heartRate = measurement.bpm
            lastSampleAt = ts
            batcher?.append(measurement, at: ts)
        case .battery(let percent):
            batteryPercent = percent
        case .firmware(let version):
            firmware = version
        }
    }
}
