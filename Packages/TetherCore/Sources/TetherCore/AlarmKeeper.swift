import Foundation
import Observation

/// Keeps the strap's silent alarm set for the next time you chose. It sets the strap's clock and alarm
/// when the data link is up, waits for the strap when it isn't, and sets the next morning's once one has
/// passed. If the strap refuses, the refusal stands: nothing is sent again until you ask.
@MainActor
@Observable
public final class AlarmKeeper {
    public struct Setting: Codable, Equatable, Sendable {
        public var hour: Int
        public var minute: Int
        public var isOn: Bool
        /// Smart wake window before the alarm time, in minutes; 0 is off.
        public var windowMinutes: Int

        public init(hour: Int, minute: Int, isOn: Bool, windowMinutes: Int = 0) {
            self.hour = hour
            self.minute = minute
            self.isOn = isOn
            self.windowMinutes = windowMinutes
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            hour = try values.decode(Int.self, forKey: .hour)
            minute = try values.decode(Int.self, forKey: .minute)
            isOn = try values.decode(Bool.self, forKey: .isOn)
            windowMinutes = try values.decodeIfPresent(Int.self, forKey: .windowMinutes) ?? 0
        }
    }

    public enum Status: Equatable, Sendable {
        case off
        /// Set on the phone; goes to the strap when it next connects.
        case waitingForStrap(wake: Int)
        /// Sent; waiting for the strap's answer.
        case sending(wake: Int)
        /// The strap said it has the alarm.
        case set(wake: Int)
        /// The strap said no. Stays this way until the alarm is set again.
        case refused(wake: Int)
    }

    public private(set) var setting: Setting?
    public private(set) var status: Status = .off

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Int
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let send: ([UInt8]) -> Void
    @ObservationIgnored private var linkReady = false
    @ObservationIgnored private var seq: UInt8 = 0x80

    private static let settingKey = "tether.alarm.setting"
    private static let armedKey = "tether.alarm.armedFor"
    private static let refusedKey = "tether.alarm.refusedFor"
    private static let cancelKey = "tether.alarm.cancelPending"
    /// The window-end time an early (smart) alarm was set for, so the keeper doesn't put the later one back.
    private static let smartKey = "tether.alarm.smartFor"

