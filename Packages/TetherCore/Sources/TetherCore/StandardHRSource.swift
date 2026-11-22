import CoreBluetooth
import Foundation
@preconcurrency import WhoopProtocol

public enum LinkState: Equatable, Sendable {
    case bluetoothOff, unauthorized, unavailable, idle, scanning, connecting, connected, reconnecting
}

public struct DiscoveredStrap: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    /// Same name rule that switches R-R to milliseconds.
    public var isWhoop: Bool { RRUnit.forPeripheral(named: name) == .milliseconds }

    /// WHOOP straps first, then by signal strength, so another heart-rate device is harder to pick by mistake.
    public static func whoopFirst(_ straps: [DiscoveredStrap]) -> [DiscoveredStrap] {
        straps.sorted { lhs, rhs in
            lhs.isWhoop != rhs.isWhoop ? lhs.isWhoop : lhs.rssi > rhs.rssi
        }
    }
}

public enum HeartSourceEvent: Sendable {
    case link(LinkState)
    case discovered(DiscoveredStrap)
    case measurement(HeartRateMeasurement, at: Int)
    case battery(percent: Int)
    case firmware(String)
    /// The strap's own data link, which carries its stored history (skin temperature, motion, missed minutes).
    case dataLink(StrapDataLink)
    /// One complete frame from the data link.
    case strapFrame([UInt8])
}

/// The WHOOP 5 data link beside the standard heart-rate service.
public enum StrapDataLink: Equatable, Sendable {
    /// Not this strap, not this device, or not connected.
    case unavailable
    /// Waiting for the strap to accept the hello; iOS may show its pairing prompt.
    case pairing
    case ready
    /// The hello was refused, for example the pairing prompt was cancelled or another device holds
    /// the strap's pairing. `reason` is what iOS said.
    case declined(reason: String)
}

/// Anything that can feed heart data into Tether: the standard heart-rate service, plus on iPhone
/// the WHOOP 5 data link for the strap's stored history.
@MainActor
public protocol HeartDataSource: AnyObject {
    var onEvent: ((HeartSourceEvent) -> Void)? { get set }
    var rememberedStrap: UUID? { get }
    func startScan()
    func stopScan()
    func connect(to strap: UUID)
    func forget()
    /// Lets go of the strap but stays paired, so another device can hold it. No reconnecting until `reclaimStrap`.
    func releaseStrap()
    /// Goes back to a standing connection request for the remembered strap.
    func reclaimStrap()
    /// Writes one framed command to the strap's data link. Does nothing without one.
    func sendStrapCommand(_ frame: [UInt8])
    /// Sends the hello again on the current connection, after a refusal.
    func retryDataLink()
}

public extension HeartDataSource {
    func releaseStrap() {}
    func reclaimStrap() {}
    func sendStrapCommand(_ frame: [UInt8]) {}
    func retryDataLink() {}
}

/// Reads Heart Rate Measurement (0x2A37), Battery Level (0x2A19) and Firmware Revision (0x2A26).
/// Keeps a standing connection request to the remembered strap, so iOS reconnects in the background
/// whenever the strap comes back in range, and uses state restoration to survive the app being closed.
@MainActor
public final class StandardHRSource: NSObject, HeartDataSource {
    public var onEvent: ((HeartSourceEvent) -> Void)?

    static let heartRateService = CBUUID(string: "180D")
    static let measurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInfoService = CBUUID(string: "180A")
    static let firmwareRevision = CBUUID(string: "2A26")
    // tether: the WHOOP 5 data link, from NOOP's BLEManager (whoop5Service / whoop5CmdWriteChar / notify chars).
    static let dataService = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    static let dataCommand = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
    static let dataNotify: [CBUUID] = ["fd4b0003", "fd4b0004", "fd4b0005", "fd4b0007"].map {
        CBUUID(string: "\($0)-cce1-4033-93ce-002d5875f58a")
    }

