import Fluent
import XCTVapor

@testable import swiftarr

// Optional age rating on schedule events (issue #489).
class EventAgeRatingTests: XCTestCase, SwiftarrBaseTest {

	private func makeEvent(
		_ app: Application,
		title: String,
		ageRating: AgeRating?,
		uid: String
	) async throws -> Event {
		let start = Date()
		let event = Event(
			startTime: start,
			endTime: start.addingTimeInterval(3600),
			title: title,
			description: "fixture",
			location: "Deck 5",
			eventType: .general,
			uid: uid
		)
		event.ageRating = ageRating
		try await event.save(on: app.db)
		return event
	}

	func testEventDataIncludesAgeRating() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let rated = try await makeEvent(app, title: "Rated \(suffix)", ageRating: .adultsOnly, uid: "age-rated-\(suffix)")
			let unrated = try await makeEvent(app, title: "Unrated \(suffix)", ageRating: nil, uid: "age-unrated-\(suffix)")
			XCTAssertEqual(try EventData(rated).ageRating, .adultsOnly)
			XCTAssertNil(try EventData(unrated).ageRating)
		}
	}

	func testAgeRatingFilter() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let adults = try await makeEvent(app, title: "Adults \(suffix)", ageRating: .adultsOnly, uid: "age-adults-\(suffix)")
			let all = try await makeEvent(app, title: "All \(suffix)", ageRating: .allAges, uid: "age-all-\(suffix)")
			let none = try await makeEvent(app, title: "None \(suffix)", ageRating: nil, uid: "age-none-\(suffix)")

			try await app.test(
				.GET,
				"/api/v3/events?ageRating=adultsOnly&search=\(suffix)",
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let events = try res.content.decode([EventData].self)
					XCTAssertTrue(events.contains { $0.eventID == adults.id })
					XCTAssertFalse(events.contains { $0.eventID == all.id })
					XCTAssertFalse(events.contains { $0.eventID == none.id })
					XCTAssertEqual(events.first { $0.eventID == adults.id }?.ageRating, .adultsOnly)
				}
			)

			try await app.test(
				.GET,
				"/api/v3/events?ageRating=unrated&search=\(suffix)",
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let events = try res.content.decode([EventData].self)
					XCTAssertTrue(events.contains { $0.eventID == none.id })
					XCTAssertFalse(events.contains { $0.eventID == adults.id })
					XCTAssertFalse(events.contains { $0.eventID == all.id })
				}
			)

			try await app.test(
				.GET,
				"/api/v3/events?ageRating=bogus",
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
				}
			)
		}
	}
}
