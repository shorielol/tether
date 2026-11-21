import Foundation
import StrandAnalytics

/// The four things that decide whether tonight records cleanly. A reading the phone can't get is
/// shown as unknown, never as a pass.
public enum BedtimeCheck {
    public static let minStrapBattery = 30

    public enum Status: Sendable, Equatable { case ok, warn, unknown }

    public struct Inputs: Sendable, Equatable {
        public let phoneCharging: Bool?
        public let bluetoothOn: Bool
        public let strapBatteryPercent: Int?
        public let lowPowerMode: Bool

        public init(phoneCharging: Bool?, bluetoothOn: Bool, strapBatteryPercent: Int?, lowPowerMode: Bool) {
            self.phoneCharging = phoneCharging
            self.bluetoothOn = bluetoothOn
            self.strapBatteryPercent = strapBatteryPercent
            self.lowPowerMode = lowPowerMode
        }
    }

    public struct Item: Sendable, Equatable, Identifiable {
        public let label: String
        public let state: String
        public let status: Status
        public var id: String { label }
    }

    public static func items(_ inputs: Inputs) -> [Item] {
        [charging(inputs.phoneCharging), bluetooth(inputs.bluetoothOn),
         strapBattery(inputs.strapBatteryPercent), lowPower(inputs.lowPowerMode)]
    }

    public static func isClear(_ items: [Item]) -> Bool {
        items.allSatisfy { $0.status == .ok }
    }

    private static func charging(_ charging: Bool?) -> Item {
        switch charging {
        case .some(true): Item(label: "Phone charging", state: "Yes", status: .ok)
        case .some(false): Item(label: "Phone charging", state: "No · plug it in", status: .warn)
        case .none: Item(label: "Phone charging", state: "Unknown", status: .unknown)
        }
    }

    private static func bluetooth(_ on: Bool) -> Item {
        on ? Item(label: "Bluetooth on", state: "Yes", status: .ok)
           : Item(label: "Bluetooth on", state: "Off", status: .warn)
    }

    private static func strapBattery(_ percent: Int?) -> Item {
        let label = "Strap battery above \(minStrapBattery)%"
        guard let percent else { return Item(label: label, state: "Not read yet", status: .unknown) }
        return Item(label: label, state: "\(percent)%", status: percent >= minStrapBattery ? .ok : .warn)
    }

    private static func lowPower(_ on: Bool) -> Item {
        on ? Item(label: "Low Power Mode", state: "On · may drop the link", status: .warn)
           : Item(label: "Low Power Mode", state: "Off", status: .ok)
    }
}

/// How many scored nights the personal baselines still need.
public struct BaselineProgress: Sendable, Equatable {
    /// NOOP's own thresholds: Charge scores from `minNightsSeed` nights, the baseline is trusted at `minNightsTrust`.
    public static let chargeNights = Baselines.minNightsSeed
    public static let sleepNeedNights = Baselines.minNightsTrust

    public let scoredNights: Int

    public init(scoredNights: Int) {
        self.scoredNights = max(0, scoredNights)
    }

    public var nightsUntilCharge: Int { max(0, Self.chargeNights - scoredNights) }
    public var nightsUntilSleepNeed: Int { max(0, Self.sleepNeedNights - scoredNights) }
    public var isChargeReady: Bool { nightsUntilCharge == 0 }

    public var chargeLabel: String {
        switch nightsUntilCharge {
        case 0: "Charge is ready"
        case 1: "Charge ready after one more night"
        case Self.chargeNights: "Charge ready after \(Self.chargeNights) nights"
        case let n: "Charge ready in \(n) nights"
        }
    }
}

/// A free Apple account signs the app for 7 days. The date is read from the app's own profile.
public enum InstallExpiry {
    public static let warnDays = 2
    public static let reminderLead: TimeInterval = 86_400

    public struct Status: Sendable, Equatable {
        public let expires: Date
        public let now: Date

        public init(expires: Date, now: Date) {
            self.expires = expires
            self.now = now
        }

        public var isExpired: Bool { now >= expires }
        public var daysLeft: Int { max(0, Int(expires.timeIntervalSince(now) / 86_400)) }
        public var needsReinstallSoon: Bool { daysLeft <= InstallExpiry.warnDays }

        /// A day before expiry, so there's time to refresh. Nil once that moment has passed.
        public var reminderDate: Date? {
            let date = expires.addingTimeInterval(-InstallExpiry.reminderLead)
            return date > now ? date : nil
        }
    }

    /// `embedded.mobileprovision` is a signed CMS blob with an XML plist inside.
    public static func expirationDate(fromProvision data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }

    /// Nil on the simulator, on the Mac, and for App Store builds, which carry no profile.
    public static func current(bundle: Bundle = .main, now: Date = .now) -> Status? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let expires = expirationDate(fromProvision: data) else { return nil }
        return Status(expires: expires, now: now)
    }
}
