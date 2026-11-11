import Testing
import XCTVapor

@testable import swiftarr

// Verifies that a forum category gated on the Community Support role never reaches users who hold neither the role nor moderator access,
// through any API path. Like every role-gated category, moderators and above can read it.
class CommunitySupportForumLeakTests: XCTestCase, SwiftarrBaseTest {

	/// A phrase that appears only in private content, so any response containing it is a leak.
	private let secretToken = "ZEBRAQUARTZ"
	private let secretTag = "csprivatetagxyz"

	private struct Fixture {
		let memberToken: String
		let twitarrTeamToken: String
		let moderatorToken: String
		let verifiedToken: String
		let forumID: UUID
		let postID: Int
		let shutternautForumID: UUID
	}

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

	private func bearer(_ token: String?) -> HTTPHeaders {
		var headers = HTTPHeaders()
		if let token = token {
			headers.bearerAuthorization = BearerAuthorization(token: token)
		}
		return headers
	}

	private func makeFixture(_ app: Application) async throws -> Fixture {
		let suffix = UUID().uuidString.prefix(8).lowercased()
		let member = try await makeUser(
			app,
			username: "csmember-\(suffix)",
			accessLevel: .verified,
			role: .communitysupport
		)
		let memberToken = member.token
		let ttToken = try await makeUser(app, username: "tt-\(suffix)", accessLevel: .twitarrteam).token
		let modToken = try await makeUser(app, username: "mod-\(suffix)", accessLevel: .moderator).token
		let verifiedToken = try await makeUser(app, username: "verified-\(suffix)", accessLevel: .verified).token
		_ = try await makeUser(app, username: "shutter-\(suffix)", accessLevel: .verified, role: .shutternaut)

		let csCategory = Category(
			title: "Community Support Test \(suffix)",
			purpose: "test",
			requiredRole: .communitysupport
		)
		try await csCategory.save(on: app.db)
		let forum = try Forum(title: "Private \(secretToken) forum", category: csCategory, creatorID: member.id)
		try await forum.save(on: app.db)
		let post = try ForumPost(
			forum: forum,
			authorID: member.id,
			text: "\(secretToken) body #\(secretTag)",
			images: []
		)
		try await post.save(on: app.db)

		let shutterCategory = Category(title: "Shutter Test \(suffix)", purpose: "test", requiredRole: .shutternaut)
		try await shutterCategory.save(on: app.db)
		let shutterForum = try Forum(title: "Shutter forum", category: shutterCategory, creatorID: member.id)
		try await shutterForum.save(on: app.db)
		try await ForumPost(forum: shutterForum, authorID: member.id, text: "shutter post", images: []).save(on: app.db)

		// The cache is built from Redis, which is not reachable until the app has booted.
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return Fixture(
			memberToken: memberToken,
			twitarrTeamToken: ttToken,
			moderatorToken: modToken,
			verifiedToken: verifiedToken,
			forumID: try forum.requireID(),
			postID: try post.requireID(),
			shutternautForumID: try shutterForum.requireID()
		)
	}

