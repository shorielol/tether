import Foundation
import Observation
import TetherCore
import UIKit
import UserNotifications

/// Owns the one collector for the app's lifetime and the phone-side state the screens read.
@MainActor
@Observable
final class AppModel {
    private static let onboardedKey = "tether.onboarded"
    private static let expiryReminderId = "tether.expiry"
    /// One day at one sample a second, with headroom for R-R (more than one beat a second).
    private static let dayReadLimit = 250_000
    private static let scoringInterval: TimeInterval = 15 * 60

    let collector: LiveCollector
    private let sink: WhoopStoreSink
    /// Today's analytics from stored samples, refreshed every 30 s while the app is open.
    private(set) var today: TodaySnapshot?
    @ObservationIgnored private var todayLoop: Task<Void, Never>?
    /// Scored nights, oldest first (last 30 days).
    private(set) var nights: [NightSummary] = []
    /// The most recent scoring of today's night, which also carries Charge drivers.
    private(set) var latestNight: NightSummary?
    private(set) var scoredNightCount = 0
    @ObservationIgnored private var lastScoredAt: Date?
    private(set) var profile: UserProfile?
    private(set) var onboarded: Bool
    private(set) var phoneCharging: Bool?
    private(set) var lowPowerMode = false
    private(set) var storeError: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        let sink = WhoopStoreSink(path: Self.storePath())
        self.sink = sink
        collector = LiveCollector(source: StandardHRSource(), sink: sink, defaults: defaults)
        profile = UserProfile.load(from: defaults)
        onboarded = defaults.bool(forKey: Self.onboardedKey)
        collector.startAutoFlush(every: 30)
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshDeviceState()
        watchDeviceState()
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

    var installExpiry: InstallExpiry.Status? { InstallExpiry.current() }

    func finishOnboarding(profile: UserProfile, strap: UUID?) {
        profile.save()
        self.profile = profile
        if let strap { collector.pair(with: strap) }
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        onboarded = true
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

    /// Live heart rate for the hero card.
    var liveHeartRate: Int? {
        #if DEBUG
        if let fixture = DebugFixture.liveHeartRate { return fixture }
        #endif
        return collector.heartRate
    }

    func startTodayUpdates() {
        #if DEBUG
        if DebugFixture.isOn {
            let profile = profile
            nights = DebugFixture.nights()
            latestNight = nights.last
            scoredNightCount = nights.count
            Task { today = await Task.detached { DebugFixture.today(profile: profile) }.value }
            return
        }
        #endif
        todayLoop?.cancel()
        lastScoredAt = nil
        todayLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshToday()
                await self?.scoreNights()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopTodayUpdates() {
        todayLoop?.cancel()
        todayLoop = nil
    }

    /// Reads today's samples (from midnight, or from pairing if later) and recomputes off the main actor.
    func refreshToday() async {
        guard let pairedAt = collector.pairedAt else { today = nil; return }
        let now = Int(Date().timeIntervalSince1970)
        let start = max(Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970), pairedAt)
        guard start < now else { return }
        await collector.flush()
        guard let batch = try? await sink.readBack(from: start, to: now, limit: Self.dayReadLimit) else { return }
        let profile = profile
        today = await Task.detached(priority: .utility) {
            TodayAnalytics.compute(hr: batch.streams.hr, rr: batch.streams.rr, profile: profile,
                                   window: start...now, now: now)
        }.value
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
        var day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(pairedAt)))
        var latest: NightSummary?
        while day <= today {
            let dayStart = Int(day.timeIntervalSince1970)
            let isRecent = calendar.dateComponents([.day], from: day, to: today).day ?? 0 <= 1
            if isRecent || !alreadyScored.contains(DayScorer.dayKey(dayStart: dayStart)) {
                if let scored = try? await sink.scoreDay(dayStart: dayStart, now: now, profile: profile) {
                    latest = scored
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        latestNight = latest
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        nights = (try? await sink.nights(from: DayScorer.dayKey(dayStart: Int(monthAgo.timeIntervalSince1970)),
                                         to: DayScorer.dayKey(dayStart: Int(today.timeIntervalSince1970)))) ?? nights
        scoredNightCount = (try? await sink.baselineNightCount()) ?? scoredNightCount
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
