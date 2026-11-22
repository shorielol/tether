import Foundation
import Observation
import TetherCore
import TetherFiles
import TetherSnapshot
import UIKit
import UserNotifications
@preconcurrency import WhoopProtocol
import WidgetKit

/// Owns the one collector for the app's lifetime and the phone-side state the screens read.
@MainActor
@Observable
final class AppModel {
    private static let onboardedKey = "tether.onboarded"
    private static let expiryReminderId = "tether.expiry"
    /// One day at one sample a second, with headroom for R-R (more than one beat a second).
    private static let dayReadLimit = 250_000
    private static let scoringInterval: TimeInterval = 15 * 60
    private static let syncInterval: TimeInterval = 15 * 60
    private static let folderKey = "tether.folder"
    private static let macSpansKey = "tether.macSpans"
    /// Mac spans older than this are no longer written into any day file.
    private static let macSpanKeepSeconds = 3 * 86_400
    /// The morning pass looks for a finished night from 04:00 until this hour.
    private static let morningEndHour = 16
    /// In the morning window, pull the strap's history at most this often (seconds).
    private static let morningHistoryInterval = 30 * 60
    private static let morningTick: Duration = .seconds(60)

    let collector: LiveCollector
    private let sink: WhoopStoreSink
    /// Today's analytics from stored samples, refreshed every 30 s while the app is open.
    private(set) var today: TodaySnapshot?
    /// Today's stress and effort in depth, computed alongside `today` from the same samples.
    private(set) var stress: StressDetail?
    private(set) var effort: EffortDetail?
    /// Today's steps from the strap's own counter; it fills in with each history sync.
    private(set) var steps: DailySteps?
    @ObservationIgnored private var todayLoop: Task<Void, Never>?
    /// Scored nights, oldest first (last 30 days).
    private(set) var nights: [NightSummary] = []
    /// The most recent scoring of today's night, which also carries Charge drivers.
    private(set) var latestNight: NightSummary?
    private(set) var scoredNightCount = 0
    @ObservationIgnored private var lastScoredAt: Date?
    /// The iCloud Drive folder shared with the Mac.
    private(set) var folderName: String?
    private(set) var lastSavedAt: Date?
    private(set) var folderError: String?
    @ObservationIgnored private var lastSyncAt: Date?
    @ObservationIgnored private var lastMorningPassAt: Date?
    @ObservationIgnored private var morningLoop: Task<Void, Never>?
    @ObservationIgnored private let recordingCard = RecordingActivityController()
    private(set) var profile: UserProfile?
    private(set) var onboarded: Bool
    private(set) var phoneCharging: Bool?
    private(set) var lowPowerMode = false
    private(set) var storeError: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        let sink = WhoopStoreSink(path: Self.storePath())
        self.sink = sink
        collector = LiveCollector(source: StandardHRSource(opensDataLink: true), sink: sink, defaults: defaults)
        profile = UserProfile.load(from: defaults)
        onboarded = defaults.bool(forKey: Self.onboardedKey)
        collector.startAutoFlush(every: 30)
        collector.onHistorySynced = { [weak self] outcome in
            Task { await self?.historyArrived(outcome) }
        }
        collector.onMark = { [weak self] mark, fresh in
            guard let self else { return }
            Task { await self.refreshMarks() }
            if fresh { Task { await self.markNotifier.ask(about: mark, offering: self.markLabels.recent) } }
        }
        markNotifier.onAnswer = { [weak self] mark, label in self?.setLabel(label, for: mark) }
        UNUserNotificationCenter.current().delegate = markNotifier
        folderName = defaults.data(forKey: Self.folderKey).flatMap(SharedFolder.resolve)?.folder.url.lastPathComponent
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshDeviceState()
        watchDeviceState()
        startMorningLoop()
    }

    var bedtimeItems: [BedtimeCheck.Item] {
        BedtimeCheck.items(.init(phoneCharging: phoneCharging,
                                 bluetoothOn: ![.bluetoothOff, .unavailable].contains(collector.link),
                                 strapBatteryPercent: collector.batteryPercent,
                                 lowPowerMode: lowPowerMode))
    }

    var baseline: BaselineProgress { BaselineProgress(scoredNights: scoredNightCount) }

    /// Last night with sleep found in it: the fresh score if it has one, else the latest stored night.
    var lastNight: NightSummary? {
        if let latestNight, latestNight.sleepStart != nil { return latestNight }
        return nights.last { $0.sleepStart != nil }
    }

    /// Last night against your normal, from the nights already loaded.
    var recovery: RecoveryDetail? { RecoveryDetail.compute(latest: lastNight, history: nights) }

    var installExpiry: InstallExpiry.Status? { InstallExpiry.current() }

    func finishOnboarding(profile: UserProfile, strap: UUID?) {
        profile.save()
        self.profile = profile
        if let strap { collector.pair(with: strap) }
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        onboarded = true
    }

    // MARK: - Marks

    let markLabels = MarkLabels()
    @ObservationIgnored let markNotifier = MarkNotifier()
    /// Taps on the strap in the last `marksLookback`, oldest first.
    var marks: [Int] = []
    /// Heart rate either side of each mark whose half hour after has passed.
    var markWindows: [Int: MarkWindow] = [:]
    /// Bumped when a name changes, so views re-read `markLabels`.
    private var labelsVersion = 0
    static let marksLookback = 60 * 86_400

    func label(for mark: Int) -> String? {
        _ = labelsVersion
        return markLabels.label(for: mark)
    }

    func setLabel(_ label: String, for mark: Int) {
        markLabels.set(label, for: mark)
        labelsVersion += 1
    }

    /// Deletes a mark everywhere on this phone; a resent tap from the strap stays hidden.
    func deleteMark(_ mark: Int) {
        markLabels.delete(mark)
        marks.removeAll { $0 == mark }
        markWindows[mark] = nil
        labelsVersion += 1
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["tether.mark.\(mark)"])
    }

    /// Last night's vitals against your range, and the early warning.
    var healthMonitor: HealthMonitor? { HealthMonitor.check(latest: lastNight, history: nights) }

    private static let healthNotifiedKey = "tether.health.lastNotifiedDay"

    /// The morning heads-up: only when the early warning is raised, at most once a day.
    private func notifyHealth(after night: NightSummary?) async {
        guard let night, let report = HealthMonitor.check(latest: night, history: nights) else { return }
        let defaults = UserDefaults.standard
        guard let notice = HealthMonitor.notification(for: report.warning, day: night.day,
                                                      lastNotifiedDay: defaults.string(forKey: Self.healthNotifiedKey))
        else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        try? await center.add(UNNotificationRequest(identifier: "tether.health.\(night.day)", content: content, trigger: nil))
        defaults.set(night.day, forKey: Self.healthNotifiedKey)
    }

    var marksToday: [Int] {
        let start = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        return marks.filter { $0 >= start }
    }

    /// What each name usually does, for names with enough marks behind them.
    var markEffects: [MarkEffect] {
        _ = labelsVersion
        let named = marks.compactMap { mark in markLabels.label(for: mark).map { (label: $0, mark: mark) } }
        return Dictionary(grouping: named) { $0.label.lowercased() }.values
            .compactMap { group in
                MarkEffect.compute(label: group[0].label, windows: group.compactMap { markWindows[$0.mark] })
            }
            .sorted { $0.marks > $1.marks }
    }

    func refreshMarks() async {
        #if DEBUG
        if DebugFixture.isOn { return }
        #endif
        guard let pairedAt = collector.pairedAt else { marks = []; return }
        await collector.flush()
        let now = Int(Date().timeIntervalSince1970)
        guard let stored = try? await sink.marks(from: max(pairedAt, now - Self.marksLookback), to: now) else { return }
        let found = markLabels.visible(stored)
        if found != marks { marks = found }
        for mark in found where markWindows[mark] == nil && now >= mark + MarkWindow.afterSeconds {
            if let window = try? await sink.window(around: mark) { markWindows[mark] = window }
        }
    }

    /// One local notification a day before the signing runs out. Rescheduled on every launch and
    /// foreground, so a renewal (new expiry date) moves it automatically.
    func scheduleExpiryReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.expiryReminderId])
        guard let reminder = installExpiry?.reminderDate else { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tether needs renewing"
        content.body = "The install runs out tomorrow. Put your iPhone on the same Wi-Fi as your Mac, or plug it in, so the Mac can renew it."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, reminder.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.expiryReminderId, content: content, trigger: trigger))
    }

    /// Live heart rate while the strap is connected; nil otherwise, so a stale reading never shows as live.
    var liveHeartRate: Int? {
        #if DEBUG
        if let fixture = DebugFixture.liveHeartRate { return fixture }
        #endif
        return collector.link == .connected ? collector.heartRate : nil
    }

    func startTodayUpdates() {
        #if DEBUG
        if DebugFixture.isOn {
            let profile = profile
            nights = DebugFixture.nights()
            latestNight = nights.last
            scoredNightCount = nights.count
            steps = DebugFixture.steps()
            let fixtureMarks = DebugFixture.marks()
            marks = fixtureMarks.map(\.ts)
            markWindows = Dictionary(uniqueKeysWithValues: fixtureMarks.compactMap { mark in mark.window.map { (mark.ts, $0) } })
            for mark in fixtureMarks { if let label = mark.label { markLabels.set(label, for: mark.ts) } }
            Task {
                let day = await Task.detached { DebugFixture.dayStreams() }.value
                apply(await Self.analyse(hr: day.hr, rr: day.rr, gravity: [], profile: profile, window: day.window,
                                         now: day.window.upperBound))
            }
            return
        }
        #endif
        todayLoop?.cancel()
        lastScoredAt = nil
        todayLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRecordingCard(canStart: true)
                await self?.refreshToday()
                await self?.scoreNights()
                await self?.refreshMarks()
                await self?.syncFolder()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopTodayUpdates() {
        todayLoop?.cancel()
        todayLoop = nil
    }

    private struct DayAnalysis: Sendable {
        let today: TodaySnapshot
        let stress: StressDetail
        let effort: EffortDetail
    }

    /// Today's summary plus the stress and effort detail, all off the main actor from one read.
    private static func analyse(hr: [HRSample], rr: [RRInterval], gravity: [GravitySample], profile: UserProfile?,
                                window: ClosedRange<Int>, now: Int) async -> DayAnalysis {
        await Task.detached(priority: .utility) {
            let tz = TimeZone.current.secondsFromGMT()
            let today = TodayAnalytics.compute(hr: hr, rr: rr, gravity: gravity, profile: profile, window: window,
                                               now: now)
            let inWindow = hr.filter { window.contains($0.ts) }
            return DayAnalysis(
                today: today,
                stress: StressDetail.compute(hr: inWindow, rr: rr.filter { window.contains($0.ts) },
                                             gravity: gravity.filter { window.contains($0.ts) }, tzOffsetSeconds: tz),
                effort: EffortDetail.compute(hr: inWindow, maxHR: today.maxHR, restingHR: today.restingHR,
                                             sex: profile?.sex.rawValue ?? "male", tzOffsetSeconds: tz))
        }.value
    }

    private func apply(_ analysis: DayAnalysis) {
        today = analysis.today
        stress = analysis.stress
        effort = analysis.effort
    }

    /// Reads today's samples (from midnight, or from pairing if later) and recomputes off the main actor.
    func refreshToday() async {
        guard let pairedAt = collector.pairedAt else { today = nil; return }
        let now = Int(Date().timeIntervalSince1970)
        let start = max(Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970), pairedAt)
        guard start < now else { return }
        await collector.flush()
        guard let batch = try? await sink.readBack(from: start, to: now, limit: Self.dayReadLimit) else { return }
        let gravity = (try? await sink.gravity(from: start, to: now, limit: Self.dayReadLimit)) ?? []
        apply(await Self.analyse(hr: batch.streams.hr, rr: batch.streams.rr, gravity: gravity, profile: profile,
                                 window: start...now, now: now))
        let midnight = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        if let counted = try? await sink.dailySteps(dayStart: midnight, now: now) { steps = counted }
    }

    /// Scores every night since pairing that hasn't been scored, plus yesterday and today again (their
    /// nights may have finished since the last pass). Runs at most every 15 minutes while the app is open.
    func scoreNights() async {
        guard let pairedAt = collector.pairedAt, let profile else { return }
        if let lastScoredAt, Date().timeIntervalSince(lastScoredAt) < Self.scoringInterval { return }
        lastScoredAt = .now
        let calendar = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        let today = calendar.startOfDay(for: .now)
        let alreadyScored = Set((try? await sink.scoredDays(from: "0000-01-01", to: "9999-12-31")) ?? [])
        let historyFrom = collector.historyRescoreFrom
        var latest: NightSummary?
        var allScored = true
        for dayStart in NightsToScore.days(pairedAt: pairedAt, now: now, scored: alreadyScored,
                                           historyFrom: historyFrom, calendar: calendar) {
            if let scored = try? await sink.scoreDay(dayStart: dayStart, now: now, profile: profile) {
                latest = scored
            } else {
                allScored = false
            }
        }
        if let historyFrom, allScored { collector.historyRescored(from: historyFrom) }
        latestNight = latest
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        nights = (try? await sink.nights(from: DayScorer.dayKey(dayStart: Int(monthAgo.timeIntervalSince1970)),
                                         to: DayScorer.dayKey(dayStart: Int(today.timeIntervalSince1970)))) ?? nights
        scoredNightCount = (try? await sink.baselineNightCount()) ?? scoredNightCount
        publishMorning(night: latest, baselineNights: scoredNightCount)
    }

    /// A history sync filled in minutes the phone missed: rescore the nights and today with them.
    private func historyArrived(_ outcome: StrapHistoryOutcome) async {
        switch outcome {
        case .caughtUp(let rows) where rows > 0, .timedOut(let rows) where rows > 0:
            lastScoredAt = nil
            lastMorningPassAt = nil
            await scoreNights()
            await refreshToday()
        default:
            break
        }
    }

    // MARK: - Lock-screen widgets

    /// Runs for the app's whole life. Overnight the strap's Bluetooth stream keeps the app alive in the
    /// background, the same way the collector's auto-flush keeps writing, so this sees the night end.
    private func startMorningLoop() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "tether.debugMorning") {
            publishDebugMorning()
            return
        }
        #endif
        morningLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRecordingCard(canStart: false)
                await self?.morningPass()
                try? await Task.sleep(for: Self.morningTick)
            }
        }
    }

    /// From 04:00 until the afternoon, at most every 15 minutes: score this morning's night and update the
    /// widgets if its numbers changed.
    func morningPass() async {
        guard let pairedAt = collector.pairedAt, let profile else { return }
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        guard (WakeDay.boundaryHour..<Self.morningEndHour).contains(hour) else { return }
        // Mornings pull the night's history from the strap (skin temperature, motion, missed minutes).
        // When it lands, historyArrived rescores with it.
        if Int(now.timeIntervalSince1970) - (collector.lastHistorySync ?? 0) >= Self.morningHistoryInterval {
            collector.syncHistoryNow()
        }
        if let lastMorningPassAt, now.timeIntervalSince(lastMorningPassAt) < Self.scoringInterval { return }
        lastMorningPassAt = now
        let dayStart = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        guard dayStart + 86_400 > pairedAt else { return }
        await collector.flush()
        let night = try? await sink.scoreDay(dayStart: dayStart, now: Int(now.timeIntervalSince1970), profile: profile)
        let baselineNights = (try? await sink.baselineNightCount()) ?? scoredNightCount
        publishMorning(night: night, baselineNights: baselineNights)
        await notifyHealth(after: night)
    }

    private func publishMorning(night: NightSummary?, baselineNights: Int) {
        guard let store = SnapshotStore.shared() else { return }
        let decision = MorningCheck.decide(night: night, baselineNights: baselineNights, now: .now,
                                           published: store.read())
        guard case let .publish(snapshot) = decision else { return }
        do {
            try store.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            storeError = "Couldn't update the lock-screen widgets: \(error.localizedDescription)"
        }
    }

    // MARK: - Recording card (Live Activity)

    /// Starts the lock-screen card when the strap is linked and the app is on screen (`canStart`), and
    /// updates it every pass. Ends it when the strap is forgotten.
    func refreshRecordingCard(canStart: Bool) async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "tether.debugRecording") {
            if canStart { recordingCard.startIfNeeded(Self.debugRecordingStatus, at: .now.addingTimeInterval(-71 * 60)) }
            return
        }
        #endif
        guard collector.isPaired else {
            if recordingCard.startedAt != nil { await recordingCard.end() }
            return
        }
        let now = Date()
        if canStart, collector.link == .connected, recordingCard.startedAt == nil {
            recordingCard.startIfNeeded(recordingStatus(since: now, now: now, captured: 0), at: now)
        }
        guard let start = recordingCard.startedAt else { return }
        await collector.flush()
        let from = Int(start.timeIntervalSince1970), to = Int(now.timeIntervalSince1970)
        let captured = (try? await sink.hrSeconds(from: from, to: to).count) ?? 0
        await recordingCard.update(recordingStatus(since: start, now: now, captured: captured))
    }

    private func recordingStatus(since start: Date, now: Date, captured: Int) -> RecordingStatus {
        RecordingStatus.make(heartRate: collector.heartRate, link: .init(collector.link), startedAt: start, now: now,
                             capturedSeconds: captured, strapBattery: collector.batteryPercent)
    }

    #if DEBUG
    /// `-tether.debugRecording YES` shows the card with fixture numbers, to check it without a strap.
    private static let debugRecordingStatus = RecordingStatus(heartRate: 57, link: .solid, missedMinutes: 0,
                                                              coveragePercent: 100, strapBattery: 58, isNight: true)

    /// `-tether.debugMorning YES` fills the widgets with fixture numbers, to check them without a strap.
    private func publishDebugMorning() {
        let snapshot = MorningSnapshot(wakeDay: WakeDay.key(for: .now), savedAt: Int(Date().timeIntervalSince1970),
                                       sleepMin: 437, rest: 81, charge: 67, baselineNights: 6, restingHR: 52)
        try? SnapshotStore.shared()?.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

    // MARK: - Shared folder

    /// Keeps access to the folder picked in Files, then writes to it straight away.
    func setFolder(_ url: URL) {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        do {
            UserDefaults.standard.set(try SharedFolder.bookmark(for: url), forKey: Self.folderKey)
            folderName = url.lastPathComponent
            folderError = nil
            Task { await syncFolder(force: true) }
        } catch {
            folderError = "Couldn't keep access to that folder: \(error.localizedDescription)"
        }
    }

    /// Imports the Mac's recordings, then writes profile.md and yesterday's and today's day files.
    /// Runs at most every 15 minutes, plus whenever the app goes to the background.
    func syncFolder(force: Bool = false) async {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey),
              let (folder, stale) = SharedFolder.resolve(data) else { return }
        if stale, let fresh = try? folder.withAccess({ try SharedFolder.bookmark(for: folder.url) }) {
            UserDefaults.standard.set(fresh, forKey: Self.folderKey)
        }
        if !force, let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < Self.syncInterval { return }
        lastSyncAt = .now
        guard let pairedAt = collector.pairedAt, let profile else { return }
        if await importMacRecordings(from: folder, notBefore: pairedAt) > 0 {
            lastScoredAt = nil
            await scoreNights()
        }
        let records = await dayRecords(pairedAt: pairedAt, profile: profile)
        let strapName = StandardHRSource.rememberedName()
        do {
            try await Task.detached(priority: .utility) {
                try folder.withAccess {
                    try folder.write(ProfileFile.write(profile: profile, pairedAt: pairedAt, strapName: strapName),
                                     to: ProfileFile.relativePath)
                    for record in records {
                        try folder.write(DayFile.write(record), to: DayFile.relativePath(day: record.day))
                    }
                }
            }.value
            lastSavedAt = .now
            folderError = nil
        } catch {
            folderError = "Couldn't save to your folder: \(error.localizedDescription)"
        }
    }

    private func importMacRecordings(from folder: SharedFolder, notBefore cutoff: Int) async -> Int {
        var imported = 0
        for file in folder.withAccess({ folder.pendingInbox() }) {
            do {
                let text = try folder.withAccess { try folder.read(url: file) }
                let result = try await InboxImporter.importFile(text, into: sink, notBefore: cutoff)
                imported += result.samples
                if let span = result.span { rememberMacSpan(span) }
                try folder.withAccess { try folder.markImported(file) }
            } catch {
                folderError = "Couldn't import \(file.lastPathComponent) from your Mac: \(error.localizedDescription)"
            }
        }
        return imported
    }

    private var macSpans: [ClosedRange<Int>] {
        let stored = UserDefaults.standard.array(forKey: Self.macSpansKey) as? [[Int]] ?? []
        return stored.compactMap { $0.count == 2 && $0[0] <= $0[1] ? $0[0]...$0[1] : nil }
    }

    private func rememberMacSpan(_ span: ClosedRange<Int>) {
        let cutoff = Int(Date().timeIntervalSince1970) - Self.macSpanKeepSeconds
        let kept = MacSpans.dropping(MacSpans.adding(span, to: macSpans), before: cutoff)
        UserDefaults.standard.set(kept.map { [$0.lowerBound, $0.upperBound] }, forKey: Self.macSpansKey)
    }

    /// Yesterday and today, each with what Today showed and the night that ended on it.
    private func dayRecords(pairedAt: Int, profile: UserProfile) async -> [DayRecord] {
        let calendar = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        var records: [DayRecord] = []
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) else { continue }
            let dayStart = Int(day.timeIntervalSince1970)
            let key = DayScorer.dayKey(dayStart: dayStart)
            let start = max(dayStart, pairedAt), end = min(now, dayStart + 86_399)
            var snapshot: TodaySnapshot?
            if start < end, let batch = try? await sink.readBack(from: start, to: end, limit: Self.dayReadLimit) {
                let computed = await Task.detached(priority: .utility) {
                    TodayAnalytics.compute(hr: batch.streams.hr, rr: batch.streams.rr, profile: profile,
                                           window: start...end, now: end)
                }.value
                snapshot = computed.isEmpty ? nil : computed
            }
            let night = latestNight?.day == key ? latestNight : nights.first { $0.day == key }
            guard snapshot != nil || night != nil else { continue }
            records.append(DayRecord(day: key, savedAt: now, strapBatteryPct: offset == 0 ? collector.batteryPercent : nil,
                                     today: snapshot, night: night,
                                     macSpans: MacSpans.within(macSpans, day: dayStart...(dayStart + 86_399))))
        }
        return records
    }

    func refreshDeviceState() {
        switch UIDevice.current.batteryState {
        case .charging, .full: phoneCharging = true
        case .unplugged: phoneCharging = false
        case .unknown: phoneCharging = nil
        @unknown default: phoneCharging = nil
        }
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func watchDeviceState() {
        let names = [UIDevice.batteryStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDeviceState() }
            }
        }
    }

    /// Application Support/Tether/tether.sqlite, created on first launch.
    private static func storePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tether", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("tether.sqlite").path
    }
}
