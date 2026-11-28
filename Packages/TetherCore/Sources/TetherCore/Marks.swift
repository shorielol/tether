import Foundation
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore

/// The strap's double-tap: read from its EVENT frame, live or from history. Tether only listens; the
/// strap gets no reply, so tapping changes nothing on it.
public enum StrapTap {
    /// How a tap is stored in the event table, the same name the strap's history uses.
    public static let kind = "DOUBLE_TAP(14)"

    /// When the strap was tapped (unix seconds), or nil for any other frame.
    public static func timestamp(of frame: [UInt8]) -> Int? {
        guard frame.count > 16, frame[0] == 0xAA else { return nil }
        let parsed = parseFrame(frame, family: .whoop5)
        guard parsed.typeName == "EVENT", parsed.crcOK != false,
              parsed.parsed["event"]?.stringValue == kind else { return nil }
        return parsed.parsed["event_timestamp"]?.intValue
    }

    /// Whether a stored event is a tap.
    public static func isTap(_ event: WhoopEvent) -> Bool { event.kind == kind }
}

/// What you called each mark, kept on this phone. A blank name clears it.
public final class MarkLabels: @unchecked Sendable {
    let defaults: UserDefaults
    private static let key = "tether.marks.labels"
    /// How many recent names to offer as quick replies.
    public static let recentLimit = 4

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var all: [String: String] {
        get { (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.key) }
    }

    public func label(for mark: Int) -> String? { all[String(mark)] }

    public func set(_ label: String, for mark: Int) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        var labels = all
        labels[String(mark)] = trimmed.isEmpty ? nil : trimmed
        all = labels
    }

    /// Removes names inside `range` that no tap stands behind (a name is only ever given to a tap), and
    /// says how many went. Names outside the range are left, since their taps weren't looked at.
    @discardableResult
    public func removeOrphans(taps: [Int], in range: ClosedRange<Int>) -> Int {
        let tapped = Set(taps)
        var labels = all
        let orphans = labels.keys.filter { key in
            guard let ts = Int(key) else { return false }
            return range.contains(ts) && !tapped.contains(ts)
        }
        guard !orphans.isEmpty else { return 0 }
        for key in orphans { labels[key] = nil }
        all = labels
        return orphans.count
    }

    private static let deletedKey = "tether.marks.deleted"

    private var deleted: Set<Int> {
        get { Set((defaults.array(forKey: Self.deletedKey) as? [Int]) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Self.deletedKey) }
    }

    /// Deletes a mark: its name goes, and the tap stays hidden even if the strap's history sends it again.
    public func delete(_ mark: Int) {
        var labels = all
        labels[String(mark)] = nil
        all = labels
        var gone = deleted
        gone.insert(mark)
        deleted = gone
    }

    /// Deletes many at once, with one write.
    public func delete(all marks: [Int]) {
        var labels = all
        for mark in marks { labels[String(mark)] = nil }
        all = labels
        deleted = deleted.union(marks)
    }

    /// The marks that haven't been deleted.
    public func visible(_ marks: [Int]) -> [Int] {
        let gone = deleted
        return marks.filter { !gone.contains($0) }
    }

    private static let twoTapsKey = "tether.marks.twoTaps"

    /// Marks need two double-taps within `MarkFilter.pairSeconds`, so a knock doesn't count. On by default.
    public var needsTwoTaps: Bool {
        get { defaults.object(forKey: Self.twoTapsKey) == nil ? true : defaults.bool(forKey: Self.twoTapsKey) }
        set { defaults.set(newValue, forKey: Self.twoTapsKey) }
    }

    /// Marks that have a name.
    public var named: Set<Int> { Set(all.keys.compactMap(Int.init)) }

    /// Names used most recently first, each once.
    public var recent: [String] {
        var seen = Set<String>()
        return all.sorted { (Int($0.key) ?? 0) > (Int($1.key) ?? 0) }
            .map(\.value)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(Self.recentLimit)
            .map { $0 }
    }

    /// Every mark that carries `label`, matched without regard to case.
    public func marks(labelled label: String) -> [Int] {
        all.filter { $0.value.lowercased() == label.lowercased() }.compactMap { Int($0.key) }.sorted()
    }
}

