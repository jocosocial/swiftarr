import XCTVapor

@testable import swiftarr

// Tests that editing a forum post through the API keeps the photos the post already has, whatever
// shape the client uses to refer to them.
//
// processImages picks between an entry's image bytes and its filename. An entry carrying an empty
// value for either one is carrying nothing, and has to be read that way: a zero-byte image that
// counts as present shadows the filename beside it, and the post loses a photo it already had (#526).
class ForumPostImagePreservationTests: XCTestCase, SwiftarrBaseTest {

	private let existingImage = "already-on-the-post.jpg"

	private struct Fixture {
		let token: String
		let postID: Int
	}

	private func makeFixture(_ app: Application, suffix: String) async throws -> Fixture {
		let author = User(
			username: "author-\(suffix)",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: .verified
		)
		try await author.save(on: app.db)

		let category = Category(title: "Image Fixture \(suffix)", purpose: "test fixture")
		try await category.save(on: app.db)
		let forum = try Forum(title: "Image Fixture \(suffix)", category: category, creatorID: author.requireID())
		try await forum.save(on: app.db)
		let post = try ForumPost(
			forum: forum,
			authorID: author.requireID(),
			text: "original text",
			images: [existingImage]
		)
		try await post.save(on: app.db)

		let token = try Token.generate(for: author)
		try await token.save(on: app.db)
		// The cache is built from Redis, which is not reachable until the app has booted.
		try await app.asyncBoot()
		try await app.initializeUserCache(app)

		return Fixture(token: token.token, postID: try post.requireID())
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	// Sends a raw body so a test can express an empty image or filename. Encoding an ImageUploadData
	// would normalize those away, and they are the whole point here.
	private func editPost(
		_ app: Application,
		_ fixture: Fixture,
		imagesJSON: String,
		verify: @escaping (PostData) throws -> Void
	) async throws {
		let body = """
			{"text":"edited text","images":\(imagesJSON),"postAsModerator":false,"postAsTwitarrTeam":false}
			"""
		try await app.test(
			.POST,
			"/api/v3/forum/post/\(fixture.postID)/update",
			headers: bearer(fixture.token),
			beforeRequest: { req async throws in
				req.headers.contentType = .json
				req.body = ByteBuffer(string: body)
			},
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
				try verify(try res.content.decode(PostData.self))
			}
		)
	}

	private func suffix() -> String { UUID().uuidString.prefix(8).lowercased() }

	// A client that fills in every field of ImageUploadData sends an empty image alongside the
	// filename of a photo the post already has. The empty image must not discard that photo.
	func testEditKeepsAPhotoSentWithAnEmptyImage() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: suffix())
			try await editPost(app, fixture, imagesJSON: #"[{"filename":"\#(existingImage)","image":""}]"#) { post in
				XCTAssertEqual(post.images, [self.existingImage], "an empty image must not discard the filename beside it")
			}
		}
	}

	// The shape current clients send. Guards the fix against regressing the normal path.
	func testEditKeepsAPhotoSentAsFilenameOnly() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: suffix())
			try await editPost(app, fixture, imagesJSON: #"[{"filename":"\#(existingImage)"}]"#) { post in
				XCTAssertEqual(post.images, [self.existingImage])
			}
		}
	}

	// Empty on both sides means the slot holds nothing, so it must not be stored as an image whose
	// filename is the empty string.
	func testEditDropsASlotEmptyOnBothSides() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: suffix())
			try await editPost(app, fixture, imagesJSON: #"[{"filename":"","image":""}]"#) { post in
				XCTAssertEqual(post.images ?? [], [], "an entry with nothing in it must not be stored")
			}
		}
	}

	// Removing a photo has to keep working: the client sends no entries at all.
	func testEditWithNoImagesRemovesThePhoto() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, suffix: suffix())
			try await editPost(app, fixture, imagesJSON: "[]") { post in
				XCTAssertEqual(post.images ?? [], [])
			}
		}
	}
}
