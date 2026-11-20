import Testing
@testable import TetherCore

@Test func versionIsSet() {
    #expect(!TetherCore.version.isEmpty)
}
