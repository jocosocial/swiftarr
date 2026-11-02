import Fluent
import XCTVapor
import ZIPFoundation

@testable import swiftarr

// Creating LFGs and Personal/Private Events during preregistration (#611, #495).
class PreregistrationFezTests: XCTestCase, SwiftarrBaseTest {

	// MARK: Helpers

	private func makeUser(
		_ app: Application,
		username: String,
		accessLevel: UserAccessLevel = .verified,
		verification: String? = nil
	) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			verification: verification,
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

	private func bootCache(_ app: Application) async throws {
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
	}

	/// Restores the global Settings after a test that turned on preregistration.
	private struct SavedSettings {
		let prereg = Settings.shared.enablePreregistration
		let minAccess = Settings.shared.minAccessLevel
		let imagesRoot = Settings.shared.userImagesRootPath
		func restore() {
			Settings.shared.enablePreregistration = prereg
			Settings.shared.minAccessLevel = minAccess
			Settings.shared.userImagesRootPath = imagesRoot
		}
	}

	private func setPreregistration(_ on: Bool) {
		Settings.shared.enablePreregistration = on
		Settings.shared.minAccessLevel = on ? .twitarrteam : .banned
	}

	private struct Response {
		let status: HTTPStatus
		let body: ByteBuffer
		var isSuccess: Bool { (200..<300).contains(status.code) }
		func decode<T: Decodable>(_ type: T.Type) throws -> T {
			try JSONDecoder.custom(dates: .iso8601).decode(T.self, from: body)
		}
	}

	private func send<B: Content>(
		_ app: Application,
		_ method: HTTPMethod,
		_ path: String,
		token: String,
		body: B? = nil as String?
	) async throws -> Response {
		var result: Response?
		try await app.test(
			method,
			path,
			headers: bearer(token),
			beforeRequest: { req in
				if let body = body {
					try req.content.encode(body, as: .json)
				}
			},
			afterResponse: { res async throws in
				result = Response(status: res.status, body: res.body)
			}
		)
		return result!
	}

	private func get(_ app: Application, _ path: String, token: String) async throws -> Response {
		try await send(app, .GET, path, token: token)
	}

	private func fezData(
		type: FezType,
		title: String = "Test Fez",
		visibility: FezVisibility? = nil,
		initialUsers: [UUID] = [],
		firstPost: PostContentData? = nil
	) -> FezContentData {
		let start = Settings.shared.cruiseStartDate().addingTimeInterval(10 * 3600)
		var data = FezContentData(
			fezType: type,
			visibility: visibility,
			title: title,
			info: "Some info about it",
			startTime: start,
			endTime: start.addingTimeInterval(3600),
			location: "Pool Deck",
			minCapacity: 0,
			maxCapacity: 0,
			initialUsers: initialUsers
		)
		data.firstPost = firstPost
		return data
	}

	private func createFez(
		_ app: Application,
		token: String,
		_ data: FezContentData
	) async throws -> Response {
		try await send(app, .POST, "/api/v3/fez/create", token: token, body: data)
	}

	private func createFezID(_ app: Application, token: String, _ data: FezContentData) async throws -> UUID {
		let res = try await createFez(app, token: token, data)
		XCTAssertEqual(res.status, .created, String(buffer: res.body))
		return try res.decode(FezData.self).fezID
	}

	// MARK: Preregistration, restricted user

