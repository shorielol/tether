/// When the Mac should let the phone have the strap back, and when it can take it again.
/// The strap talks to one device at a time, so a Mac that never lets go would keep the phone
/// from reconnecting after school.
public enum HandOver {
    /// A phone file newer than the Mac's connection by this much means the phone is on again.
    public static let phoneBackMarginSeconds = 60
    /// After this long without a phone file, the phone is taken to be off or away.
    public static let quietPhoneSeconds = 30 * 60
    /// Stay released at least this long so the phone gets a fair chance to connect.
    public static let minReleasedSeconds = 10 * 60

    public static func shouldRelease(connectedSince: Int?, phoneSavedAt: Int?, now: Int) -> Bool {
        guard let connectedSince, let phoneSavedAt else { return false }
        return phoneSavedAt > connectedSince + phoneBackMarginSeconds && now - phoneSavedAt <= quietPhoneSeconds
    }

    public static func shouldReclaim(releasedAt: Int, phoneSavedAt: Int?, now: Int) -> Bool {
        guard now - releasedAt >= minReleasedSeconds else { return false }
        guard let phoneSavedAt else { return true }
        return now - phoneSavedAt > quietPhoneSeconds
    }
}
