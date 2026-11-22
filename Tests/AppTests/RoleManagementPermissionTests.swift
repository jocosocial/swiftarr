import XCTVapor

@testable import swiftarr

final class RoleManagementPermissionTests: XCTestCase, SwiftarrBaseTest {
	private struct Actor {
		let name: String
		let token: String
	}

	private func makeActor(
		_ app: Application,
		_ name: String,
		_ level: UserAccessLevel,
		roles: [UserRoleType] = []
	) async throws -> (actor: Actor, id: UUID) {
		let user = User(
			username: "\(name)-\(UUID().uuidString.prefix(6).lowercased())",
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: level
		)
		try await user.save(on: app.db)
		for role in roles {
			try await UserRole(user: user.requireID(), role: role).create(on: app.db)
		}
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return (Actor(name: name, token: token.token), try user.requireID())
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	// MARK: - Routes

	func testRoleManagementRoutes() async throws {
		try await withApp { app in
			let admin = try await makeActor(app, "rmadmin", .admin).actor
			let tho = try await makeActor(app, "rmtho", .tho).actor
			let tt = try await makeActor(app, "rmtt", .twitarrteam).actor
			let mod = try await makeActor(app, "rmmod", .moderator).actor
			let mgr = try await makeActor(app, "rmmgr", .verified, roles: [.shutternautmanager]).actor
			let plain = try await makeActor(app, "rmplain", .verified).actor
			let targetID = try await makeActor(app, "rmtarget", .verified).id
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			func status(_ actor: Actor, _ method: HTTPMethod, _ path: String) async throws -> HTTPStatus {
				var result = HTTPStatus.internalServerError
				try await app.test(method, path, headers: bearer(actor.token)) { res async throws in
					result = res.status
				}
				return result
			}

			// Admin routes: any role, TwitarrTeam and above.
			for actor in [admin, tho, tt] {
				for role in ["shutternaut", "karaokemanager"] {
					let base = "/api/v3/admin/userroles/\(role)"
					var s = try await status(actor, .GET, base)
					XCTAssertEqual(s, .ok, "\(actor.name) list \(role)")
					s = try await status(actor, .POST, "\(base)/addrole/\(targetID)")
					XCTAssertEqual(s, .ok, "\(actor.name) add \(role)")
					s = try await status(actor, .POST, "\(base)/removerole/\(targetID)")
					XCTAssertEqual(s, .ok, "\(actor.name) remove \(role)")
				}
			}
			for actor in [mod, mgr, plain] {
				let base = "/api/v3/admin/userroles/shutternaut"
				var s = try await status(actor, .GET, base)
				XCTAssertEqual(s, .forbidden, "\(actor.name) list via admin route")
				s = try await status(actor, .POST, "\(base)/addrole/\(targetID)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) add via admin route")
				s = try await status(actor, .POST, "\(base)/removerole/\(targetID)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) remove via admin route")
			}

			// Shutternaut routes: TwitarrTeam and above, plus Shutternaut Managers; shutternaut role only.
			for actor in [admin, tho, tt, mgr] {
				let base = "/api/v3/users/userrole/shutternaut"
				var s = try await status(actor, .GET, base)
				XCTAssertEqual(s, .ok, "\(actor.name) list shutternauts")
				s = try await status(actor, .POST, "\(base)/addrole/\(targetID)")
				XCTAssertEqual(s, .ok, "\(actor.name) add shutternaut")
				s = try await status(actor, .POST, "\(base)/removerole/\(targetID)")
				XCTAssertEqual(s, .ok, "\(actor.name) remove shutternaut")
				s = try await status(actor, .POST, "/api/v3/users/userrole/karaokemanager/addrole/\(targetID)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) add non-shutternaut role")
			}
			for actor in [mod, plain] {
				let base = "/api/v3/users/userrole/shutternaut"
				var s = try await status(actor, .GET, base)
				XCTAssertEqual(s, .forbidden, "\(actor.name) list shutternauts")
				s = try await status(actor, .POST, "\(base)/addrole/\(targetID)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) add shutternaut")
				s = try await status(actor, .POST, "\(base)/removerole/\(targetID)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) remove shutternaut")
			}
		}
	}
}
