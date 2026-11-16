import Fluent
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

	/// Sends a reaction through the JSON API and returns the response status.
	private static func reactStatus(_ app: Application, fixture: Fixture, emoji: String) async throws -> HTTPStatus {
		var status = HTTPStatus.ok
		try await app.test(
			.POST,
			"/api/v3/forum/post/\(try fixture.post.requireID())/react",
			headers: HTTPHeaders([("Authorization", "Bearer \(fixture.token)")]),
			beforeRequest: { req async throws in
				req.headers.contentType = .json
				req.body = ByteBuffer(data: try JSONEncoder().encode(PostReactionData(reaction: emoji)))
			},
			afterResponse: { res async throws in status = res.status }
		)
		return status
	}

	/// Free text is refused, and a user is held to ten distinct reactions on one post.
	func testReactRejectsTextAndCapsDistinctReactionsPerUser() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			let postID = try fixture.post.requireID()
			let rejected = try await Self.reactStatus(app, fixture: fixture, emoji: "lol")
			XCTAssertEqual(rejected, .badRequest)

			let ten = ["👍", "❤️", "😆", "🎉", "👀", "✅", "🔥", "🙏", ":arr:", ":mbta:"]
			for emoji in ten {
				let status = try await Self.reactStatus(app, fixture: fixture, emoji: emoji)
				XCTAssertEqual(status, .ok, emoji)
			}
			// The eleventh distinct reaction is refused...
			let eleventh = try await Self.reactStatus(app, fixture: fixture, emoji: "🚀")
			XCTAssertEqual(eleventh, .badRequest)
			// ...but repeating one the user already has is still the idempotent no-op it always was.
			let repeated = try await Self.reactStatus(app, fixture: fixture, emoji: "👍")
			XCTAssertEqual(repeated, .ok)
			let stored = try await ForumPostReaction.query(on: app.db).filter(\.$post.$id == postID).count()
			XCTAssertEqual(stored, 10)

			// Removing one makes room again.
			try await app.test(.POST, "/api/v3/forum/post/\(postID)/unreact", headers: bearer(fixture.token),
				beforeRequest: { req async throws in
					req.headers.contentType = .json
					req.body = ByteBuffer(data: try JSONEncoder().encode(PostReactionData(reaction: "👍")))
				}, afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) })
			let afterRemoval = try await Self.reactStatus(app, fixture: fixture, emoji: "🚀")
			XCTAssertEqual(afterRemoval, .ok)
		}
	}

	/// Concurrent writes cannot exceed the cap or turn an idempotent repeat into a unique-key error.
	func testConcurrentReactionWrites() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			for emoji in ["👍", "❤️", "😆", "🎉", "👀", "✅", "🔥", "🙏", ":arr:"] {
				let status = try await Self.reactStatus(app, fixture: fixture, emoji: emoji)
				XCTAssertEqual(status, .ok)
			}
			async let first = Self.reactStatus(app, fixture: fixture, emoji: "🚀")
			async let second = Self.reactStatus(app, fixture: fixture, emoji: "🌊")
			let statuses = try await [first, second]
			XCTAssertEqual(statuses.filter { $0 == .ok }.count, 1)
			XCTAssertEqual(statuses.filter { $0 == .badRequest }.count, 1)
			let count = try await ForumPostReaction.query(on: app.db).filter(\.$post.$id == fixture.post.requireID()).count()
			XCTAssertEqual(count, 10)
			async let repeatOne = Self.reactStatus(app, fixture: fixture, emoji: "👍")
			async let repeatTwo = Self.reactStatus(app, fixture: fixture, emoji: "👍")
			let repeated = try await [repeatOne, repeatTwo]
			XCTAssertTrue(repeated.allSatisfy { $0 == .ok })
		}
	}

	/// A chip keeps its position after its first contributor leaves; presentation variants remain distinct.
	func testExactReactionRetainsGroupPosition() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			var tokens = [fixture.token]
			for _ in 0..<2 {
				let user = User(username: "reaction-order-\(UUID())", password: try Bcrypt.hash("password1"),
					recoveryKey: try Bcrypt.hash("recovery key"), accessLevel: .verified)
				try await user.save(on: app.db)
				let token = try Token.generate(for: user)
				try await token.save(on: app.db)
				tokens.append(token.token)
			}
			try await app.initializeUserCache(app)
			let postID = try fixture.post.requireID()
			/// Sends one mutation and checks the complete resulting chip order.
			func mutate(_ user: Int, _ action: String, _ emoji: String, expected: [String]) async throws {
				try await app.test(.POST, "/api/v3/forum/post/\(postID)/\(action)", headers: bearer(tokens[user]),
					beforeRequest: { req async throws in
						req.headers.contentType = .json
						req.body = ByteBuffer(data: try JSONEncoder().encode(PostReactionData(reaction: emoji)))
					}, afterResponse: { res async throws in
						XCTAssertEqual(res.status, .ok)
						XCTAssertEqual(try res.content.decode(PostData.self).reactions.map(\.reaction), expected)
					})
			}
			try await mutate(0, "react", "👍", expected: ["👍"])
			try await mutate(1, "react", "❤️", expected: ["👍", "❤️"])
			try await mutate(2, "react", "👍", expected: ["👍", "❤️"])
			try await mutate(0, "unreact", "👍", expected: ["👍", "❤️"])
			try await mutate(1, "react", "👍\u{FE0F}", expected: ["👍", "❤️", "👍\u{FE0F}"])
			try await mutate(1, "react", "👍", expected: ["👍", "❤️", "👍\u{FE0F}"])
			let stored = try await ForumPostReaction.query(on: app.db).filter(\.$post.$id == postID).all()
			XCTAssertEqual(stored.count, 4)
			XCTAssertEqual(Set(stored.filter { $0.emoji == "👍" }.map(\.groupOrder)).count, 1)
		}
	}

	/// Private-event and Seamail reactions must work while LFG is disabled, but respect their own feature gates.
	func testChatReactionFeatureGates() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			let previous = Settings.shared.disabledFeatures
			defer { Settings.shared.disabledFeatures = previous }
			for (type, feature) in [(FezType.privateEvent, SwiftarrFeature.personalevents), (.closed, .seamail), (.activity, .friendlyfez)] {
				let fez = FriendlyFez(owner: fixture.post.$author.id, fezType: type, title: "Reaction feature fixture", location: nil, startTime: nil, endTime: nil)
				fez.participantArray = [try fixture.reactor.requireID()]
				try await fez.save(on: app.db)
				let post = try FezPost(fez: fez, authorID: fixture.post.$author.id, text: "reaction feature fixture", image: nil)
				try await post.save(on: app.db)
				let path = "/api/v3/fez/post/\(try post.requireID())/react"
				Settings.shared.disabledFeatures = DisabledFeaturesGroup(value: [.all: [.friendlyfez]])
				try await app.test(.POST, path, headers: bearer(fixture.token), beforeRequest: { req async throws in
					req.headers.contentType = .json
					req.body = ByteBuffer(string: "{\"reaction\":\"👍\"}")
				}, afterResponse: { res async throws in
					XCTAssertEqual(res.status, type == .activity ? .unavailableForLegalReasons : .ok)
				})
				Settings.shared.disabledFeatures = DisabledFeaturesGroup(value: [.all: [feature]])
				try await app.test(.POST, path, headers: bearer(fixture.token), beforeRequest: { req async throws in
					req.headers.contentType = .json
					req.body = ByteBuffer(string: "{\"reaction\":\"👍\"}")
				}, afterResponse: { res async throws in
					XCTAssertEqual(res.status, .unavailableForLegalReasons)
				})
			}
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
