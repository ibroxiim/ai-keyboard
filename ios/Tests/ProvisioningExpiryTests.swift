import XCTest

final class ProvisioningExpiryTests: XCTestCase {
    private let expiry = Date(timeIntervalSinceReferenceDate: 810_000_000)

    private func hours(_ value: Double) -> TimeInterval { value * 3600 }

    /// A provisioning profile is a signed (CMS) blob with the plist inside as plain XML.
    private func profile(expiring date: Date?) -> Data {
        var plist: [String: Any] = ["Name": "iOS Team Provisioning Profile", "TeamName": "Test"]
        if let date { plist["ExpirationDate"] = date }
        let xml = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x0a, 0xff, 0x06, 0x09]) + xml + Data([0x00, 0x01, 0x30, 0x82, 0x04])
    }

    // MARK: Reading the profile

    func testReadsTheExpirationDateFromInsideTheSignedBlob() throws {
        let date = try XCTUnwrap(ProvisioningExpiry.expirationDate(profile: profile(expiring: expiry)))
        XCTAssertEqual(date.timeIntervalSinceReferenceDate, expiry.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testNoPlistMeansNoDate() {
        XCTAssertNil(ProvisioningExpiry.expirationDate(profile: Data([0x30, 0x82, 0x01, 0x02])))
    }

    func testProfileWithoutExpirationMeansNoDate() {
        XCTAssertNil(ProvisioningExpiry.expirationDate(profile: profile(expiring: nil)))
    }

    // MARK: Status

    func testStatusIsValidFarFromExpiry() {
        XCTAssertEqual(ProvisioningExpiry.status(expiry: expiry, now: expiry - hours(100)), .valid)
    }

    func testStatusIsSoonInTheLastThreeDays() {
        XCTAssertEqual(ProvisioningExpiry.status(expiry: expiry, now: expiry - hours(72)), .soon)
        XCTAssertEqual(ProvisioningExpiry.status(expiry: expiry, now: expiry - hours(1)), .soon)
    }

    func testStatusIsExpiredAtAndAfterTheDeadline() {
        XCTAssertEqual(ProvisioningExpiry.status(expiry: expiry, now: expiry), .expired)
        XCTAssertEqual(ProvisioningExpiry.status(expiry: expiry, now: expiry + hours(5)), .expired)
    }

    // MARK: Wording

    func testRemainingTimeIsWrittenInDaysOrHours() {
        XCTAssertEqual(ProvisioningExpiry.remainingText(expiry: expiry, now: expiry - hours(70)), "2 kun")
        XCTAssertEqual(ProvisioningExpiry.remainingText(expiry: expiry, now: expiry - hours(20)), "20 soat")
    }

    func testRemainingTimeNeverPromisesMoreThanThereIs() {
        XCTAssertEqual(ProvisioningExpiry.remainingText(expiry: expiry, now: expiry - hours(20.5)), "20 soat")
        XCTAssertEqual(ProvisioningExpiry.remainingText(expiry: expiry, now: expiry - hours(47.9)), "1 kun")
        XCTAssertEqual(ProvisioningExpiry.remainingText(expiry: expiry, now: expiry - 40 * 60), "<1 soat")
        XCTAssertEqual(ProvisioningExpiry.remainingText(expiry: expiry, now: expiry + 60), "<1 soat")
    }

    func testKeyboardNoteOnlyAppearsWhenExpiryIsNear() {
        XCTAssertNil(ProvisioningExpiry.keyboardNote(expiry: nil, now: expiry))
        XCTAssertNil(ProvisioningExpiry.keyboardNote(expiry: expiry, now: expiry - hours(100)))
        XCTAssertEqual(ProvisioningExpiry.keyboardNote(expiry: expiry, now: expiry - hours(50)), "⏳ 2 kun")
        XCTAssertEqual(ProvisioningExpiry.keyboardNote(expiry: expiry, now: expiry - hours(5)), "⏳ 5 soat")
        XCTAssertEqual(ProvisioningExpiry.keyboardNote(expiry: expiry, now: expiry + hours(1)), "⏳ tugadi")
    }

    // MARK: Reminders

    func testRemindersCoverTheDaysBeforeAndTheMomentAfter() {
        let dates = ProvisioningExpiry.reminderDates(expiry: expiry, now: expiry - hours(100))
        XCTAssertEqual(dates, [expiry - hours(48), expiry - hours(24), expiry - hours(6), expiry + hours(1)])
    }

    func testRemindersInThePastAreDropped() {
        XCTAssertEqual(
            ProvisioningExpiry.reminderDates(expiry: expiry, now: expiry - hours(30)),
            [expiry - hours(24), expiry - hours(6), expiry + hours(1)])
        XCTAssertEqual(ProvisioningExpiry.reminderDates(expiry: expiry, now: expiry + hours(2)), [])
    }
}
