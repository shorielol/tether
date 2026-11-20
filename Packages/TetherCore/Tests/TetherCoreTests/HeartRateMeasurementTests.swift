import Testing
@testable import TetherCore

@Suite("Heart Rate Measurement (0x2A37) parsing")
struct HeartRateMeasurementTests {
    @Test func eightBitHeartRateWithoutRR() throws {
        let m = try #require(HeartRateMeasurement.parse([0x00, 72], rrUnit: .bleSpec))
        #expect(m.bpm == 72)
        #expect(m.rrMs.isEmpty)
    }

    @Test func sixteenBitHeartRate() throws {
        let m = try #require(HeartRateMeasurement.parse([0x01, 0x48, 0x00], rrUnit: .bleSpec))
        #expect(m.bpm == 72)
    }

    @Test func rrInSpecUnitsConvertsFrom1024ths() throws {
        let m = try #require(HeartRateMeasurement.parse([0x10, 60, 0x00, 0x04], rrUnit: .bleSpec))
        #expect(m.rrMs == [1000])
    }

    /// Payload from a locked WHOOP 5.0 on firmware 50.43.2.0 (OpenStrap/edge#673): 81 bpm, two R-R values.
    @Test func whoopFiveSendsRRInMilliseconds() throws {
        let payload: [UInt8] = [0x10, 0x51, 0xE5, 0x02, 0xEC, 0x02]
        let asMs = try #require(HeartRateMeasurement.parse(payload, rrUnit: .milliseconds))
        #expect(asMs.bpm == 81)
        #expect(asMs.rrMs == [741, 748])
        let asSpec = try #require(HeartRateMeasurement.parse(payload, rrUnit: .bleSpec))
        #expect(asSpec.rrMs == [724, 730])
    }

    @Test func energyExpendedFieldIsSkipped() throws {
        let m = try #require(HeartRateMeasurement.parse([0x18, 70, 0x10, 0x00, 0x52, 0x03], rrUnit: .milliseconds))
        #expect(m.bpm == 70)
        #expect(m.rrMs == [850])
    }

    @Test func implausibleRRValuesAreDropped() throws {
        let m = try #require(HeartRateMeasurement.parse([0x10, 70, 0x00, 0x00, 0x52, 0x03, 0xA0, 0x0F], rrUnit: .milliseconds))
        #expect(m.rrMs == [850])
    }

    @Test(arguments: [[UInt8](), [0x01, 0x48], [0x00]])
    func truncatedPayloadsReturnNil(_ bytes: [UInt8]) {
        #expect(HeartRateMeasurement.parse(bytes, rrUnit: .bleSpec) == nil)
    }

    @Test func zeroHeartRateIsRejected() {
        #expect(HeartRateMeasurement.parse([0x00, 0], rrUnit: .bleSpec) == nil)
    }

    @Test func sensorContactIsDecoded() throws {
        #expect(try #require(HeartRateMeasurement.parse([0x06, 60], rrUnit: .bleSpec)).contact == .detected)
        #expect(try #require(HeartRateMeasurement.parse([0x04, 60], rrUnit: .bleSpec)).contact == .notDetected)
        #expect(try #require(HeartRateMeasurement.parse([0x00, 60], rrUnit: .bleSpec)).contact == .unsupported)
    }

    @Test func rrUnitFollowsTheStrapName() {
        #expect(RRUnit.forPeripheral(named: "WHOOP 4C0123456") == .milliseconds)
        #expect(RRUnit.forPeripheral(named: "whoop") == .milliseconds)
        #expect(RRUnit.forPeripheral(named: "Polar H10 1A2B") == .bleSpec)
        #expect(RRUnit.forPeripheral(named: nil) == .bleSpec)
    }
}
