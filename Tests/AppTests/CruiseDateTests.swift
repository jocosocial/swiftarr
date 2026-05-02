import XCTVapor
@testable import swiftarr

// Pure tests for Settings.shared.getDateInCruiseWeek that don't require app/DB spinup.
// They override Settings.shared.cruiseStartDateComponents in setUp so the fixture
// date is stable regardless of what the in-source default happens to be.
class CruiseDateTests: XCTestCase {

	// Fixture cruise: embarks 2024-03-09 (Saturday), 8 days, departs from US Eastern timezone.
	// Mid-cruise date 2024-03-12 06:00 UTC is during DST (UTC-4).
	private let fixtureStartComponents = DateComponents(year: 2024, month: 3, day: 9)
	private let embarkationDate = ISO8601DateFormatter().date(from: "2024-03-09T05:00:00Z")!

	private var savedComponents: DateComponents!
	private var savedLength: Int!
	private var savedDayOfWeek: Int!

	override func setUp() {
		super.setUp()
		savedComponents = Settings.shared.cruiseStartDateComponents
		savedLength = Settings.shared.cruiseLengthInDays
		savedDayOfWeek = Settings.shared.cruiseStartDayOfWeek
		Settings.shared.cruiseStartDateComponents = fixtureStartComponents
		Settings.shared.cruiseLengthInDays = 8
		// Calendar weekday: Sunday=1, Saturday=7. The fixture cruise embarks on a Saturday,
		// so this must align with cruiseStartDateComponents above.
		Settings.shared.cruiseStartDayOfWeek = 7
	}

	override func tearDown() {
		Settings.shared.cruiseStartDateComponents = savedComponents
		Settings.shared.cruiseLengthInDays = savedLength
		Settings.shared.cruiseStartDayOfWeek = savedDayOfWeek
		super.tearDown()
	}

	// MARK: - Within the cruise week — date returns unchanged

	func testGetDateInCruiseWeek_WithinCruiseWeek_ReturnsSameDate() {
		let testDate = embarkationDate
		let result = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(result, testDate)
	}

	// MARK: - Date in the past — projects forward into cruise week

	func testGetDateInCruiseWeek_PastDate_ProjectsIntoCruiseWeek() {
		// 2023-07-08 is a Saturday well before the fixture cruise.
		let testDate = ISO8601DateFormatter().date(from: "2023-07-08T04:00:00Z")!
		let result = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(result, embarkationDate)
	}

	// MARK: - Date in the future — projects back into cruise week

	func testGetDateInCruiseWeek_FutureDate_ProjectsIntoCruiseWeek() {
		// 2025-01-11 is a Saturday well after the fixture cruise.
		// Outside DST so "midnight Eastern" is UTC-5 == 05:00:00Z.
		let testDate = ISO8601DateFormatter().date(from: "2025-01-11T05:00:00Z")!
		let result = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(result, embarkationDate)
	}

	// MARK: - DST boundary

	func testGetDateInCruiseWeek_DSTSundayWithinCruise_ReturnsSameDate() {
		// 2024-03-10 is the DST transition Sunday during the fixture cruise.
		// "11:00 UTC" is 07:00 EDT (UTC-4) — midnight on the cruise day shifted by 7h.
		let dstDate = ISO8601DateFormatter().date(from: "2024-03-10T11:00:00Z")!
		let result = Settings.shared.getDateInCruiseWeek(from: dstDate)
		XCTAssertEqual(result, dstDate)
	}

	// MARK: - Sanity check that fixture took effect

	func testFixtureSetUpAppliesCruiseStart() {
		XCTAssertEqual(Settings.shared.cruiseStartDate(), embarkationDate)
	}

	// MARK: - Mid-week projection (non-DST input → non-DST cruise day)

	func testGetDateInCruiseWeek_WednesdayInput_ProjectsToWednesdayInCruiseWeek() {
		// 2024-08-14 is a Wednesday (weekday=4) outside the cruise window.
		// Cruise embarks Saturday 2024-03-09; the Wednesday during the cruise is 2024-03-13.
		let testDate = ISO8601DateFormatter().date(from: "2024-08-14T16:00:00Z")!
		let result = Settings.shared.getDateInCruiseWeek(from: testDate)
		let cal = Calendar(identifier: .gregorian)
		var comps = cal.dateComponents(in: TimeZone(identifier: "America/New_York")!, from: result)
		// Should land in the 2024-03-09..03-16 window, on a Wednesday.
		XCTAssertEqual(comps.year, 2024)
		XCTAssertEqual(comps.month, 3)
		XCTAssertEqual(comps.day, 13)
	}

	// MARK: - getCurrentFilterDate strips sub-second precision

	func testGetCurrentFilterDate_StripsSubsecondPrecision() {
		let dateWithFractional = Date(timeIntervalSince1970: 1_710_000_000.5678)
		let stripped = Settings.shared.getCurrentFilterDate(from: dateWithFractional)
		// Sub-second portion must be zero — this is the function's whole reason for existing.
		let nanos = Calendar(identifier: .gregorian).component(.nanosecond, from: stripped)
		XCTAssertEqual(nanos, 0)
	}
}
