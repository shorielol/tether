import Foundation

/// A night's blood oxygen from the strap's own reading: the WHOOP 5 works the % out itself and sends it in
/// byte 82 of each history record, about every 40 s while you sleep. It isn't checked against a medical
/// device, so Tether shows it as experimental and never feeds it into Charge or the early warning.
public struct NightSpO2: Codable, Sendable, Equatable, Identifiable {
    public let day: String
    /// The night's middle reading, in %.
    public let median: Int
    /// The 5th percentile, so one stray reading doesn't set it.
    public let low: Int
    public let minutesBelow90: Int
    public let readings: Int
    public var id: String { day }

    public init(day: String, median: Int, low: Int, minutesBelow90: Int, readings: Int) {
        self.day = day
        self.median = median
        self.low = low
        self.minutesBelow90 = minutesBelow90
        self.readings = readings
    }

    /// Values outside this are status and saturation codes, not a %.
    static let validRange = 70...100
    /// About 40 minutes of readings.
    public static let minimumReadings = 60
    static let secondsPerReading = 40

    /// Nil when there are too few readings inside the sleep window.
    public static func compute(day: String, readings: [(ts: Int, value: Int)], sleepStart: Int, sleepEnd: Int) -> NightSpO2? {
        let values = readings.filter { $0.ts >= sleepStart && $0.ts <= sleepEnd && validRange.contains($0.value) }
            .map(\.value).sorted()
        guard values.count >= minimumReadings else { return nil }
        let below = values.filter { $0 < 90 }.count
        return NightSpO2(day: day, median: values[values.count / 2], low: values[values.count * 5 / 100],
                         minutesBelow90: Int((Double(below * secondsPerReading) / 60).rounded()), readings: values.count)
    }

    // MARK: Kept per night, since the raw records are pruned after about a week

    static let key = "tether.spo2.nights"

    public static func load(defaults: UserDefaults = .standard) -> [NightSpO2] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([NightSpO2].self, from: data)) ?? []
    }

    /// Adds or replaces nights by day, oldest first.
    public static func save(_ nights: [NightSpO2], defaults: UserDefaults = .standard) {
        var byDay = Dictionary(load(defaults: defaults).map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        for night in nights { byDay[night.day] = night }
        let sorted = byDay.values.sorted { $0.day < $1.day }
        if let data = try? JSONEncoder().encode(sorted) { defaults.set(data, forKey: key) }
    }
}

extension WhoopStoreSink {
    /// The strap's byte-82 readings between two times.
    public func spo2Readings(from: Int, to: Int) async throws -> [(ts: Int, value: Int)] {
        try await openStore().v18AuxSamples(deviceId: Self.deviceId, from: from, to: to)
            .compactMap { sample in sample.auxByte82.map { (ts: sample.ts, value: $0) } }
    }
}
