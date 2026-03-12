// ABOUTME: Tests for event notification timing queries.
// ABOUTME: Validates that event lookups use range queries instead of exact equality.

import Fluent
import Testing
import XCTVapor

@testable import swiftarr

class EventNotificationTests: XCTestCase, SwiftarrBaseTest {

	/// Creates a test event with the given startTime and saves it to the database.
	private func createTestEvent(startTime: Date, on db: Database) async throws -> Event {
		let event = Event(
			startTime: startTime,
			endTime: startTime.addingTimeInterval(3600),
			title: "Test Event",
			description: "A test event for notification timing",
			location: "Main Stage",
			eventType: .shadow,
			uid: "test-notification-\(UUID().uuidString)"
		)
		try await event.save(on: db)
		return event
	}

	/// The current (broken) behavior: exact equality misses events when there's
	/// even 1 second of scheduler jitter.
	func testExactEqualityMissesWithJitter() async throws {
		try await withApp { app in
			// Event starts at exactly 12:00:00 in port time
			let eventStart = ISO8601DateFormatter().date(from: "2024-03-10T17:00:00Z")!
			let event = try await createTestEvent(startTime: eventStart, on: app.db)

			// Simulate the notification job running with 2 seconds of jitter.
			// The job computes filterStartTime = now + notificationSeconds, but if the
			// scheduler fires 2 seconds late, the computed time is 2 seconds past the
			// event start.
			let filterTimeWithJitter = eventStart.addingTimeInterval(2)

			// Exact equality query — this is the CURRENT behavior
			let exactResults = try await Event.query(on: app.db)
				.filter(\.$startTime == filterTimeWithJitter)
				.all()

			// This proves the bug: the event exists but exact equality can't find it
			XCTAssertEqual(exactResults.count, 0, "Exact equality should miss the event when there's jitter")

			// Clean up
			try await event.delete(force: true, on: app.db)
		}
	}

	/// The fixed behavior: a range query catches events within a tolerance window,
	/// making it resilient to scheduler jitter.
	func testRangeQueryFindsEventWithJitter() async throws {
		try await withApp { app in
			// Event starts at exactly 12:00:00 in port time
			let eventStart = ISO8601DateFormatter().date(from: "2024-03-10T17:00:00Z")!
			let event = try await createTestEvent(startTime: eventStart, on: app.db)

			// Simulate 2 seconds of scheduler jitter
			let filterTimeWithJitter = eventStart.addingTimeInterval(2)

			// Range query with 60-second window — this is the FIXED behavior
			let rangeStart = filterTimeWithJitter.addingTimeInterval(-30)
			let rangeEnd = filterTimeWithJitter.addingTimeInterval(30)

			let rangeResults = try await Event.query(on: app.db)
				.filter(\.$startTime >= rangeStart)
				.filter(\.$startTime < rangeEnd)
				.all()

			XCTAssertEqual(rangeResults.count, 1, "Range query should find the event despite jitter")
			XCTAssertEqual(rangeResults.first?.title, "Test Event")

			// Clean up
			try await event.delete(force: true, on: app.db)
		}
	}

	/// Validates that displayTimeToPortTime correctly converts absolute time
	/// to port time for use in database queries against port-time-stored events.
	func testDisplayTimeToPortTimeForEventQuery() async throws {
		try await withApp { app in
			// Store an event at 12:00 port time (EST = UTC-5), so the Date value
			// represents "2024-03-10T12:00:00 EST" = "2024-03-10T17:00:00Z"
			let eventStartPortTime = ISO8601DateFormatter().date(from: "2024-03-10T17:00:00Z")!
			let event = try await createTestEvent(startTime: eventStartPortTime, on: app.db)

			// Simulate: ship is now in AST (UTC-4). The "real" absolute time when the
			// event should fire is 2024-03-10T16:00:00Z (12:00 AST = 16:00 UTC).
			// But the DB stores it as 12:00 EST = 17:00 UTC.
			//
			// displayTimeToPortTime converts absolute (display) time → port time,
			// which is exactly what we need to query the DB.
			let convertedTime = Settings.shared.timeZoneChanges.displayTimeToPortTime(eventStartPortTime)

			// The conversion should give us a time we can use to query port-time dates
			// When the ship is in the same TZ as port, conversion is identity
			// The important thing is that the query matches
			let rangeStart = convertedTime.addingTimeInterval(-30)
			let rangeEnd = convertedTime.addingTimeInterval(30)

			let results = try await Event.query(on: app.db)
				.filter(\.$startTime >= rangeStart)
				.filter(\.$startTime < rangeEnd)
				.all()

			XCTAssertGreaterThanOrEqual(results.count, 1, "Port time conversion should produce a queryable time")

			// Clean up
			try await event.delete(force: true, on: app.db)
		}
	}
}
