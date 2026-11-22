import Foundation
@preconcurrency import WhoopProtocol
@preconcurrency import WhoopStore

/// A day's steps from the strap's own step counter, which arrives with each history sync.
///
/// The counter adds up as you walk and now and then starts again from a low number (seen going
/// 941 → 0 on 22 Nov), so the day is the sum of its increases, and a drop counts as a fresh start.
/// A jump faster than anyone walks is skipped rather than trusted.
public struct DailySteps: Sendable, Equatable {
    public struct Hour: Sendable, Equatable, Identifiable {
        public let hour: Int
        public let steps: Int
        public var id: Int { hour }
    }

    public let total: Int
    /// All 24 hours of the day, so a chart keeps its shape.
    public let hours: [Hour]
    /// Minutes in which the strap flagged you as moving.
    public let movingMinutes: Int
    /// When the newest reading in the day was taken, or nil before the first sync.
    public let lastSampleTs: Int?

    public var hasData: Bool { lastSampleTs != nil }

    /// Faster than a sprint's cadence; an increase above this rate is a glitch, not steps.
    public static let maxStepsPerSecond = 4.0

    /// `samples` may start before `dayStart`: the last one before the day is only the starting point.
    public static func compute(samples: [StepSample], dayStart: Int, dayEnd: Int) -> DailySteps {
        let sorted = samples.filter { $0.ts < dayEnd }.sorted { $0.ts < $1.ts }
        var perHour = Array(repeating: 0, count: 24)
        var previous: StepSample?
        var moving = Set<Int>()
        var last: Int?
        for sample in sorted {
            defer { previous = sample }
            guard sample.ts >= dayStart else { continue }
            last = sample.ts
            if sample.activityClass == 1 { moving.insert(sample.ts / 60) }
            guard let previous else { continue }
            let added = sample.counter >= previous.counter ? sample.counter - previous.counter : sample.counter
            let allowed = maxStepsPerSecond * Double(max(1, sample.ts - previous.ts))
            guard added > 0, Double(added) <= allowed else { continue }
            perHour[min(23, max(0, (sample.ts - dayStart) / 3_600))] += added
        }
        return DailySteps(total: perHour.reduce(0, +),
                          hours: perHour.enumerated().map { Hour(hour: $0.offset, steps: $0.element) },
                          movingMinutes: moving.count, lastSampleTs: last)
    }
}

extension WhoopStoreSink {
    /// Today's steps so far. Reads an hour before the day so the first reading has a starting point.
    public func dailySteps(dayStart: Int, now: Int) async throws -> DailySteps {
        let end = min(now, dayStart + 86_400)
        let samples = try await openStore().stepSamples(deviceId: Self.deviceId, from: dayStart - 3_600, to: end,
                                                        limit: 200_000)
        return DailySteps.compute(samples: samples, dayStart: dayStart, dayEnd: dayStart + 86_400)
    }
}
