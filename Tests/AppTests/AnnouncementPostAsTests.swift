import XCTVapor

@testable import swiftarr

// Who may author announcements as whom (issue #589):
//
// Caller          | self | TwitarrTeam | THO | admin
// ----------------+------+-------------+-----+------
// TwitarrTeam     | yes  | yes         | no  | yes
// THO             | yes  | no          | yes | yes
// admin           | yes  | yes         | yes | yes
//
// Unknown values (including "moderator") are forbidden. Edit keeps the author when
// postAsUser is omitted and changes it when postAsUser is given.
class AnnouncementPostAsTests: XCTestCase, SwiftarrBaseTest {

	private struct Accounts {
		let ttUsername: String
		let ttToken: String
		let thoUsername: String
		let thoToken: String
		let adminUsername: String
		let adminToken: String
	}

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

	private func makeAccounts(_ app: Application) async throws -> Accounts {
		let suffix = UUID().uuidString.prefix(8).lowercased()
		let tt = try await makeUser(app, username: "tt-\(suffix)", accessLevel: .twitarrteam)
		let tho = try await makeUser(app, username: "tho-\(suffix)", accessLevel: .tho)
		let admin = try await makeUser(app, username: "adm-\(suffix)", accessLevel: .admin)
		let ttToken = try await makeToken(app, for: tt)
		let thoToken = try await makeToken(app, for: tho)
		let adminToken = try await makeToken(app, for: admin)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return Accounts(
			ttUsername: tt.username,
			ttToken: ttToken,
			thoUsername: tho.username,
			thoToken: thoToken,
			adminUsername: admin.username,
			adminToken: adminToken
		)
	}

	private func futureISO() -> String {
		ISO8601DateFormatter([.withInternetDateTime, .withFractionalSeconds])
			.string(from: Date().addingTimeInterval(86_400))
	}

	private func bodyJSON(text: String, postAsUser: String?) -> String {
		let until = futureISO()
		if let postAsUser {
			return #"{"text":"\#(text)","displayUntil":"\#(until)","postAsUser":"\#(postAsUser)"}"#
		}
		return #"{"text":"\#(text)","displayUntil":"\#(until)"}"#
	}

	private func uniqueText(_ label: String) -> String {
		"589-\(label)-\(UUID().uuidString.prefix(8).lowercased())"
	}

	@discardableResult
	private func postCreate(
		_ app: Application,
		token: String,
		text: String,
		postAsUser: String? = nil
	) async throws -> HTTPStatus {
		var status: HTTPStatus = .internalServerError
		try await app.test(
			.POST,
			"/api/v3/notification/announcement/create",
			headers: bearer(token),
			beforeRequest: { req async throws in
				req.headers.contentType = .json
				req.body = ByteBuffer(string: bodyJSON(text: text, postAsUser: postAsUser))
			},
			afterResponse: { res async throws in
				status = res.status
			}
		)
		return status
	}

