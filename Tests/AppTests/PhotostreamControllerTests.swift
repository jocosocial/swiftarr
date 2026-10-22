import XCTVapor
import XCTest

@testable import swiftarr

final class PhotostreamControllerTests: XCTestCase, SwiftarrBaseTest {

	// `photostreamUploadHandler` builds its response straight off the `StreamPhoto` it just
	// created, and `StreamPhoto.init` records an `atEvent` by id only. `@OptionalParent`'s
	// getter is `self.value ?? nil`, so an unloaded relation reads as "no event" rather than
	// trapping — and `PhotostreamImageData.init` then falls through to the boat-location
	// branch. An event-tagged upload comes back tagged `onBoat` with no event attached, even
	// though the row it just wrote has the right `at_event`. Only the immediate response is
	// wrong; a later fetch that eager-loads the relation is correct, which is why this
	// survived review.
	func testEventTaggedPhoto_ResponseCarriesTheEvent() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = User(
				username: "photographer-\(suffix)",
				password: try Bcrypt.hash("password1"),
				recoveryKey: try Bcrypt.hash("recovery key"),
				accessLevel: .verified
			)
			try await user.save(on: app.db)

			let event = Event(
				startTime: Date(timeIntervalSince1970: 1_725_000_000),
				endTime: Date(timeIntervalSince1970: 1_725_003_600),
				title: "Tagged Event \(suffix)",
				description: "fixture",
				location: "Deck 5",
				eventType: .general,
				uid: "photostream-fixture-\(suffix)"
			)
			try await event.save(on: app.db)

			// Re-read the saved row with `roles` eager-loaded: `User.init` leaves optional columns
			// uninitialized and `UserCacheData.init` reads every field plus `user.roles`, either
			// of which traps when unfetched.
			let userID = try user.requireID()
			guard let storedUser = try await User.find(userID, on: app.db) else {
				return XCTFail("the fixture user was not saved")
			}
			try await storedUser.$roles.load(on: app.db)
			let cacheUser = UserCacheData(userID: try storedUser.requireID(), user: storedUser, blocks: nil, mutewords: nil)
			// Exactly what the handler does: designated init, then save, then build the response.
			let streamPhoto = StreamPhoto(
				image: "photostream-\(suffix).jpg",
				captureTime: Date(timeIntervalSince1970: 1_725_001_000),
				user: cacheUser,
				atEvent: event,
				boatLocation: nil
			)
			try await streamPhoto.save(on: app.db)

			XCTAssertEqual(
				streamPhoto.$atEvent.id,
				try event.requireID(),
				"the row itself is tagged correctly — the stored data is not the problem"
			)

			let photoData = try PhotostreamImageData(
				streamPhoto: streamPhoto,
				author: UserHeader(
					userID: try user.requireID(),
					username: user.username,
					displayName: nil,
					userImage: nil,
					preferredPronoun: nil
				)
			)

