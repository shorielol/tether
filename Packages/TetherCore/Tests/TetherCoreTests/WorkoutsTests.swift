import Foundation
import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

/// Phase 5 workouts: found from heart rate (and motion when the strap sent it), typed, scored, and
/// yours to retype, delete or add.
@Suite("Workouts")
struct WorkoutsTests {
    private let t0 = 1_700_000_000

    private func steady(_ bpm: Int, from start: Int, seconds: Int) -> [HRSample] {
        (0..<seconds).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    /// An hour at rest, 30 minutes hard, then rest again.
    private var day: [HRSample] {
        steady(62, from: t0, seconds: 3_600) + steady(150, from: t0 + 3_600, seconds: 1_800)
            + steady(70, from: t0 + 5_400, seconds: 1_800)
    }

    private func find(_ hr: [HRSample]) -> [Workout] {
        WorkoutFinder.find(hr: hr, gravity: [], steps: [], restingHR: 60, maxHR: 196, sex: "male")
    }

    @Test func aSustainedHardStretchIsAWorkout() throws {
        let workouts = find(day)
        #expect(workouts.count == 1)
        let workout = try #require(workouts.first)
        #expect(abs(workout.durationMin - 30) <= 2)
        #expect(workout.averageBPM >= 140)
        #expect((workout.effort ?? 0) > 0)
        #expect(!workout.isManual)
    }

    @Test func theEffortTargetFollowsCharge() {
        #expect(EffortTarget.band(for: .green).low > EffortTarget.band(for: .yellow).low)
        #expect(EffortTarget.band(for: .yellow).low > EffortTarget.band(for: .red).low)
        #expect(EffortTarget.band(for: .red).contains(25))
    }

    @Test func aShortBurstIsNot() {
        let burst = steady(62, from: t0, seconds: 3_600) + steady(150, from: t0 + 3_600, seconds: 300)
            + steady(62, from: t0 + 3_900, seconds: 1_800)
        #expect(find(burst).isEmpty)
    }

    @Test func yourEditsWin() throws {
        let edits = WorkoutEdits(defaults: UserDefaults(suiteName: "workouts-\(UUID().uuidString)")!)
        let detected = find(day)
        let start = try #require(detected.first?.start)
        edits.setKind(.cycle, for: start)
        var shown = WorkoutFinder.apply(edits, to: detected, hr: day, restingHR: 60, maxHR: 196, sex: "male")
        #expect(shown.first?.kind == .cycle)
        #expect(shown.first?.kindIsYours == true)

        edits.add(start: t0 + 6_000, end: t0 + 7_200, kind: .strength)
        shown = WorkoutFinder.apply(edits, to: detected, hr: day, restingHR: 60, maxHR: 196, sex: "male")
        #expect(shown.count == 2)
        let manual = try #require(shown.first { $0.isManual })
        #expect(manual.kind == .strength)
        #expect(manual.averageBPM == 70)

        edits.delete(start)
        edits.delete(manual.start)
        #expect(WorkoutFinder.apply(edits, to: detected, hr: day, restingHR: 60, maxHR: 196, sex: "male").isEmpty)
        #expect(WorkoutEdits(defaults: edits.defaults).isDeleted(start), "edits survive a relaunch")
    }
}
