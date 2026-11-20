import Foundation
import Observation
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore

/// Where collected samples go. Production writes to NOOP's `WhoopStore`; tests use a fake.
public protocol SampleSink: Sendable {
    func write(_ batch: SampleBatch) async throws
}

/// NOOP's `Streams` predates Swift 6 and isn't marked Sendable, but it is a struct of arrays of plain
/// value structs with no reference state, so handing a copy across actors is safe.
public struct SampleBatch: @unchecked Sendable {
    public let streams: Streams
    public init(_ streams: Streams) { self.streams = streams }
}

/// Writes into NOOP's SQLite store under one fixed device id: Tether only ever has one strap.
public actor WhoopStoreSink: SampleSink {
    public static let deviceId = "tether-strap"
    private let store: WhoopStore
    private var deviceRegistered = false

    public init(store: WhoopStore) {
        self.store = store
    }

    public func write(_ batch: SampleBatch) async throws {
        if !deviceRegistered {
            try await store.upsertDevice(id: Self.deviceId, mac: nil, name: "WHOOP 5.0")
            deviceRegistered = true
        }
        try await store.insert(batch.streams, deviceId: Self.deviceId)
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

    public func forgetStrap() {
        source.forget()
        heartRate = nil
        batteryPercent = nil
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
