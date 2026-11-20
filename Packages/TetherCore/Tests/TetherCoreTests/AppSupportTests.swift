import Foundation
import Testing
@testable import TetherCore

@Suite("Profile")
struct ProfileTests {
    @Test func validFormBuildsAProfile() throws {
        let profile = try UserProfile.parse(age: "17", heightCm: "178", weightKg: "68,5", restingHR: "", sex: .male).get()
        #expect(profile == UserProfile(age: 17, heightCm: 178, weightKg: 68.5, restingHR: nil, sex: .male))
        #expect(profile.maxHR == 196)
    }

    @Test func outOfRangeAndBlankFieldsAreRejected() {
        #expect(UserProfile.parse(age: "9", heightCm: "178", weightKg: "68", restingHR: "", sex: .male) == .failure(.age))
        #expect(UserProfile.parse(age: "17", heightCm: "", weightKg: "68", restingHR: "", sex: .male) == .failure(.height))
        #expect(UserProfile.parse(age: "17", heightCm: "178", weightKg: "abc", restingHR: "", sex: .female) == .failure(.weight))
        #expect(UserProfile.parse(age: "17", heightCm: "178", weightKg: "68", restingHR: "12", sex: .female) == .failure(.restingHR))
    }

    @Test func profileRoundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "tether-profile-\(UUID().uuidString)"))
        #expect(UserProfile.load(from: defaults) == nil)
        let profile = UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: 52, sex: .male)
        profile.save(to: defaults)
        #expect(UserProfile.load(from: defaults) == profile)
    }
}

@Suite("Bedtime check")
struct BedtimeCheckTests {
    @Test func allGoodReadsAsClear() {
        let items = BedtimeCheck.items(.init(phoneCharging: true, bluetoothOn: true, strapBatteryPercent: 61, lowPowerMode: false))
        #expect(items.map(\.status) == [.ok, .ok, .ok, .ok])
        #expect(items[2].state == "61%")
        #expect(BedtimeCheck.isClear(items))
    }

    @Test func problemsWarnAndUnknownsNeverPass() {
        let items = BedtimeCheck.items(.init(phoneCharging: nil, bluetoothOn: false, strapBatteryPercent: nil, lowPowerMode: true))
        #expect(items.map(\.status) == [.unknown, .warn, .unknown, .warn])
        #expect(!BedtimeCheck.isClear(items))
        let low = BedtimeCheck.items(.init(phoneCharging: false, bluetoothOn: true, strapBatteryPercent: 29, lowPowerMode: false))
        #expect(low[0].status == .warn)
        #expect(low[2].status == .warn)
    }
}

@Suite("Baseline progress")
struct BaselineProgressTests {
    @Test func countsDownToCharge() {
        #expect(BaselineProgress(scoredNights: 0).chargeLabel == "Charge ready after 4 nights")
        #expect(BaselineProgress(scoredNights: 2).chargeLabel == "Charge ready in 2 nights")
        #expect(BaselineProgress(scoredNights: 3).chargeLabel == "Charge ready after one more night")
        #expect(BaselineProgress(scoredNights: 4).isChargeReady)
        #expect(BaselineProgress(scoredNights: 9).nightsUntilCharge == 0)
        #expect(BaselineProgress(scoredNights: 0).nightsUntilSleepNeed == 14)
    }
}

@Suite("Install expiry")
struct InstallExpiryTests {
    @Test func readsExpiryFromAProvisioningBlob() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-27T18:58:00Z</date></dict></plist>
        """
        var blob = Data([0x30, 0x82, 0x01, 0xFF, 0x00])   // CMS wrapper bytes before the plist
        blob.append(Data(plist.utf8))
        blob.append(Data([0x00, 0xA0, 0x82]))
        let date = try #require(InstallExpiry.expirationDate(fromProvision: blob))
        #expect(date == ISO8601DateFormatter().date(from: "2026-11-27T18:58:00Z"))
        #expect(InstallExpiry.expirationDate(fromProvision: Data("nothing here".utf8)) == nil)
    }

    @Test func daysLeftAndWarning() throws {
        let expiry = try #require(ISO8601DateFormatter().date(from: "2026-11-27T18:58:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-25T10:00:00Z"))
        let status = InstallExpiry.Status(expires: expiry, now: now)
        #expect(status.daysLeft == 2)
        #expect(status.needsReinstallSoon)
        #expect(!InstallExpiry.Status(expires: expiry, now: expiry.addingTimeInterval(-6 * 86_400)).needsReinstallSoon)
        #expect(InstallExpiry.Status(expires: expiry, now: expiry.addingTimeInterval(60)).isExpired)
    }
}
