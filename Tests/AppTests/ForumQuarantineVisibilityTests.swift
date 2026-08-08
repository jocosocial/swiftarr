import Testing
import XCTVapor

@testable import swiftarr

// Tests who sees a quarantined post's real content on `GET /api/v3/forum/post/:postID`.
//
// Moderators must receive the real text and images. The edit form is populated from this
// response, so hiding them from a moderator means saving an edit wipes the post's images (#526).
class ForumQuarantineVisibilityTests: XCTestCase, SwiftarrBaseTest {

	private let images = ["quarantined-one.jpg", "quarantined-two.jpg"]

	private struct Fixture {
		let moderatorToken: String
		let verifiedToken: String
		let postID: Int
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

	// Builds a quarantined post with images, owned by a plain verified user, plus tokens for a
	// moderator and a non-moderator. Rebuilds the user cache so token auth can resolve both.
	private func makeFixture(_ app: Application, suffix: String) async throws -> Fixture {
		let moderator = try await makeUser(app, username: "mod-\(suffix)", accessLevel: .moderator)
		let author = try await makeUser(app, username: "author-\(suffix)", accessLevel: .verified)

		let category = Category(title: "Quarantine Fixture \(suffix)", purpose: "test fixture")
		try await category.save(on: app.db)
		let forum = try Forum(title: "Quarantine Fixture \(suffix)", category: category, creatorID: author.requireID())
		try await forum.save(on: app.db)

		let post = try ForumPost(forum: forum, authorID: author.requireID(), text: "hidden text", images: images)
		post.moderationStatus = .quarantined
		try await post.save(on: app.db)

		let moderatorToken = try await makeToken(app, for: moderator)
		let verifiedToken = try await makeToken(app, for: author)
		// The cache is built from Redis, which is not reachable until the app has booted.
		try await app.asyncBoot()
		try await app.initializeUserCache(app)

		return Fixture(moderatorToken: moderatorToken, verifiedToken: verifiedToken, postID: try post.requireID())
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	// The regression from #526: a moderator loading a quarantined post for editing got no images,
	// so saving the edit overwrote the post's images with an empty set.
	func testQuarantinedPost_ModeratorSeesImages() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())

			try await app.test(
				.GET,
				"/api/v3/forum/post/\(fixture.postID)",
				headers: bearer(fixture.moderatorToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let detail = try res.content.decode(PostDetailData.self)
					XCTAssertEqual(detail.images, images, "a moderator must see a quarantined post's images")
					XCTAssertEqual(detail.text, "hidden text", "a moderator must see a quarantined post's text")
				}
			)
		}
	}

	// The same regression on the write path. `POST /api/v3/forum/post/:postID/update` builds its
	// response through `buildPostData`, which does not pass `overrideQuarantine`, so a moderator
	// who saves an edit gets back `images: nil` and the placeholder text — the API reporting that
	// the edit wiped the post it just stored. A client that re-seeds its edit form from this
	// response then writes that emptiness back on the next save, which is #526 exactly.
	func testQuarantinedPost_ModeratorEditResponseShowsWhatWasSaved() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			let edit = PostContentData(text: "edited by a moderator", images: images.map { ImageUploadData($0) })

			try await app.test(
				.POST,
				"/api/v3/forum/post/\(fixture.postID)/update",
				headers: bearer(fixture.moderatorToken),
				beforeRequest: { req async throws in
					try req.content.encode(edit)
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let updated = try res.content.decode(PostData.self)
					XCTAssertEqual(updated.images, images, "the edit response must show the images the moderator just saved")
					XCTAssertEqual(
						updated.text,
						"edited by a moderator",
						"the edit response must show the text the moderator just saved"
					)
				}
			)
		}
	}

	// The bound on the above: quarantine is not loosened for anyone who cannot already edit
	// others' content, so there is no path by which a non-moderator reaches the override.
	func testQuarantinedPost_NonModeratorCannotEdit() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())
			let edit = PostContentData(text: "edited by the author", images: images.map { ImageUploadData($0) })

			try await app.test(
				.POST,
				"/api/v3/forum/post/\(fixture.postID)/update",
				headers: bearer(fixture.verifiedToken),
				beforeRequest: { req async throws in
					try req.content.encode(edit)
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden, "only moderators may edit a quarantined post")
				}
			)
		}
	}

	// The other half of the contract: quarantine still hides content from everyone else.
	func testQuarantinedPost_NonModeratorSeesNoImages() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: UUID().uuidString.prefix(8).lowercased())

			try await app.test(
				.GET,
				"/api/v3/forum/post/\(fixture.postID)",
				headers: bearer(fixture.verifiedToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let detail = try res.content.decode(PostDetailData.self)
					XCTAssertNil(detail.images, "quarantine must still hide images from non-moderators")
					XCTAssertEqual(detail.text, "This post is under moderator review.")
				}
			)
		}
	}
}
