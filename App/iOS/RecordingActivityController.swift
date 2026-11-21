import ActivityKit
import Foundation
import TetherCore
import TetherSnapshot

/// Owns the "Recording your night" Live Activity. iOS only lets an app start one while it's on screen
/// (push-to-start needs a paid account), so AppModel starts it from the foreground loop when the strap
/// links, and keeps it updated from the background loop the Bluetooth stream keeps alive.
@MainActor
final class RecordingActivityController {
    private var activity: Activity<RecordingAttributes>?

    init() {
        activity = Activity<RecordingAttributes>.activities.first { Self.isShowing($0) }
    }

    /// When the card on screen started, or nil if none is showing (never started, ended after iOS's
    /// 8-hour limit, or swiped away).
    var startedAt: Date? {
        guard let activity, Self.isShowing(activity) else { return nil }
        return activity.attributes.startedAt
    }

    /// Starts a card if none is showing. Call only while the app is in the foreground.
    func startIfNeeded(_ status: RecordingStatus, at start: Date) {
        guard startedAt == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: RecordingAttributes(startedAt: start),
                                            content: ActivityContent(state: status, staleDate: nil))
        } catch {
            // Live Activities turned off for Tether, or the system refused; the app works without the card.
            activity = nil
        }
    }

    func update(_ status: RecordingStatus) async {
        guard let current = activity, Self.isShowing(current) else { return }
        // ActivityKit's Activity is safe to use from any thread but isn't marked Sendable.
        nonisolated(unsafe) let running = current
        // Stale after 3 minutes without an update, so a frozen card doesn't look live.
        await running.update(ActivityContent(state: status, staleDate: .now.addingTimeInterval(180)))
    }

    func end() async {
        for running in Activity<RecordingAttributes>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    private static func isShowing(_ activity: Activity<RecordingAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }
}

extension RecordingStatus.Link {
    init(_ state: LinkState) {
        switch state {
        case .connected: self = .solid
        case .connecting, .reconnecting, .scanning: self = .reconnecting
        case .bluetoothOff, .unauthorized, .unavailable, .idle: self = .lost
        }
    }
}
