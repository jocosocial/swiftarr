import XCTVapor

@testable import swiftarr

final class VCardHelperTests: XCTestCase {

	private func makeProfileUser() throws -> User {
		let user = User(
			username: "janedoe",
			password: "not-a-hash",
			recoveryKey: "not-a-hash",
			accessLevel: .verified,
			profileUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
		)
		user.id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
		user.displayName = "Jane Display"
		user.realName = "Jane Doe"
		user.email = "jane@example.com"
		user.homeLocation = "Boston"
		user.about = "Likes turtles"
		user.preferredPronoun = "she/her"
		user.discordUsername = "jane1234"
		user.roomNumber = "Cabin 5000"
		user.message = "Greeting must not appear"
		user.userImage = "not-a-real-image.jpg"
		return user
	}

	func testHelper_MapsLandBasedFields_OmitsCruiseFields() throws {
		let user = try makeProfileUser()
		let vcf = try VCardHelper.buildVCard(from: user, includeDetails: true)

		XCTAssertTrue(vcf.contains("BEGIN:VCARD"))
		XCTAssertTrue(vcf.contains("VERSION:3.0"))
		XCTAssertTrue(vcf.contains("FN:Jane Display"))
		XCTAssertTrue(vcf.contains("NICKNAME:janedoe"))
		XCTAssertTrue(vcf.contains("jane@example.com"))
		XCTAssertTrue(vcf.contains("Boston"))
		XCTAssertTrue(vcf.contains("Pronouns: she/her"))
		XCTAssertTrue(vcf.contains("Likes turtles"))
		XCTAssertTrue(vcf.contains("Discord:jane1234"))
		XCTAssertTrue(vcf.contains("UID:urn:uuid:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
		XCTAssertTrue(vcf.contains("-//Twitarr//EN"))
		XCTAssertTrue(vcf.contains("N:Doe;Jane;;;") || vcf.contains("N:Doe;Jane"))
		XCTAssertFalse(vcf.contains("Cabin 5000"), "roomNumber must not appear in the vCard")
		XCTAssertFalse(vcf.contains("Greeting must not appear"), "profile message must not appear in the vCard")
		XCTAssertFalse(vcf.contains("PHOTO"), "PHOTO must be omitted when no image data is provided")
	}

	func testHelper_HidesDetailsWhenNotIncluded() throws {
		let user = try makeProfileUser()
		let vcf = try VCardHelper.buildVCard(from: user, includeDetails: false)

		XCTAssertTrue(vcf.contains("FN:janedoe"))
		XCTAssertTrue(vcf.contains("NICKNAME:janedoe"))
		XCTAssertFalse(vcf.contains("Jane Display"))
		XCTAssertFalse(vcf.contains("jane@example.com"))
		XCTAssertFalse(vcf.contains("Boston"))
		XCTAssertFalse(vcf.contains("Likes turtles"))
		XCTAssertFalse(vcf.contains("jane1234"))
		XCTAssertFalse(vcf.contains("PHOTO"))
	}

	func testHelper_EmbedsPhotoWhenDataProvided() throws {
		let user = try makeProfileUser()
		let photo = Data("fake-jpeg-bytes".utf8)
		let vcf = try VCardHelper.buildVCard(
			from: user,
			includeDetails: true,
			photoData: photo,
			photoFileExtension: "jpg"
		)
		XCTAssertTrue(vcf.contains("PHOTO"))
		XCTAssertTrue(vcf.contains("ENCODING=b") || vcf.contains("ENCODING=B"))
		XCTAssertTrue(vcf.contains("TYPE=JPEG") || vcf.contains("TYPE=jpeg"))
		XCTAssertTrue(vcf.contains(photo.base64EncodedString()))
	}
}

final class UserVCardControllerTests: XCTestCase, SwiftarrBaseTest {

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

	func testVCard_Unauthenticated_Returns401() async throws {
		try await withApp { app in
			try await app.asyncBoot()
			try await app.test(.GET, "/api/v3/users/00000000-0000-0000-0000-000000000000/vcard") { res async throws in
				XCTAssertEqual(res.status, .unauthorized)
			}
		}
	}

	func testVCard_ReturnsAttachmentWithContactFields() async throws {
		try await withApp { app in
			let requester = try await makeUser(
				app,
				username: "vcf-req-\(UUID().uuidString.prefix(6))",
				accessLevel: .verified
			)
			let target = try await makeUser(
				app,
				username: "vcf-tgt-\(UUID().uuidString.prefix(6))",
				accessLevel: .verified
			)
			target.displayName = "Target Display"
			target.email = "target@example.com"
			target.homeLocation = "Portland"
			target.roomNumber = "Cabin 12"
			try await target.save(on: app.db)
			let token = try await makeToken(app, for: requester)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let targetID = try target.requireID()
			try await app.test(.GET, "/api/v3/users/\(targetID)/vcard", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok)
				XCTAssertTrue(res.headers.contentType?.description.contains("vcard") ?? false, "content-type=\(res.headers.contentType as Any)")
				XCTAssertTrue(
					res.headers.first(name: .contentDisposition)?.contains("attachment") ?? false,
					"missing attachment disposition"
				)
				XCTAssertTrue(res.headers.first(name: .contentDisposition)?.contains("\(target.username).vcf") ?? false)
				let body = res.body.string
				XCTAssertTrue(body.contains("BEGIN:VCARD"))
				XCTAssertTrue(body.contains("FN:Target Display"))
				XCTAssertTrue(body.contains("target@example.com"))
				XCTAssertTrue(body.contains("Portland"))
				XCTAssertFalse(body.contains("Cabin 12"))
			}
		}
	}

	func testVCard_BlockedUser_Returns404() async throws {
		try await withApp { app in
			let blocker = try await makeUser(
				app,
				username: "vcf-blk-\(UUID().uuidString.prefix(6))",
				accessLevel: .verified
			)
			let blocked = try await makeUser(
				app,
				username: "vcf-blkd-\(UUID().uuidString.prefix(6))",
				accessLevel: .verified
			)
			let token = try await makeToken(app, for: blocker)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let blockedID = try blocked.requireID()
			try await app.test(.POST, "/api/v3/users/\(blockedID)/block", headers: bearer(token)) { res async throws in
				XCTAssertTrue([.ok, .created].contains(res.status), "block request failed: \(res.status)")
			}

			try await app.test(.GET, "/api/v3/users/\(blockedID)/vcard", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .notFound)
			}
		}
	}
}
