import Foundation

/// The only commands Tether may send the strap: the hello that opens the data link, history requests
/// and acks, setting the clock, and the alarm (set, read back, cancel). Everything else, including
/// firmware updates, settings and buzzing the strap on demand, is refused before it reaches Bluetooth.
public enum StrapCommandPolicy {
    static let commandType: UInt8 = 35
    static let typeIndex = 8
    static let commandIndex = 10

    public static let clientHello: UInt8 = 145
    public static let setClock: UInt8 = 10
    public static let setAlarm: UInt8 = 66
    public static let readAlarm: UInt8 = 67
    public static let cancelAlarm: UInt8 = 69

    public static let allowed: Set<UInt8> = [
        clientHello, WhoopCommandCode.sendHistoricalData, WhoopCommandCode.historicalDataResult,
        setClock, setAlarm, readAlarm, cancelAlarm,
    ]

    /// True for a well-formed command frame whose command is on the list.
    public static func allows(_ frame: [UInt8]) -> Bool {
        guard frame.count > commandIndex, frame[0] == 0xAA, frame[typeIndex] == commandType else { return false }
        return allowed.contains(frame[commandIndex])
    }
}
