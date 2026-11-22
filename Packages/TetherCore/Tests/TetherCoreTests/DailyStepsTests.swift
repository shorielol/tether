import Testing
@preconcurrency import WhoopProtocol
@testable import TetherCore

@Suite("Daily steps from the strap's counter")
struct DailyStepsTests {
    private let dayStart = 1_000_000
    private var dayEnd: Int { dayStart + 86_400 }

    private func samples(_ values: [(Int, Int)], moving: Set<Int> = []) -> [StepSample] {
        values.map { StepSample(ts: dayStart + $0.0, counter: $0.1, activityClass: moving.contains($0.0) ? 1 : 0) }
    }

    @Test func addsUpTheIncreasesOfTheCounter() {
        let steps = DailySteps.compute(samples: samples([(60, 844), (120, 844), (180, 851), (240, 918), (300, 941)]),
                                       dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.total == 97)
    }

    @Test func aResetStartsCountingAgainWithoutLosingSteps() {
        let toZero = DailySteps.compute(samples: samples([(60, 100), (120, 150), (180, 0), (240, 20)]),
                                        dayStart: dayStart, dayEnd: dayEnd)
        #expect(toZero.total == 70)
        let toLow = DailySteps.compute(samples: samples([(60, 100), (120, 150), (180, 30)]),
                                       dayStart: dayStart, dayEnd: dayEnd)
        #expect(toLow.total == 80)
    }

    @Test func aSampleBeforeTheDayIsOnlyTheStartingPoint() {
        let steps = DailySteps.compute(samples: samples([(-60, 500), (60, 520)]), dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.total == 20)
    }

    @Test func anImpossibleJumpIsIgnored() {
        let steps = DailySteps.compute(samples: samples([(60, 100), (120, 5_100), (180, 5_130)]),
                                       dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.total == 30)
    }

    @Test func stepsLandInTheHourTheyWereCounted() {
        let steps = DailySteps.compute(samples: samples([(9 * 3_600 - 60, 0), (9 * 3_600 + 60, 40), (14 * 3_600, 100)]),
                                       dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.hours.count == 24)
        #expect(steps.hours[9].steps == 40)
        #expect(steps.hours[14].steps == 60)
        #expect(steps.hours.map(\.steps).reduce(0, +) == steps.total)
    }

    @Test func movingMinutesCountEachMinuteTheStrapFlaggedMovement() {
        let steps = DailySteps.compute(samples: samples([(60, 0), (61, 1), (62, 2), (200, 3)], moving: [61, 62, 200]),
                                       dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.movingMinutes == 2)
    }

    @Test func noSamplesMeansNothingYet() {
        let steps = DailySteps.compute(samples: [], dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.total == 0)
        #expect(steps.lastSampleTs == nil)
        #expect(steps.hasData == false)
    }

    @Test func remembersWhenTheLastReadingWas() {
        let steps = DailySteps.compute(samples: samples([(60, 0), (500, 10)]), dayStart: dayStart, dayEnd: dayEnd)
        #expect(steps.lastSampleTs == dayStart + 500)
        #expect(steps.hasData)
    }
}