    private let defaults: UserDefaults
    private static let strapKey = "tether.strap.id"
    private static let strapNameKey = "tether.strap.name"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rrUnit: RRUnit = .bleSpec
    private var wantsScan = false
    private var isReleased = false
    /// Only the iPhone opens the data link; the Mac stays on the standard heart-rate service.
    private let opensDataLink: Bool
    private var dataCommandChar: CBCharacteristic?
    private var dataNotifyChars: [CBCharacteristic] = []
    private var helloPending = false
    private var dataLinkReady = false
    private var reassembler = Reassembler(family: .whoop5)

    public init(restoreIdentifier: String? = "tether.central", defaults: UserDefaults = .standard,
                opensDataLink: Bool = false) {
        self.defaults = defaults
        self.opensDataLink = opensDataLink
        super.init()
        var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
        #if os(iOS)
        if let restoreIdentifier { options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier }
        #endif
        central = CBCentralManager(delegate: self, queue: nil, options: options)
    }

    /// The name of the strap this device last paired with, e.g. "WHOOP NAKV".
    public static func rememberedName(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: strapNameKey)
    }

    public var rememberedStrap: UUID? {
        defaults.string(forKey: Self.strapKey).flatMap(UUID.init(uuidString:))
    }

    public func startScan() {
        wantsScan = true
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [Self.heartRateService],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        emit(.link(.scanning))
    }

    public func stopScan() {
        wantsScan = false
        if central.isScanning { central.stopScan() }
    }

    public func connect(to strap: UUID) {
        stopScan()
        defaults.set(strap.uuidString, forKey: Self.strapKey)
        reconnectRemembered(state: .connecting)
    }

    public func releaseStrap() {
        isReleased = true
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        emit(.link(.idle))
    }

    public func reclaimStrap() {
        isReleased = false
        reconnectRemembered(state: .connecting)
    }

    public func forget() {
        isReleased = false
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        defaults.removeObject(forKey: Self.strapKey)
        defaults.removeObject(forKey: Self.strapNameKey)
        emit(.link(.idle))
    }

    private func reconnectRemembered(state: LinkState) {
        guard !isReleased, central.state == .poweredOn, let id = rememberedStrap,
              let known = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        adopt(known)
        central.connect(known, options: nil)   // standing request: completes whenever the strap is in range
        emit(.link(state))
    }

    private func adopt(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        let name = p.name ?? defaults.string(forKey: Self.strapNameKey)
        if let name { defaults.set(name, forKey: Self.strapNameKey) }
        rrUnit = RRUnit.forPeripheral(named: name)
    }

    private func emit(_ event: HeartSourceEvent) {
        onEvent?(event)
    }

    public func sendStrapCommand(_ frame: [UInt8]) {
        guard StrapCommandPolicy.allows(frame), dataLinkReady, let peripheral, let dataCommandChar else { return }
        peripheral.writeValue(Data(frame), for: dataCommandChar, type: .withResponse)
    }

    private func resetDataLink() {
        let wasOpen = dataLinkReady || helloPending
        dataCommandChar = nil
        dataNotifyChars = []
        helloPending = false
        dataLinkReady = false
        reassembler = Reassembler(family: .whoop5)
        if wasOpen { emit(.dataLink(.unavailable)) }
    }

    /// Writes the hello once the command characteristic is known; iOS may show its pairing prompt.
    public func retryDataLink() {
        guard opensDataLink, let peripheral, peripheral.state == .connected, !dataLinkReady else { return }
        helloPending = false
        if dataCommandChar == nil {
            peripheral.discoverServices([Self.dataService])
        } else {
            openDataLink(on: peripheral)
        }
    }

    private func openDataLink(on peripheral: CBPeripheral) {
        guard opensDataLink, !helloPending, !dataLinkReady, let dataCommandChar else { return }
        helloPending = true
        emit(.dataLink(.pairing))
        peripheral.writeValue(Data(WhoopCommandCode.clientHello), for: dataCommandChar, type: .withResponse)
    }

    private func linkStateForPowerState(_ state: CBManagerState) -> LinkState? {
        switch state {
        case .poweredOff: .bluetoothOff
        case .unauthorized: .unauthorized
        case .unsupported: .unavailable
        default: nil
        }
    }
}

