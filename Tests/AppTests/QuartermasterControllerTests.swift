import Fluent
import XCTVapor
@testable import swiftarr

// Tests for Quartermaster Phase 2: DTO validation and HTTP controller behaviour.
//
// Validation tests (QuartermasterValidationTests) are pure-Swift — no DB or network required.
// Controller tests (QuartermasterControllerTests) use SwiftarrBaseTest and a live Postgres instance
// (port 5433) plus Redis (port 6380) in the same way as ForumQuarantineVisibilityTests.

// MARK: - DTO Validation

class QuartermasterValidationTests: XCTestCase {

	private let decoder = ValidatingJSONDecoder()

	// Collect tester.validate() failures for a given JSON string.
	// Returns an empty array when validation passes.
	// Throws when runValidations() calls `throw Abort(...)` (cross-field / throw-based checks).
	private func validationErrors<T: Decodable>(_ type: T.Type, _ json: String) throws -> [String] {
		let data = json.data(using: .utf8)!
		let result = try decoder.validate(type, from: data)
		return result?.validationFailures.map { $0.errorString } ?? []
	}

	// MARK: - QuartermasterCreateData — location required when hiding name

	func testCreate_HideOwnerNameWithoutLocation_Throws() {
		let json = #"{"category":"have","hideOwnerName":true,"items":[{"itemName":"Widget"}]}"#
		XCTAssertThrowsError(try validationErrors(QuartermasterCreateData.self, json)) { err in
			let abort = err as? Abort
			XCTAssertEqual(abort?.status, .badRequest)
			XCTAssertTrue(abort?.reason.contains("location") ?? false)
		}
	}

