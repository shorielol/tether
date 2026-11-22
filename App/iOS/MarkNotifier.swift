import UIKit
import UserNotifications

/// Asks "what was it?" right after you double-tap the strap. Your recent names are one-tap answers;
/// "Name it…" takes a new one. Tapping the notification itself opens Marks.
@MainActor
final class MarkNotifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let category = "tether.mark"
    nonisolated static let nameAction = "tether.mark.name"
    nonisolated static let labelPrefix = "tether.mark.label:"
    /// Quick replies shown on the notification, besides "Name it…".
    static let quickReplies = 3

    /// A mark (unix seconds) was given a name from the notification.
    var onAnswer: ((Int, String) -> Void)?

    func ask(about mark: Int, offering labels: [String]) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let quick = labels.prefix(Self.quickReplies).map {
            UNNotificationAction(identifier: Self.labelPrefix + $0, title: $0)
        }
        let name = UNTextInputNotificationAction(identifier: Self.nameAction, title: "Name it…",
                                                 textInputButtonTitle: "Save",
                                                 textInputPlaceholder: "Coffee, exam, nap…")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: quick + [name],
                                                                 intentIdentifiers: [])])
        let content = UNMutableNotificationContent()
        let time = Date(timeIntervalSince1970: TimeInterval(mark)).formatted(date: .omitted, time: .shortened)
        content.title = "Marked \(time)"
        content.body = "What was it? Press and hold to name it."
        content.categoryIdentifier = Self.category
        content.userInfo = ["mark": mark]
        try? await center.add(UNNotificationRequest(identifier: "tether.mark.\(mark)", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == Self.category, let mark = content.userInfo["mark"] as? Int else { return }
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            if action == Self.nameAction, let typed {
                onAnswer?(mark, typed)
            } else if action.hasPrefix(Self.labelPrefix) {
                onAnswer?(mark, String(action.dropFirst(Self.labelPrefix.count)))
            } else if action == UNNotificationDefaultActionIdentifier, let url = URL(string: "tether://marks") {
                UIApplication.shared.open(url)
            }
        }
    }
}
