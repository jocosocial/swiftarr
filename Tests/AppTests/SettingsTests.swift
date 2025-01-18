import Testing
import XCTVapor

@testable import swiftarr

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

	func testEmbarkationStartDate() async throws {
		try await withApp { app in
			XCTAssertEqual(embarkationDate, Settings.shared.cruiseStartDate())
		}
	}

	func testTimeZoneChange() async throws {
		try await withApp { app in
			let testDate = ISO8601DateFormatter().date(from: "2024-03-12T06:00:00Z")!
			XCTAssertEqual(Settings.shared.timeZoneChanges.tzAtTime(testDate).identifier, "America/Grand_Turk")
		}
	}

	func testPresentEmbarkationDate() async throws {
		try await withApp { app in
			let testDate = embarkationDate
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(embarkationDate, resultDate)
		}
	}

	func testPastEmbarkationDate() async throws {
		try await withApp { app in
			let testDate = ISO8601DateFormatter().date(from: "2023-07-08T05:00:00Z")!
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(embarkationDate, resultDate)
		}
	}

	func testFutureEmbarkationDate() async throws {
		try await withApp { app in
			let testDate = ISO8601DateFormatter().date(from: "2025-01-11T05:00:00Z")!
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(embarkationDate, resultDate)
		}
	}

	// The day we go to DST, 11:00AM UTC 7:00AM UTC-4 (EDT, EST+DST, AST)
	// "Theme: Retro Day" uses this date so its an easy checkpoint. In the database
	// it is stored as 2024-03-10T11:00:00Z. Whereas "Theme: Welcome, New Cruisers!"
	// starts at "2024-03-09 12:00:00+00" in the DB at 12:00PM UTC aka 7:00AM UTC-5, EST.
	let dstDate = ISO8601DateFormatter().date(from: "2024-03-10T11:00:00Z")!

	func testPresentDstDate() async throws {
		try await withApp { app in
			let testDate = dstDate
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(dstDate, resultDate)
		}
	}

	// This date is in the past but is still within daylight time (UTC-4)
    // 2023 July 09 is a Sunday
	func testPastDstDate() async throws {
		let testDate = ISO8601DateFormatter().date(from: "2023-07-09T11:00:00Z")!
		let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
		XCTAssertEqual(dstDate, resultDate)
	}

	// This date is in the past but back in standard time (UTC-5)
	func testPastNonDstDate() async throws {
		try await withApp { app in
			let testDate = ISO8601DateFormatter().date(from: "2023-11-12T11:00:00Z")!
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(dstDate, resultDate)
		}
	}

	// This date is in the future but is still within daylight time (UTC-4)
	func testFutureDstDate() async throws {
		try await withApp { app in
			let testDate = ISO8601DateFormatter().date(from: "2024-05-12T11:00:00Z")!
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(dstDate, resultDate)
		}
	}

	// This date is the future but back in standard time (UTC-5)
	func testFutureNonDstDate() async throws {
		try await withApp { app in
			let testDate = ISO8601DateFormatter().date(from: "2025-01-12T11:00:00Z")!
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
			XCTAssertEqual(dstDate, resultDate)
		}
	}

    // That "now" (the time that this test function was called) translates successfully
    // into the cruise week.
	func testNowDate() async throws {
		try await withApp { app in
			let testDate = Date()
            let cal = Settings.shared.calendarForDate(testDate)
            let testDateComponents = cal.dateComponents([.minute, .hour], from: testDate)
			let resultDate = Settings.shared.getDateInCruiseWeek(from: testDate)
            let resultDateComponents = cal.dateComponents([.minute, .hour], from: resultDate)

            // We only really care about the hour. Minute is there for fun.
            XCTAssertEqual(testDateComponents.hour, resultDateComponents.hour)
            XCTAssertEqual(testDateComponents.minute, resultDateComponents.minute)
		}
	}
}
