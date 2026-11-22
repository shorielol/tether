import Foundation
import StrandAnalytics
@preconcurrency import WhoopProtocol

/// One workout: found from your heart rate (12 minutes or more clearly above resting) or added by you.
public struct Workout: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case walk, run, strength, cycle, ski, other

        public var name: String {
            switch self {
            case .walk: "Walk"
            case .run: "Run"
            case .strength: "Strength"
            case .cycle: "Ride"
            case .ski: "Ski"
            case .other: "Workout"
            }
        }
    }

    public let start: Int
    public let end: Int
    public let averageBPM: Int
    public let peakBPM: Int
    public let kind: Kind
    /// True when you set the type, false when it's Tether's guess.
    public let kindIsYours: Bool
    /// 0–100 on the same scale as the day's Effort, for this workout alone.
    public let effort: Double?
    public let isManual: Bool
    public var durationMin: Int { (end - start) / 60 }
    public var id: Int { start }
}

/// Your changes to workouts, kept on this phone: a type you chose, ones you deleted, ones you added.
public final class WorkoutEdits: @unchecked Sendable {
    struct Manual: Codable, Equatable {
        let start: Int
        let end: Int
        let kind: Workout.Kind
    }

    let defaults: UserDefaults
    private static let kindsKey = "tether.workouts.kinds"
    private static let deletedKey = "tether.workouts.deleted"
    private static let manualKey = "tether.workouts.manual"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func kind(for start: Int) -> Workout.Kind? {
        ((defaults.dictionary(forKey: Self.kindsKey) as? [String: String]) ?? [:])[String(start)].flatMap(Workout.Kind.init)
    }

    public func setKind(_ kind: Workout.Kind, for start: Int) {
        var kinds = (defaults.dictionary(forKey: Self.kindsKey) as? [String: String]) ?? [:]
        kinds[String(start)] = kind.rawValue
        defaults.set(kinds, forKey: Self.kindsKey)
        var manual = self.manual
        if let index = manual.firstIndex(where: { $0.start == start }) {
            manual[index] = Manual(start: start, end: manual[index].end, kind: kind)
            self.manual = manual
        }
    }

    public func isDeleted(_ start: Int) -> Bool {
        ((defaults.array(forKey: Self.deletedKey) as? [Int]) ?? []).contains(start)
    }

    public func delete(_ start: Int) {
        var deleted = Set((defaults.array(forKey: Self.deletedKey) as? [Int]) ?? [])
        deleted.insert(start)
        defaults.set(deleted.sorted(), forKey: Self.deletedKey)
        manual.removeAll { $0.start == start }
    }

    public func add(start: Int, end: Int, kind: Workout.Kind) {
        guard end > start else { return }
        manual = (manual.filter { $0.start != start } + [Manual(start: start, end: end, kind: kind)]).sorted { $0.start < $1.start }
    }

    var manual: [Manual] {
        get { defaults.data(forKey: Self.manualKey).flatMap { try? JSONDecoder().decode([Manual].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.manualKey) }
    }
}

/// Finds the day's workouts with NOOP's `AutoWorkoutDetector`, guesses each one's type with its
/// `WorkoutTypeClassifier`, and scores each with the same Effort scorer as the day.
public enum WorkoutFinder {
    /// Below this the type guess is shown as a plain "Workout".
    static let confidentEnough = 0.45

    public static func find(hr: [HRSample], gravity: [GravitySample], steps: [StepSample], restingHR: Int,
                            maxHR: Int, sex: String) -> [Workout] {
        let sorted = hr.sorted { $0.ts < $1.ts }
        let motion = gravity.isEmpty ? nil : AutoWorkoutDetector.motionPoints(gravity.sorted { $0.ts < $1.ts })
        return AutoWorkoutDetector.detect(hr: sorted.map { (ts: $0.ts, bpm: $0.bpm) }, restingBpm: restingHR,
                                          motion: motion).map { found in
            var kind = Workout.Kind.other
            if let features = WorkoutTypeFeatureExtractor.extract(hr: sorted, gravity: gravity, steps: steps,
                                                                    start: found.startSec, end: found.endSec,
                                                                    restingHR: Double(restingHR), maxHR: Double(maxHR)) {
                let guess = WorkoutTypeClassifier.classify(features)
                if guess.confidence >= confidentEnough { kind = Workout.Kind(rawValue: guess.predictedClass.rawValue) ?? .other }
            }
            return Workout(start: found.startSec, end: found.endSec, averageBPM: found.avgBpm, peakBPM: found.peakBpm,
                           kind: kind, kindIsYours: false,
                           effort: effort(sorted, found.startSec, found.endSec, restingHR, maxHR, sex), isManual: false)
        }
    }

    /// The workouts to show: detected ones you haven't deleted, with your type where you set one, plus
    /// the ones you added, each measured from the heart rate in its window.
    public static func apply(_ edits: WorkoutEdits, to detected: [Workout], hr: [HRSample], restingHR: Int,
                             maxHR: Int, sex: String) -> [Workout] {
        let kept = detected.filter { !edits.isDeleted($0.start) }.map { workout in
            guard let mine = edits.kind(for: workout.start) else { return workout }
            return Workout(start: workout.start, end: workout.end, averageBPM: workout.averageBPM, peakBPM: workout.peakBPM,
                           kind: mine, kindIsYours: true, effort: workout.effort, isManual: false)
        }
        let sorted = hr.sorted { $0.ts < $1.ts }
        let added = edits.manual.filter { !edits.isDeleted($0.start) }.compactMap { manual -> Workout? in
            let inside = sorted.filter { $0.ts >= manual.start && $0.ts <= manual.end }.map(\.bpm)
            guard !inside.isEmpty else {
                return Workout(start: manual.start, end: manual.end, averageBPM: 0, peakBPM: 0, kind: manual.kind,
                               kindIsYours: true, effort: nil, isManual: true)
            }
            return Workout(start: manual.start, end: manual.end,
                           averageBPM: Int((Double(inside.reduce(0, +)) / Double(inside.count)).rounded()),
                           peakBPM: inside.max() ?? 0, kind: manual.kind, kindIsYours: true,
                           effort: effort(sorted, manual.start, manual.end, restingHR, maxHR, sex), isManual: true)
        }
        return (kept + added).sorted { $0.start < $1.start }
    }

    private static func effort(_ hr: [HRSample], _ start: Int, _ end: Int, _ resting: Int, _ maxHR: Int,
                               _ sex: String) -> Double? {
        StrainScorer.strain(hr.filter { $0.ts >= start && $0.ts <= end }, maxHR: Double(maxHR),
                            restingHR: Double(resting), sex: sex)
    }
}