	private func fetchByText(_ app: Application, token: String, text: String) async throws -> AnnouncementData {
		var match: AnnouncementData?
		try await app.test(
			.GET,
			"/api/v3/notification/announcements?inactives=true",
			headers: bearer(token),
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
				let all = try res.content.decode([AnnouncementData].self)
				match = all.first { $0.text == text }
			}
		)
		return try XCTUnwrap(match, "expected an announcement with text \(text)")
	}

	private func postEdit(
		_ app: Application,
		token: String,
		id: Int,
		text: String,
		postAsUser: String? = nil
	) async throws -> (HTTPStatus, AnnouncementData?) {
		var status: HTTPStatus = .internalServerError
		var decoded: AnnouncementData?
		try await app.test(
			.POST,
			"/api/v3/notification/announcement/\(id)/edit",
			headers: bearer(token),
			beforeRequest: { req async throws in
				req.headers.contentType = .json
				req.body = ByteBuffer(string: bodyJSON(text: text, postAsUser: postAsUser))
			},
			afterResponse: { res async throws in
				status = res.status
				if res.status == .ok {
					decoded = try res.content.decode(AnnouncementData.self)
				}
			}
		)
		return (status, decoded)
	}

	func testTTPostsAsSelf() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("tt-self")
			let status = try await postCreate(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(status, .created)
			let announcement = try await fetchByText(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(announcement.author.username, accounts.ttUsername)
		}
	}

	func testTTPostsAsTwitarrTeam() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("tt-as-tt")
			let status = try await postCreate(
				app,
				token: accounts.ttToken,
				text: text,
				postAsUser: PrivilegedUser.TwitarrTeam.rawValue
			)
			XCTAssertEqual(status, .created)
			let announcement = try await fetchByText(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(announcement.author.username, PrivilegedUser.TwitarrTeam.rawValue)
		}
	}

	func testTTPostsAsAdmin() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("tt-as-admin")
			let status = try await postCreate(
				app,
				token: accounts.ttToken,
				text: text,
				postAsUser: PrivilegedUser.admin.rawValue
			)
			XCTAssertEqual(status, .created)
			let announcement = try await fetchByText(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(announcement.author.username, PrivilegedUser.admin.rawValue)
		}
	}

	func testTTCannotPostAsTHO() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let status = try await postCreate(
				app,
				token: accounts.ttToken,
				text: uniqueText("tt-as-tho"),
				postAsUser: PrivilegedUser.THO.rawValue
			)
			XCTAssertEqual(status, .forbidden)
		}
	}

	func testTHOPostsAsTHO() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("tho-as-tho")
			let status = try await postCreate(
				app,
				token: accounts.thoToken,
				text: text,
				postAsUser: PrivilegedUser.THO.rawValue
			)
			XCTAssertEqual(status, .created)
			let announcement = try await fetchByText(app, token: accounts.thoToken, text: text)
			XCTAssertEqual(announcement.author.username, PrivilegedUser.THO.rawValue)
		}
	}

	func testTHOPostsAsAdmin() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("tho-as-admin")
			let status = try await postCreate(
				app,
				token: accounts.thoToken,
				text: text,
				postAsUser: PrivilegedUser.admin.rawValue
			)
			XCTAssertEqual(status, .created)
			let announcement = try await fetchByText(app, token: accounts.thoToken, text: text)
			XCTAssertEqual(announcement.author.username, PrivilegedUser.admin.rawValue)
		}
	}

	func testTHOCannotPostAsTwitarrTeam() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let status = try await postCreate(
				app,
				token: accounts.thoToken,
				text: uniqueText("tho-as-tt"),
				postAsUser: PrivilegedUser.TwitarrTeam.rawValue
			)
			XCTAssertEqual(status, .forbidden)
		}
	}

	func testAdminPostsAsTwitarrTeamAndTHO() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let asTT = uniqueText("admin-as-tt")
			let asTHO = uniqueText("admin-as-tho")
			let ttStatus = try await postCreate(
				app,
				token: accounts.adminToken,
				text: asTT,
				postAsUser: PrivilegedUser.TwitarrTeam.rawValue
			)
			let thoStatus = try await postCreate(
				app,
				token: accounts.adminToken,
				text: asTHO,
				postAsUser: PrivilegedUser.THO.rawValue
			)
			XCTAssertEqual(ttStatus, .created)
			XCTAssertEqual(thoStatus, .created)
			let ttAnnouncement = try await fetchByText(app, token: accounts.adminToken, text: asTT)
			let thoAnnouncement = try await fetchByText(app, token: accounts.adminToken, text: asTHO)
			XCTAssertEqual(ttAnnouncement.author.username, PrivilegedUser.TwitarrTeam.rawValue)
			XCTAssertEqual(thoAnnouncement.author.username, PrivilegedUser.THO.rawValue)
		}
	}

	func testUnknownPostAsIsForbidden() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let modStatus = try await postCreate(
				app,
				token: accounts.ttToken,
				text: uniqueText("unknown-mod"),
				postAsUser: PrivilegedUser.moderator.rawValue
			)
			let unknownStatus = try await postCreate(
				app,
				token: accounts.ttToken,
				text: uniqueText("unknown-user"),
				postAsUser: "someuser"
			)
			XCTAssertEqual(modStatus, .forbidden)
			XCTAssertEqual(unknownStatus, .forbidden)
		}
	}

	func testEditKeepsAuthorWhenPostAsAbsent() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("edit-keep")
			let createStatus = try await postCreate(
				app,
				token: accounts.ttToken,
				text: text,
				postAsUser: PrivilegedUser.TwitarrTeam.rawValue
			)
			XCTAssertEqual(createStatus, .created)
			let created = try await fetchByText(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(created.author.username, PrivilegedUser.TwitarrTeam.rawValue)
			let editedText = text + "-edited"
			let (status, edited) = try await postEdit(
				app,
				token: accounts.ttToken,
				id: created.id,
				text: editedText
			)
			XCTAssertEqual(status, .ok)
			XCTAssertEqual(try XCTUnwrap(edited).author.username, PrivilegedUser.TwitarrTeam.rawValue)
		}
	}

	func testEditChangesAuthorWhenPostAsGiven() async throws {
		try await withApp { app in
			let accounts = try await makeAccounts(app)
			let text = uniqueText("edit-change")
			let createStatus = try await postCreate(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(createStatus, .created)
			let created = try await fetchByText(app, token: accounts.ttToken, text: text)
			XCTAssertEqual(created.author.username, accounts.ttUsername)
			let editedText = text + "-edited"
			let (status, edited) = try await postEdit(
				app,
				token: accounts.ttToken,
				id: created.id,
				text: editedText,
				postAsUser: PrivilegedUser.admin.rawValue
			)
			XCTAssertEqual(status, .ok)
			XCTAssertEqual(try XCTUnwrap(edited).author.username, PrivilegedUser.admin.rawValue)
		}
	}
}
