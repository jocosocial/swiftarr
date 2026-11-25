import Fluent
import XCTVapor

@testable import swiftarr

// Tests that handlers which write several rows (and sometimes image files) either complete or leave nothing behind.
class AtomicHandlerTests: XCTestCase, SwiftarrBaseTest {

	private func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel = .verified) async throws -> User {
		// Passing tests don't clean up after themselves, so keep usernames unique across runs.
		let user = User(
			username: "\(username)\(UUID().uuidString.prefix(6).lowercased())",
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

	private func fixtureImageData() throws -> Data {
		let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/test_base.png")
		return try Data(contentsOf: url)
	}

	/// Points image storage at a fresh temporary directory for the duration of `body`.
	private func withTemporaryImageRoot(_ body: (URL) async throws -> Void) async throws {
		let original = Settings.shared.userImagesRootPath
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftarr-atomic-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		Settings.shared.userImagesRootPath = root
		defer {
			Settings.shared.userImagesRootPath = original
			try? FileManager.default.removeItem(at: root)
		}
		try await body(root)
	}

	private func imageFileCount(in root: URL) -> Int {
		guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
			return 0
		}
		return enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.count
	}

	// MARK: Fez creation

	// The first post's rules (no photos in a Seamail) used to be checked after the fez had been saved, so rejecting the post
	// left a fez behind that a client retry would duplicate.
	func testRejectedFirstPostLeavesNoFez() async throws {
		try await withApp { app in
			let creator = try await makeUser(app, username: "atomiccreator")
			let other = try await makeUser(app, username: "atomicother")
			let token = try await makeToken(app, for: creator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			// The test database has seed data, so compare against what was there before.
			let fezCountBefore = try await FriendlyFez.query(on: app.db).count()
			let participantCountBefore = try await FezParticipant.query(on: app.db).count()

			let content = FezContentData(
				fezType: .closed,
				title: "Atomic Seamail",
				info: "",
				minCapacity: 0,
				maxCapacity: 0,
				initialUsers: [try other.requireID()],
				firstPost: PostContentData(
					text: "hello with a photo",
					images: [ImageUploadData(nil, Data([1, 2, 3]))]
				)
			)
			try await app.test(
				.POST,
				"/api/v3/fez/create",
				headers: bearer(token),
				beforeRequest: { req in try req.content.encode(content) },
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
				}
			)
			let fezCount = try await FriendlyFez.query(on: app.db).count()
			let participantCount = try await FezParticipant.query(on: app.db).count()
			XCTAssertEqual(fezCount, fezCountBefore)
			XCTAssertEqual(participantCount, participantCountBefore)
		}
	}

	func testCreateWithFirstPostWritesEverythingTogether() async throws {
		try await withApp { app in
			let creator = try await makeUser(app, username: "atomiccreator2")
			let other = try await makeUser(app, username: "atomicother2")
			let token = try await makeToken(app, for: creator)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let content = FezContentData(
				fezType: .closed,
				title: "Atomic Seamail",
				info: "",
				minCapacity: 0,
				maxCapacity: 0,
				initialUsers: [try other.requireID()],
				firstPost: PostContentData(text: "the first post", images: [])
			)
			try await app.test(
				.POST,
				"/api/v3/fez/create",
				headers: bearer(token),
				beforeRequest: { req in try req.content.encode(content) },
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .created)
					let fezData = try res.content.decode(FezData.self)
					XCTAssertEqual(fezData.members?.posts?.count, 1)
					XCTAssertEqual(fezData.members?.postCount, 1)
				}
			)
			let creatorID = try creator.requireID()
			let foundFez = try await FriendlyFez.query(on: app.db).filter(\FriendlyFez.$owner.$id == creatorID).first()
			let fez = try XCTUnwrap(foundFez)
			let fezID = try fez.requireID()
			XCTAssertEqual(fez.postCount, 1)
			let posts = try await FezPost.query(on: app.db).filter(\.$fez.$id == fezID).all()
			XCTAssertEqual(posts.map { $0.text }, ["the first post"])
			let pivots = try await FezParticipant.query(on: app.db).filter(\.$fez.$id == fezID).all()
			XCTAssertEqual(pivots.count, 2)
			// The creator wrote the post so has read it; the user who was added has an unread post and the 'added to' flag.
			let creatorPivot = try XCTUnwrap(pivots.first { $0.$user.id == (try? creator.requireID()) })
			let otherPivot = try XCTUnwrap(pivots.first { $0.$user.id == (try? other.requireID()) })
			XCTAssertEqual(creatorPivot.readCount, 1)
			XCTAssertEqual(creatorPivot.addedTo, false)
			XCTAssertEqual(otherPivot.readCount, 0)
			XCTAssertEqual(otherPivot.addedTo, true)
		}
	}

	// MARK: Transactions

	// If anything in the transaction throws, the fez, the post and the post count all roll back together.
	func testFezPostInsertRollsBackWithTheTransaction() async throws {
		try await withApp { app in
			let creator = try await makeUser(app, username: "atomiccreator3")
			let other = try await makeUser(app, username: "atomicother3")
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			let req = Request(application: app, on: app.eventLoopGroup.next())
			let cacheUser = try XCTUnwrap(req.userCache.getUser(try creator.requireID()))
			struct Boom: Error {}
			let fezCountBefore = try await FriendlyFez.query(on: app.db).count()
			let postCountBefore = try await FezPost.query(on: app.db).count()

			do {
				try await app.db.transaction { db in
					let fez = FriendlyFez(owner: try creator.requireID(), fezType: .closed, visibility: .private, title: "Rollback", info: "",
							location: nil, startTime: nil, endTime: nil, minCapacity: 0, maxCapacity: 0)
					fez.participantArray = [try creator.requireID(), try other.requireID()]
					try await fez.save(on: db)
					_ = try await FezController().insertFezPost(to: fez, data: PostContentData(text: "never committed", images: []),
							imageFilename: nil, cacheUser: cacheUser, on: req, db: db)
					throw Boom()
				}
				XCTFail("transaction should have thrown")
			}
			catch is Boom {}
			let fezCount = try await FriendlyFez.query(on: app.db).count()
			let postCount = try await FezPost.query(on: app.db).count()
			XCTAssertEqual(fezCount, fezCountBefore)
			XCTAssertEqual(postCount, postCountBefore)
		}
	}

	// postCount is bumped with SET post_count = post_count + 1, so simultaneous posts all count.
	func testConcurrentFezPostsAllCount() async throws {
		try await withApp { app in
			let creator = try await makeUser(app, username: "atomiccreator4")
			let other = try await makeUser(app, username: "atomicother4")
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			let req = Request(application: app, on: app.eventLoopGroup.next())
			let creatorID = try creator.requireID()
			let cacheUser = try XCTUnwrap(req.userCache.getUser(creatorID))
			let fez = FriendlyFez(owner: creatorID, fezType: .closed, visibility: .private, title: "Concurrent", info: "",
					location: nil, startTime: nil, endTime: nil, minCapacity: 0, maxCapacity: 0)
			fez.participantArray = [creatorID, try other.requireID()]
			try await fez.save(on: app.db)
			let fezID = try fez.requireID()
			let postCount = 10

			try await withThrowingTaskGroup(of: Void.self) { group in
				for i in 0..<postCount {
					group.addTask {
						try await app.db.transaction { db in
							_ = try await FezController().insertFezPost(to: fez, data: PostContentData(text: "post \(i)", images: []),
									imageFilename: nil, cacheUser: cacheUser, on: req, db: db)
						}
					}
				}
				try await group.waitForAll()
			}
			let stored = try await FriendlyFez.find(fezID, on: app.db)
			XCTAssertEqual(stored?.postCount, postCount)
			let posts = try await FezPost.query(on: app.db).filter(\FezPost.$fez.$id == fezID).count()
			XCTAssertEqual(posts, postCount)
		}
	}

	// MARK: Images

	func testWithProcessedImagesDeletesNewFilesWhenBodyFails() async throws {
		try await withApp { app in
			try await withTemporaryImageRoot { root in
				let req = Request(application: app, on: app.eventLoopGroup.next())
				let controller = FezController()
				let upload = ImageUploadData(nil, try fixtureImageData())
				struct Boom: Error {}

				do {
					_ = try await controller.withProcessedImages([upload], usage: .forumPost, on: req) { filenames -> Void in
						XCTAssertEqual(filenames.count, 1)
						XCTAssertEqual(self.imageFileCount(in: root), 2)  // full + thumbnail
						throw Boom()
					}
					XCTFail("body should have thrown")
				}
				catch is Boom {}
				XCTAssertEqual(imageFileCount(in: root), 0)

				// On success the files stay.
				let filenames = try await controller.withProcessedImages([upload], usage: .forumPost, on: req) { $0 }
				XCTAssertEqual(filenames.count, 1)
				XCTAssertEqual(imageFileCount(in: root), 2)
			}
		}
	}

	// Existing filenames passed back in by an edit refer to files the content already owns; a failure must not delete those.
	func testWithProcessedImagesLeavesExistingFilenamesAlone() async throws {
		try await withApp { app in
			try await withTemporaryImageRoot { root in
				let req = Request(application: app, on: app.eventLoopGroup.next())
				let controller = FezController()
				let existing = try await controller.processImages([ImageUploadData(nil, try fixtureImageData())], usage: .forumPost, on: req)
				XCTAssertEqual(imageFileCount(in: root), 2)
				struct Boom: Error {}

				do {
					_ = try await controller.withProcessedImages([ImageUploadData(existing[0], nil)], usage: .forumPost, on: req) { _ -> Void in
						throw Boom()
					}
				}
				catch is Boom {}
				XCTAssertEqual(imageFileCount(in: root), 2)
			}
		}
	}

	// Adding a second daily theme for the same day is an expected failure that used to leave the uploaded image behind.
	func testDailyThemeConflictDoesNotOrphanImage() async throws {
		try await withApp { app in
			try await withTemporaryImageRoot { root in
				let admin = try await makeUser(app, username: "atomicadmin", accessLevel: .twitarrteam)
				let token = try await makeToken(app, for: admin)
				try await app.asyncBoot()
				try await app.initializeUserCache(app)
				let imageData = try fixtureImageData()
				// Passing tests don't clean up, so pick a day no earlier run used.
				let cruiseDay = Int.random(in: 1000...1_000_000)

				func create(expecting status: HTTPStatus) async throws {
					let body = DailyThemeUploadData(title: "Atomic Day", info: "A theme", image: ImageUploadData(nil, imageData), cruiseDay: cruiseDay)
					try await app.test(
						.POST,
						"/api/v3/admin/dailytheme/create",
						headers: bearer(token),
						beforeRequest: { req in try req.content.encode(body) },
						afterResponse: { res async throws in XCTAssertEqual(res.status, status) }
					)
				}
				try await create(expecting: .created)
				XCTAssertEqual(imageFileCount(in: root), 2)
				try await create(expecting: .conflict)
				XCTAssertEqual(imageFileCount(in: root), 2)
			}
		}
	}
}
