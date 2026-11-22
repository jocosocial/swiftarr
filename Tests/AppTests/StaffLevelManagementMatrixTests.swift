import XCTVapor

@testable import swiftarr

/// Exhaustive promote/demote matrix: every caller level against every staff level, below, at, and above the caller's own level.
/// Expectations are written out by hand on purpose, so they don't just restate `UserAccessLevel.canManageStaffLevel`.
final class StaffLevelManagementMatrixTests: XCTestCase, SwiftarrBaseTest {
	private typealias Level = UserAccessLevel

	private func makeUser(_ app: Application, _ name: String, _ level: Level) async throws -> (id: UUID, token: String) {
		let user = User(
			username: "\(name)-\(UUID().uuidString.prefix(6).lowercased())",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: level
		)
		try await user.save(on: app.db)
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return (try user.requireID(), token.token)
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func dbLevel(_ app: Application, _ id: UUID) async throws -> Level {
		let user = try await User.find(id, on: app.db)
		return try XCTUnwrap(user).accessLevel
	}

	private let promoteRoute: [Level: String] = [
		.moderator: "moderator", .twitarrteam: "twitarrteam", .tho: "tho",
	]

	func testPromoteAndDemoteMatrix() async throws {
		try await withApp { app in
			let callers: [Level] = [.verified, .moderator, .twitarrteam, .tho, .admin]
			var tokens = [Level: String]()
			for level in callers { tokens[level] = try await makeUser(app, "mx\(level.rawValue)", level).token }
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			func call(_ caller: Level, _ path: String) async throws -> HTTPStatus {
				var result = HTTPStatus.internalServerError
				try await app.test(.POST, path, headers: bearer(tokens[caller]!)) { res async throws in result = res.status }
				return result
			}

			// MARK: Promotion: a verified target promoted to each staff level.
			// A caller may promote up to, and including, their own level. Below TwitarrTeam there's no promotion at all.
			let promoteAllowed: [Level: Set<Level>] = [
				.verified: [],
				.moderator: [],
				.twitarrteam: [.moderator, .twitarrteam],
				.tho: [.moderator, .twitarrteam, .tho],
				.admin: [.moderator, .twitarrteam, .tho],
			]
			for caller in callers {
				for target in [Level.moderator, .twitarrteam, .tho] {
					let victim = try await makeUser(app, "pv", .verified).id
					let status = try await call(caller, "/api/v3/admin/\(promoteRoute[target]!)/promote/\(victim)")
					let after = try await dbLevel(app, victim)
					if promoteAllowed[caller]!.contains(target) {
						XCTAssertEqual(status, .ok, "\(caller) promoting verified -> \(target)")
						XCTAssertEqual(after, target, "\(caller) promoting verified -> \(target) should take effect")
					}
					else {
						XCTAssertEqual(status, .forbidden, "\(caller) promoting verified -> \(target)")
						XCTAssertEqual(after, .verified, "refused \(caller) promotion to \(target) must change nothing")
					}
				}
			}

			// MARK: Promotion edge cases, TwitarrTeam caller.
			// Below the caller's level: a moderator can be promoted to TwitarrTeam.
			let modVictim = try await makeUser(app, "pm", .moderator).id
			var status = try await call(.twitarrteam, "/api/v3/admin/twitarrteam/promote/\(modVictim)")
			XCTAssertEqual(status, .ok, "TwitarrTeam promoting moderator -> TwitarrTeam")
			var after = try await dbLevel(app, modVictim)
			XCTAssertEqual(after, .twitarrteam)
			// At the caller's level: already TwitarrTeam.
			let ttVictim = try await makeUser(app, "pt", .twitarrteam).id
			status = try await call(.twitarrteam, "/api/v3/admin/twitarrteam/promote/\(ttVictim)")
			XCTAssertEqual(status, .badRequest, "promoting someone who's already TwitarrTeam")
			// Above the caller's level: a THO can't be 'promoted' down to moderator.
			let thoVictim = try await makeUser(app, "ph", .tho).id
			status = try await call(.twitarrteam, "/api/v3/admin/moderator/promote/\(thoVictim)")
			XCTAssertEqual(status, .badRequest, "promoting a THO to moderator")
			after = try await dbLevel(app, thoVictim)
			XCTAssertEqual(after, .tho, "a refused promotion must not demote anyone")

			// MARK: Demotion: a target at each level, demoted by each caller.
			// A caller may demote targets at or below their own level, never above it. Below TwitarrTeam there's no demotion.
			let demoteAllowed: [Level: Set<Level>] = [
				.verified: [],
				.moderator: [],
				.twitarrteam: [.moderator, .twitarrteam],
				.tho: [.moderator, .twitarrteam, .tho],
				.admin: [.moderator, .twitarrteam, .tho],
			]
			for caller in callers {
				for target in [Level.moderator, .twitarrteam, .tho] {
					let victim = try await makeUser(app, "dv", target).id
					let status = try await call(caller, "/api/v3/admin/user/demote/\(victim)")
					let after = try await dbLevel(app, victim)
					if demoteAllowed[caller]!.contains(target) {
						XCTAssertEqual(status, .ok, "\(caller) demoting \(target)")
						XCTAssertEqual(after, .verified, "\(caller) demoting \(target) should take effect")
					}
					else {
						XCTAssertEqual(status, .forbidden, "\(caller) demoting \(target)")
						XCTAssertEqual(after, target, "refused \(caller) demotion of \(target) must change nothing")
					}
				}
			}

			// MARK: Demotion edge cases.
			// Nothing to demote: a verified target is a bad request for anyone who is allowed to try.
			for caller in [Level.twitarrteam, .tho, .admin] {
				let victim = try await makeUser(app, "dn", .verified).id
				status = try await call(caller, "/api/v3/admin/user/demote/\(victim)")
				XCTAssertEqual(status, .badRequest, "\(caller) demoting a verified user")
				after = try await dbLevel(app, victim)
				XCTAssertEqual(after, .verified)
			}
			// Special accounts can't be changed by anyone, whatever their level.
			for name in ["admin", "THO", "TwitarrTeam", "moderator"] {
				let special = try await User.query(on: app.db).filter(\.$username, .equal, name).first()
				let specialAccount = try XCTUnwrap(special, "special account @\(name)")
				let specialID = try specialAccount.requireID()
				for caller in [Level.twitarrteam, .tho, .admin] {
					status = try await call(caller, "/api/v3/admin/user/demote/\(specialID)")
					XCTAssertEqual(status, .forbidden, "\(caller) demoting @\(name)")
					after = try await dbLevel(app, specialID)
					XCTAssertEqual(after, specialAccount.accessLevel, "@\(name) must be unchanged")
				}
			}
			// At their own level: a TwitarrTeam member can demote themselves.
			let selfTT = try await makeUser(app, "selfdemote", .twitarrteam)
			try await app.initializeUserCache(app)
			try await app.test(.POST, "/api/v3/admin/user/demote/\(selfTT.id)", headers: bearer(selfTT.token)) { res async throws in
				XCTAssertEqual(res.status, .ok, "TwitarrTeam demoting themselves")
			}
			after = try await dbLevel(app, selfTT.id)
			XCTAssertEqual(after, .verified)
		}
	}
}