/// Which of the strap's taps count as marks. The strap reports a double-tap for knocks and bumps too,
/// so by default a mark is two double-taps close together; taps while you're asleep don't count; and a
/// mark you've named always stays. Every tap stays stored, so changing the setting re-reads them all.
public enum MarkFilter {
    /// The second double-tap must come within this many seconds of the first.
    public static let pairSeconds = 10

    public static func marks(taps: [Int], twoTaps: Bool, named: Set<Int>, asleep: [ClosedRange<Int>]) -> [Int] {
        let sorted = Array(Set(taps)).sorted()
        var marks: [Int] = []
        var index = 0
        while index < sorted.count {
            let tap = sorted[index]
            if named.contains(tap) {
                marks.append(tap)
                index += 1
                continue
            }
            let sleeping = asleep.contains { $0.contains(tap) }
            if !twoTaps {
                if !sleeping { marks.append(tap) }
                index += 1
                continue
            }
            if index + 1 < sorted.count, sorted[index + 1] - tap <= pairSeconds {
                if !sleeping { marks.append(tap) }
                // Skip the pair's second tap and any more taps in the same burst.
                var next = index + 1
                while next < sorted.count, sorted[next] - tap <= pairSeconds { next += 1 }
                index = next
            } else {
                index += 1
            }
        }
        return marks
    }
}

/// Heart rate either side of one mark: the 15 minutes before and the 30 after.
public struct MarkWindow: Sendable, Equatable {
    public static let beforeSeconds = 15 * 60
    public static let afterSeconds = 30 * 60
    /// Each side needs this many seconds of heart rate to count.
    static let minimumSeconds = 5 * 60

    public let before: Int
    public let after: Int
    public var change: Int { after - before }

    public init(before: Int, after: Int) {
        self.before = before
        self.after = after
    }

    public static func compute(mark: Int, hr: [HRSample]) -> MarkWindow? {
        func mean(_ range: Range<Int>) -> Double? {
            let inside = hr.filter { range.contains($0.ts) }
            guard inside.count >= minimumSeconds else { return nil }
            return Double(inside.reduce(0) { $0 + $1.bpm }) / Double(inside.count)
        }
        guard let before = mean((mark - beforeSeconds)..<mark),
              let after = mean(mark..<(mark + afterSeconds)) else { return nil }
        return MarkWindow(before: Int(before.rounded()), after: Int(after.rounded()))
    }
}

/// What a label usually does to your heart rate, once it has enough marks behind it.
public struct MarkEffect: Sendable, Equatable, Identifiable {
    public static let marksNeeded = 3

    public let label: String
    /// Average change from the 15 minutes before to the 30 after, in bpm.
    public let bpmChange: Int
    public let marks: Int
    public var id: String { label }

    public static func compute(label: String, marks: [Int], hr: [HRSample]) -> MarkEffect? {
        compute(label: label, windows: marks.compactMap { MarkWindow.compute(mark: $0, hr: hr) })
    }
}

public extension MarkEffect {
    /// The same average, from windows already read.
    static func compute(label: String, windows: [MarkWindow]) -> MarkEffect? {
        guard windows.count >= marksNeeded else { return nil }
        let mean = Double(windows.reduce(0) { $0 + $1.change }) / Double(windows.count)
        return MarkEffect(label: label, bpmChange: Int(mean.rounded()), marks: windows.count)
    }
}

extension WhoopStoreSink {
    /// Every tap stored between `from` and `to`, oldest first: live ones and ones from the strap's history.
    public func marks(from: Int, to: Int) async throws -> [Int] {
        try await openStore().events(deviceId: Self.deviceId, from: from, to: to, limit: 10_000)
            .filter(StrapTap.isTap).map(\.ts)
    }

    /// Heart rate around one mark, enough for its window.
    public func window(around mark: Int) async throws -> MarkWindow? {
        let batch = try await readBack(from: mark - MarkWindow.beforeSeconds, to: mark + MarkWindow.afterSeconds,
                                       limit: 10_000)
        return MarkWindow.compute(mark: mark, hr: batch.streams.hr)
    }
}
