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

    let collector: LiveCollector
    private let sink: WhoopStoreSink
    /// Today's analytics from stored samples, refreshed every 30 s while the app is open.
    private(set) var today: TodaySnapshot?
    @ObservationIgnored private var todayLoop: Task<Void, Never>?
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

    /// Scored nights arrive with the day scorer. Until then the countdown starts from zero.
    var baseline: BaselineProgress { BaselineProgress(scoredNights: 0) }

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
            Task { today = await Task.detached { DebugFixture.today(profile: profile) }.value }
            return
        }
        #endif
        todayLoop?.cancel()
        todayLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshToday()
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
