import Fluent
import XCTVapor

@testable import swiftarr

// Tests `ForumData.readCount`: the number of posts the user had read in the forum *before* the request, using the
// same definition as `ForumListData.readCount`. `readCount - paginator.start` is the index of the first unread post.
final class ForumReadCountTests: XCTestCase, SwiftarrBaseTest {

	private struct Fixture {
		let reader: User
		let readerToken: String
		let authors: [User]
		let category: swiftarr.Category
		let forum: Forum
		/// In creation order, so `posts[i].id` increases with `i`.
		let posts: [ForumPost]
	}

	private func makeUser(_ app: Application, _ prefix: String) async throws -> User {
		let user = User(
			username: "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: .verified
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

	/// Creates a reader, `authorCount` other users, a category, and a forum with `postCount` posts. Post `i` is written by
	/// `authors[i % authorCount]`. The reader has no `ForumReaders` pivot yet.
	private func makeFixture(_ app: Application, postCount: Int, authorCount: Int = 1) async throws -> Fixture {
		let reader = try await makeUser(app, "reader")
		var authors: [User] = []
		for index in 0..<authorCount {
			authors.append(try await makeUser(app, "author\(index)"))
		}
		let category = swiftarr.Category(title: "Read count \(UUID().uuidString)", purpose: "test fixture")
		try await category.save(on: app.db)
		let forum = try Forum(title: "Read count thread", category: category, creatorID: authors[0].requireID())
		try await forum.save(on: app.db)
		var posts: [ForumPost] = []
		for index in 0..<postCount {
			let post = try ForumPost(
				forum: forum,
				authorID: authors[index % authorCount].requireID(),
				text: "post \(index)"
			)
			try await post.save(on: app.db)
			posts.append(post)
		}
		forum.lastPostID = try posts.last?.requireID() ?? 0
		try await forum.save(on: app.db)
		let readerToken = try await makeToken(app, for: reader)
		// The cache is built from Redis, which is not reachable until the app has booted.
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return Fixture(
			reader: reader,
			readerToken: readerToken,
			authors: authors,
			category: category,
			forum: forum,
			posts: posts
		)
	}

	/// Sets the reader's `lastPostReadID` for the fixture's forum, creating or updating the pivot. `nil` clears the marker.
	private func setLastRead(_ app: Application, _ fixture: Fixture, to post: ForumPost?) async throws {
		let userID = try fixture.reader.requireID()
		let forumID = try fixture.forum.requireID()
		let existing = try await ForumReaders.query(on: app.db)
			.filter(\.$user.$id == userID)
			.filter(\.$forum.$id == forumID)
			.first()
		let pivot = try existing ?? ForumReaders(userID, fixture.forum)
		pivot.lastPostReadID = post?.id
		try await pivot.save(on: app.db)
	}

	private func lastRead(_ app: Application, _ fixture: Fixture) async throws -> Int? {
		let userID = try fixture.reader.requireID()
		let forumID = try fixture.forum.requireID()
		let pivot = try await ForumReaders.query(on: app.db)
			.filter(\.$user.$id == userID)
			.filter(\.$forum.$id == forumID)
			.first()
		return pivot?.lastPostReadID
	}

	private func send(_ app: Application, _ method: HTTPMethod, _ path: String, token: String) async throws -> XCTHTTPResponse {
		try await app.performTest(
			request: XCTHTTPRequest(
				method: method,
				url: URI(string: path),
				headers: bearer(token),
				body: ByteBuffer()
			)
		)
	}

	private func getForum(_ app: Application, _ fixture: Fixture, query: String = "") async throws -> ForumData {
		try await getForum(app, "/api/v3/forum/\(fixture.forum.requireID())\(query)", token: fixture.readerToken)
	}

	private func getForum(_ app: Application, _ path: String, token: String) async throws -> ForumData {
		let response = try await send(app, .GET, path, token: token)
		XCTAssertEqual(response.status, .ok, "GET \(path)")
		return try response.content.decode(ForumData.self)
	}

	/// The `ForumListData` the category's forum list reports for the fixture's forum.
	private func listEntry(_ app: Application, _ fixture: Fixture) async throws -> ForumListData {
		let path = "/api/v3/forum/categories/\(try fixture.category.requireID())"
		let response = try await send(app, .GET, path, token: fixture.readerToken)
		XCTAssertEqual(response.status, .ok)
		let category = try response.content.decode(CategoryData.self)
		let forumID = try fixture.forum.requireID()
		return try XCTUnwrap(category.forumThreads?.first { $0.forumID == forumID })
	}

	private func postWithoutBody(_ app: Application, _ path: String, token: String, expecting: [HTTPStatus]) async throws {
		let response = try await send(app, .POST, path, token: token)
		XCTAssertTrue(expecting.contains(response.status), "POST \(path) returned \(response.status)")
	}

	// MARK: Tests

	// The headline contract: the first GET reports the position from before the request, and the request advances the marker.
	func testReadCountIsValueBeforeRequestThenAdvances() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 10)
			try await setLastRead(app, fixture, to: fixture.posts[3])  // 4 posts read: indexes 0...3

			let first = try await getForum(app, fixture)
			XCTAssertEqual(first.readCount, 4, "readCount counts the last-read post itself")
			XCTAssertEqual(first.paginator.total, 10)
			XCTAssertEqual(first.paginator.start, 0)
			XCTAssertEqual(first.posts[first.readCount - first.paginator.start].postID, fixture.posts[4].id)
			let advanced = try await lastRead(app, fixture)
			XCTAssertEqual(advanced, fixture.posts[9].id)

			let second = try await getForum(app, fixture)
			XCTAssertEqual(second.readCount, 10, "the second request reports the marker the first one advanced to")
		}
	}

	// With a small page size the first unread post is on a later page than the one with the last-read post.
	func testFirstUnreadIndexIsReadCountMinusStart() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 10)
			try await setLastRead(app, fixture, to: fixture.posts[3])

			let first = try await getForum(app, fixture, query: "?limit=3")
			// The default start is where the last-read post is: posts[3] sits at index 3, so the page is indexes 3...5.
			XCTAssertEqual(first.paginator.start, 3)
			XCTAssertEqual(first.readCount, 4)
			XCTAssertEqual(first.readCount - first.paginator.start, 1)
			XCTAssertEqual(first.posts[1].postID, fixture.posts[4].id, "the first unread post")

			// The marker advanced to the end of that page (posts[5]), so 6 posts are now read and the first unread one
			// (index 6) is past the end of the page at indexes 3...5.
			let second = try await getForum(app, fixture, query: "?limit=3")
			XCTAssertEqual(second.readCount, 6)
			XCTAssertEqual(second.paginator.start, 3)
			XCTAssertEqual(second.readCount - second.paginator.start, second.posts.count)
		}
	}

	func testNeverReadThreadReturnsZero() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 5)
			let data = try await getForum(app, fixture)
			XCTAssertEqual(data.readCount, 0)
			XCTAssertEqual(data.paginator.total, 5)
		}
	}

	// A pivot can exist without a read marker (favoriting a forum creates one).
	func testPivotWithoutReadMarkerReturnsZero() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 5)
			try await setLastRead(app, fixture, to: nil)
			let listed = try await listEntry(app, fixture)
			XCTAssertEqual(listed.readCount, 0)
			let data = try await getForum(app, fixture)
			XCTAssertEqual(data.readCount, 0)
		}
	}

	func testFullyReadThreadReturnsTotal() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 6)
			try await setLastRead(app, fixture, to: fixture.posts[5])
			let data = try await getForum(app, fixture)
			XCTAssertEqual(data.readCount, data.paginator.total)
			XCTAssertEqual(data.readCount, 6)
		}
	}

	// `ForumData.readCount` and `ForumListData.readCount` must agree for the same user, thread, and moment.
	func testReadCountMatchesForumListData() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 8)
			for readThrough in [nil, 0, 3, 7] as [Int?] {
				try await setLastRead(app, fixture, to: readThrough.map { fixture.posts[$0] })
				let listed = try await listEntry(app, fixture)
				let data = try await getForum(app, fixture)
				XCTAssertEqual(data.readCount, listed.readCount, "read through index \(String(describing: readThrough))")
				XCTAssertEqual(data.readCount, (readThrough ?? -1) + 1)
			}
		}
	}

	// Blocked and muted authors and deleted posts are not counted, and they're left out the same way in both places.
	func testBlockedMutedAndDeletedPostsAreExcluded() async throws {
		try await withApp { app in
			// Authors cycle A, B, C: indexes 0,3,6 are A's, 1,4,7 are B's, 2,5,8 are C's.
			let fixture = try await makeFixture(app, postCount: 9, authorCount: 3)
			let blocked = fixture.authors[1]
			let muted = fixture.authors[2]
			try await setLastRead(app, fixture, to: fixture.posts[7])  // indexes 0...7 are at or before the marker

			// Nothing hidden yet: all 8 posts at or before the marker count.
			var listed = try await listEntry(app, fixture)
			var data = try await getForum(app, fixture)
			XCTAssertEqual(listed.readCount, 8)
			XCTAssertEqual(data.readCount, 8)
			try await setLastRead(app, fixture, to: fixture.posts[7])

			// Delete a post by the visible author (index 3).
			try await fixture.posts[3].delete(on: app.db)
			listed = try await listEntry(app, fixture)
			data = try await getForum(app, fixture)
			XCTAssertEqual(listed.readCount, 7, "a soft-deleted post is not counted")
			XCTAssertEqual(data.readCount, 7)
			try await setLastRead(app, fixture, to: fixture.posts[7])

			// Block B (indexes 1, 4, 7).
			try await postWithoutBody(
				app,
				"/api/v3/users/\(try blocked.requireID())/block",
				token: fixture.readerToken,
				expecting: [.created, .ok]
			)
			listed = try await listEntry(app, fixture)
			data = try await getForum(app, fixture)
			XCTAssertEqual(listed.readCount, 4, "indexes 0, 2, 5, 6 remain")
			XCTAssertEqual(data.readCount, 4)
			XCTAssertEqual(data.paginator.total, listed.postCount)
			try await setLastRead(app, fixture, to: fixture.posts[7])

			// Mute C (indexes 2, 5, 8).
			try await postWithoutBody(
				app,
				"/api/v3/users/\(try muted.requireID())/mute",
				token: fixture.readerToken,
				expecting: [.created, .ok]
			)
			listed = try await listEntry(app, fixture)
			data = try await getForum(app, fixture)
			XCTAssertEqual(listed.readCount, 2, "only A's indexes 0 and 6 remain")
			XCTAssertEqual(data.readCount, 2)
			XCTAssertEqual(data.paginator.total, listed.postCount)
			XCTAssertEqual(data.posts.count, 2, "only A's undeleted posts, indexes 0 and 6, are returned")
		}
	}

	// `start` and `startPost` choose where the page begins, but readCount still reports the position from before the request.
	func testExplicitStartPathsReturnReadCountFromBeforeTheRequest() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 10)
			let k = 4
			let forumID = try fixture.forum.requireID()

			// start=6 returns the tail of the thread, which advances the marker; readCount must still be k.
			try await setLastRead(app, fixture, to: fixture.posts[k - 1])
			var data = try await getForum(app, fixture, query: "?start=6&limit=4")
			XCTAssertEqual(data.readCount, k)
			XCTAssertEqual(data.paginator.start, 6)
			var advanced = try await lastRead(app, fixture)
			XCTAssertEqual(advanced, fixture.posts[9].id)

			// start=0 with a small page doesn't pass the marker, so it isn't advanced.
			try await setLastRead(app, fixture, to: fixture.posts[k - 1])
			data = try await getForum(app, fixture, query: "?start=0&limit=2")
			XCTAssertEqual(data.readCount, k)
			advanced = try await lastRead(app, fixture)
			XCTAssertEqual(advanced, fixture.posts[k - 1].id)

			// startPost
			try await setLastRead(app, fixture, to: fixture.posts[k - 1])
			let startPostID = try fixture.posts[8].requireID()
			data = try await getForum(app, fixture, query: "?startPost=\(startPostID)&limit=3")
			XCTAssertEqual(data.readCount, k)
			XCTAssertEqual(data.paginator.start, 8, "startPost isn't rounded down to a page boundary")
			advanced = try await lastRead(app, fixture)
			XCTAssertEqual(advanced, fixture.posts[9].id)

			// GET /forum/post/:postID/forum
			try await setLastRead(app, fixture, to: fixture.posts[k - 1])
			data = try await getForum(
				app,
				"/api/v3/forum/post/\(startPostID)/forum?limit=3",
				token: fixture.readerToken
			)
			XCTAssertEqual(data.forumID, forumID)
			XCTAssertEqual(data.readCount, k)
		}
	}

	// A forum the creator has just made has not been read by anyone.
	func testCreatedForumReportsZeroReadCount() async throws {
		try await withApp { app in
			let fixture = try await makeFixture(app, postCount: 1)
			let create = ForumCreateData(
				title: "Brand new thread",
				firstPost: PostContentData(text: "first post", images: [])
			)
			try await app.test(
				.POST,
				"/api/v3/forum/categories/\(try fixture.category.requireID())/create",
				headers: bearer(fixture.readerToken),
				beforeRequest: { req async throws in
					try req.content.encode(create)
				},
				afterResponse: { res async throws in
					XCTAssertTrue(res.status == .ok || res.status == .created, "\(res.status)")
					let data = try res.content.decode(ForumData.self)
					XCTAssertEqual(data.readCount, 0)
					XCTAssertEqual(data.paginator.total, 1)
				}
			)
		}
	}
}
