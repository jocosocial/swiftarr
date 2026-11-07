import XCTVapor

@testable import swiftarr

// Covers the Community Support additions to the privileged-mailbox table (#517): the mailbox row, the phantom account and its
// reserved name, and who may read the shared mailbox. The general machinery is covered by `PrivilegedMailboxTests`.
class CommunitySupportMailboxTests: XCTestCase, SwiftarrBaseTest {

	private func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel, role: UserRoleType? = nil)
		async throws -> (token: String, id: UUID)
	{
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		if let role = role {
			try await UserRole(user: user.requireID(), role: role).save(on: app.db)
		}
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return (token.token, try user.requireID())
	}

	private func makeRequest(_ app: Application) -> Request {
		Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
	}

	// MARK: - Pure logic

	func testCommunitySupportRowIsLast() {
		XCTAssertEqual(PrivilegedMailbox.all.map { $0.user }, [.TwitarrTeam, .moderator, .CommunitySupport])
	}

	func testCommunitySupportRequirementAdmitsRoleHoldersAndTwitarrTeamButNotModerators() {
		let mailbox = PrivilegedMailbox.matching(queryParam: "CommunitySupport")
		XCTAssertEqual(mailbox?.inbox, .communitySupportSeamail)
		XCTAssertEqual(mailbox?.isSatisfied(accessLevel: .verified, roles: [.communitysupport]), true)
		XCTAssertEqual(mailbox?.isSatisfied(accessLevel: .twitarrteam, roles: []), true)
		XCTAssertEqual(mailbox?.isSatisfied(accessLevel: .tho, roles: []), true)
		XCTAssertEqual(mailbox?.isSatisfied(accessLevel: .moderator, roles: []), false)
		XCTAssertEqual(mailbox?.isSatisfied(accessLevel: .verified, roles: []), false)
	}

	func testReservedUsernameIsCaseInsensitive() {
		for name in ["CommunitySupport", "communitysupport", "COMMUNITYSUPPORT", "cOmMuNiTySuPpOrT"] {
			XCTAssertTrue(PrivilegedUser.isReservedUsername(name), name)
		}
		XCTAssertFalse(PrivilegedUser.isReservedUsername("communitysupporter"))
		XCTAssertFalse(PrivilegedUser.isReservedUsername("community-support"))
	}

	func testUsernameValidationRejectsReservedName() throws {
		let decoder = ValidatingJSONDecoder()
		for name in ["CommunitySupport", "communitysupport"] {
			let data = #"{"username":"\#(name)"}"#.data(using: .utf8)!
			let errors = try decoder.validate(UserUsernameData.self, from: data)?.validationFailures.map { $0.errorString } ?? []
			XCTAssertTrue(errors.contains("username is reserved"), "\(name): \(errors)")
		}
		let ok = try decoder.validate(UserUsernameData.self, from: #"{"username":"communitysupporter"}"#.data(using: .utf8)!)
		XCTAssertNil(ok)
	}

	// MARK: - Against a real app

	func testPhantomAccountAndCategoryAreSeeded() async throws {
		try await withApp { app in
			let req = makeRequest(app)
			XCTAssertNotNil(req.userCache.getUser(username: PrivilegedUser.CommunitySupport.rawValue))
			let category = try await Category.query(on: app.db).all().first { $0.title == AddCommunitySupportCategory.title }
			XCTAssertEqual(category?.requiredRole, .communitysupport)
		}
	}

	func testForChatPrefersModeratorOverCommunitySupport() async throws {
		try await withApp { app in
			let req = makeRequest(app)
			guard let modUser = req.userCache.getUser(username: PrivilegedUser.moderator.rawValue),
				let csUser = req.userCache.getUser(username: PrivilegedUser.CommunitySupport.rawValue)
			else {
				XCTFail("seed migrations should have created the moderator and CommunitySupport phantom accounts")
				return
			}
			let mailbox = PrivilegedMailbox.forChat(participantArray: [csUser.userID, modUser.userID], on: req)
			XCTAssertEqual(mailbox?.user, .moderator)
			XCTAssertEqual(PrivilegedMailbox.forChat(participantArray: [csUser.userID], on: req)?.user, .CommunitySupport)
		}
	}

	func testRosterIsRoleHoldersAndTwitarrTeamOnly() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8)
			let member = try await makeUser(app, username: "csm-\(suffix)", accessLevel: .verified, role: .communitysupport)
			let moderator = try await makeUser(app, username: "csmod-\(suffix)", accessLevel: .moderator)
			let tt = try await makeUser(app, username: "cstt-\(suffix)", accessLevel: .twitarrteam)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			let roster = PrivilegedMailbox.matching(queryParam: "communitysupport")!.members(on: makeRequest(app)).map { $0.userID }
			XCTAssertTrue(roster.contains(member.id))
			XCTAssertTrue(roster.contains(tt.id))
			XCTAssertFalse(roster.contains(moderator.id), "plain moderators must not be in the Community Support roster")
		}
	}

	func testForuserCommunitySupportAccess() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8)
			let member = try await makeUser(app, username: "csm-\(suffix)", accessLevel: .verified, role: .communitysupport)
			let moderator = try await makeUser(app, username: "csmod-\(suffix)", accessLevel: .moderator)
			let plain = try await makeUser(app, username: "csplain-\(suffix)", accessLevel: .verified)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			for (token, expected) in [(member.token, HTTPResponseStatus.ok), (moderator.token, .forbidden), (plain.token, .forbidden)] {
				try await app.test(
					.GET,
					"/api/v3/fez/owner?foruser=communitysupport",
					beforeRequest: { (req: inout XCTHTTPRequest) async throws in
						req.headers.bearerAuthorization = BearerAuthorization(token: token)
					},
					afterResponse: { (res: XCTHTTPResponse) async throws in XCTAssertEqual(res.status, expected) }
				)
			}
		}
	}
}
