import Fluent
import XCTVapor
@testable import swiftarr

// Tests for Quartermaster Phase 3: moderation integration.
//
// Uses SwiftarrBaseTest and a live Postgres instance (port 5433) plus Redis (port 6380), in the
// same way as QuartermasterControllerTests and ForumQuarantineVisibilityTests. There were no
// tests against any /api/v3/mod/* route before this file -- these are the first.

final class QuartermasterModerationTests: XCTestCase, SwiftarrBaseTest {

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

	private func contentHeaders(_ token: String) -> HTTPHeaders {
		var headers = bearer(token)
		headers.contentType = .json
		return headers
	}

	/// Creates one item owned by `token`, returning its ID.
	private func createItem(_ app: Application, token: String, itemName: String = "Widget") async throws -> UUID {
		let payload = "{\"category\":\"have\",\"location\":\"Deck 5\",\"items\":[{\"itemName\":\"\(itemName)\"}]}"
		var itemID: UUID?
		try await app.test(
			.POST, "/api/v3/quartermaster/create",
			headers: contentHeaders(token), body: ByteBuffer(string: payload)
		) { res async throws in
			itemID = try res.content.decode([QuartermasterData].self).first?.itemID
		}
		guard let id = itemID else { XCTFail("failed to create fixture item"); throw Abort(.internalServerError) }
		return id
	}

	// MARK: - GET /api/v3/mod/quartermaster/:id

	func testModGet_ReturnsItemReportsAndEdits() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-mg-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let reporter = try await makeUser(app, username: "qm-mg-rpt-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let moderator = try await makeUser(app, username: "qm-mg-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let reporterToken = try await makeToken(app, for: reporter)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken, itemName: "Original name")

			// One text edit.
			let updatePayload = #"{"category":"have","itemName":"Updated name","location":"Deck 5"}"#
			try await app.test(.POST, "/api/v3/quartermaster/\(id)/update",
				headers: contentHeaders(ownerToken), body: ByteBuffer(string: updatePayload)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
			}

			// One report.
			let reportPayload = #"{"message":"Inappropriate content"}"#
			try await app.test(.POST, "/api/v3/quartermaster/\(id)/report",
				headers: contentHeaders(reporterToken), body: ByteBuffer(string: reportPayload)
			) { res async throws in
				XCTAssertEqual(res.status, .created)
			}

