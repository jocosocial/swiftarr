import XCTVapor

@testable import swiftarr

/// Covers multi-reaction search results and legacy LikeType deletion compatibility.
final class ForumReactionCompatibilityTests: XCTestCase, SwiftarrBaseTest {

	private struct Fixture {
		let reactor: User
		let token: String
		let post: ForumPost
	}

	/// Creates an author, reactor, forum post, token, and user-cache entry for API requests.
	private func makeFixture(_ app: Application, suffix: String) async throws -> Fixture {
		let author = User(
			username: "reaction-author-\(suffix)",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: .verified
		)
		try await author.save(on: app.db)
		let reactor = User(
			username: "reaction-user-\(suffix)",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: .verified
		)
		try await reactor.save(on: app.db)

		let category = Category(title: "Reaction Fixture \(suffix)", purpose: "test fixture")
		try await category.save(on: app.db)
		let forum = try Forum(title: "Reaction Fixture \(suffix)", category: category, creatorID: author.requireID())
		try await forum.save(on: app.db)
		let post = try ForumPost(forum: forum, authorID: author.requireID(), text: "reaction fixture")
		try await post.save(on: app.db)

		let token = try Token.generate(for: reactor)
		try await token.save(on: app.db)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return Fixture(reactor: reactor, token: token.token, post: post)
	}

	/// Returns bearer authorization headers for a fixture user.
	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	/// Adds a reaction through the JSON API and asserts that the endpoint accepts it.
	private func addReaction(_ app: Application, fixture: Fixture, emoji: String) async throws {
		try await app.test(
			.POST,
			"/api/v3/forum/post/\(try fixture.post.requireID())/react",
			headers: bearer(fixture.token),
			beforeRequest: { req async throws in
				req.headers.contentType = .json
				req.body = ByteBuffer(string: "{\"reaction\":\"\(emoji)\"}")
			},
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
			}
		)
	}

	/// Verifies one post remains one paginated result even when the user added several emoji.
	func testOwnReactsReturnsEachPostOnceForMultipleEmojis() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			try await addReaction(app, fixture: fixture, emoji: "🎉")
			try await addReaction(app, fixture: fixture, emoji: "👀")

			try await app.test(
				.GET,
				"/api/v3/forum/post/search?ownreacts=true&limit=50",
				headers: bearer(fixture.token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let search = try res.content.decode(PostSearchData.self)
					XCTAssertEqual(search.paginator.total, 1)
					XCTAssertEqual(search.posts.map(\.postID), [try fixture.post.requireID()])
				}
			)
		}
	}

	/// Verifies each legacy DELETE endpoint removes only the matching LikeType emoji.
	func testLegacyDeleteRoutesRemoveOnlyTheirOwnEmoji() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			let postID = try fixture.post.requireID()
			for emoji in ["👍", "😆", "❤️"] {
				let reaction = try ForumPostReaction(fixture.reactor.requireID(), fixture.post, emoji: emoji)
				try await reaction.save(on: app.db)
			}

			let cases: [(route: String, remaining: Set<String>)] = [
				("like", ["😆", "❤️"]),
				("laugh", ["❤️"]),
				("love", []),
			]
			for testCase in cases {
				try await app.test(
					.DELETE,
					"/api/v3/forum/post/\(postID)/\(testCase.route)",
					headers: bearer(fixture.token),
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, .ok)
						let postData = try res.content.decode(PostData.self)
						XCTAssertEqual(Set(postData.reactions.map(\.reaction)), testCase.remaining)
					}
				)
			}
		}
	}
}
