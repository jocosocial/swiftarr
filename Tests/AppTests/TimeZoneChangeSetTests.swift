import XCTVapor
@testable import swiftarr

class TimeZoneChangeSetTests: XCTestCase {

	// MARK: - Empty change set

	func testTzAtTime_EmptyChangeSet_ReturnsSettingsPortTimeZone() {
		let set = TimeZoneChangeSet()
		let now = Date()
		XCTAssertEqual(set.tzAtTime(now).identifier, Settings.shared.portTimeZone.identifier)
	}

	func testTzAtTime_EmptyChangeSet_NoArgument_ReturnsSettingsPortTimeZone() {
		let set = TimeZoneChangeSet()
		XCTAssertEqual(set.tzAtTime().identifier, Settings.shared.portTimeZone.identifier)
	}

	func testPortTimeToDisplayTime_EmptyChangeSet_ReturnsInputUnchanged() {
		let set = TimeZoneChangeSet()
		let testDate = ISO8601DateFormatter().date(from: "2024-03-12T15:00:00Z")!
		XCTAssertEqual(set.portTimeToDisplayTime(testDate), testDate)
	}

	func testDisplayTimeToPortTime_EmptyChangeSet_ReturnsInputUnchanged() {
		let set = TimeZoneChangeSet()
		let testDate = ISO8601DateFormatter().date(from: "2024-03-12T15:00:00Z")!
		XCTAssertEqual(set.displayTimeToPortTime(testDate), testDate)
	}

	func testAbbrevAtTime_EmptyChangeSet_ReturnsPortTimeZoneAbbrev() {
		let set = TimeZoneChangeSet()
		// With an empty set, falls through to Settings.shared.portTimeZone (default America/New_York).
		// The abbreviation depends on whether the date is in DST, but it must be 3 chars and in {EST, EDT}.
		let summer = ISO8601DateFormatter().date(from: "2024-07-01T12:00:00Z")!
		let abbrev = set.abbrevAtTime(summer)
		XCTAssertTrue(["EDT", "EST"].contains(abbrev), "Got \(abbrev)")
	}
}
