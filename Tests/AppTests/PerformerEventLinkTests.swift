import Fluent
import XCTVapor
@testable import swiftarr

// Tests for TwitarrTeam manual Performer <-> Event linking (issue #492), and for the spreadsheet
// link import preserving manual links.
final class PerformerEventLinkTests: XCTestCase, SwiftarrBaseTest {

	// MARK: - Helpers

	private func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		return user
	}

	private func makeToken(_ app: Application, for user: User) async throws -> String {
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return token.token
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func makePerformer(_ app: Application, name: String, official: Bool) async throws -> Performer {
		let performer = Performer()
		performer.name = name
		performer.sortOrder = name.uppercased()
		performer.yearsAttended = [2026]
		performer.officialPerformer = official
		try await performer.save(on: app.db)
		return performer
	}

	private func makeEvent(_ app: Application, title: String) async throws -> Event {
		let start = Date()
		let event = Event(
			startTime: start,
			endTime: start.addingTimeInterval(3600),
			title: title,
			description: "Test event",
			location: "Test Room",
			eventType: .general,
			uid: UUID().uuidString
		)
		try await event.save(on: app.db)
		return event
	}

	private func pivot(_ app: Application, performer: Performer, event: Event) async throws -> EventPerformer? {
		try await EventPerformer.query(on: app.db)
			.filter(\.$performer.$id == performer.requireID())
			.filter(\.$event.$id == event.requireID()).first()
	}

	// MARK: - Tests

	func testTTCanLinkAndUnlink() async throws {
		try await withApp { app in
			let tt = try await makeUser(app, username: "perf-link-tt-\(UUID().uuidString.prefix(6))", accessLevel: .twitarrteam)
			let token = try await makeToken(app, for: tt)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			let performer = try await makePerformer(app, name: "Link Shadow \(UUID().uuidString.prefix(6))", official: false)
			let event = try await makeEvent(app, title: "Official Office Hours")
			let url = "/api/v3/admin/performer/\(try performer.requireID())/event/\(try event.requireID())"

			try await app.test(.POST, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .created, "body=\(String(buffer: res.body))")
			}
			let linked = try await pivot(app, performer: performer, event: event)
			XCTAssertEqual(linked?.manuallyLinked, true)

			// Linking again is idempotent.
			try await app.test(.POST, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok)
			}
			let count = try await EventPerformer.query(on: app.db).filter(\.$event.$id == event.requireID()).count()
			XCTAssertEqual(count, 1)

			try await app.test(.DELETE, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok)
			}
			let removed = try await pivot(app, performer: performer, event: event)
			XCTAssertNil(removed)

			try await app.test(.DELETE, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .noContent)
			}
		}
	}

	func testLinkingExistingImportedPivotMarksItManual() async throws {
		try await withApp { app in
			let tt = try await makeUser(app, username: "perf-link-tt2-\(UUID().uuidString.prefix(6))", accessLevel: .twitarrteam)
			let token = try await makeToken(app, for: tt)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			let performer = try await makePerformer(app, name: "Link Official \(UUID().uuidString.prefix(6))", official: true)
			let event = try await makeEvent(app, title: "Imported Event")
			try await EventPerformer(event: event, performer: performer).save(on: app.db)

			let url = "/api/v3/admin/performer/\(try performer.requireID())/event/\(try event.requireID())"
			try await app.test(.POST, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok)
			}
			let updated = try await pivot(app, performer: performer, event: event)
			XCTAssertEqual(updated?.manuallyLinked, true)
		}
	}

	func testNonTTCannotLink() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-link-user-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			let performer = try await makePerformer(app, name: "Link Denied \(UUID().uuidString.prefix(6))", official: true)
			let event = try await makeEvent(app, title: "Denied Event")
			let url = "/api/v3/admin/performer/\(try performer.requireID())/event/\(try event.requireID())"

			try await app.test(.POST, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .forbidden)
			}
			try await app.test(.DELETE, url, headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .forbidden)
			}
		}
	}

	func testSpreadsheetReplaceKeepsManualPivots() async throws {
		try await withApp { app in
			try await app.asyncBoot()
			let performer = try await makePerformer(app, name: "Sheet Official \(UUID().uuidString.prefix(6))", official: true)
			let manualEvent = try await makeEvent(app, title: "Manual Event")
			let importedEvent = try await makeEvent(app, title: "Imported Event")
			let newEvent = try await makeEvent(app, title: "New Sheet Event")
			try await EventPerformer(event: manualEvent, performer: performer, manuallyLinked: true).save(on: app.db)
			try await EventPerformer(event: importedEvent, performer: performer).save(on: app.db)

			// The new spreadsheet drops importedEvent, adds newEvent, and also (redundantly) lists manualEvent.
			let newPivots = [
				try EventPerformer(event: newEvent, performer: performer),
				try EventPerformer(event: manualEvent, performer: performer),
			]
			try await PerformerController().replaceOfficialPerformerPivots(with: newPivots, on: app.db)

			let manual = try await pivot(app, performer: performer, event: manualEvent)
			XCTAssertEqual(manual?.manuallyLinked, true)
			let stale = try await pivot(app, performer: performer, event: importedEvent)
			XCTAssertNil(stale)
			let added = try await pivot(app, performer: performer, event: newEvent)
			XCTAssertNotNil(added)
		}
	}

	private func uploadData(name: String) -> PerformerUploadData {
		PerformerUploadData(performerID: nil, name: name, pronouns: nil, bio: "Bio", photo: ImageUploadData(filename: nil, image: nil),
				isOfficialPerformer: false, organization: nil, title: nil, yearsAttended: [], website: nil, facebookURL: nil, xURL: nil,
				instagramURL: nil, youtubeURL: nil, alternativeNames: nil, eventUIDs: [])
	}

	func testRoleHolderCanCreateUnattachedShadowPerformer() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-self-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			try await UserRole(user: user.requireID(), role: .performerselfeditor).save(on: app.db)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await app.test(.POST, "/api/v3/performer/self", headers: bearer(token), beforeRequest: { req in
				try req.content.encode(uploadData(name: "Unattached Organizer"))
			}) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
			}
			let performer = try await Performer.query(on: app.db).filter(\.$user.$id == user.requireID()).first()
			XCTAssertEqual(performer?.name, "Unattached Organizer")
			XCTAssertEqual(performer?.officialPerformer, false)
			let pivots = try await performer?.$events.query(on: app.db).count()
			XCTAssertEqual(pivots, 0)

			// Re-posting updates the same profile instead of creating a second one.
			try await app.test(.POST, "/api/v3/performer/self", headers: bearer(token), beforeRequest: { req in
				try req.content.encode(uploadData(name: "Renamed Organizer"))
			}) { res async throws in
				XCTAssertEqual(res.status, .ok)
			}
			let all = try await Performer.query(on: app.db).filter(\.$user.$id == user.requireID()).all()
			XCTAssertEqual(all.count, 1)
			XCTAssertEqual(all.first?.name, "Renamed Organizer")
		}
	}

	func testTwitarrTeamCanCreateUnattachedShadowPerformer() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-self-tt-\(UUID().uuidString.prefix(6))", accessLevel: .twitarrteam)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			try await app.test(.POST, "/api/v3/performer/self", headers: bearer(token), beforeRequest: { req in
				try req.content.encode(uploadData(name: "TT Organizer"))
			}) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
			}
			let performer = try await Performer.query(on: app.db).filter(\.$user.$id == user.requireID()).first()
			XCTAssertEqual(performer?.name, "TT Organizer")
		}
	}

	func testUserWithoutRoleCannotCreateUnattachedShadowPerformer() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-self-norole-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			try await app.test(.POST, "/api/v3/performer/self", headers: bearer(token), beforeRequest: { req in
				try req.content.encode(uploadData(name: "Nope"))
			}) { res async throws in
				XCTAssertEqual(res.status, .forbidden)
			}
		}
	}
}
