import Fluent
import XCTVapor

@testable import swiftarr

// Notification Log (issue #316): a durable history of notifications a user was sent, so a client can recover
// one it missed (e.g. a push notification swiped away before being read).
class NotificationLogTests: XCTestCase, SwiftarrBaseTest {

	private func makeUser(_ app: Application, username: String) async throws -> User {
		let user = User(
			username: username,
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

	private func bootCache(_ app: Application) async throws {
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
	}

	// Drives the real fan-out hook in `addNotifications`--where `NotificationLogEntry`/`NotificationRecipient`
	// rows actually get written--without needing to stand up a forum/category just to trigger a mention.
	// `addNotifications` touches `req.redis`, which needs the app's Redis storage booted first (`app.test`
	// would normally do this as part of simulating a request; a directly-constructed `Request` doesn't).
	private func fireNotification(_ app: Application, type: NotificationType, info: String, recipients: [UUID]) async throws {
		try await app.asyncBoot()
		let req = Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
		try await AlertController().addNotifications(users: recipients, type: type, info: info, on: req)
	}

	func testLoggedNotificationAppearsInOwnLog() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let recipient = try await makeUser(app, username: "recip-\(suffix)")
			try await fireNotification(
				app,
				type: .twarrtMention(42),
				info: "Someone mentioned you",
				recipients: [try recipient.requireID()]
			)

			let token = try await makeToken(app, for: recipient)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/notification/log",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<NotificationLogData>.self)
					XCTAssertEqual(data.items.count, 1)
					XCTAssertEqual(data.items.first?.type, .twarrtMention)
					XCTAssertEqual(data.items.first?.info, "Someone mentioned you")
					XCTAssertEqual(data.items.first?.contentID, "42")
				}
			)
		}
	}

	// A broadcast-style notification fanned out to many users (e.g. an announcement) must write its content
	// exactly once--storing it per-recipient would duplicate the same text once for every one of the
	// (potentially thousands of) recipients.
	func testBroadcastNotificationWritesContentOnce() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let first = try await makeUser(app, username: "bcast-a-\(suffix)")
			let second = try await makeUser(app, username: "bcast-b-\(suffix)")
			let contentID = Int.random(in: 100_000...999_999)
			try await fireNotification(
				app,
				type: .announcement(contentID),
				info: "New announcement",
				recipients: [try first.requireID(), try second.requireID()]
			)

			let notificationCount = try await NotificationLogEntry.query(on: app.db).filter(\.$contentID == String(contentID)).count()
			XCTAssertEqual(notificationCount, 1)

			let recipientCount = try await NotificationLogEntry.query(on: app.db)
				.join(NotificationRecipient.self, on: \NotificationLogEntry.$id == \NotificationRecipient.$notification.$id)
				.filter(\.$contentID == String(contentID))
				.count()
			XCTAssertEqual(recipientCount, 2)

			let token = try await makeToken(app, for: second)
			try await bootCache(app)
			try await app.test(
				.GET,
				"/api/v3/notification/log",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<NotificationLogData>.self)
					XCTAssertEqual(data.items.count, 1)
					XCTAssertEqual(data.items.first?.type, .announcement)
				}
			)
		}
	}

	func testUserOnlySeesTheirOwnNotifications() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let targeted = try await makeUser(app, username: "targeted-\(suffix)")
			let bystander = try await makeUser(app, username: "bystander-\(suffix)")
			try await fireNotification(
				app,
				type: .twarrtMention(7),
				info: "for targeted only",
				recipients: [try targeted.requireID()]
			)

			let token = try await makeToken(app, for: bystander)
			try await bootCache(app)
			try await app.test(
				.GET,
				"/api/v3/notification/log",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<NotificationLogData>.self)
					XCTAssertEqual(data.items.count, 0)
				}
			)
		}
	}

	func testPaginationOrdersNewestFirst() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let recipient = try await makeUser(app, username: "paged-\(suffix)")
			let recipientID = try recipient.requireID()
			try await fireNotification(app, type: .twarrtMention(1), info: "first", recipients: [recipientID])
			try await fireNotification(app, type: .twarrtMention(2), info: "second", recipients: [recipientID])
			try await fireNotification(app, type: .twarrtMention(3), info: "third", recipients: [recipientID])

			let token = try await makeToken(app, for: recipient)
			try await bootCache(app)
			try await app.test(
				.GET,
				"/api/v3/notification/log?start=0&limit=2",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<NotificationLogData>.self)
					XCTAssertEqual(data.paginator.total, 3)
					XCTAssertEqual(data.items.count, 2)
					XCTAssertEqual(data.items[0].contentID, "3")
					XCTAssertEqual(data.items[1].contentID, "2")
				}
			)
		}
	}

	// The notificationID sent over the live socket push must be exactly the logged entry's id, so clients
	// can de-dupe a live push against a later log fetch. Scoped to this test's own recipient--`withApp`
	// gives each test a fresh `Application`, but all tests share the same underlying test database, so a
	// bare `contentID` filter could pick up a leftover row from a previous run using the same literal ID.
	func testNotificationIDMatchesTheLoggedRow() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let recipient = try await makeUser(app, username: "dedupe-\(suffix)")
			let recipientID = try recipient.requireID()
			try await fireNotification(app, type: .twarrtMention(55), info: "dedupe me", recipients: [recipientID])

			let entry = try await NotificationLogEntry.query(on: app.db)
				.join(NotificationRecipient.self, on: \NotificationLogEntry.$id == \NotificationRecipient.$notification.$id)
				.filter(NotificationRecipient.self, \.$user.$id == recipientID)
				.filter(\.$contentID == "55")
				.first()
			let notificationID = try XCTUnwrap(entry?.id)

			let token = try await makeToken(app, for: recipient)
			try await bootCache(app)
			try await app.test(
				.GET,
				"/api/v3/notification/log",
				headers: bearer(token),
				afterResponse: { res async throws in
					let data = try res.content.decode(Paginated<NotificationLogData>.self)
					XCTAssertEqual(data.items.first?.id, notificationID)
				}
			)
		}
	}

	// A row written under a `NotificationTypeData` case that's since been renamed/removed has a `typeKey`
	// that no longer decodes. The endpoint must drop that one row and return everything else with a 200,
	// not fail the whole page--a stale row would otherwise permanently 500 every future fetch of this user's
	// notification history.
	func testUnrecognizedNotificationTypeIsSkippedNotFatal() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let recipient = try await makeUser(app, username: "stale-\(suffix)")
			let recipientID = try recipient.requireID()

			let staleEntry = NotificationLogEntry()
			staleEntry.typeKey = "notARealCaseAnymore"
			staleEntry.info = "stale"
			staleEntry.contentID = "0"
			try await staleEntry.save(on: app.db)
			try await NotificationRecipient(notificationID: try staleEntry.requireID(), userID: recipientID).save(on: app.db)

			try await fireNotification(app, type: .twarrtMention(9), info: "still works", recipients: [recipientID])

			let token = try await makeToken(app, for: recipient)
			try await bootCache(app)
			try await app.test(
				.GET,
				"/api/v3/notification/log",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<NotificationLogData>.self)
					XCTAssertEqual(data.paginator.total, 2)
					XCTAssertEqual(data.items.count, 1)
					XCTAssertEqual(data.items.first?.contentID, "9")
				}
			)
		}
	}
}