	/// GETs the path as the given token and asserts the status and, optionally, that the body never contains the secret.
	private func expectGET(
		_ app: Application,
		_ path: String,
		token: String?,
		status: HTTPResponseStatus,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		try await app.test(
			.GET,
			path,
			headers: bearer(token),
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, status, "GET \(path)", file: file, line: line)
				if status != .ok {
					return
				}
			}
		)
	}

	/// Asserts that a GET is refused (403 or 404, depending on how far the request gets before the category check).
	private func expectDenied(
		_ app: Application,
		_ path: String,
		token: String?,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		try await app.test(
			.GET,
			path,
			headers: bearer(token),
			afterResponse: { res async throws in
				XCTAssertTrue(
					[.forbidden, .notFound].contains(res.status),
					"GET \(path) was \(res.status)",
					file: file,
					line: line
				)
			}
		)
	}

	/// Asserts that a GET succeeds (or 404s) and its body never mentions private content.
	private func expectNoSecret(
		_ app: Application,
		_ path: String,
		token: String?,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		try await app.test(
			.GET,
			path,
			headers: bearer(token),
			afterResponse: { res async throws in
				// Search responses echo the request's query string back (`PostSearchData.queryString`), which isn't a leak.
				var body = res.body.string
				if let query = path.split(separator: "?", maxSplits: 1).last, path.contains("?") {
					body = body.replacingOccurrences(of: String(query), with: "")
				}
				XCTAssertFalse(body.contains(secretToken), "GET \(path) leaked private content", file: file, line: line)
				XCTAssertFalse(
					body.contains("Community Support Test"),
					"GET \(path) leaked the category",
					file: file,
					line: line
				)
			}
		)
	}

	func testOutsidersCannotReadPrivateForumOrPost() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			for path in [
				"/api/v3/forum/\(f.forumID)", "/api/v3/forum/post/\(f.postID)", "/api/v3/forum/post/\(f.postID)/forum",
				"/api/v3/forum/\(f.forumID)/pinnedposts",
			] {
				try await expectDenied(app, path, token: f.verifiedToken)
			}
			// Other role-gated categories behave the same way: denied without the role, readable by moderators.
			try await expectDenied(app, "/api/v3/forum/\(f.shutternautForumID)", token: f.verifiedToken)
			try await expectGET(app, "/api/v3/forum/\(f.shutternautForumID)", token: f.moderatorToken, status: .ok)
		}
	}

	func testOutsidersCannotFindPrivateContentThroughListsOrSearch() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			for token in [f.verifiedToken] {
				for path in [
					"/api/v3/forum/search?search=\(secretToken)",
					"/api/v3/forum/search?search=\(secretToken)&searchposts=true",
					"/api/v3/forum/post/search?search=\(secretToken)",
					"/api/v3/forum/post/search?hashtag=\(secretTag)",
					"/api/v3/forum/recent",
					"/api/v3/forum/unread",
					"/api/v3/forum/favorites",
					"/api/v3/forum/owner",
					"/api/v3/forum/categories",
				] {
					try await expectNoSecret(app, path, token: token)
				}
			}
		}
	}

	func testRoleHoldersTwitarrTeamAndModeratorsCanRead() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			for token in [f.memberToken, f.twitarrTeamToken, f.moderatorToken] {
				try await expectGET(app, "/api/v3/forum/\(f.forumID)", token: token, status: .ok)
				try await expectGET(app, "/api/v3/forum/post/\(f.postID)", token: token, status: .ok)
			}
		}
	}

	func testPrivateHashtagsNeverEnterAutocomplete() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			try await app.test(
				.POST,
				"/api/v3/forum/\(f.forumID)/create",
				headers: bearer(f.memberToken),
				beforeRequest: { req throws in
					try req.content.encode(PostContentData(text: "another post #\(secretTag)", images: []))
				},
				afterResponse: { res async throws in XCTAssertEqual(res.status, .created) }
			)
			// Unauthenticated: the hashtag endpoint doesn't require login.
			try await app.test(
				.GET,
				"/api/v3/notification/hashtags/\(secretTag.prefix(8))",
				afterResponse: { res async throws in
					XCTAssertFalse(res.body.string.contains(secretTag), "private hashtag leaked into autocomplete")
				}
			)
		}
	}

	// The team's private areas sit together at the top of the category list, above the public categories.
	func testStaffCategoriesListFirst() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			try await app.test(
				.GET,
				"/api/v3/forum/categories",
				headers: bearer(f.twitarrTeamToken),
				afterResponse: { res async throws in
					let titles = try res.content.decode([CategoryData].self).map { $0.title }
					let isStaff = { (title: String) in
						title == "Moderators Only" || title == "Mods Only Dumpster Fire"
							|| title.hasPrefix("Community Support")
					}
					let staffCount = titles.filter(isStaff).count
					XCTAssertGreaterThanOrEqual(staffCount, 3, "\(titles)")
					XCTAssertTrue(
						titles.prefix(staffCount).allSatisfy(isStaff),
						"staff categories should come first: \(titles)"
					)
					// The moderator forums keep their place at the very top of the staff group.
					XCTAssertEqual(Set(titles.prefix(2)), ["Moderators Only", "Mods Only Dumpster Fire"], "\(titles)")
				}
			)
		}
	}
}
