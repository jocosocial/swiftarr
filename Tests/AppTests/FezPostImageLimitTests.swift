import XCTVapor

@testable import swiftarr

// Private Event posts use the forum image limit (`maxForumPostImages`, 8 for Shutternauts).
// LFG posts stay at one image. Seamail still cannot attach photos.
class FezPostImageLimitTests: XCTestCase, SwiftarrBaseTest {

	private struct Fixture {
		let token: String
		let fezID: UUID
	}

	private func makeUser(_ app: Application, username: String, shutternaut: Bool = false) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: .verified
		)
		try await user.save(on: app.db)
		if shutternaut {
			let role = UserRole(user: try user.requireID(), role: .shutternaut)
			try await role.save(on: app.db)
		}
		return user
	}

	private func makeToken(_ app: Application, for user: User) async throws -> String {
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return token.token
	}

	private func makeFez(
		_ app: Application,
		owner: User,
		type: FezType,
		title: String
	) async throws -> FriendlyFez {
		let ownerID = try owner.requireID()
		let fez = FriendlyFez(
			owner: ownerID,
			fezType: type,
			title: title,
			info: "test fixture",
			location: "Deck 9",
			startTime: Date(),
			endTime: Date().addingTimeInterval(3600)
		)
		fez.participantArray = [ownerID]
		try await fez.save(on: app.db)
		try await fez.$participants.attach(
			[owner],
			on: app.db,
			{
				$0.readCount = 0
				$0.hiddenCount = 0
			}
		)
		return fez
	}

	private func makeFixture(
		_ app: Application,
		suffix: String,
		type: FezType,
		shutternaut: Bool = false
	) async throws -> Fixture {
		let user = try await makeUser(app, username: "fezimg-\(suffix)", shutternaut: shutternaut)
		let fez = try await makeFez(app, owner: user, type: type, title: "Event \(suffix)")
		let token = try await makeToken(app, for: user)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return Fixture(token: token, fezID: try fez.requireID())
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func namedImages(_ names: [String]) -> [ImageUploadData] {
		names.map { ImageUploadData($0, nil) }
	}

	private func postImages(
		_ app: Application,
		fixture: Fixture,
		names: [String],
		text: String = "photo post"
	) async throws -> (HTTPStatus, FezPostData?) {
		var status: HTTPStatus = .internalServerError
		var post: FezPostData?
		try await app.test(
			.POST,
			"/api/v3/fez/\(fixture.fezID)/post",
			headers: bearer(fixture.token),
			beforeRequest: { req async throws in
				try req.content.encode(PostContentData(text: text, images: namedImages(names)))
			},
			afterResponse: { res async throws in
				status = res.status
				if res.status == .ok {
					post = try res.content.decode(FezPostData.self)
				}
			}
		)
		return (status, post)
	}

	func testPrivateEvent_RegularUser_CanPostUpToLimit() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(
				app,
				suffix: UUID().uuidString.prefix(8).lowercased(),
				type: .privateEvent
			)
			let names = (1...Settings.shared.maxForumPostImages).map { "pe-ok-\($0).jpg" }
			let (status, post) = try await postImages(app, fixture: fixture, names: names)
			XCTAssertEqual(status, .ok)
			XCTAssertEqual(post?.images, names)
			XCTAssertEqual(post?.image, names.first)
		}
	}

	func testPrivateEvent_RegularUser_RejectedOverLimit() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(
				app,
				suffix: UUID().uuidString.prefix(8).lowercased(),
				type: .privateEvent
			)
			let over = Settings.shared.maxForumPostImages + 1
			let names = (1...over).map { "pe-over-\($0).jpg" }
			let (status, _) = try await postImages(app, fixture: fixture, names: names)
			XCTAssertEqual(status, .badRequest)
		}
	}

	func testPrivateEvent_Shutternaut_CanPostEight() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(
				app,
				suffix: UUID().uuidString.prefix(8).lowercased(),
				type: .privateEvent,
				shutternaut: true
			)
			let names = (1...8).map { "pe-naut-\($0).jpg" }
			let (status, post) = try await postImages(app, fixture: fixture, names: names)
			XCTAssertEqual(status, .ok)
			XCTAssertEqual(post?.images?.count, 8)
			XCTAssertEqual(post?.image, names.first)
		}
	}

	func testPrivateEvent_Shutternaut_RejectedOverEight() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(
				app,
				suffix: UUID().uuidString.prefix(8).lowercased(),
				type: .privateEvent,
				shutternaut: true
			)
			let names = (1...9).map { "pe-naut-over-\($0).jpg" }
			let (status, _) = try await postImages(app, fixture: fixture, names: names)
			XCTAssertEqual(status, .badRequest)
		}
	}

	func testLFG_StillLimitedToOne() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(
				app,
				suffix: UUID().uuidString.prefix(8).lowercased(),
				type: .activity,
				shutternaut: true
			)
			let (oneStatus, _) = try await postImages(app, fixture: fixture, names: ["lfg-one.jpg"])
			XCTAssertEqual(oneStatus, .ok)
			let (twoStatus, _) = try await postImages(app, fixture: fixture, names: ["lfg-a.jpg", "lfg-b.jpg"])
			XCTAssertEqual(twoStatus, .badRequest)
		}
	}

	func testSeamail_StillRejectsPhotos() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(
				app,
				suffix: UUID().uuidString.prefix(8).lowercased(),
				type: .closed
			)
			let (status, _) = try await postImages(app, fixture: fixture, names: ["seamail.jpg"])
			XCTAssertEqual(status, .badRequest)
		}
	}

	func testFezPostData_KeepsImageForOlderClients() throws {
		let author = UserHeader(
			userID: UUID(),
			username: "photo-user",
			displayName: nil,
			userImage: nil,
			preferredPronoun: nil
		)
		let data = FezPostData(
			postID: 7,
			author: author,
			text: "shots",
			timestamp: Date(timeIntervalSince1970: 1_725_000_000),
			image: "first.jpg",
			images: ["first.jpg", "second.jpg"]
		)
		let encoded = try JSONEncoder().encode(data)
		let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
		XCTAssertEqual(json?["image"] as? String, "first.jpg")
		XCTAssertEqual(json?["images"] as? [String], ["first.jpg", "second.jpg"])
	}
}
