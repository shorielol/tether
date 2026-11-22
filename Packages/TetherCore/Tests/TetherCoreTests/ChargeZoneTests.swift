import Testing
@testable import TetherCore

@Suite("Charge zones")
struct ChargeZoneTests {
    @Test(arguments: [(99.0, ChargeZone.green), (67, .green), (66.6, .green), (66.4, .yellow), (34, .yellow),
                      (33.4, .red), (1, .red), (0, .red), (100, .green)])
    func zonesFollowTheBands(charge: Double, zone: ChargeZone) {
        #expect(ChargeZone(charge: charge) == zone)
    }

    @Test func eachZoneSaysWhatToDo() {
        #expect(ChargeZone.green.name == "Green")
        #expect(ChargeZone.green.advice == "Ready for a harder day")
        #expect(ChargeZone.yellow.advice == "Keep it steady")
        #expect(ChargeZone.red.advice == "Rest and recover")
        #expect(ChargeZone.yellow.range == 34...66)
    }
}
