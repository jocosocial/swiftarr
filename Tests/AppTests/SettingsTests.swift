@testable import swiftarr
import XCTVapor
import Testing

// In 2024:
// Embarkation Day 2024-03-09 (Saturday)
// DST 2024-03-10 (Sunday)
// Return Day 2024-03-16 (Saturday)
//
// Present == Within the cruise week, aka real time.
// Past == Before the cruise week, simulating what is to come.
// Future == After the cruise week, simulating what was.
//
// Needs to match the data in time-zone-changes.txt seed and default cruiseStartDate.
class SettingsTests: XCTestCase, SwiftarrBaseTest {
	// Midnight UTC on the day that we depart port.
	let embarkationDate = ISO8601DateFormatter().date(from: "2024-03-09T05:00:00Z")!

    func testEmbarkationStartDate() {
        XCTAssertEqual(embarkationDate, Settings.shared.cruiseStartDate())
    }

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

    // The day we go to DST, 11:00AM UTC 7:00AM UTC-4 (EDT, EST+DST, AST)
    // "Theme: Retro Day" uses this date so its an easy checkpoint.
	let dstDate = ISO8601DateFormatter().date(from: "2024-03-10T11:00:00Z")!

    func testPresentDstDate() {
		let testDate = dstDate
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(dstDate, resultDate)
    }

	func testPastDstDate() {
		let testDate = ISO8601DateFormatter().date(from: "2023-07-09T11:00:00Z")!
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(dstDate, resultDate)
    }

	func testFutureDstDate() {
		let testDate = ISO8601DateFormatter().date(from: "2025-01-12T11:00:00Z")!
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(dstDate, resultDate)
    }
}