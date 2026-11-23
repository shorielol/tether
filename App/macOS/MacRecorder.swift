import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import TetherCore
import TetherFiles

/// Tether for Mac's own strap link: records while the iPhone isn't holding the strap, hands the
/// recordings to the phone through `inbox/mac/`, and lets go again once the phone is back.
@MainActor
@Observable
final class MacRecorder {
    static let tickSeconds = 5
    static let exportSeconds = 5 * 60
    private static let cursorKey = "tether.mac.exportCursor"
    private static let keepAwakeKey = "tether.mac.keepAwake"
    private static let handedOverAtKey = "tether.mac.handedOverAt"

    let collector: LiveCollector
    /// When this Mac's current connection began.
    private(set) var connectedSince: Int?
    private(set) var lastExportAt: Date?
    private(set) var exportError: String?
    /// Set while the strap is handed to the iPhone, by hand or because the phone came back.
    private(set) var handedOverAt: Int?
    var keepAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepAwake, forKey: Self.keepAwakeKey)
            updateSleepAssertion()
        }
    }

    @ObservationIgnored private let sink: WhoopStoreSink
    @ObservationIgnored private let folder: () -> SharedFolder?
    @ObservationIgnored private let phoneSavedAt: () -> Int?
    @ObservationIgnored private let wantedStrapName: () -> String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastExportTick = 0
    @ObservationIgnored private var sleepAssertion: IOPMAssertionID?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?

    init(folder: @escaping () -> SharedFolder?, phoneSavedAt: @escaping () -> Int?,
         wantedStrapName: @escaping () -> String?) {
        self.folder = folder
        self.phoneSavedAt = phoneSavedAt
        self.wantedStrapName = wantedStrapName
        sink = WhoopStoreSink(path: Self.storePath())
        collector = LiveCollector(source: StandardHRSource(restoreIdentifier: nil), sink: sink)
        keepAwake = UserDefaults.standard.object(forKey: Self.keepAwakeKey) as? Bool ?? true
        if UserDefaults.standard.object(forKey: Self.handedOverAtKey) != nil {
            handedOverAt = UserDefaults.standard.integer(forKey: Self.handedOverAtKey)
        }
    }

    /// Who holds the strap, from this Mac's side.
    var holder: LinkHolder {
        LinkHolder.resolve(link: collector.link, heartRate: collector.heartRate, lastSampleAt: collector.lastSampleAt,
                           phoneSavedAt: phoneSavedAt(), now: Self.now)
    }

    var isRecording: Bool { collector.link == .connected && handedOverAt == nil }

    func start() {
        guard loop == nil else { return }
        collector.startAutoFlush()
        if handedOverAt != nil { Task { await collector.release() } }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
            }
        }
    }

    /// Starts looking for straps, for the pairing step.
    func startScan() { collector.startScan() }
    func stopScan() { collector.stopScan() }

    func pair(with strap: DiscoveredStrap) {
        collector.stopScan()
        collector.pair(with: strap.id)
        setExportCursor(to: (collector.pairedAt ?? Self.now) - 1)
    }

    /// The person asked for the iPhone to have the strap.
    func handToPhone() {
        markHandedOver(at: Self.now)
        Task { await collector.release() }
    }

    /// The person asked for this Mac to hold the strap again.
    func useOnThisMac() {
        markHandedOver(at: nil)
        collector.reclaim()
    }

    /// Flush and export straight away: the lid is closing or the person asked.
    func saveNow() {
        Task {
            await collector.flush()
            await export()
        }
    }

    /// Minute averages this Mac recorded itself in `window`, for drawing before the phone imports them.
    func minutes(in window: ClosedRange<Int>, profile: UserProfile?) async -> [TodaySnapshot.MinutePoint] {
        guard let batch = try? await sink.readBack(from: window.lowerBound, to: window.upperBound),
              !batch.streams.hr.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            TodayAnalytics.compute(hr: batch.streams.hr, rr: [], profile: profile, window: window,
                                   now: window.upperBound).minuteSeries
        }.value
    }

    func forget(erase: Bool) async {
        await collector.forgetStrap(erase: erase)
        markHandedOver(at: nil)
        UserDefaults.standard.removeObject(forKey: Self.cursorKey)
    }

    // MARK: - Loop

    private func tick() async {
        let now = Self.now
        trackConnection(now: now)
        autoPairIfNeeded()
        handOverIfNeeded(now: now)
        updateSleepAssertion()
        if now - lastExportTick >= Self.exportSeconds {
            lastExportTick = now
            await collector.flush()
            await export()
        }
    }

    private func trackConnection(now: Int) {
        if collector.link == .connected {
            if connectedSince == nil { connectedSince = now }
        } else {
            connectedSince = nil
        }
    }

    /// Before the first pairing, look for the strap the iPhone named in profile.md and pair with it.
    private func autoPairIfNeeded() {
        guard !collector.isPaired, let name = wantedStrapName() else { return }
        if let match = collector.discovered.first(where: { $0.name == name }) {
            pair(with: match)
        } else if collector.link != .scanning {
            collector.startScan()
        }
    }

    private func handOverIfNeeded(now: Int) {
        let phone = phoneSavedAt()
        if let handedOverAt {
            if HandOver.shouldReclaim(releasedAt: handedOverAt, phoneSavedAt: phone, now: now) { useOnThisMac() }
        } else if HandOver.shouldRelease(connectedSince: connectedSince, phoneSavedAt: phone, now: now) {
            handToPhone()
        }
    }

    private func export() async {
        guard let folder = folder(), let pairedAt = collector.pairedAt else { return }
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Int ?? pairedAt - 1
        let sink = sink
        do {
            let next = try await InboxExporter.export(
                after: cursor, now: Self.now,
                read: { from, to in try await sink.readBack(from: from, to: to) },
                write: { text, path in try folder.withAccess { try folder.write(text, to: path) } })
            setExportCursor(to: next)
            lastExportAt = .now
            exportError = nil
        } catch {
            exportError = "Couldn't send this Mac's recording to your iPhone's folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func setExportCursor(to value: Int) {
        UserDefaults.standard.set(value, forKey: Self.cursorKey)
    }

    private func markHandedOver(at value: Int?) {
        handedOverAt = value
        if let value { UserDefaults.standard.set(value, forKey: Self.handedOverAtKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.handedOverAtKey) }
    }

    /// Stops idle sleep while recording. A closed lid on battery still sleeps the Mac.
    private func updateSleepAssertion() {
        let wanted = keepAwake && isRecording
        if wanted, sleepAssertion == nil {
            var id = IOPMAssertionID(0)
            let made = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                   IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                   "Tether is recording your strap" as CFString, &id)
            if made == kIOReturnSuccess { sleepAssertion = id }
        } else if !wanted, let id = sleepAssertion {
            IOPMAssertionRelease(id)
            sleepAssertion = nil
        }
    }

    private static var now: Int { Int(Date().timeIntervalSince1970) }

    /// Application Support/Tether/mac.sqlite inside the app's container.
    private static func storePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tether", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("mac.sqlite").path
    }
}