			XCTAssertEqual(photoData.event?.title, "Tagged Event \(suffix)", "the upload response must carry the event the photo was tagged with")
			XCTAssertNil(photoData.location, "a photo tagged with an event has no boat location")
		}
	}

	func testUploadResponseIncludesCreatedPhotoAndRateLimit() throws {
		let createdAt = Date(timeIntervalSince1970: 1_725_000_000)
		let photo = PhotostreamImageData(
			postID: 42,
			createdAt: createdAt,
			author: UserHeader(
				userID: UUID(uuidString: "A914114F-0B8E-4D86-9FB3-7D8C37F36FB7")!,
				username: "photographer",
				displayName: "Photographer",
				userImage: "avatar.png",
				preferredPronoun: nil
			),
			image: "photostream-42.jpg",
			event: nil,
			location: PhotoStreamBoatLocation.onBoat.rawValue
		)

		let response = try PhotostreamController()
			.makeUploadResponse(
				photo: photo,
				rateLimit: 900
			)

		XCTAssertEqual(response.status, .ok)
		XCTAssertEqual(response.headers.first(name: "Retry-After"), "900.0")
		let content = try response.content.decode(PhotostreamImageData.self)
		XCTAssertEqual(content.postID, 42)
		XCTAssertEqual(content.createdAt, createdAt)
		XCTAssertEqual(content.author.username, "photographer")
		XCTAssertEqual(content.image, "photostream-42.jpg")
		XCTAssertEqual(content.location, PhotoStreamBoatLocation.onBoat.rawValue)
	}

	// MARK: - Upload rate limit

	func testRateLimit_ZeroDisablesTheLimit() {
		let controller = PhotostreamController()
		let now = Date(timeIntervalSince1970: 1_725_000_000)
		XCTAssertFalse(
			controller.isWithinUploadRateLimit(
				previousCaptureTime: now,
				now: now,
				rateLimit: 0
			),
			"a 0 second interval must allow back-to-back uploads for testing"
		)
	}

	func testRateLimit_DefaultBlocksARecentUpload() {
		let controller = PhotostreamController()
		let now = Date(timeIntervalSince1970: 1_725_000_000)
		XCTAssertTrue(
			controller.isWithinUploadRateLimit(
				previousCaptureTime: now.addingTimeInterval(-60),
				now: now,
				rateLimit: 300
			),
			"the production 5 minute default must reject an upload from 1 minute ago"
		)
	}

	func testRateLimit_AllowsAnUploadAfterTheInterval() {
		let controller = PhotostreamController()
		let now = Date(timeIntervalSince1970: 1_725_000_000)
		XCTAssertFalse(
			controller.isWithinUploadRateLimit(
				previousCaptureTime: now.addingTimeInterval(-301),
				now: now,
				rateLimit: 300
			)
		)
	}

	func testRateLimitErrorReason_FormatsWholeMinutesAndOddSeconds() {
		let controller = PhotostreamController()
		XCTAssertEqual(
			controller.photostreamRateLimitErrorReason(30),
			"You may only upload one Photostream photo every 30 seconds."
		)
		XCTAssertEqual(
			controller.photostreamRateLimitErrorReason(85),
			"You may only upload one Photostream photo every 85 seconds."
		)
		XCTAssertEqual(
			controller.photostreamRateLimitErrorReason(60),
			"You may only upload one Photostream photo every 1 minute."
		)
		XCTAssertEqual(
			controller.photostreamRateLimitErrorReason(300),
			"You may only upload one Photostream photo every 5 minutes."
		)
	}

	func testSettingsAdminDataExposesPhotostreamRateLimit() {
		let data = SettingsAdminData(Settings.shared)
		XCTAssertEqual(data.photostreamUploadRateLimit, Settings.shared.photostreamUploadRateLimit)
		XCTAssertEqual(data.photostreamUploadRateLimit, 300, "production default is 5 minutes")
	}

	func testSettingsUpdateDataDecodesPhotostreamRateLimit() throws {
		let json = """
			{
				"enableFeatures": [],
				"disableFeatures": [],
				"photostreamUploadRateLimit": 0
			}
			""".data(using: .utf8)!
		let data = try JSONDecoder().decode(SettingsUpdateData.self, from: json)
		XCTAssertEqual(data.photostreamUploadRateLimit, 0)
	}

	// MARK: - Placenames (suggested event list) and upload validation

	private func makeVerifiedUser(_ app: Application) async throws -> (User, HTTPHeaders) {
		let suffix = UUID().uuidString.prefix(8).lowercased()
		let user = User(
			username: "pstream-\(suffix)",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: .verified
		)
		try await user.save(on: app.db)
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token.token)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return (user, headers)
	}

	/// Makes "now" in the placenames logic the same as `Date()`, so test events can be placed relative to the current time:
	/// the cruise week is pinned to the current day and the boat is kept in the port timezone for the duration of `body`.
	private func withNowPinned(_ app: Application, _ body: () async throws -> Void) async throws {
		let savedStart = Settings.shared.cruiseStartDateComponents
		let savedChangeSet = Settings.shared.timeZoneChanges
		let savedChanges = try await TimeZoneChange.query(on: app.db).all()
		Settings.shared.cruiseStartDateComponents = Settings.shared.getPortCalendar().dateComponents([.year, .month, .day], from: Date())
		Settings.shared.timeZoneChanges = TimeZoneChangeSet()
		try await TimeZoneChange.query(on: app.db).delete()
		do {
			try await body()
		}
		catch {
			try await restore(app, savedStart, savedChangeSet, savedChanges)
			throw error
		}
		try await restore(app, savedStart, savedChangeSet, savedChanges)
	}

	private func restore(_ app: Application, _ start: DateComponents, _ changeSet: TimeZoneChangeSet, _ changes: [TimeZoneChange]) async throws {
		Settings.shared.cruiseStartDateComponents = start
		Settings.shared.timeZoneChanges = changeSet
		for change in changes {
			try await TimeZoneChange(startTime: change.startTime, name: change.timeZoneName, id: change.timeZoneID).save(on: app.db)
		}
	}

	private func makeEvent(
		_ app: Application,
		title: String,
		type: EventType = .general,
		startingMinutesFromNow start: Double,
		endingMinutesFromNow end: Double
	) async throws -> Event {
		// Sample the clock once so the event's duration is exactly (end - start) minutes. Two Date() calls would
		// add a few microseconds, pushing a 6 hour event just over the controller's "longer than 6 hours" cutoff.
		let now = Date()
		let event = Event(
			startTime: now.addingTimeInterval(start * 60),
			endTime: now.addingTimeInterval(end * 60),
			title: title,
			description: "fixture",
			location: "Deck 5",
			eventType: type,
			uid: "pstream-\(UUID().uuidString)"
		)
		try await event.save(on: app.db)
		return event
	}

	private func suggestedEventIDs(_ app: Application, headers: HTTPHeaders) async throws -> Set<UUID> {
		var ids = Set<UUID>()
		try await app.test(
			.GET,
			"/api/v3/photostream/placenames",
			headers: headers,
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
				ids = Set(try res.content.decode(PhotostreamLocationData.self).events.map { $0.eventID })
			}
		)
		return ids
	}

	/// Attempts an upload tagged with the event. The image is junk, so a request that gets past place-tag validation
	/// fails later on image processing. Returns the failure reason.
	private func uploadReason(_ app: Application, headers: HTTPHeaders, eventID: UUID) async throws -> String {
		var reason = ""
		let body = PhotostreamUploadData(image: Data([0, 1, 2, 3]), createdAt: Date(), eventID: eventID, locationName: nil)
		try await app.test(
			.POST,
			"/api/v3/photostream/upload",
			headers: headers,
			beforeRequest: { req async throws in try req.content.encode(body) },
			afterResponse: { res async throws in
				reason = (try? res.content.decode(ErrorResponse.self).reason) ?? ""
			}
		)
		return reason
	}

	private let rejectedTagReason = "not in list of allowed tags"

	func testPlacenames_ListsRunningEventsOnly() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let running = try await makeEvent(app, title: "Running", startingMinutesFromNow: -30, endingMinutesFromNow: 30)
				let ended = try await makeEvent(app, title: "Ended", startingMinutesFromNow: -120, endingMinutesFromNow: -60)
				let upcoming = try await makeEvent(app, title: "Upcoming", startingMinutesFromNow: 60, endingMinutesFromNow: 120)

				let ids = try await suggestedEventIDs(app, headers: headers)
				XCTAssertTrue(ids.contains(try running.requireID()))
				XCTAssertFalse(ids.contains(try ended.requireID()))
				XCTAssertFalse(ids.contains(try upcoming.requireID()))
			}
		}
	}

	func testPlacenames_ExcludesDiningEvents() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let dining = try await makeEvent(app, title: "Dinner", type: .dining, startingMinutesFromNow: -30, endingMinutesFromNow: 60)
				let party = try await makeEvent(app, title: "Party", type: .party, startingMinutesFromNow: -30, endingMinutesFromNow: 60)

				let ids = try await suggestedEventIDs(app, headers: headers)
				XCTAssertFalse(ids.contains(try dining.requireID()), "dining events are not photostream tags")
				XCTAssertTrue(ids.contains(try party.requireID()))
			}
		}
	}

	func testPlacenames_ExcludesEventsLongerThanSixHoursExceptShadowEvents() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				// Multi-hour events are legitimate things to photograph, up to 6 hours.
				let longParty = try await makeEvent(app, title: "Long Party", type: .party, startingMinutesFromNow: -30, endingMinutesFromNow: 210)
				let sixHourGame = try await makeEvent(app, title: "Six Hour Game", type: .gaming, startingMinutesFromNow: -30, endingMinutesFromNow: 330)
				// Anything longer is excluded, except Shadow Cruise events such as megagames.
				let longGame = try await makeEvent(app, title: "High Score", type: .gaming, startingMinutesFromNow: -30, endingMinutesFromNow: 570)
				let longOfficial = try await makeEvent(app, title: "Quiet Zone", type: .general, startingMinutesFromNow: -30, endingMinutesFromNow: 400)
				let longShadow = try await makeEvent(app, title: "Megagame", type: .shadow, startingMinutesFromNow: -30, endingMinutesFromNow: 400)
				let themeDay = try await makeEvent(app, title: "Theme: Cosplay Day", type: .general, startingMinutesFromNow: -30, endingMinutesFromNow: 1050)

				let ids = try await suggestedEventIDs(app, headers: headers)
				XCTAssertTrue(ids.contains(try longParty.requireID()))
				XCTAssertTrue(ids.contains(try sixHourGame.requireID()), "a 6 hour event is not longer than 6 hours")
				XCTAssertTrue(ids.contains(try longShadow.requireID()), "shadow events are exempt from the duration limit")
				for event in [longGame, longOfficial, themeDay] {
					XCTAssertFalse(ids.contains(try event.requireID()), "\(event.title) runs longer than 6 hours")
				}
			}
		}
	}

	func testUpload_AcceptsTagsFromSuggestedList() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let event = try await makeEvent(app, title: "Running", startingMinutesFromNow: -30, endingMinutesFromNow: 30)
				let id = try event.requireID()

				let suggested = try await suggestedEventIDs(app, headers: headers)
				XCTAssertTrue(suggested.contains(id))
				let reason = try await uploadReason(app, headers: headers, eventID: id)
				XCTAssertFalse(reason.contains(rejectedTagReason), "every suggested event must be accepted as a tag: \(reason)")
			}
		}
	}

	func testUpload_RejectsTagsNotInSuggestedList() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let dining = try await makeEvent(app, title: "Dinner", type: .dining, startingMinutesFromNow: -30, endingMinutesFromNow: 60)
				let themeDay = try await makeEvent(app, title: "Theme: Formal Night", startingMinutesFromNow: -30, endingMinutesFromNow: 1050)
				let upcoming = try await makeEvent(app, title: "Upcoming", startingMinutesFromNow: 60, endingMinutesFromNow: 120)

				for event in [dining, themeDay, upcoming] {
					let reason = try await uploadReason(app, headers: headers, eventID: try event.requireID())
					XCTAssertTrue(reason.contains(rejectedTagReason), "\(event.title) is not suggested, so it must not be accepted: \(reason)")
				}
			}
		}
	}

	func testUpload_AcceptsEventThatEndedWithinGracePeriod() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let justEnded = try await makeEvent(app, title: "Just Ended", startingMinutesFromNow: -60, endingMinutesFromNow: -2)

				let suggested = try await suggestedEventIDs(app, headers: headers)
				XCTAssertFalse(suggested.contains(try justEnded.requireID()), "an ended event is not suggested")
				let reason = try await uploadReason(app, headers: headers, eventID: try justEnded.requireID())
				XCTAssertFalse(reason.contains(rejectedTagReason), "an event that ended 2 minutes ago is still accepted: \(reason)")
			}
		}
	}

	func testUpload_RejectsEventThatEndedLongAgo() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let ended = try await makeEvent(app, title: "Ended", startingMinutesFromNow: -120, endingMinutesFromNow: -10)

				let reason = try await uploadReason(app, headers: headers, eventID: try ended.requireID())
				XCTAssertTrue(reason.contains(rejectedTagReason), "an event that ended 10 minutes ago is outside the grace period: \(reason)")
			}
		}
	}

	func testUpload_AcceptsEventEndingInTheNextFewMinutes() async throws {
		try await withApp { app in
			try await withNowPinned(app) {
				let (_, headers) = try await makeVerifiedUser(app)
				let ending = try await makeEvent(app, title: "Ending Soon", startingMinutesFromNow: -60, endingMinutesFromNow: 3)
				let id = try ending.requireID()

				let suggested = try await suggestedEventIDs(app, headers: headers)
				XCTAssertTrue(suggested.contains(id))
				let reason = try await uploadReason(app, headers: headers, eventID: id)
				XCTAssertFalse(reason.contains(rejectedTagReason), "an event suggested a moment ago must still be accepted: \(reason)")
			}
		}
	}
}