    public init(defaults: UserDefaults, now: @escaping () -> Int, calendar: Calendar = .current,
                send: @escaping ([UInt8]) -> Void) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.send = send
        setting = defaults.data(forKey: Self.settingKey).flatMap { try? JSONDecoder().decode(Setting.self, from: $0) }
        status = restoredStatus()
    }

    // MARK: What the person does

    /// Turns the alarm on for `hour:minute`, every morning. Asking again after a refusal is allowed.
    public func set(hour: Int, minute: Int) {
        save(Setting(hour: hour, minute: minute, isOn: true, windowMinutes: setting?.windowMinutes ?? 0))
        defaults.removeObject(forKey: Self.smartKey)
        defaults.removeObject(forKey: Self.refusedKey)
        defaults.removeObject(forKey: Self.armedKey)
        defaults.set(false, forKey: Self.cancelKey)
        arm(StrapAlarm.nextWake(hour: hour, minute: minute, after: now(), calendar: calendar))
    }

    /// Chooses the smart wake window. Nothing is sent: the strap keeps the alarm for the window's end.
    public func setWindow(_ minutes: Int) {
        guard var current = setting else { return }
        current.windowMinutes = max(0, minutes)
        save(current)
    }

    /// True inside the window before an alarm the strap has confirmed, until a smart alarm has been set.
    public var inSmartWindow: Bool {
        guard let setting, setting.isOn, setting.windowMinutes > 0, case .set(let wake) = status,
              defaults.object(forKey: Self.smartKey) == nil || defaults.integer(forKey: Self.smartKey) != wake
        else { return false }
        let now = now()
        return now >= wake - setting.windowMinutes * 60 && now < wake - Self.earlyLeadSeconds
    }

    /// True when today's alarm was moved earlier because you were surfacing.
    public var wokeEarly: Bool {
        guard let setting, defaults.object(forKey: Self.smartKey) != nil else { return false }
        return defaults.integer(forKey: Self.smartKey) == StrapAlarm.nextWake(hour: setting.hour, minute: setting.minute,
                                                                             after: now(), calendar: calendar)
    }

    /// How soon after the cue the strap buzzes.
    static let earlyLeadSeconds = 60

    /// You're surfacing inside the window: move the strap's alarm to a minute from now.
    public func wakeEarly() {
        guard inSmartWindow, case .set(let wake) = status, linkReady else { return }
        defaults.set(wake, forKey: Self.smartKey)
        let early = now() + Self.earlyLeadSeconds
        StrapAlarm.armFrames(wakeAt: early, now: now(), clockSeq: nextSeq(), alarmSeq: nextSeq()).forEach(send)
        status = .sending(wake: early)
    }

    /// Turns the alarm off and cancels it on the strap, now or when it next connects.
    public func turnOff() {
        guard var current = setting else { return }
        current.isOn = false
        save(current)
        status = .off
        defaults.removeObject(forKey: Self.armedKey)
        defaults.removeObject(forKey: Self.refusedKey)
        defaults.set(true, forKey: Self.cancelKey)
        if linkReady { send(StrapAlarm.cancelFrame(seq: nextSeq())) }
    }

    // MARK: What the collector tells it

    func linkChanged(ready: Bool) {
        linkReady = ready
        guard ready else {
            if case .sending(let wake) = status { status = .waitingForStrap(wake: wake) }
            return
        }
        if defaults.bool(forKey: Self.cancelKey) { send(StrapAlarm.cancelFrame(seq: nextSeq())) }
        tick()
    }

    /// Called on connect and every few minutes: sends the next morning's alarm when the strap doesn't have it.
    func tick() {
        guard let setting, setting.isOn else { return }
        let wake = StrapAlarm.nextWake(hour: setting.hour, minute: setting.minute, after: now(), calendar: calendar)
        // A smart alarm moved earlier stands until the window's end has passed.
        if defaults.object(forKey: Self.smartKey) != nil, defaults.integer(forKey: Self.smartKey) == wake { return }
        switch status {
        case .refused: return
        case .set(let armed) where armed == wake: return
        case .sending(let armed) where armed == wake: return
        default: arm(wake)
        }
    }

    /// Handles the strap's answer to an alarm or clock command. False for any other frame.
    @discardableResult
    func receive(_ frame: [UInt8]) -> Bool {
        guard let reply = StrapAlarm.reply(frame) else { return false }
        switch reply.command {
        case StrapCommandPolicy.setAlarm:
            guard case .sending(let wake) = status else { return true }
            switch reply.result {
            case .accepted:
                status = .set(wake: wake)
                defaults.set(wake, forKey: Self.armedKey)
            case .refused, .unsupported:
                status = .refused(wake: wake)
                defaults.set(wake, forKey: Self.refusedKey)
            case .pending:
                break
            }
        case StrapCommandPolicy.cancelAlarm where reply.result == .accepted:
            defaults.set(false, forKey: Self.cancelKey)
        default:
            break
        }
        return true
    }

    // MARK: Inside

    private func arm(_ wake: Int) {
        guard linkReady else {
            status = .waitingForStrap(wake: wake)
            return
        }
        StrapAlarm.armFrames(wakeAt: wake, now: now(), clockSeq: nextSeq(), alarmSeq: nextSeq()).forEach(send)
        status = .sending(wake: wake)
    }

    private func restoredStatus() -> Status {
        guard let setting, setting.isOn else { return .off }
        if defaults.object(forKey: Self.refusedKey) != nil {
            return .refused(wake: defaults.integer(forKey: Self.refusedKey))
        }
        let armed = defaults.integer(forKey: Self.armedKey)
        if armed > now() { return .set(wake: armed) }
        return .waitingForStrap(wake: StrapAlarm.nextWake(hour: setting.hour, minute: setting.minute,
                                                          after: now(), calendar: calendar))
    }

    private func save(_ new: Setting) {
        setting = new
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: Self.settingKey) }
    }

    private func nextSeq() -> UInt8 {
        seq &+= 1
        return seq
    }
}