extension StandardHRSource: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if let blocked = linkStateForPowerState(central.state) { emit(.link(blocked)); return }
        guard central.state == .poweredOn else { return }
        if rememberedStrap != nil { reconnectRemembered(state: .reconnecting) }
        else if wantsScan { startScan() }
        else { emit(.link(.idle)) }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        if let p = restored.first(where: { $0.identifier == rememberedStrap }) ?? restored.first { adopt(p) }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Heart-rate strap"
        emit(.discovered(DiscoveredStrap(id: peripheral.identifier, name: name, rssi: RSSI.intValue)))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        adopt(peripheral)
        emit(.link(.connected))
        var services = [Self.heartRateService, Self.batteryService, Self.deviceInfoService]
        if opensDataLink { services.append(Self.dataService) }
        peripheral.discoverServices(services)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: (any Error)?) {
        resetDataLink()
        guard !isReleased, rememberedStrap == peripheral.identifier else { return }
        emit(.link(.reconnecting))
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                           error: (any Error)?) {
        guard !isReleased, rememberedStrap == peripheral.identifier else { return }
        emit(.link(.reconnecting))
        central.connect(peripheral, options: nil)
    }
}

extension StandardHRSource: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case Self.heartRateService: peripheral.discoverCharacteristics([Self.measurement], for: service)
            case Self.batteryService: peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            case Self.deviceInfoService: peripheral.discoverCharacteristics([Self.firmwareRevision], for: service)
            case Self.dataService: peripheral.discoverCharacteristics([Self.dataCommand] + Self.dataNotify, for: service)
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                       error: (any Error)?) {
        guard characteristic.uuid == Self.dataCommand, helloPending else { return }
        helloPending = false
        if let error {
            emit(.dataLink(.declined(reason: error.localizedDescription)))
            return
        }
        dataNotifyChars.forEach { peripheral.setNotifyValue(true, for: $0) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: (any Error)?) {
        if let error, Self.dataNotify.contains(characteristic.uuid), !dataLinkReady {
            emit(.dataLink(.declined(reason: error.localizedDescription)))
            return
        }
        guard !dataLinkReady, !dataNotifyChars.isEmpty,
              dataNotifyChars.allSatisfy(\.isNotifying) else { return }
        dataLinkReady = true
        emit(.dataLink(.ready))
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                       error: (any Error)?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case Self.measurement: peripheral.setNotifyValue(true, for: c)
            case Self.batteryLevel:
                peripheral.readValue(for: c)
                if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
            case Self.firmwareRevision: peripheral.readValue(for: c)
            case Self.dataCommand: dataCommandChar = c
            case let uuid where Self.dataNotify.contains(uuid): dataNotifyChars.append(c)
            default: break
            }
        }
        if service.uuid == Self.dataService { openDataLink(on: peripheral) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                       error: (any Error)?) {
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        switch characteristic.uuid {
        case Self.measurement:
            if let m = HeartRateMeasurement.parse(bytes, rrUnit: rrUnit) {
                emit(.measurement(m, at: Int(Date().timeIntervalSince1970)))
            }
        case Self.batteryLevel:
            if let level = bytes.first, level <= 100 { emit(.battery(percent: Int(level))) }
        case Self.firmwareRevision:
            if let text = String(bytes: bytes, encoding: .utf8) {
                emit(.firmware(text.trimmingCharacters(in: .controlCharacters.union(.whitespaces))))
            }
        case let uuid where Self.dataNotify.contains(uuid):
            reassembler.feed(bytes).forEach { emit(.strapFrame($0)) }
        default: break
        }
    }
}
