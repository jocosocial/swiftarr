import XCTVapor

@testable import swiftarr

final class ForumDefaultSortTests: XCTestCase, SwiftarrBaseTest {
	/// A category default must beat update ordering, while an explicit request must beat the category default.
	func testCategoryDefaultAndExplicitOverride() async throws {
		try await withApp { app in
			let user = User(
				username: "sort-\(UUID().uuidString.prefix(8).lowercased())",
				password: try Bcrypt.hash("password1"),
				recoveryKey: try Bcrypt.hash("recovery key"),
				accessLevel: .verified
			)
			try await user.save(on: app.db)
			let token = try Token.generate(for: user)
			try await token.save(on: app.db)
			let category = Category(title: "Sort fixture \(UUID().uuidString)", purpose: "test", defaultSort: .create)
			try await category.save(on: app.db)
			let older = try Forum(title: "Older", category: category, creatorID: user.requireID())
			let newer = try Forum(title: "Newer", category: category, creatorID: user.requireID())
			try await older.save(on: app.db)
			try await newer.save(on: app.db)
			older.createdAt = Date(timeIntervalSince1970: 100)
			newer.createdAt = Date(timeIntervalSince1970: 200)
			older.lastPostTime = Date(timeIntervalSince1970: 400)
			newer.lastPostTime = Date(timeIntervalSince1970: 300)
			try await older.save(on: app.db)
			try await newer.save(on: app.db)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)
			var headers = HTTPHeaders()
			headers.bearerAuthorization = BearerAuthorization(token: token.token)
			let path = "/api/v3/forum/categories/\(try category.requireID())"
			for (query, expected) in [("", [newer, older]), ("?sort=update", [older, newer])] {
				try await app.test(
					.GET,
					path + query,
					headers: headers,
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, .ok)
						let data = try res.content.decode(CategoryData.self)
						XCTAssertEqual(data.forumThreads?.map(\.forumID), try expected.map { try $0.requireID() })
					}
				)
			}
			try await app.test(
				.GET,
				path + "?sort=event",
				headers: headers,
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
				}
			)
			let events = Category(
				title: "Event sort fixture \(UUID().uuidString)",
				purpose: "test",
				isEventCategory: true,
				defaultSort: .event
			)
			try await events.save(on: app.db)
			try await app.test(
				.GET,
				"/api/v3/forum/categories/\(try events.requireID())?sort=event",
				headers: headers,
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(CategoryData.self)
					XCTAssertEqual(data.defaultSort, .event)
				}
			)
		}
	}
}
