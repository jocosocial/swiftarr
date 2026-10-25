import Queues
import XCTVapor

@testable import swiftarr

// Regression tests for the nightly `UpdateRedisJob`'s handling of its privileged mailbox phantom
// accounts (issue #628): a mailbox whose phantom account hasn't been seeded on this instance yet
// must be skipped, not abort the whole job.
class ConsistencyJobsTests: XCTestCase, SwiftarrBaseTest {

	private func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		// roles is @Children and crashes if accessed unloaded; this user has none.
		user.$roles.value = []
		return user
	}

	private func phantomUser(username: String) -> User {
		let user = User()
		user.username = username
		user.id = UUID()
		return user
	}

	func testResolvePrivilegedUserIDsIncludesEveryPresentPhantom() throws {
		let phantoms = PrivilegedMailbox.all.map { phantomUser(username: $0.user.rawValue) }
		let ids = try UpdateRedisJobBase.resolvePrivilegedUserIDs(from: phantoms, logger: Logger(label: "test"))
		for mailbox in PrivilegedMailbox.all {
			XCTAssertEqual(ids[mailbox.user], try phantoms.first { $0.username == mailbox.user.rawValue }?.requireID())
		}
	}

	// The actual regression: historically a missing phantom account made `execute()` throw and abort
	// the entire nightly run for every user. `resolvePrivilegedUserIDs` must instead just omit that
	// mailbox so `processUser` can still run for every other mailbox and for normal (non-privileged)
	// Fez consistency.
	func testResolvePrivilegedUserIDsOmitsAMissingPhantomWithoutThrowing() throws {
		guard let onlyMailbox = PrivilegedMailbox.all.first else {
			XCTFail("PrivilegedMailbox.all should not be empty")
			return
		}
		let phantoms = [phantomUser(username: onlyMailbox.user.rawValue)]
		let ids = try UpdateRedisJobBase.resolvePrivilegedUserIDs(from: phantoms, logger: Logger(label: "test"))

		XCTAssertEqual(ids.count, 1)
		XCTAssertNotNil(ids[onlyMailbox.user])
		for mailbox in PrivilegedMailbox.all where mailbox.user != onlyMailbox.user {
			XCTAssertNil(ids[mailbox.user], "a missing phantom account should be omitted, not crash resolution")
		}
	}

	func testResolvePrivilegedUserIDsReturnsEmptyWhenNoPhantomsExist() throws {
		let ids = try UpdateRedisJobBase.resolvePrivilegedUserIDs(from: [], logger: Logger(label: "test"))
		XCTAssertTrue(ids.isEmpty)
	}

	// `processUser` must tolerate privilegedUserIDs missing an entry for a mailbox the user otherwise
	// qualifies for (e.g. an admin, who satisfies every current requirement)--it should simply skip
	// that mailbox's processing rather than crash on the missing dictionary entry.
	func testProcessUserDoesNotThrowWhenPrivilegedUserIDsIsEmpty() async throws {
		try await withApp { app in
			// processUser needs app.redis wired up for the eventLoop it runs on; a request is the
			// sanctioned way to get the app through Vapor's boot sequence in a test (see withApp).
			try await app.test(.GET, "/api/v3/fez/types") { (_: XCTHTTPResponse) async throws in }
			let suffix = UUID().uuidString.prefix(8)
			let user = try await makeUser(app, username: "consistency-\(suffix)", accessLevel: .admin)
			let context = QueueContext(
				queueName: .default,
				configuration: app.queues.configuration,
				application: app,
				logger: app.logger,
				on: app.eventLoopGroup.next()
			)
			try await UpdateRedisJobBase().processUser(context, user: user, privilegedUserIDs: [:])
		}
	}
}
