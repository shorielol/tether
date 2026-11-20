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

    let collector: LiveCollector
    private(set) var profile: UserProfile?
    private(set) var onboarded: Bool
    private(set) var phoneCharging: Bool?
    private(set) var lowPowerMode = false
    private(set) var storeError: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        let sink = WhoopStoreSink(path: Self.storePath())
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
