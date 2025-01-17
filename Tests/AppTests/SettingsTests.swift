@testable import swiftarr
import XCTVapor
import Testing

class SettingsTests: XCTestCase, SwiftarrBaseTest {
	// Midnight UTC on the day that we depart port.
	let embarkationDate = ISO8601DateFormatter().date(from: "2024-03-09T05:00:00Z")!

	// Present == Within the cruise week, aka real time.
	// Past == Before the cruise week, simulating what is to come.
	// Future == After the cruise week, simulating what was.
    func testPresentEmbarkationDate() {
		let testDate = embarkationDate
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(embarkationDate, resultDate)
    }

	func testPastEmbarkationDate() {
		let testDate = ISO8601DateFormatter().date(from: "2023-07-08T05:00:00Z")!
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(embarkationDate, resultDate)
    }

	func testFutureEmbarkationDate() {
		let testDate = ISO8601DateFormatter().date(from: "2025-01-11T05:00:00Z")!
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(embarkationDate, resultDate)
    }
}