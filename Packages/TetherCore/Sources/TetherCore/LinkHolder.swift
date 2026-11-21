/// Who has the strap right now, from this device's point of view. Drives every "who holds it" line.
/// The strap talks to one device at a time, so "not connected here" plus a fresh file from the other
/// device means the other device has it.
public enum LinkHolder: Equatable, Sendable {
    /// Connected here. `bpm` is nil when the last beat is older than `freshBeatSeconds`.
    case thisDevice(bpm: Int?)
    /// Not connected here, and the other device wrote recently.
    case otherDevice
    /// Bluetooth is off, not allowed, or missing on this device.
    case bluetoothOff
    /// Looking, but nobody seems to have it: out of range, or the other device has been quiet.
    case nobody

    public static let freshBeatSeconds = 15
    public static let otherDeviceFreshSeconds = 30 * 60

    public static func resolve(link: LinkState, heartRate: Int?, lastSampleAt: Int?,
                               phoneSavedAt: Int?, now: Int) -> LinkHolder {
        switch link {
        case .bluetoothOff, .unauthorized, .unavailable:
            return .bluetoothOff
        case .connected:
            let fresh = lastSampleAt.map { now - $0 <= freshBeatSeconds } ?? false
            return .thisDevice(bpm: fresh ? heartRate : nil)
        case .idle, .scanning, .connecting, .reconnecting:
            if let phoneSavedAt, now - phoneSavedAt <= otherDeviceFreshSeconds { return .otherDevice }
            return .nobody
        }
    }
}
