import XCTVapor

@testable import swiftarr

class PrivilegedMailboxTests: XCTestCase, SwiftarrBaseTest {

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

	// A bare Request, for exercising userCache-backed lookups directly without going through a route.
	private func makeRequest(_ app: Application) -> Request {
		Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
	}

	// MARK: - Pure logic (no app required)

	func testAllIsOrderedTwitarrTeamThenModeratorThenCommunitySupport() {
		XCTAssertEqual(PrivilegedMailbox.all.map { $0.user }, [.TwitarrTeam, .moderator, .CommunitySupport])
	}

	func testMatchingQueryParamIsCaseInsensitive() {
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "moderator")?.user, .moderator)
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "MODERATOR")?.user, .moderator)
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "twitarrteam")?.user, .TwitarrTeam)
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "TwitarrTeam")?.user, .TwitarrTeam)
	}

	func testMatchingQueryParamReturnsNilForUnknownValue() {
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: "javascript:alert(1)"))
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: ""))
	}

	// "admin"/"tho" are valid PrivilegedUser query params (service accounts), but neither is a
	// mailbox in `all`--matching must say so, not just happen to return nil for garbage input.
	func testMatchingQueryParamReturnsNilForNonMailboxPrivilegedUser() {
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: "admin"))
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: "tho"))
	}

	func testModeratorRequirementIsSatisfiedByModeratorAndAbove() {
		let requirement = PrivilegedMailboxRequirement.accessLevel(.moderator)
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .moderator, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .twitarrteam, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .tho, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .admin, roles: []))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .verified, roles: []))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .quarantined, roles: []))
	}

	func testTwitarrTeamRequirementIsNotSatisfiedByPlainModerator() {
		let requirement = PrivilegedMailboxRequirement.accessLevel(.twitarrteam)
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .moderator, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .twitarrteam, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .tho, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .admin, roles: []))
	}

	func testRoleRequirementIsSatisfiedOnlyByMatchingRole() {
		let requirement = PrivilegedMailboxRequirement.role(.accountmanager)
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .verified, roles: [.accountmanager]))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .verified, roles: [.huntmanager]))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .admin, roles: []))
	}

	// The pending Community Support mailbox (#517) needs "holders of the role OR (twitarrTeam and
	// above)"--a plain .role or .accessLevel case can't express that union by itself.
	func testRoleOrAccessLevelRequirementIsSatisfiedByEitherSide() {
		let requirement = PrivilegedMailboxRequirement.roleOrAccessLevel(.accountmanager, .twitarrteam)
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .verified, roles: [.accountmanager]), "role alone should satisfy it")
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .twitarrteam, roles: []), "access level alone should satisfy it")
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .admin, roles: [.accountmanager]), "both should still satisfy it")
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .moderator, roles: []), "plain moderator has neither")
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .verified, roles: [.huntmanager]), "an unrelated role doesn't satisfy it")
	}

	func testAccessDeniedReasonsAreUnchanged() {
		XCTAssertEqual(
			PrivilegedMailbox.all.first { $0.user == .moderator }?.accessDeniedReason,
			"Only moderators can access moderator seamail."
		)
		XCTAssertEqual(
			PrivilegedMailbox.all.first { $0.user == .TwitarrTeam }?.accessDeniedReason,
			"Only TwitarrTeam members can access TwitarrTeam seamail."
		)
	}

	func testInboxesMatchExistingMailInboxCases() {
		XCTAssertEqual(PrivilegedMailbox.all.first { $0.user == .moderator }?.inbox, .moderatorSeamail)
		XCTAssertEqual(PrivilegedMailbox.all.first { $0.user == .TwitarrTeam }?.inbox, .twitarrTeamSeamail)
	}

	// MARK: - Against a real app (userCache-backed lookups)

	// `forChat` resolving to the *first* match in `all`'s order is the actual behavior
	// `PrivilegedMailbox.all`'s doc comment promises--a test that only checks array order (as this
	// one used to) doesn't prove `forChat` honors it.
	func testForChatResolvesToTwitarrTeamWhenBothPhantomsAreParticipants() async throws {
		try await withApp { app in
			let req = makeRequest(app)
			guard let ttUser = req.userCache.getUser(username: PrivilegedUser.TwitarrTeam.rawValue),
				let modUser = req.userCache.getUser(username: PrivilegedUser.moderator.rawValue)
			else {
				XCTFail("seed migration should have created the moderator and TwitarrTeam phantom accounts")
				return
			}
			let mailbox = PrivilegedMailbox.forChat(participantArray: [modUser.userID, ttUser.userID], on: req)
			XCTAssertEqual(mailbox?.user, .TwitarrTeam)
		}
	}

	func testForChatReturnsNilWhenNoPhantomIsAParticipant() async throws {
		try await withApp { app in
			let req = makeRequest(app)
			let mailbox = PrivilegedMailbox.forChat(participantArray: [UUID(), UUID()], on: req)
			XCTAssertNil(mailbox)
		}
	}

	func testAllUsersWithRoleReturnsOnlyRoleHolders() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8)
			let holder = try await makeUser(app, username: "rolematch-\(suffix)", accessLevel: .verified)
			try await UserRole(user: holder.requireID(), role: .accountmanager).create(on: app.db)
			let nonHolder = try await makeUser(app, username: "rolemiss-\(suffix)", accessLevel: .verified)
			// Refresh the cache so these just-created users (and the role) are visible to userCache.
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let req = makeRequest(app)
			let members = req.userCache.allUsersWithRole(.accountmanager).map { $0.userID }
			XCTAssertTrue(members.contains(try holder.requireID()))
			XCTAssertFalse(members.contains(try nonHolder.requireID()))
		}
	}

	// `getEffectiveUser(user:req:)`'s 403 path: a user below the mailbox's required access level
	// gets rejected with the mailbox's unchanged reason string, rather than silently falling back
	// to acting as themself.
	func testForuserQueryParamIsForbiddenBelowRequiredAccessLevel() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8)
			let plainUser = try await makeUser(app, username: "plain-\(suffix)", accessLevel: .verified)
			let token = try await makeToken(app, for: plainUser)
			// Token auth resolves against the cache, not the DB directly; refresh it so this
			// just-created user/token pair is visible.
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			try await app.test(
				.GET,
				"/api/v3/fez/owner?foruser=moderator",
				beforeRequest: { (req: inout XCTHTTPRequest) async throws in
					req.headers.bearerAuthorization = BearerAuthorization(token: token)
				},
				afterResponse: { (res: XCTHTTPResponse) async throws in
					XCTAssertEqual(res.status, .forbidden)
					XCTAssertTrue(res.body.string.contains("Only moderators can access moderator seamail."))
				}
			)
		}
	}
}
