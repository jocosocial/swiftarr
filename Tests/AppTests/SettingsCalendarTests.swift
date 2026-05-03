import XCTVapor
@testable import swiftarr

class SettingsCalendarTests: XCTestCase {

	// MARK: - getPortCalendar

	func testGetPortCalendar_UsesPortTimeZone() {
		let cal = Settings.shared.getPortCalendar()
		XCTAssertEqual(cal.timeZone.identifier, Settings.shared.portTimeZone.identifier)
	}

	func testGetPortCalendar_IsGregorian() {
		let cal = Settings.shared.getPortCalendar()
		XCTAssertEqual(cal.identifier, .gregorian)
	}

	// MARK: - calendarForDate

	func testCalendarForDate_FallsBackToPortTimeZone_WithEmptyChangeSet() {
		// With the default (empty) timeZoneChanges, calendarForDate returns a calendar
		// whose timezone is the port timezone — fall-through behavior of tzAtTime.
		let date = Date()
		let cal = Settings.shared.calendarForDate(date)
		XCTAssertEqual(cal.timeZone.identifier, Settings.shared.portTimeZone.identifier)
		XCTAssertEqual(cal.identifier, .gregorian)
	}

	// MARK: - cruiseStartDate

	func testCruiseStartDate_UsesComponentsAndPortTimeZone() {
		// Save and override so the assertion is independent of source-default drift.
		let savedComponents = Settings.shared.cruiseStartDateComponents
		defer { Settings.shared.cruiseStartDateComponents = savedComponents }
		Settings.shared.cruiseStartDateComponents = DateComponents(year: 2024, month: 3, day: 9)
		// The fixture cruise date interpreted at midnight in America/New_York (UTC-5 in March, pre-DST)
		// is 2024-03-09T05:00:00Z.
		let expected = ISO8601DateFormatter().date(from: "2024-03-09T05:00:00Z")!
		XCTAssertEqual(Settings.shared.cruiseStartDate(), expected)
	}
}
