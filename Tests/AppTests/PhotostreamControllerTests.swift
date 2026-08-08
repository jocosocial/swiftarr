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
}
