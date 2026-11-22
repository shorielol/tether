import Foundation
import Observation
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore

/// Where collected samples go. Production writes to NOOP's `WhoopStore`; tests use a fake.
public protocol SampleSink: Sendable {
    func write(_ batch: SampleBatch) async throws
    /// Removes every stored sample timestamped at or after `from`.
    func erase(from: Int) async throws
    /// Seconds in `from...to` that already have a heart-rate sample. Imports use it to skip
    /// seconds this store recorded itself.
    func hrSeconds(from: Int, to: Int) async throws -> Set<Int>
}

public extension SampleSink {
    func hrSeconds(from: Int, to: Int) async throws -> Set<Int> { [] }

    /// Saves a chunk of the strap's history and says how many rows it held.
    func writeHistory(_ batch: SampleBatch) async throws -> Int {
        try await write(batch)
        let s = batch.streams
        return s.hr.count + s.rr.count + s.skinTemp.count + s.gravity.count + s.resp.count + s.spo2.count
    }
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
        // Beats saved before live R-R carried a source label would otherwise drop out of scoring once
        // the strap's history arrives. Only unlabelled rows change, so this is a no-op after the first run.
        _ = try await opened.labelLegacyRR(deviceId: Self.deviceId, as: .whoop5Standard)
        store = opened
        return opened
    }

    public func write(_ batch: SampleBatch) async throws {
        try await openStore().insert(batch.streams, deviceId: Self.deviceId)
    }

    public func erase(from: Int) async throws {
        try await openStore().deleteLiveSamples(deviceId: Self.deviceId, from: from)
    }

    public func hrSeconds(from: Int, to: Int) async throws -> Set<Int> {
        let samples = try await openStore().hrSamples(deviceId: Self.deviceId, from: from, to: to, limit: to - from + 1)
        return Set(samples.map(\.ts))
    }

    /// Reads HR and R-R for a time range back out, wrapped so it can leave the actor.
    public func readBack(from: Int, to: Int, limit: Int = 100_000) async throws -> SampleBatch {
        let store = try await openStore()
        let hr = try await store.hrSamples(deviceId: Self.deviceId, from: from, to: to, limit: limit)
        let rr = try await store.rrIntervals(deviceId: Self.deviceId, from: from, to: to, limit: limit)
        return SampleBatch(Streams(hr: hr, rr: rr))
    }

    /// The strap's motion between two times, from its history. Empty until a history sync has brought some.
    public func gravity(from: Int, to: Int, limit: Int = 100_000) async throws -> [GravitySample] {
        try await openStore().gravitySamples(deviceId: Self.deviceId, from: from, to: to, limit: limit)
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
    /// The strap was handed to another device on purpose; nothing reconnects until `reclaim`.
    public private(set) var isReleased = false
    public private(set) var dataLink: StrapDataLink = .unavailable
    public private(set) var isSyncingHistory = false
    /// When the last history sync ended (unix seconds), kept across launches.
    public private(set) var lastHistorySync: Int?
    /// The app was opened while the strap was away; sync when it next connects.
    @ObservationIgnored private var syncOnConnect = false
    /// The oldest moment the strap's history has filled in since the nights were last rescored, kept across
    /// launches. Nights from that day on get scored again so minutes the phone missed count.
    public private(set) var historyRescoreFrom: Int?
    public private(set) var lastHistoryOutcome: StrapHistoryOutcome?
    /// Called when a history sync ends, so the app can rescore the days it filled in.
    @ObservationIgnored public var onHistorySynced: ((StrapHistoryOutcome) -> Void)?
    /// A double-tap on the strap: when it was tapped, and whether it's fresh enough to ask about now.
    @ObservationIgnored public var onMark: ((Int, Bool) -> Void)?
    /// The last hour of live heart rate, for the smart wake window's cue.
    @ObservationIgnored private var recentHR: [HRSample] = []
    @ObservationIgnored private var lastSmartCheck = 0
    /// How often, inside the window, to look for the cue.
    static let smartCheckSeconds = 30
    /// A tap older than this arrived late (from history), so it's saved without asking about it.
    public static let freshTapSeconds = 2 * 60
    /// The strap's silent alarm, set over the data link.
    @ObservationIgnored public let alarm: AlarmKeeper

    @ObservationIgnored private let source: any HeartDataSource
    @ObservationIgnored private let sink: any SampleSink
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Int
    @ObservationIgnored private var batcher: SampleBatcher?
    @ObservationIgnored private var pending: [Streams] = []
    @ObservationIgnored private var autoFlush: Task<Void, Never>?
    @ObservationIgnored private var history: StrapHistorySession?
    @ObservationIgnored private var historyIdle: Task<Void, Never>?
    @ObservationIgnored private var historyTicker: Task<Void, Never>?

    private static let pairedAtKey = "tether.pairedAt"
    private static let lastHistorySyncKey = "tether.history.lastSync"
    private static let historyRescoreKey = "tether.history.rescoreFrom"
    /// A ready data link syncs on its own when the last sync is at least this old.
    public static let historySyncInterval = 30 * 60
    /// Opening the app syncs unless the last sync is younger than this, so flicking between apps
    /// doesn't re-read the strap.
    public static let openSyncInterval = 2 * 60
    /// While the link stays up, how often to check whether a sync is due.
    static let heartbeatSeconds = 5 * 60

    public init(source: any HeartDataSource, sink: any SampleSink, defaults: UserDefaults = .standard,
                now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.source = source
        self.sink = sink
        self.defaults = defaults
        self.now = now
        alarm = AlarmKeeper(defaults: defaults, now: now) { [source] frame in
            guard StrapCommandPolicy.allows(frame) else { return }
            source.sendStrapCommand(frame)
        }
        if defaults.object(forKey: Self.pairedAtKey) != nil {
            let saved = defaults.integer(forKey: Self.pairedAtKey)
            pairedAt = saved
            batcher = SampleBatcher(cutoff: OwnershipCutoff(pairedAt: saved))
        }
        if defaults.object(forKey: Self.historyRescoreKey) != nil {
            historyRescoreFrom = defaults.integer(forKey: Self.historyRescoreKey)
        }
        if defaults.object(forKey: Self.lastHistorySyncKey) != nil {
            lastHistorySync = defaults.integer(forKey: Self.lastHistorySyncKey)
        }
        source.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: Strap history

    /// After a refusal, sends the hello again on the current connection.
    public func retryDataLink() {
        source.retryDataLink()
    }

    /// Starts a history sync now if the data link is ready and none is running.
    public func syncHistoryNow() {
        guard let pairedAt, dataLink == .ready, !isSyncingHistory, !isReleased else { return }
        let sink = self.sink
        let session = StrapHistorySession(
            cutoff: OwnershipCutoff(pairedAt: pairedAt),
            write: { [weak self] frame in
                guard StrapCommandPolicy.allows(frame) else { return }
                self?.source.sendStrapCommand(frame)
            },
            save: { [weak self] streams in
                let rows = try await sink.writeHistory(SampleBatch(streams))
                if let oldest = streams.hr.map(\.ts).min() { await self?.historyFilledIn(from: oldest) }
                return rows
            },
            now: now)
        session.onFinish = { [weak self] outcome in self?.finishHistory(outcome) }
        history = session
        isSyncingHistory = true
        session.start()
        armHistoryIdle()
    }

    private func historyFilledIn(from oldest: Int) {
        let from = min(historyRescoreFrom ?? oldest, oldest)
        historyRescoreFrom = from
        defaults.set(from, forKey: Self.historyRescoreKey)
    }

    /// The nights from `from` on have been scored again. Older history that arrived meanwhile stays marked.
    public func historyRescored(from: Int) {
        guard let marked = historyRescoreFrom, marked >= from else { return }
        historyRescoreFrom = nil
        defaults.removeObject(forKey: Self.historyRescoreKey)
    }

    /// The app was opened: read the strap now if it's connected, or as soon as it connects, so the
    /// numbers on screen include what the strap stored while the phone wasn't listening.
    public func appOpened() {
        if let last = lastHistorySync, now() - last < Self.openSyncInterval { return }
        guard dataLink == .ready else {
            syncOnConnect = true
            return
        }
        syncHistoryNow()
    }

    private func syncHistoryIfDue() {
        if syncOnConnect {
            syncOnConnect = false
            if let last = lastHistorySync, now() - last < Self.openSyncInterval { return }
            syncHistoryNow()
            return
        }
        if let last = lastHistorySync, now() - last < Self.historySyncInterval { return }
        syncHistoryNow()
    }

    /// Called every few minutes while the data link is up, so history keeps arriving without a reconnect.
    func historyHeartbeat() {
        guard dataLink == .ready else { return }
        alarm.tick()
        syncHistoryIfDue()
    }

    private func startHistoryHeartbeat() {
        historyTicker?.cancel()
        historyTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatSeconds))
                guard !Task.isCancelled else { return }
                self?.historyHeartbeat()
            }
        }
    }

    /// The strap stopped sending mid-sync. The idle timer calls this; tests call it directly.
    func historyWentQuiet() {
        history?.idleTimeout()
    }

    /// Feeds frames and waits until the session has handled them. For tests and replays.
    func receiveStrapFrames(_ frames: [[UInt8]]) async {
        await history?.receiveAll(frames)
    }

    private func armHistoryIdle() {
        historyIdle?.cancel()
        historyIdle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(StrapHistorySession.idleTimeoutSeconds))
            guard !Task.isCancelled else { return }
            self?.historyWentQuiet()
        }
    }

    private func finishHistory(_ outcome: StrapHistoryOutcome) {
        historyIdle?.cancel()
        historyIdle = nil
        history = nil
        isSyncingHistory = false
        lastHistoryOutcome = outcome
        if outcome != .saveFailed {
            let ended = now()
            lastHistorySync = ended
            defaults.set(ended, forKey: Self.lastHistorySyncKey)
        }
        onHistorySynced?(outcome)
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

    /// Saves what's collected, then lets go of the strap while staying paired.
    public func release() async {
        isReleased = true
        source.releaseStrap()
        await flush()
        heartRate = nil
        lastSampleAt = nil
    }

    public func reclaim() {
        isReleased = false
        source.reclaimStrap()
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

    /// Inside the smart wake window, moves the alarm earlier once heart rate shows you're surfacing.
    private func watchForSurfacing(bpm: Int, at ts: Int) {
        recentHR.append(HRSample(ts: ts, bpm: bpm))
        guard ts - lastSmartCheck >= Self.smartCheckSeconds else { return }
        lastSmartCheck = ts
        recentHR.removeAll { $0.ts <= ts - SmartWake.lookbackSeconds }
        if alarm.inSmartWindow, SmartWake.surfacing(recentHR, now: ts) { alarm.wakeEarly() }
    }

    /// Saves a tap with the next write and tells the app. Taps from before pairing aren't the owner's.
    private func markTapped(at ts: Int) {
        guard let pairedAt, ts >= pairedAt else { return }
        var streams = Streams(hr: [], rr: [])
        streams.events = [WhoopEvent(ts: ts, kind: StrapTap.kind, payload: [:])]
        pending.append(streams)
        onMark?(ts, now() - ts <= Self.freshTapSeconds)
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
            watchForSurfacing(bpm: measurement.bpm, at: ts)
        case .battery(let percent):
            batteryPercent = percent
        case .firmware(let version):
            firmware = version
        case .dataLink(let state):
            dataLink = state
            alarm.linkChanged(ready: state == .ready)
            if state == .ready {
                syncHistoryIfDue()
                startHistoryHeartbeat()
            } else {
                historyTicker?.cancel()
                historyTicker = nil
                historyWentQuiet()
            }
        case .strapFrame(let frame):
            if alarm.receive(frame) { return }
            if let tapped = StrapTap.timestamp(of: frame) {
                markTapped(at: tapped)
                return
            }
            guard let history else { return }
            history.receive(frame)
            armHistoryIdle()
        }
    }
}
