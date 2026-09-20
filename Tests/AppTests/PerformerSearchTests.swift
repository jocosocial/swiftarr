import Fluent
import XCTVapor
@testable import swiftarr

// Tests for Performer search (issue #507): full-text search across name, organization, title, and bio,
// scoped to either /performer/official or /performer/shadow.
//
// Uses SwiftarrBaseTest and a live Postgres instance (port 5433) plus Redis (port 6380), same as
// QuartermasterControllerTests.
final class PerformerSearchTests: XCTestCase, SwiftarrBaseTest {

	// MARK: - Helpers

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

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	@discardableResult
	private func makeOfficialPerformer(
		_ app: Application,
		name: String,
		organization: String? = nil,
		title: String? = nil,
		bio: String? = nil
	) async throws -> Performer {
		let performer = Performer()
		performer.name = name
		performer.sortOrder = (name.split(separator: " ").last?.string ?? name).uppercased()
		performer.organization = organization
		performer.title = title
		performer.bio = bio
		performer.yearsAttended = [2026]
		performer.officialPerformer = true
		try await performer.save(on: app.db)
		return performer
	}

	// MARK: - Tests

	func testOfficialSearch_MatchesOrganization() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-search-org-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await makeOfficialPerformer(app, name: "Sam Reich", organization: "Dropout")
			try await makeOfficialPerformer(app, name: "Someone Else", organization: "Other Company")

			try await app.test(.GET, "/api/v3/performer/official?search=dropout", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(PerformerResponseData.self)
				XCTAssertTrue(list.performers.contains { $0.name == "Sam Reich" },
					"search=dropout should match performers via organization")
				XCTAssertFalse(list.performers.contains { $0.name == "Someone Else" },
					"search=dropout should not match unrelated performers")
			}
		}
	}

	func testOfficialSearch_MatchesTitleAndBio() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-search-bio-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await makeOfficialPerformer(app, name: "Jonathan Coulton", title: "Musician")
			try await makeOfficialPerformer(app, name: "Bio Person", bio: "Known for narwhal-related folk songs.")

			try await app.test(.GET, "/api/v3/performer/official?search=musician", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(PerformerResponseData.self)
				XCTAssertTrue(list.performers.contains { $0.name == "Jonathan Coulton" },
					"search=musician should match performers via title")
			}

			try await app.test(.GET, "/api/v3/performer/official?search=narwhal", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(PerformerResponseData.self)
				XCTAssertTrue(list.performers.contains { $0.name == "Bio Person" },
					"search=narwhal should match performers via bio")
			}
		}
	}

	func testOfficialSearch_NoMatch_ExcludesPerformer() async throws {
		try await withApp { app in
			let user = try await makeUser(app, username: "perf-search-none-\(UUID().uuidString.prefix(6))", accessLevel: .verified)
			let token = try await makeToken(app, for: user)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await makeOfficialPerformer(app, name: "Zzyzx Performer")

			try await app.test(.GET, "/api/v3/performer/official?search=nonexistentsearchterm", headers: bearer(token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "body=\(String(buffer: res.body))")
				let list = try res.content.decode(PerformerResponseData.self)
				XCTAssertFalse(list.performers.contains { $0.name == "Zzyzx Performer" })
			}
		}
	}
}