			try await app.test(.GET, "/api/v3/mod/quartermaster/\(id)", headers: bearer(modToken)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let modData = try res.content.decode(QuartermasterModerationData.self)
				XCTAssertEqual(modData.item.itemID, id)
				XCTAssertFalse(modData.isDeleted)
				XCTAssertEqual(modData.edits.count, 1, "the text update should show up as one edit")
				XCTAssertEqual(modData.edits.first?.itemName, "Original name", "edit log stores the pre-edit text")
				XCTAssertEqual(modData.reports.count, 1)
				XCTAssertEqual(modData.reports.first?.submitterMessage, "Inappropriate content")
			}
		}
	}

	func testModGet_SeesQuarantinedTextUnmasked() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-mq-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let moderator = try await makeUser(app, username: "qm-mq-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken, itemName: "Secret widget")

			guard let item = try await QuartermasterItem.find(id, on: app.db) else {
				XCTFail("item not found"); return
			}
			item.moderationStatus = .quarantined
			try await item.save(on: app.db)

			try await app.test(.GET, "/api/v3/mod/quartermaster/\(id)", headers: bearer(modToken)) { res async throws in
				let modData = try res.content.decode(QuartermasterModerationData.self)
				XCTAssertEqual(modData.item.itemName, "Secret widget", "a moderator must see quarantined text unmasked")
			}

			try await app.test(.GET, "/api/v3/quartermaster/\(id)", headers: bearer(ownerToken)) { res async throws in
				let itemData = try res.content.decode(QuartermasterData.self)
				XCTAssertEqual(itemData.itemName, "Item name is under moderator review", "quarantine must still mask text for non-mods")
			}
		}
	}

	func testModGet_DeletedItem_StillVisible() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-md-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let moderator = try await makeUser(app, username: "qm-md-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken)

			try await app.test(.POST, "/api/v3/quartermaster/\(id)/delete", headers: bearer(ownerToken)) { res async throws in
				XCTAssertEqual(res.status, .noContent)
			}

			try await app.test(.GET, "/api/v3/mod/quartermaster/\(id)", headers: bearer(modToken)) { res async throws in
				XCTAssertEqual(res.status, .ok, "mods must be able to review deleted items")
				let modData = try res.content.decode(QuartermasterModerationData.self)
				XCTAssertTrue(modData.isDeleted)
			}
		}
	}

	func testModGet_UnknownID_Returns404() async throws {
		try await withApp { app in
			let moderator = try await makeUser(app, username: "qm-mu-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await app.test(.GET, "/api/v3/mod/quartermaster/\(UUID())", headers: bearer(modToken)) { res async throws in
				XCTAssertEqual(res.status, .notFound)
			}
		}
	}

	func testModGet_NonModerator_Rejected() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-mn-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let ownerToken = try await makeToken(app, for: owner)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken)

			try await app.test(.GET, "/api/v3/mod/quartermaster/\(id)", headers: bearer(ownerToken)) { res async throws in
				XCTAssertTrue(res.status == .forbidden || res.status == .unauthorized, "status=\(res.status)")
			}
		}
	}

	// MARK: - POST /api/v3/mod/quartermaster/:id/setstate/:state

	func testSetState_Quarantine_MasksForRegularUser() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-sq-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let moderator = try await makeUser(app, username: "qm-sq-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken, itemName: "Flagged widget")

			try await app.test(
				.POST, "/api/v3/mod/quartermaster/\(id)/setstate/quarantined", headers: bearer(modToken)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
			}

			try await app.test(.GET, "/api/v3/quartermaster/\(id)", headers: bearer(ownerToken)) { res async throws in
				let itemData = try res.content.decode(QuartermasterData.self)
				XCTAssertEqual(itemData.itemName, "Item name is under moderator review")
			}

			try await app.test(.GET, "/api/v3/mod/quartermaster/\(id)", headers: bearer(modToken)) { res async throws in
				let modData = try res.content.decode(QuartermasterModerationData.self)
				XCTAssertEqual(modData.item.itemName, "Flagged widget", "mods still see the real text after quarantine")
				XCTAssertEqual(modData.moderationStatus, .quarantined)
			}

			let actionCount = try await ModeratorAction.query(on: app.db)
				.filter(\.$contentType == .quartermasterItem)
				.filter(\.$contentID == id.uuidString)
				.filter(\.$actionType == .quarantine)
				.count()
			XCTAssertEqual(actionCount, 1, "quarantining should log one ModeratorAction")
		}
	}

	func testSetState_Reviewed_SetsModReviewed() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-sr-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let moderator = try await makeUser(app, username: "qm-sr-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken)

			try await app.test(
				.POST, "/api/v3/mod/quartermaster/\(id)/setstate/reviewed", headers: bearer(modToken)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
			}

			guard let item = try await QuartermasterItem.find(id, on: app.db) else {
				XCTFail("item not found"); return
			}
			XCTAssertEqual(item.moderationStatus, .modReviewed)
		}
	}

	func testSetState_InvalidState_Returns400() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-si-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let moderator = try await makeUser(app, username: "qm-si-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: moderator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken)

			try await app.test(
				.POST, "/api/v3/mod/quartermaster/\(id)/setstate/bogus", headers: bearer(modToken)
			) { res async throws in
				XCTAssertEqual(res.status, .badRequest)
			}
		}
	}

	func testSetState_NonModerator_Rejected() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-sn-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let ownerToken = try await makeToken(app, for: owner)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let id = try await createItem(app, token: ownerToken)

			try await app.test(
				.POST, "/api/v3/mod/quartermaster/\(id)/setstate/quarantined", headers: bearer(ownerToken)
			) { res async throws in
				XCTAssertTrue(res.status == .forbidden || res.status == .unauthorized, "status=\(res.status)")
			}
		}
	}
}
