import Testing
@testable import TetherCore

@Suite("Who holds the strap")
struct LinkHolderTests {
    private let now = 1_795_300_000

    @Test func connectedWithAFreshBeatIsThisDevice() {
        let holder = LinkHolder.resolve(link: .connected, heartRate: 72, lastSampleAt: now - 3,
                                        phoneSavedAt: now - 60, now: now)
        #expect(holder == .thisDevice(bpm: 72))
    }

    @Test func connectedButSilentIsStillThisDeviceWithoutABeat() {
        let holder = LinkHolder.resolve(link: .connected, heartRate: 72, lastSampleAt: now - 120,
                                        phoneSavedAt: nil, now: now)
        #expect(holder == .thisDevice(bpm: nil))
    }

    @Test func notConnectedAndPhoneWroteRecentlyIsThePhone() {
        let holder = LinkHolder.resolve(link: .reconnecting, heartRate: nil, lastSampleAt: nil,
                                        phoneSavedAt: now - 10 * 60, now: now)
        #expect(holder == .otherDevice)
    }

    @Test func notConnectedAndPhoneQuietIsNobody() {
        let holder = LinkHolder.resolve(link: .connecting, heartRate: nil, lastSampleAt: nil,
                                        phoneSavedAt: now - 3 * 3600, now: now)
        #expect(holder == .nobody)
        #expect(LinkHolder.resolve(link: .idle, heartRate: nil, lastSampleAt: nil, phoneSavedAt: nil, now: now) == .nobody)
    }

    @Test func bluetoothProblemsAreTheirOwnState() {
        #expect(LinkHolder.resolve(link: .bluetoothOff, heartRate: nil, lastSampleAt: nil, phoneSavedAt: now, now: now)
                == .bluetoothOff)
        #expect(LinkHolder.resolve(link: .unauthorized, heartRate: nil, lastSampleAt: nil, phoneSavedAt: nil, now: now)
                == .bluetoothOff)
    }
}

@Suite("Handing the strap back to the phone")
struct HandOverTests {
    private let now = 1_795_300_000

    @Test func letsGoWhenThePhoneWritesAfterTheMacTookOver() {
        #expect(HandOver.shouldRelease(connectedSince: now - 3_600, phoneSavedAt: now - 120, now: now))
    }

    @Test func keepsItWhenThePhoneLastWroteBeforeTheMacTookOver() {
        #expect(!HandOver.shouldRelease(connectedSince: now - 600, phoneSavedAt: now - 900, now: now))
        #expect(!HandOver.shouldRelease(connectedSince: nil, phoneSavedAt: now - 60, now: now))
        #expect(!HandOver.shouldRelease(connectedSince: now - 600, phoneSavedAt: nil, now: now))
    }

    @Test func takesItBackOnceThePhoneHasBeenQuiet() {
        #expect(HandOver.shouldReclaim(releasedAt: now - 3_600, phoneSavedAt: now - 40 * 60, now: now))
        #expect(HandOver.shouldReclaim(releasedAt: now - 3_600, phoneSavedAt: nil, now: now))
    }

    @Test func waitsWhileThePhoneIsActiveOrJustAfterLettingGo() {
        #expect(!HandOver.shouldReclaim(releasedAt: now - 3_600, phoneSavedAt: now - 5 * 60, now: now))
        #expect(!HandOver.shouldReclaim(releasedAt: now - 120, phoneSavedAt: nil, now: now))
    }
}
