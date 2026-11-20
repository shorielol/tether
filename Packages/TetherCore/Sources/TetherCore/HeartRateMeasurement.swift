import Foundation

/// How a strap encodes R-R intervals on the standard Heart Rate Measurement characteristic.
public enum RRUnit: Equatable, Sendable {
    /// The Bluetooth spec: 1/1024 of a second.
    case bleSpec
    /// WHOOP 5.0 (seen on firmware 50.41 and 50.43): plain milliseconds, against the spec.
    case milliseconds

    /// WHOOP straps advertise a name starting with "WHOOP"; everything else follows the spec.
    public static func forPeripheral(named name: String?) -> RRUnit {
        guard let name, name.lowercased().hasPrefix("whoop") else { return .bleSpec }
        return .milliseconds
    }
}

/// Skin-contact state from the measurement flags (bit 2 = supported, bit 1 = detected).
public enum SensorContact: Equatable, Sendable {
    case unsupported, notDetected, detected

    init(flags: UInt8) {
        if flags & 0x04 == 0 { self = .unsupported }
        else if flags & 0x02 == 0 { self = .notDetected }
        else { self = .detected }
    }
}

/// One notification from the standard Heart Rate Measurement characteristic (0x2A37).
/// Adapted from NOOP's `StandardHeartRate.parse` (PolyForm Noncommercial, see ThirdParty/NOOP-LICENSE).
public struct HeartRateMeasurement: Equatable, Sendable {
    public let bpm: Int
    public let rrMs: [Int]
    public let contact: SensorContact

    /// R-R values outside this range are physiologically impossible at rest or in exercise and are dropped.
    public static let plausibleRRMs = 250...2500

    public static func parse(_ data: [UInt8], rrUnit: RRUnit) -> HeartRateMeasurement? {
        guard let flags = data.first else { return nil }
        var index = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard index + 1 < data.count else { return nil }
            bpm = Int(data[index]) | Int(data[index + 1]) << 8
            index += 2
        } else {
            guard index < data.count else { return nil }
            bpm = Int(data[index])
            index += 1
        }
        guard bpm > 0 else { return nil }
        if flags & 0x08 != 0 { index += 2 }   // Energy Expended, not used

        var rrMs: [Int] = []
        if flags & 0x10 != 0 {
            while index + 1 < data.count {
                let raw = Int(data[index]) | Int(data[index + 1]) << 8
                index += 2
                let ms = rrUnit == .milliseconds ? raw : Int((Double(raw) * 1000 / 1024).rounded())
                if plausibleRRMs.contains(ms) { rrMs.append(ms) }
            }
        }
        return HeartRateMeasurement(bpm: bpm, rrMs: rrMs, contact: SensorContact(flags: flags))
    }
}
