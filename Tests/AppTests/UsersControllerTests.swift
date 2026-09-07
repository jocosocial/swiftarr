import XCTVapor

@testable import swiftarr

// Tests for `GET /api/v3/users/match/allnames/:search_string`, especially `?sort=favorites`.
class UsersControllerTests: XCTestCase, SwiftarrBaseTest {

	private struct MatchFixture {
		let token: String
		let search: String
		let aaa: String
		let mmm: String
		let zzz: String
	}

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

	private func matchURL(_ search: String, sort: String? = nil) -> String {
		var url = "/api/v3/users/match/allnames/\(search)"
		if let sort {
			url += "?sort=\(sort)"
		}
		return url
	}

	/// Builds a requester plus three users whose usernames share a unique substring, so the match
	/// query returns only this set. Favorites the last-sorting user (`zzz`).
	private func makeMatchFixture(_ app: Application, favoriteMMM: Bool = false) async throws -> MatchFixture {
		let tag = "favsort\(UUID().uuidString.prefix(8).lowercased())"
		let requester = try await makeUser(app, username: "searcher\(UUID().uuidString.prefix(8).lowercased())")
		let aaa = try await makeUser(app, username: "aaa\(tag)")
		let mmm = try await makeUser(app, username: "mmm\(tag)")
		let zzz = try await makeUser(app, username: "zzz\(tag)")

		try await UserFavorite(userID: requester.requireID(), favoriteUserID: zzz.requireID()).create(on: app.db)
		if favoriteMMM {
			try await UserFavorite(userID: requester.requireID(), favoriteUserID: mmm.requireID()).create(on: app.db)
		}

		let token = try await makeToken(app, for: requester)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)

		return MatchFixture(
			token: token,
			search: tag,
			aaa: aaa.username,
			mmm: mmm.username,
			zzz: zzz.username
		)
	}

	func testMatchAllNames_DefaultSortIsAlphabetical() async throws {
		try await withApp { app in
			let fixture = try await makeMatchFixture(app)

			try await app.test(
				.GET,
				matchURL(fixture.search),
				headers: bearer(fixture.token)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let users = try res.content.decode([UserHeader].self)
				XCTAssertEqual(
					users.map(\.username),
					[fixture.aaa, fixture.mmm, fixture.zzz],
					"without sort, matches are alphabetical by username"
				)
			}
		}
	}

	func testMatchAllNames_SortFavorites_PutsFavoriteFirst() async throws {
		try await withApp { app in
			let fixture = try await makeMatchFixture(app)

			try await app.test(
				.GET,
				matchURL(fixture.search, sort: "favorites"),
				headers: bearer(fixture.token)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let users = try res.content.decode([UserHeader].self)
				XCTAssertEqual(
					users.map(\.username),
					[fixture.zzz, fixture.aaa, fixture.mmm],
					"sort=favorites lists the favorited user first, then remaining matches alphabetically"
				)
			}
		}
	}

	func testMatchAllNames_SortFavorites_MultipleFavoritesStayAlphabetical() async throws {
		try await withApp { app in
			let fixture = try await makeMatchFixture(app, favoriteMMM: true)

			try await app.test(
				.GET,
				matchURL(fixture.search, sort: "favorites"),
				headers: bearer(fixture.token)
			) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let users = try res.content.decode([UserHeader].self)
				XCTAssertEqual(
					users.map(\.username),
					[fixture.mmm, fixture.zzz, fixture.aaa],
					"multiple favorites stay alphabetical among themselves, then non-favorites"
				)
			}
		}
	}

	func testMatchAllNames_UnknownSort_Returns400() async throws {
		try await withApp { app in
			let fixture = try await makeMatchFixture(app)

			try await app.test(
				.GET,
				matchURL(fixture.search, sort: "bogus"),
				headers: bearer(fixture.token)
			) { res async throws in
				XCTAssertEqual(res.status, .badRequest, "unknown sort values must 400")
			}
		}
	}
}