	func testCreate_NoLocationNoHide_PassesCrossFieldCheck() throws {
		let json = #"{"category":"have","items":[{"itemName":"Widget"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertFalse(errs.contains { $0.contains("location") },
			"location should not be required when hideOwnerName is absent/false")
	}

	func testCreate_HideOwnerNameWithLocation_PassesCrossFieldCheck() throws {
		let json = #"{"category":"need","location":"Deck 5","hideOwnerName":true,"items":[{"itemName":"Widget"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertFalse(errs.contains { $0.contains("location") && $0.contains("hid") })
	}

	// MARK: - QuartermasterCreateData — items array bounds

	func testCreate_EmptyItemsArray_FailsValidation() throws {
		let json = #"{"category":"have","location":"Deck 5","items":[]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertTrue(errs.contains("must include at least one item"), "errs=\(errs)")
	}

	func testCreate_11Items_FailsValidation() throws {
		let items = Array(repeating: #"{"itemName":"Widget"}"#, count: 11).joined(separator: ",")
		let json = #"{"category":"have","location":"Deck 5","items":[\#(items)]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertTrue(errs.contains("cannot create more than 10 items at once"), "errs=\(errs)")
	}

	func testCreate_10Items_PassesValidation() throws {
		let items = Array(repeating: #"{"itemName":"Widget"}"#, count: 10).joined(separator: ",")
		let json = #"{"category":"have","location":"Deck 5","items":[\#(items)]}"#
		XCTAssertNoThrow(try validationErrors(QuartermasterCreateData.self, json))
	}

	// MARK: - QuartermasterCreateData — per-item itemName bounds

	func testCreate_ItemNameTooShort_Throws() {
		let json = #"{"category":"have","location":"Deck 5","items":[{"itemName":"x"}]}"#
		XCTAssertThrowsError(try validationErrors(QuartermasterCreateData.self, json)) { err in
			let abort = err as? Abort
			XCTAssertEqual(abort?.status, .badRequest)
			XCTAssertTrue(abort?.reason.contains("2 character minimum") ?? false, "reason=\(abort?.reason ?? "")")
		}
	}

	func testCreate_ItemNameTooLong_Throws() {
		let name = String(repeating: "a", count: 101)
		let json = #"{"category":"have","location":"Deck 5","items":[{"itemName":"\#(name)"}]}"#
		XCTAssertThrowsError(try validationErrors(QuartermasterCreateData.self, json)) { err in
			let abort = err as? Abort
			XCTAssertEqual(abort?.status, .badRequest)
			XCTAssertTrue(abort?.reason.contains("100 character limit") ?? false)
		}
	}

	func testCreate_ItemDescriptionTooLong_Throws() {
		let desc = String(repeating: "a", count: 2049)
		let json = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Widget","itemDescription":"\#(desc)"}]}"#
		XCTAssertThrowsError(try validationErrors(QuartermasterCreateData.self, json)) { err in
			let abort = err as? Abort
			XCTAssertEqual(abort?.status, .badRequest)
			XCTAssertTrue(abort?.reason.contains("2048 character limit") ?? false)
		}
	}

	// MARK: - QuartermasterCreateData — shared location bounds

	func testCreate_LocationTooShort_FailsValidation() throws {
		let json = #"{"category":"have","location":"ab","items":[{"itemName":"Widget"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertTrue(errs.contains("location field has a 3 character minimum"), "errs=\(errs)")
	}

	func testCreate_LocationTooLong_FailsValidation() throws {
		let loc = String(repeating: "a", count: 101)
		let json = #"{"category":"have","location":"\#(loc)","items":[{"itemName":"Widget"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertTrue(errs.contains("location field has a 100 character limit"), "errs=\(errs)")
	}

	// MARK: - QuartermasterCreateData — happy paths

	func testCreate_HappyPath_WithLocation() throws {
		let json = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Widget","itemDescription":"Nice widget"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertEqual(errs, [], "unexpected validation errors: \(errs)")
	}

	func testCreate_HappyPath_NoLocationNoHide() throws {
		let json = #"{"category":"need","items":[{"itemName":"Sunscreen"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertEqual(errs, [], "unexpected validation errors: \(errs)")
	}

	func testCreate_HappyPath_WithLocationAndHide() throws {
		let json = #"{"category":"have","location":"Lido Deck","hideOwnerName":true,"items":[{"itemName":"Sunscreen"},{"itemName":"Hat"}]}"#
		let errs = try validationErrors(QuartermasterCreateData.self, json)
		XCTAssertEqual(errs, [], "unexpected validation errors: \(errs)")
	}

	// MARK: - QuartermasterContentData (update) — location required when hiding name

	func testUpdate_HideOwnerNameWithoutLocation_Throws() {
		let json = #"{"category":"have","itemName":"Widget","hideOwnerName":true}"#
		XCTAssertThrowsError(try validationErrors(QuartermasterContentData.self, json)) { err in
			XCTAssertEqual((err as? Abort)?.status, .badRequest)
		}
	}

	func testUpdate_NoLocationNoHide_PassesCrossFieldCheck() throws {
		let json = #"{"category":"have","itemName":"Widget"}"#
		let errs = try validationErrors(QuartermasterContentData.self, json)
		XCTAssertFalse(errs.contains { $0.contains("location") },
			"location should not be required when hideOwnerName is absent/false")
	}

	// MARK: - QuartermasterContentData — itemName bounds

	func testUpdate_ItemNameTooShort_FailsValidation() throws {
		let json = #"{"category":"have","itemName":"x","location":"Deck 5"}"#
		let errs = try validationErrors(QuartermasterContentData.self, json)
		XCTAssertTrue(errs.contains("itemName field has a 2 character minimum"), "errs=\(errs)")
	}

	func testUpdate_ItemNameTooLong_FailsValidation() throws {
		let name = String(repeating: "a", count: 101)
		let json = #"{"category":"have","itemName":"\#(name)","location":"Deck 5"}"#
		let errs = try validationErrors(QuartermasterContentData.self, json)
		XCTAssertTrue(errs.contains("itemName field has a 100 character limit"), "errs=\(errs)")
	}

	func testUpdate_DescriptionTooLong_FailsValidation() throws {
		let desc = String(repeating: "a", count: 2049)
		let json = #"{"category":"have","itemName":"Widget","location":"Deck 5","itemDescription":"\#(desc)"}"#
		let errs = try validationErrors(QuartermasterContentData.self, json)
		XCTAssertTrue(errs.first(where: { $0.contains("2048 character limit") }) != nil, "errs=\(errs)")
	}

	func testUpdate_HappyPath() throws {
		let json = #"{"category":"need","itemName":"Widget","location":"Deck 5"}"#
		let errs = try validationErrors(QuartermasterContentData.self, json)
		XCTAssertEqual(errs, [], "unexpected validation errors: \(errs)")
	}

	// MARK: - QuartermasterContentData — image decoding

	func testUpdate_ImageOmitted_DecodesNil() throws {
		let json = #"{"category":"need","itemName":"Widget"}"#
		let data = try JSONDecoder().decode(QuartermasterContentData.self, from: json.data(using: .utf8)!)
		XCTAssertNil(data.image)
	}

	func testUpdate_ImageWithFilename_DecodesFilename() throws {
		let json = #"{"category":"need","itemName":"Widget","image":{"filename":"existing.jpg"}}"#
		let data = try JSONDecoder().decode(QuartermasterContentData.self, from: json.data(using: .utf8)!)
		XCTAssertEqual(data.image?.filename, "existing.jpg")
	}

	// MARK: - QuartermasterData — quarantine masks the image

	func testQuartermasterData_Quarantined_MasksImage() throws {
		let ownerID = UUID()
		let item = QuartermasterItem(
			ownerID: ownerID, category: .have, itemName: "Widget", image: "photo.jpg"
		)
		item.id = UUID()
		item.moderationStatus = .quarantined
		let owner = UserHeader(userID: ownerID, username: "tester", displayName: nil, userImage: "", preferredPronoun: nil)
		let data = try QuartermasterData(item: item, owner: owner, showOwner: true)
		XCTAssertNil(data.image, "image should be masked while quarantined")
	}

	func testQuartermasterData_Normal_ShowsImage() throws {
		let ownerID = UUID()
		let item = QuartermasterItem(
			ownerID: ownerID, category: .have, itemName: "Widget", image: "photo.jpg"
		)
		item.id = UUID()
		let owner = UserHeader(userID: ownerID, username: "tester", displayName: nil, userImage: "", preferredPronoun: nil)
		let data = try QuartermasterData(item: item, owner: owner, showOwner: true)
		XCTAssertEqual(data.image, "photo.jpg")
	}
}

// MARK: - HTTP Controller Tests

final class QuartermasterControllerTests: XCTestCase, SwiftarrBaseTest {

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

	/// Builds a valid batch-create JSON payload with a single item.
	private func createPayload(
		category: String = "have",
		itemName: String = "Extra sunscreen",
		itemDescription: String? = nil,
		location: String? = "Deck 5",
		hideOwnerName: Bool = false
	) -> String {
		var fields = [#""category":"\#(category)""#]
		if let loc = location { fields.append(#""location":"\#(loc)""#) }
		if hideOwnerName { fields.append(#""hideOwnerName":true"#) }
		var itemFields = [#""itemName":"\#(itemName)""#]
		if let desc = itemDescription { itemFields.append(#""itemDescription":"\#(desc)""#) }
		let itemJSON = "{" + itemFields.joined(separator: ",") + "}"
		fields.append(#""items":[\#(itemJSON)]"#)
		return "{" + fields.joined(separator: ",") + "}"
	}

	// MARK: - Test: unauthenticated access is rejected

	func testList_Unauthenticated_Returns401() async throws {
		try await withApp { app in
			try await app.asyncBoot()
			try await app.test(.GET, "/api/v3/quartermaster") { res async throws in
				XCTAssertEqual(res.status, .unauthorized)
			}
		}
	}

	// MARK: - Test: batch create

	func testCreate_BatchCreate_ReturnsCreatedItems() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-creator-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			// Two items in one call sharing location.
			let payload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Extra sunscreen"},{"itemName":"Spare hat"}]}"#

			var createdIDs: [UUID] = []
			try await app.test(
				.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token),
				body: ByteBuffer(string: payload)
			) { res async throws in
				XCTAssertEqual(res.status, .created, "body=\(String(buffer: res.body))")
				let created = try res.content.decode([QuartermasterData].self)
				XCTAssertEqual(created.count, 2, "expected 2 created items")
				XCTAssertEqual(created[0].itemName, "Extra sunscreen")
				XCTAssertEqual(created[1].itemName, "Spare hat")
				XCTAssertTrue(created.allSatisfy { $0.location == "Deck 5" }, "shared location should apply to all")
				XCTAssertTrue(created.allSatisfy { $0.category == .have }, "shared category should apply to all")
				createdIDs = created.map { $0.itemID }
			}

			// Verify rows persisted (the DB is shared across the test run, so scope by the IDs
			// this call actually returned rather than counting the whole table).
			let count = try await QuartermasterItem.query(on: app.db).filter(\.$id ~~ createdIDs).count()
			XCTAssertEqual(count, 2, "expected 2 rows in the database")
		}
	}

	// MARK: - Test: list

	func testList_Returns200() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-lister-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await app.test(.GET, "/api/v3/quartermaster", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertNotNil(list.paginator)
			}
		}
	}

	// MARK: - Test: category filter

	func testList_CategoryFilter_ReturnsOnlyMatchingCategory() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-cat-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			// Create one "have" and one "need".
			let havePayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Sunscreen"}]}"#
			let needPayload = #"{"category":"need","location":"Deck 5","items":[{"itemName":"Sunscreen"}]}"#
			for payload in [havePayload, needPayload] {
				try await app.test(.POST, "/api/v3/quartermaster/create",
					headers: contentHeaders(token), body: ByteBuffer(string: payload)) { _ async throws in }
			}

			try await app.test(.GET, "/api/v3/quartermaster?category=have", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertTrue(list.items.allSatisfy { $0.category == .have },
					"?category=have should return only 'have' items")
			}
		}
	}

	// MARK: - Test: search filter

	func testList_SearchFilter_MatchesDescription() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-search-desc-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let payload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Widget","itemDescription":"a rare narwhal figurine"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: payload)) { _ async throws in }

			try await app.test(.GET, "/api/v3/quartermaster?search=narwhal", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertTrue(list.items.contains { $0.itemName == "Widget" },
					"search=narwhal should match items via itemDescription")
			}
		}
	}

	func testList_SearchFilter_MatchesLocation() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-search-loc-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let payload = #"{"category":"have","location":"Promenade Deck","items":[{"itemName":"Gadget"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: payload)) { _ async throws in }

			try await app.test(.GET, "/api/v3/quartermaster?search=promenade", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertTrue(list.items.contains { $0.itemName == "Gadget" },
					"search=promenade should match items via location")
			}
		}
	}

	// MARK: - Test: mine filter

	func testList_MineFilter_ReturnsOnlyCallerItems() async throws {
		try await withApp { app in
			let userA = try await makeUser(app, username: "qm-mine-a-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let userB = try await makeUser(app, username: "qm-mine-b-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let tokenA = try await makeToken(app, for: userA)
			let tokenB = try await makeToken(app, for: userB)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let payloadA = #"{"category":"have","location":"Lido Deck","items":[{"itemName":"User A item"}]}"#
			let payloadB = #"{"category":"have","location":"Pool Deck","items":[{"itemName":"User B item"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(tokenA), body: ByteBuffer(string: payloadA)) { _ async throws in }
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(tokenB), body: ByteBuffer(string: payloadB)) { _ async throws in }

			try await app.test(.GET, "/api/v3/quartermaster?mine=true", headers: bearer(tokenA)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertTrue(list.items.allSatisfy { $0.owner?.username == userA.username },
					"?mine=true should return only the caller's own items, not other users'")
				XCTAssertFalse(list.items.contains { $0.itemName == "User B item" },
					"user B's item should not appear in user A's mine list")
			}
		}
	}

	// MARK: - Test: get single item

	func testGet_ExistingItem_Returns200() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-get-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var createdID: UUID?
			let payload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Widget"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: payload)
			) { res async throws in
				let items = try res.content.decode([QuartermasterData].self)
				createdID = items.first?.itemID
			}

			guard let id = createdID else { XCTFail("no created ID"); return }
			try await app.test(.GET, "/api/v3/quartermaster/\(id)", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let item = try res.content.decode(QuartermasterData.self)
				XCTAssertEqual(item.itemID, id)
				XCTAssertEqual(item.itemName, "Widget")
			}
		}
	}

	// MARK: - Test: hideOwnerName masking

	func testGet_HideOwnerName_MasksOwnerFromOtherUsers() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-hide-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let other = try await makeUser(app, username: "qm-hide-oth-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let ownerToken = try await makeToken(app, for: owner)
			let otherToken = try await makeToken(app, for: other)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let payload = #"{"category":"have","location":"Deck 5","hideOwnerName":true,"items":[{"itemName":"Hidden widget"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(ownerToken), body: ByteBuffer(string: payload)
			) { res async throws in
				let items = try res.content.decode([QuartermasterData].self)
				itemID = items.first?.itemID
				XCTAssertNotNil(items.first?.owner, "the owner should see their own identity in the create response")
			}
			guard let id = itemID else { XCTFail("no item"); return }

			try await app.test(.GET, "/api/v3/quartermaster/\(id)", headers: bearer(otherToken)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let item = try res.content.decode(QuartermasterData.self)
				XCTAssertNil(item.owner, "owner must be masked from other users when hideOwnerName is true")
				XCTAssertTrue(item.hideOwnerName)
				XCTAssertEqual(item.location, "Deck 5", "location must remain visible so the item can still be found")
			}

			try await app.test(.GET, "/api/v3/quartermaster/\(id)", headers: bearer(ownerToken)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let item = try res.content.decode(QuartermasterData.self)
				XCTAssertNotNil(item.owner, "the owner must still see their own identity")
			}
		}
	}

	func testGet_HideOwnerNameFalse_ShowsOwnerToOtherUsers() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-show-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let other = try await makeUser(app, username: "qm-show-oth-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let ownerToken = try await makeToken(app, for: owner)
			let otherToken = try await makeToken(app, for: other)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let payload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Visible widget"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(ownerToken), body: ByteBuffer(string: payload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			try await app.test(.GET, "/api/v3/quartermaster/\(id)", headers: bearer(otherToken)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let item = try res.content.decode(QuartermasterData.self)
				XCTAssertEqual(item.owner?.username, owner.username, "owner should be visible when hideOwnerName is false")
			}
		}
	}

	// MARK: - Test: update creates edit record when text changes

	func testUpdate_TextChange_CreatesEditRecord() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-upd-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Original name"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			let updatePayload = #"{"category":"have","itemName":"Updated name","location":"Deck 5"}"#
			try await app.test(.POST, "/api/v3/quartermaster/\(id)/update",
				headers: contentHeaders(token), body: ByteBuffer(string: updatePayload)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let updated = try res.content.decode(QuartermasterData.self)
				XCTAssertEqual(updated.itemName, "Updated name")
			}

			guard let savedItem = try await QuartermasterItem.find(id, on: app.db) else {
				XCTFail("item not found after update"); return
			}
			try await savedItem.$edits.load(on: app.db)
			XCTAssertEqual(savedItem.edits.count, 1, "a text change should create a QuartermasterItemEdit")
		}
	}

	func testUpdate_CategoryOnlyChange_CreatesNoEditRecord() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-cat-upd-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Widget"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			// Only category changes; text fields stay identical.
			let updatePayload = #"{"category":"need","itemName":"Widget","location":"Deck 5"}"#
			try await app.test(.POST, "/api/v3/quartermaster/\(id)/update",
				headers: contentHeaders(token), body: ByteBuffer(string: updatePayload)
			) { res async throws in
				XCTAssertEqual(res.status, .ok)
			}

			guard let savedItem = try await QuartermasterItem.find(id, on: app.db) else {
				XCTFail("item not found after update"); return
			}
			try await savedItem.$edits.load(on: app.db)
			XCTAssertEqual(savedItem.edits.count, 0, "category-only change must not create a QuartermasterItemEdit")
		}
	}

	func testUpdate_HideOwnerNameChange_CreatesEditRecord() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-hon-upd-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Widget"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			// Only hideOwnerName changes; text fields and category stay identical.
			let updatePayload = #"{"category":"have","itemName":"Widget","location":"Deck 5","hideOwnerName":true}"#
			try await app.test(.POST, "/api/v3/quartermaster/\(id)/update",
				headers: contentHeaders(token), body: ByteBuffer(string: updatePayload)
			) { res async throws in
				XCTAssertEqual(res.status, .ok)
			}

			guard let savedItem = try await QuartermasterItem.find(id, on: app.db) else {
				XCTFail("item not found after update"); return
			}
			try await savedItem.$edits.load(on: app.db)
			XCTAssertEqual(savedItem.edits.count, 1, "a hideOwnerName change should create a QuartermasterItemEdit")
		}
	}

	// MARK: - Test: delete

	func testDelete_Owner_Succeeds() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-del-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Delete me"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			try await app.test(.POST, "/api/v3/quartermaster/\(id)/delete", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .noContent)
			}
			// Verify the row is soft-deleted (not found without withDeleted).
			let found = try await QuartermasterItem.find(id, on: app.db)
			XCTAssertNil(found, "deleted item should not appear in normal queries (soft-delete)")
		}
	}

	func testDelete_OtherUserAsNonMod_Returns403() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-del-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let other = try await makeUser(app, username: "qm-del-oth-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let ownerToken = try await makeToken(app, for: owner)
			let otherToken = try await makeToken(app, for: other)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"My item"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(ownerToken), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			try await app.test(.POST, "/api/v3/quartermaster/\(id)/delete", headers: bearer(otherToken)) { res async throws in
				XCTAssertEqual(res.status, .forbidden, "non-owner non-mod must not delete another user's item")
			}
		}
	}

	func testDelete_ModeratorCanDeleteOthers() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-del-own2-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let mod = try await makeUser(app, username: "qm-del-mod-\(UUID().uuidString.prefix(6))", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: mod)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Mod target"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(ownerToken), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			try await app.test(.POST, "/api/v3/quartermaster/\(id)/delete", headers: bearer(modToken)) { res async throws in
				XCTAssertEqual(res.status, .noContent, "moderator must be able to delete any item")
			}
		}
	}

	// MARK: - Test: block-list filtering

	func testList_BlockedUserItems_HiddenFromBlocker() async throws {
		try await withApp { app in
			let blocker = try await makeUser(app, username: "qm-blk-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let blocked = try await makeUser(app, username: "qm-blkd-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let blockerToken = try await makeToken(app, for: blocker)
			let blockedToken = try await makeToken(app, for: blocked)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			// Post from the blocked user.
			var hiddenItemID: UUID?
			let payload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Should be hidden"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(blockedToken), body: ByteBuffer(string: payload)) { res async throws in
				hiddenItemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let hiddenItemID else { XCTFail("no item"); return }

			// Block that user.
			let blockedID = try blocked.requireID()
			try await app.test(.POST, "/api/v3/users/\(blockedID)/block", headers: bearer(blockerToken)) { res async throws in
				// Accept 200 or 201; just make sure the block request doesn't error.
				XCTAssertTrue([.ok, .created].contains(res.status),
					"block request failed: \(res.status)")
			}

			try await app.test(.GET, "/api/v3/quartermaster", headers: bearer(blockerToken)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let list = try res.content.decode(QuartermasterListData.self)
				// Match on the ID this test actually created, not the item name: the DB is shared
				// across the test run, and "Should be hidden" isn't unique to this test.
				XCTAssertFalse(list.items.contains { $0.itemID == hiddenItemID },
					"items from a blocked user must not appear in the list")
			}
		}
	}

	// MARK: - Test: mute-list filtering

	func testList_MutedUserItems_HiddenFromMuter_ButMuterStillVisibleToMuted() async throws {
		try await withApp { app in
			let muter = try await makeUser(app, username: "qm-mut-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let muted = try await makeUser(app, username: "qm-mutd-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let muterToken = try await makeToken(app, for: muter)
			let mutedToken = try await makeToken(app, for: muted)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			// Post from the muted user, and from the muter, so we can check both directions.
			var hiddenItemID: UUID?
			let hiddenPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Should be hidden from muter"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(mutedToken), body: ByteBuffer(string: hiddenPayload)) { res async throws in
				hiddenItemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let hiddenItemID else { XCTFail("no item"); return }

			var muterItemID: UUID?
			let muterPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Should stay visible to muted user"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(muterToken), body: ByteBuffer(string: muterPayload)) { res async throws in
				muterItemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let muterItemID else { XCTFail("no item"); return }

			// Mute the other user (one-directional: muter mutes muted).
			let mutedID = try muted.requireID()
			try await app.test(.POST, "/api/v3/users/\(mutedID)/mute", headers: bearer(muterToken)) { res async throws in
				XCTAssertTrue([.ok, .created].contains(res.status), "mute request failed: \(res.status)")
			}

			// The muter should no longer see the muted user's items.
			try await app.test(.GET, "/api/v3/quartermaster", headers: bearer(muterToken)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertFalse(list.items.contains { $0.itemID == hiddenItemID },
					"items from a muted user must not appear in the muter's list")
			}
			try await app.test(.GET, "/api/v3/quartermaster/\(hiddenItemID)", headers: bearer(muterToken)) { res async throws in
				XCTAssertEqual(res.status, .badRequest, "fetching a muted user's item directly must also be hidden")
			}

			// Muting is one-directional: the muted user must still see the muter's items.
			try await app.test(.GET, "/api/v3/quartermaster", headers: bearer(mutedToken)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				let list = try res.content.decode(QuartermasterListData.self)
				XCTAssertTrue(list.items.contains { $0.itemID == muterItemID },
					"muting is one-directional -- the muted user must still see the muter's items")
			}
		}
	}

	// MARK: - Test: report

	func testReport_Creates201() async throws {
		try await withApp { app in
			let owner = try await makeUser(app, username: "qm-rpt-own-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let reporter = try await makeUser(app, username: "qm-rpt-usr-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let ownerToken = try await makeToken(app, for: owner)
			let reporterToken = try await makeToken(app, for: reporter)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			var itemID: UUID?
			let createPayload = #"{"category":"have","location":"Deck 5","items":[{"itemName":"Reportable item"}]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(ownerToken), body: ByteBuffer(string: createPayload)
			) { res async throws in
				itemID = try res.content.decode([QuartermasterData].self).first?.itemID
			}
			guard let id = itemID else { XCTFail("no item"); return }

			let reportPayload = #"{"message":"Inappropriate content"}"#
			try await app.test(
				.POST, "/api/v3/quartermaster/\(id)/report",
				headers: contentHeaders(reporterToken),
				body: ByteBuffer(string: reportPayload)
			) { res async throws in
				XCTAssertEqual(res.status, .created, "report should return 201 Created")
			}

			// Verify a Report row was created for this specific item (the DB is shared across the
			// test run, so scope by reportedID rather than counting all Report rows).
			let reportCount = try await Report.query(on: app.db)
				.filter(\.$reportType == .quartermasterItem)
				.filter(\.$reportedID == id.uuidString)
				.count()
			XCTAssertEqual(reportCount, 1, "filing a report should create one Report row")
		}
	}

	// MARK: - Test: create rejects empty batch

	func testCreate_EmptyBatch_Returns400() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "qm-emp-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let payload = #"{"category":"have","location":"Deck 5","items":[]}"#
			try await app.test(.POST, "/api/v3/quartermaster/create",
				headers: contentHeaders(token), body: ByteBuffer(string: payload)
			) { res async throws in
				XCTAssertEqual(res.status, .badRequest, "empty items array must be rejected with 400")
			}
		}
	}
}