	func testVerifiedUserCanCreateLFGsAndPersonalAndPrivateEvents() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)
			setPreregistration(true)

			for (type, visibility) in [
				(FezType.activity, nil), (.personalEvent, nil), (.privateEvent, nil), (.privateEvent, FezVisibility.unlisted),
			] {
				let res = try await createFez(app, token: token, fezData(type: type, visibility: visibility))
				XCTAssertEqual(res.status, .created, "\(type) \(String(describing: visibility)): \(String(buffer: res.body))")
			}
		}
	}

	func testVerifiedUserCannotCreateSeamail() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)
			setPreregistration(true)

			let open = try await createFez(app, token: token, fezData(type: .open, initialUsers: [try other.requireID()]))
			XCTAssertFalse(open.isSuccess, "open seamail should be refused")
			let closed = try await createFez(app, token: token, fezData(type: .closed, initialUsers: [try other.requireID()]))
			XCTAssertFalse(closed.isSuccess, "closed seamail should be refused")
			let openAlone = try await createFez(app, token: token, fezData(type: .open))
			XCTAssertFalse(openAlone.isSuccess, "open seamail with no other users should be refused")
		}
	}

	func testVerifiedUserCannotAddOthersOrPostOnCreate() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)
			setPreregistration(true)

			for type in [FezType.activity, .privateEvent] {
				let withUsers = try await createFez(
					app,
					token: token,
					fezData(type: type, initialUsers: [try other.requireID()])
				)
				XCTAssertFalse(withUsers.isSuccess, "\(type) with another initial user should be refused")
			}
			let post = PostContentData(text: "hello there", images: [])
			let withPost = try await createFez(app, token: token, fezData(type: .activity, firstPost: post))
			XCTAssertFalse(withPost.isSuccess, "creating with a first post should be refused")
		}
	}

	func testViewingAndListingOnlyOwnFezzes() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			let otherToken = try await makeToken(app, for: other)
			try await bootCache(app)

			// Fezzes that exist before preregistration starts: someone else's LFG, and a seamail owned by our user.
			let othersLFG = try await createFezID(app, token: otherToken, fezData(type: .activity, title: "Others LFG"))
			let seamail = try await createFez(
				app,
				token: token,
				fezData(type: .open, title: "Our Seamail", initialUsers: [try other.requireID()])
			)
			XCTAssertEqual(seamail.status, .created, String(buffer: seamail.body))

			setPreregistration(true)
			let ownLFG = try await createFezID(app, token: token, fezData(type: .gaming, title: "Own LFG"))
			let ownPersonal = try await createFezID(app, token: token, fezData(type: .personalEvent, title: "Own Personal"))
			let ownPrivate = try await createFezID(app, token: token, fezData(type: .privateEvent, title: "Own Private"))

			for id in [ownLFG, ownPersonal, ownPrivate] {
				let res = try await get(app, "/api/v3/fez/\(id)", token: token)
				XCTAssertEqual(res.status, .ok, "own fez should be viewable")
			}
			let othersRes = try await get(app, "/api/v3/fez/\(othersLFG)", token: token)
			XCTAssertFalse(othersRes.isSuccess, "another user's LFG must not be viewable")

			for path in ["/api/v3/fez/open", "/api/v3/fez/joined"] {
				let res = try await get(app, path, token: token)
				XCTAssertFalse(res.isSuccess, "\(path) should be unavailable")
			}

			let owned = try await get(app, "/api/v3/fez/owner", token: token)
			XCTAssertEqual(owned.status, .ok)
			let titles = Set(try owned.decode(FezListData.self).fezzes.map { $0.title })
			XCTAssertEqual(titles, ["Own LFG", "Own Personal", "Own Private"])
		}
	}

	func testCannotPostJoinOrChangeMembers() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			let otherToken = try await makeToken(app, for: other)
			try await bootCache(app)
			let otherID = try other.requireID()

			let othersLFG = try await createFezID(app, token: otherToken, fezData(type: .activity, title: "Others LFG"))
			setPreregistration(true)
			let ownLFG = try await createFezID(app, token: token, fezData(type: .activity))
			let ownPrivate = try await createFezID(app, token: token, fezData(type: .privateEvent))

			let post = PostContentData(text: "hello there", images: [])
			for id in [ownLFG, ownPrivate] {
				let res = try await send(app, .POST, "/api/v3/fez/\(id)/post", token: token, body: post)
				XCTAssertFalse(res.isSuccess, "posting should be refused")
				let add = try await send(app, .POST, "/api/v3/fez/\(id)/user/\(otherID)/add", token: token)
				XCTAssertFalse(add.isSuccess, "adding a user should be refused")
				let remove = try await send(app, .POST, "/api/v3/fez/\(id)/user/\(otherID)/remove", token: token)
				XCTAssertFalse(remove.isSuccess, "removing a user should be refused")
			}
			let join = try await send(app, .POST, "/api/v3/fez/\(othersLFG)/join", token: token)
			XCTAssertFalse(join.isSuccess, "joining another user's LFG should be refused")
		}
	}

	func testUpdateCancelDeleteOwnAndNotOthers() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			let otherToken = try await makeToken(app, for: other)
			try await bootCache(app)

			let othersLFG = try await createFezID(app, token: otherToken, fezData(type: .activity, title: "Others LFG"))
			let othersPersonal = try await createFezID(app, token: otherToken, fezData(type: .personalEvent, title: "Others PE"))
			setPreregistration(true)
			let ownLFG = try await createFezID(app, token: token, fezData(type: .activity, title: "Own LFG"))
			let ownPersonal = try await createFezID(app, token: token, fezData(type: .personalEvent, title: "Own PE"))

			let update = try await send(
				app,
				.POST,
				"/api/v3/fez/\(ownLFG)/update",
				token: token,
				body: fezData(type: .activity, title: "Renamed LFG")
			)
			XCTAssertEqual(update.status, .ok, String(buffer: update.body))
			XCTAssertEqual(try update.decode(FezData.self).title, "Renamed LFG")

			let cancel = try await send(app, .POST, "/api/v3/fez/\(ownLFG)/cancel", token: token)
			XCTAssertEqual(cancel.status, .ok, String(buffer: cancel.body))
			XCTAssertTrue(try cancel.decode(FezData.self).cancelled)

			let delete = try await send(app, .DELETE, "/api/v3/fez/\(ownPersonal)", token: token)
			XCTAssertEqual(delete.status, .noContent, String(buffer: delete.body))
			let gone = try await get(app, "/api/v3/fez/\(ownPersonal)", token: token)
			XCTAssertFalse(gone.isSuccess)

			for (id, type) in [(othersLFG, FezType.activity), (othersPersonal, .personalEvent)] {
				let res = try await send(
					app,
					.POST,
					"/api/v3/fez/\(id)/update",
					token: token,
					body: fezData(type: type, title: "Hijacked")
				)
				XCTAssertFalse(res.isSuccess, "updating someone else's fez should be refused")
			}
			let deleteOthers = try await send(app, .DELETE, "/api/v3/fez/\(othersPersonal)", token: token)
			XCTAssertFalse(deleteOthers.isSuccess, "deleting someone else's personal event should be refused")
			let cancelOthers = try await send(app, .POST, "/api/v3/fez/\(othersLFG)/cancel", token: token)
			XCTAssertFalse(cancelOthers.isSuccess, "cancelling someone else's LFG should be refused")
		}
	}

	func testConvertPersonalToPrivateInPreregistrationStaysOwnerOnly() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)
			setPreregistration(true)

			let id = try await createFezID(app, token: token, fezData(type: .personalEvent, title: "Convert me"))
			let convert = try await send(
				app,
				.POST,
				"/api/v3/fez/\(id)/update",
				token: token,
				body: fezData(type: .privateEvent, title: "Convert me")
			)
			XCTAssertEqual(convert.status, .ok, String(buffer: convert.body))
			XCTAssertEqual(try convert.decode(FezData.self).fezType, .privateEvent)

			let add = try await send(app, .POST, "/api/v3/fez/\(id)/user/\(try other.requireID())/add", token: token)
			XCTAssertFalse(add.isSuccess, "adding a member during preregistration should be refused")
		}
	}

	// MARK: Preregistration, staff

	func testTwitarrTeamStillSeesOthersLFGsInPreregistration() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let tt = try await makeUser(app, username: "tt-\(suffix)", accessLevel: .twitarrteam)
			let token = try await makeToken(app, for: user)
			let ttToken = try await makeToken(app, for: tt)
			try await bootCache(app)
			setPreregistration(true)

			let lfg = try await createFezID(app, token: token, fezData(type: .activity, title: "Visible To Staff"))
			let open = try await get(app, "/api/v3/fez/open?hidePast=false", token: ttToken)
			XCTAssertEqual(open.status, .ok, String(buffer: open.body))
			XCTAssertTrue(try open.decode(FezListData.self).fezzes.contains { $0.fezID == lfg })
			let single = try await get(app, "/api/v3/fez/\(lfg)", token: ttToken)
			XCTAssertEqual(single.status, .ok, String(buffer: single.body))
		}
	}

	// MARK: Conversion outside of preregistration

	func testPersonalToPrivateConversionOutsidePreregistration() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "owner-\(suffix)")
			let other = try await makeUser(app, username: "other-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)

			let id = try await createFezID(app, token: token, fezData(type: .personalEvent, title: "Personal"))
			let convert = try await send(
				app,
				.POST,
				"/api/v3/fez/\(id)/update",
				token: token,
				body: fezData(type: .privateEvent, title: "Personal")
			)
			XCTAssertEqual(convert.status, .ok, String(buffer: convert.body))
			XCTAssertEqual(try convert.decode(FezData.self).fezType, .privateEvent)

			let add = try await send(app, .POST, "/api/v3/fez/\(id)/user/\(try other.requireID())/add", token: token)
			XCTAssertTrue(add.isSuccess, "adding a user to the converted event should work: \(String(buffer: add.body))")

			// Converting while also asking for a visibility must work too.
			let id2 = try await createFezID(app, token: token, fezData(type: .personalEvent, title: "Personal Two"))
			let convert2 = try await send(
				app,
				.POST,
				"/api/v3/fez/\(id2)/update",
				token: token,
				body: fezData(type: .privateEvent, title: "Personal Two", visibility: .unlisted)
			)
			XCTAssertEqual(convert2.status, .ok, String(buffer: convert2.body))
		}
	}

	func testConversionIsOneWay() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "owner-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)

			let privateID = try await createFezID(app, token: token, fezData(type: .privateEvent, title: "Private"))
			let toPersonal = try await send(
				app,
				.POST,
				"/api/v3/fez/\(privateID)/update",
				token: token,
				body: fezData(type: .personalEvent, title: "Private")
			)
			XCTAssertFalse(toPersonal.isSuccess, "Private -> Personal must stay forbidden")

			let lfgID = try await createFezID(app, token: token, fezData(type: .activity, title: "LFG"))
			let lfgToPrivate = try await send(
				app,
				.POST,
				"/api/v3/fez/\(lfgID)/update",
				token: token,
				body: fezData(type: .privateEvent, title: "LFG")
			)
			XCTAssertFalse(lfgToPrivate.isSuccess, "LFG -> Private Event must be forbidden")

			let personalID = try await createFezID(app, token: token, fezData(type: .personalEvent, title: "Personal"))
			let personalToLFG = try await send(
				app,
				.POST,
				"/api/v3/fez/\(personalID)/update",
				token: token,
				body: fezData(type: .activity, title: "Personal")
			)
			XCTAssertFalse(personalToLFG.isSuccess, "Personal -> LFG must be forbidden")
		}
	}

	// MARK: Bulk user export / import

	private func unzip(_ data: ByteBuffer) throws -> Data {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let zipURL = dir.appendingPathComponent("userfile.zip")
		try Data(buffer: data).write(to: zipURL)
		let outDir = dir.appendingPathComponent("out", isDirectory: true)
		try FileManager.default.unzipItem(at: zipURL, to: outDir)
		return try Data(contentsOf: outDir.appendingPathComponent("Twitarr_userfile/userfile.json"))
	}

	func testUserfileExportCarriesFezzesUnderTheirOwner() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let admin = try await makeUser(app, username: "admin-\(suffix)", accessLevel: .admin)
			let ownerCode = "ex\(suffix.prefix(6))"
			let otherCode = "ey\(suffix.prefix(6))"
			let owner = try await makeUser(app, username: "owner-\(suffix)", verification: ownerCode)
			let other = try await makeUser(app, username: "other-\(suffix)", verification: otherCode)
			for (user, code) in [(owner, ownerCode), (other, otherCode)] {
				let regCode = RegistrationCode(code: code)
				regCode.$user.id = try user.requireID()
				try await regCode.save(on: app.db)
			}
			let adminToken = try await makeToken(app, for: admin)
			let ownerToken = try await makeToken(app, for: owner)
			let otherToken = try await makeToken(app, for: other)
			try await bootCache(app)

			let ownerLFG = try await createFezID(app, token: ownerToken, fezData(type: .gaming, title: "Owner LFG"))
			let ownerPE = try await createFezID(app, token: ownerToken, fezData(type: .personalEvent, title: "Owner PE"))
			_ = try await createFezID(app, token: otherToken, fezData(type: .dining, title: "Other LFG"))
			// Fezzes the owner cancelled or deleted are abandoned on this server.
			let cancelledLFG = try await createFezID(app, token: ownerToken, fezData(type: .activity, title: "Cancelled LFG"))
			let cancel = try await send(app, .POST, "/api/v3/fez/\(cancelledLFG)/cancel", token: ownerToken)
			XCTAssertEqual(cancel.status, .ok, String(buffer: cancel.body))
			let deletedPE = try await createFezID(app, token: ownerToken, fezData(type: .personalEvent, title: "Deleted PE"))
			let delete = try await send(app, .DELETE, "/api/v3/fez/\(deletedPE)", token: ownerToken)
			XCTAssertEqual(delete.status, .noContent, String(buffer: delete.body))
			let seamail = try await createFez(
				app,
				token: ownerToken,
				fezData(type: .open, title: "Owner Seamail", initialUsers: [try other.requireID()])
			)
			XCTAssertEqual(seamail.status, .created)

			Settings.shared.minAccessLevel = .admin
			let download = try await get(app, "/api/v3/admin/bulkuserfile/download", token: adminToken)
			XCTAssertEqual(download.status, .ok)
			let json = try unzip(download.body)
			let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any]
			XCTAssertNil(parsed?["fezzes"], "fezzes belong under each user, not at the top level")
			let users = parsed?["users"] as? [[String: Any]] ?? []
			func titles(of username: String) -> Set<String> {
				let entry = users.first { $0["username"] as? String == username }
				let fezzes = entry?["fezzes"] as? [[String: Any]] ?? []
				return Set(fezzes.compactMap { $0["title"] as? String })
			}
			XCTAssertEqual(titles(of: owner.username), ["Owner LFG", "Owner PE"])
			let ownerEntry = users.first { $0["username"] as? String == owner.username }
			let exportedIDs = Set((ownerEntry?["fezzes"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
			XCTAssertEqual(exportedIDs, [ownerLFG.uuidString, ownerPE.uuidString], "each fez must be exported with its ID")
			XCTAssertEqual(titles(of: other.username), ["Other LFG"])
			XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("Owner Seamail"), "seamail must never be exported")
		}
	}

	func testUserfileImportCreatesFezzesOnceForTheirOwner() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			// The default images path is inside the toolchain and isn't writable under test.
			let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
			try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
			defer { try? FileManager.default.removeItem(at: tempRoot) }
			Settings.shared.userImagesRootPath = tempRoot
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let admin = try await makeUser(app, username: "admin-\(suffix)", accessLevel: .admin)
			let adminToken = try await makeToken(app, for: admin)
			let code = "im\(suffix.prefix(6))"
			try await RegistrationCode(code: code).save(on: app.db)
			try await bootCache(app)
			let username = "imported-\(suffix)"
			let start = Settings.shared.cruiseStartDate().addingTimeInterval(10 * 3600)

			let lfgID = UUID()
			let peID = UUID()
			func fezJSON(_ id: UUID, _ type: String, _ title: String) -> [String: Any] {
				[
					"id": id.uuidString, "fezType": type, "visibility": type == "personalEvent" ? "private" : "public", "title": title,
					"info": "imported info", "location": "Pool Deck", "startTime": start.timeIntervalSinceReferenceDate,
					"endTime": start.addingTimeInterval(3600).timeIntervalSinceReferenceDate, "minCapacity": 0, "maxCapacity": 0,
				]
			}
			let userJSON: [String: Any] = [
				"username": username, "displayName": "Imported", "password": try Bcrypt.hash("password1"),
				"recoveryKey": try Bcrypt.hash("recovery"), "verification": code, "accessLevel": "verified",
				"roles": [String](), "favoriteEvents": [String](), "photographerEvents": [String](), "favoriteUsers": [String](),
				"fezzes": [fezJSON(lfgID, "gaming", "Imported LFG"), fezJSON(peID, "personalEvent", "Imported PE")],
			]
			let userfile: [String: Any] = [
				"users": [userJSON], "performers": [Any](), "needsPhotographer": [String](), "dailyThemes": [Any](),
				"hunts": [Any](),
			]
			// Lay the file down where the upload endpoint would put it.
			let dir = Settings.shared.adminDirectoryPath.appendingPathComponent("uploadUserfileDir/Twitarr_userfile", isDirectory: true)
			try? FileManager.default.removeItem(at: dir)
			try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			defer { try? FileManager.default.removeItem(at: dir) }
			try JSONSerialization.data(withJSONObject: userfile).write(to: dir.appendingPathComponent("userfile.json"))

			Settings.shared.minAccessLevel = .admin
			let first = try await get(app, "/api/v3/admin/bulkuserfile/update/apply", token: adminToken)
			XCTAssertEqual(first.status, .ok, String(buffer: first.body))
			let imported = try await User.query(on: app.db).filter(\.$username == username).first()
			let importedID = try XCTUnwrap(imported?.id)
			let fezzes = try await FriendlyFez.query(on: app.db).filter(\.$owner.$id == importedID).all()
			XCTAssertEqual(Set(fezzes.map { $0.title }), ["Imported LFG", "Imported PE"])
			XCTAssertEqual(Set(fezzes.compactMap { $0.id }), [lfgID, peID], "imported fezzes must keep their exported IDs")
			XCTAssertTrue(fezzes.allSatisfy { $0.participantArray == [importedID] })

			let second = try await get(app, "/api/v3/admin/bulkuserfile/update/apply", token: adminToken)
			XCTAssertEqual(second.status, .ok, String(buffer: second.body))
			let again = try await FriendlyFez.query(on: app.db).filter(\.$owner.$id == importedID).count()
			XCTAssertEqual(again, 2, "re-applying the same userfile must not duplicate fezzes")
		}
	}

	// MARK: Additional rules

	func testRestrictedUserCannotDeleteOwnLFG() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "prereg-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)
			setPreregistration(true)

			let id = try await createFezID(app, token: token, fezData(type: .activity))
			let res = try await send(app, .DELETE, "/api/v3/fez/\(id)", token: token)
			XCTAssertFalse(res.isSuccess, "LFG owners can cancel but not delete")
			let still = try await get(app, "/api/v3/fez/\(id)", token: token)
			XCTAssertEqual(still.status, .ok)
		}
	}

	func testModeratorCannotConvertSomeoneElsesPersonalEvent() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let owner = try await makeUser(app, username: "owner-\(suffix)")
			let mod = try await makeUser(app, username: "mod-\(suffix)", accessLevel: .moderator)
			let ownerToken = try await makeToken(app, for: owner)
			let modToken = try await makeToken(app, for: mod)
			try await bootCache(app)

			let id = try await createFezID(app, token: ownerToken, fezData(type: .personalEvent, title: "Private business"))
			let res = try await send(
				app,
				.POST,
				"/api/v3/fez/\(id)/update",
				token: modToken,
				body: fezData(type: .privateEvent, title: "Private business")
			)
			XCTAssertFalse(res.isSuccess, "only the owner may convert a personal event")
			let after = try await get(app, "/api/v3/fez/\(id)", token: ownerToken)
			XCTAssertEqual(try after.decode(FezData.self).fezType, .personalEvent)
		}
	}

	func testLFGTypeCanStillChangeToAnotherLFGType() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let user = try await makeUser(app, username: "owner-\(suffix)")
			let token = try await makeToken(app, for: user)
			try await bootCache(app)

			let id = try await createFezID(app, token: token, fezData(type: .activity, title: "Switcheroo"))
			let res = try await send(
				app,
				.POST,
				"/api/v3/fez/\(id)/update",
				token: token,
				body: fezData(type: .gaming, title: "Switcheroo")
			)
			XCTAssertEqual(res.status, .ok, String(buffer: res.body))
			XCTAssertEqual(try res.decode(FezData.self).fezType, .gaming)
		}
	}

	// MARK: Bulk import edge cases

	/// Points the images root at a temp dir (the default is inside the toolchain), and lays a userfile down where the upload endpoint would.
	private func layDownUserfile(users: [[String: Any]]) throws -> URL {
		let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
		Settings.shared.userImagesRootPath = tempRoot
		let userfile: [String: Any] = [
			"users": users, "performers": [Any](), "needsPhotographer": [String](), "dailyThemes": [Any](), "hunts": [Any](),
		]
		let dir = Settings.shared.adminDirectoryPath.appendingPathComponent("uploadUserfileDir/Twitarr_userfile", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		try JSONSerialization.data(withJSONObject: userfile).write(to: dir.appendingPathComponent("userfile.json"))
		return tempRoot
	}

	private func importUserJSON(username: String, code: String, fezTitles: [String]?) throws -> [String: Any] {
		let start = Settings.shared.cruiseStartDate().addingTimeInterval(10 * 3600)
		var user: [String: Any] = [
			"username": username, "displayName": "Imported", "password": try Bcrypt.hash("password1"),
			"recoveryKey": try Bcrypt.hash("recovery"), "verification": code, "accessLevel": "verified",
			"roles": [String](), "favoriteEvents": [String](), "photographerEvents": [String](), "favoriteUsers": [String](),
		]
		if let fezTitles = fezTitles {
			user["fezzes"] = fezTitles.map { title -> [String: Any] in
				[
					"fezType": "gaming", "visibility": "public", "title": title, "info": "imported info", "location": "Pool Deck",
					"startTime": start.timeIntervalSinceReferenceDate, "endTime": start.addingTimeInterval(3600).timeIntervalSinceReferenceDate,
					"minCapacity": 0, "maxCapacity": 0,
				]
			}
		}
		return user
	}

	func testOlderUserfileWithoutFezzesKeyStillImports() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let admin = try await makeUser(app, username: "admin-\(suffix)", accessLevel: .admin)
			let adminToken = try await makeToken(app, for: admin)
			let code = "ol\(suffix.prefix(6))"
			try await RegistrationCode(code: code).save(on: app.db)
			try await bootCache(app)
			let username = "olduser-\(suffix)"
			let tempRoot = try layDownUserfile(users: [try importUserJSON(username: username, code: code, fezTitles: nil)])
			defer { try? FileManager.default.removeItem(at: tempRoot) }

			Settings.shared.minAccessLevel = .admin
			let res = try await get(app, "/api/v3/admin/bulkuserfile/update/apply", token: adminToken)
			XCTAssertEqual(res.status, .ok, String(buffer: res.body))
			let imported = try await User.query(on: app.db).filter(\.$username == username).first()
			let importedID = try XCTUnwrap(imported?.id)
			let count = try await FriendlyFez.query(on: app.db).filter(\.$owner.$id == importedID).count()
			XCTAssertEqual(count, 0)
		}
	}

	func testVerifyOnlyReportsFezzesWithoutCreatingAnything() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let admin = try await makeUser(app, username: "admin-\(suffix)", accessLevel: .admin)
			let adminToken = try await makeToken(app, for: admin)
			let code = "vf\(suffix.prefix(6))"
			try await RegistrationCode(code: code).save(on: app.db)
			try await bootCache(app)
			let username = "verifyuser-\(suffix)"
			let tempRoot = try layDownUserfile(users: [try importUserJSON(username: username, code: code, fezTitles: ["One", "Two"])])
			defer { try? FileManager.default.removeItem(at: tempRoot) }

			Settings.shared.minAccessLevel = .admin
			let res = try await get(app, "/api/v3/admin/bulkuserfile/verify", token: adminToken)
			XCTAssertEqual(res.status, .ok, String(buffer: res.body))
			let report = try res.decode(BulkUserUpdateVerificationData.self)
			XCTAssertEqual(report.fezCounts.importedCount, 2)
			XCTAssertEqual(report.fezCounts.errorCount, 0)
			let userCount = try await User.query(on: app.db).filter(\.$username == username).count()
			XCTAssertEqual(userCount, 0, "verify must not create users")
			let fezCount = try await FriendlyFez.query(on: app.db).filter(\.$title ~~ ["One", "Two"]).count()
			XCTAssertEqual(fezCount, 0, "verify must not create fezzes")
		}
	}

	func testUsernameConflictDoesNotHandFezzesToTheExistingAccount() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let admin = try await makeUser(app, username: "admin-\(suffix)", accessLevel: .admin)
			let adminToken = try await makeToken(app, for: admin)
			let fileCode = "fc\(suffix.prefix(6))"
			try await RegistrationCode(code: fileCode).save(on: app.db)
			let username = "taken-\(suffix)"
			let existing = try await makeUser(app, username: username, verification: "zz\(suffix.prefix(6))")
			try await bootCache(app)
			let tempRoot = try layDownUserfile(users: [try importUserJSON(username: username, code: fileCode, fezTitles: ["Stolen One", "Stolen Two"])])
			defer { try? FileManager.default.removeItem(at: tempRoot) }

			Settings.shared.minAccessLevel = .admin
			let res = try await get(app, "/api/v3/admin/bulkuserfile/update/apply", token: adminToken)
			XCTAssertEqual(res.status, .ok, String(buffer: res.body))
			let report = try res.decode(BulkUserUpdateVerificationData.self)
			XCTAssertEqual(report.fezCounts.importedCount, 0)
			XCTAssertEqual(report.fezCounts.errorCount, 2)
			let owned = try await FriendlyFez.query(on: app.db).filter(\.$owner.$id == existing.requireID()).count()
			XCTAssertEqual(owned, 0, "the existing account must not receive the file's fezzes")
		}
	}

	func testImportedFezIDBelongingToAnotherUserIsRejected() async throws {
		try await withApp { app in
			let saved = SavedSettings()
			defer { saved.restore() }
			setPreregistration(false)
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let admin = try await makeUser(app, username: "admin-\(suffix)", accessLevel: .admin)
			let adminToken = try await makeToken(app, for: admin)
			let other = try await makeUser(app, username: "other-\(suffix)")
			let otherToken = try await makeToken(app, for: other)
			let fileCode = "fi\(suffix.prefix(6))"
			try await RegistrationCode(code: fileCode).save(on: app.db)
			try await bootCache(app)
			let otherLFG = try await createFezID(app, token: otherToken, fezData(type: .gaming, title: "Other's LFG"))

			let username = "importer-\(suffix)"
			var user = try importUserJSON(username: username, code: fileCode, fezTitles: ["Colliding"])
			var fezzes = user["fezzes"] as? [[String: Any]] ?? []
			fezzes[0]["id"] = otherLFG.uuidString
			user["fezzes"] = fezzes
			let tempRoot = try layDownUserfile(users: [user])
			defer { try? FileManager.default.removeItem(at: tempRoot) }

			Settings.shared.minAccessLevel = .admin
			let res = try await get(app, "/api/v3/admin/bulkuserfile/update/apply", token: adminToken)
			XCTAssertEqual(res.status, .ok, String(buffer: res.body))
			let report = try res.decode(BulkUserUpdateVerificationData.self)
			XCTAssertEqual(report.fezCounts.importedCount, 0)
			XCTAssertEqual(report.fezCounts.errorCount, 1)
			let fez = try await FriendlyFez.find(otherLFG, on: app.db)
			XCTAssertEqual(fez?.$owner.id, try other.requireID(), "the existing fez must keep its owner")
			XCTAssertEqual(fez?.title, "Other's LFG")
		}
	}
}
