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

			// Moderator management: TwitarrTeam and above. Only THO and above may demote anyone above moderator.
			let tt2 = try await makeActor(app, "rmtt2", .twitarrteam)
			for actor in [admin, tho, tt] {
				let candidate = try await makeActor(app, "rmcand", .verified).id
				var s = try await status(actor, .GET, "/api/v3/admin/moderators")
				XCTAssertEqual(s, .ok, "\(actor.name) list moderators")
				s = try await status(actor, .POST, "/api/v3/admin/moderator/promote/\(candidate)")
				XCTAssertEqual(s, .ok, "\(actor.name) promote moderator")
				s = try await status(actor, .POST, "/api/v3/admin/user/demote/\(candidate)")
				XCTAssertEqual(s, .ok, "\(actor.name) demote moderator")
			}
			for actor in [mod, mgr, plain] {
				let candidate = try await makeActor(app, "rmcand", .verified).id
				var s = try await status(actor, .GET, "/api/v3/admin/moderators")
				XCTAssertEqual(s, .forbidden, "\(actor.name) list moderators")
				s = try await status(actor, .POST, "/api/v3/admin/moderator/promote/\(candidate)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) promote moderator")
				s = try await status(actor, .POST, "/api/v3/admin/user/demote/\(candidate)")
				XCTAssertEqual(s, .forbidden, "\(actor.name) demote moderator")
			}
			// Demotion is limited to the caller's own access level and below.
			let thoTarget = try await makeActor(app, "rmthotarget", .tho).id
			let s0 = try await status(tt, .POST, "/api/v3/admin/user/demote/\(thoTarget)")
			XCTAssertEqual(s0, .forbidden, "twitarrteam must not demote a THO member")
			let s1 = try await status(tt, .POST, "/api/v3/admin/user/demote/\(tt2.id)")
			XCTAssertEqual(s1, .ok, "twitarrteam may demote a twitarrteam member")
			let s2 = try await status(tho, .POST, "/api/v3/admin/user/demote/\(thoTarget)")
			XCTAssertEqual(s2, .ok, "tho may demote a THO member")

			// Member lists are readable by TwitarrTeam and above, but promoting is not.
			for actor in [admin, tho, tt] {
				for list in ["twitarrteam", "tho"] {
					let s = try await status(actor, .GET, "/api/v3/admin/\(list)")
					XCTAssertEqual(s, .ok, "\(actor.name) list \(list) members")
				}
			}
			for actor in [mod, mgr, plain] {
				for list in ["twitarrteam", "tho"] {
					let s = try await status(actor, .GET, "/api/v3/admin/\(list)")
					XCTAssertEqual(s, .forbidden, "\(actor.name) list \(list) members")
				}
			}
			let promoteTarget = try await makeActor(app, "rmpromo", .verified).id
			let promoteTT = try await status(tt, .POST, "/api/v3/admin/twitarrteam/promote/\(promoteTarget)")
			XCTAssertEqual(promoteTT, .ok, "twitarrteam may promote to twitarrteam")
			let promoteTTMod = try await status(mod, .POST, "/api/v3/admin/twitarrteam/promote/\(promoteTarget)")
			XCTAssertEqual(promoteTTMod, .forbidden, "moderator must not promote to twitarrteam")
			let promoteTHOByTT = try await status(tt, .POST, "/api/v3/admin/tho/promote/\(promoteTarget)")
			XCTAssertEqual(promoteTHOByTT, .forbidden, "twitarrteam must not promote to tho")
			let promoteTHO = try await status(tho, .POST, "/api/v3/admin/tho/promote/\(promoteTarget)")
			XCTAssertEqual(promoteTHO, .ok, "tho may promote to tho")
			let promoteTHOByMod = try await status(mod, .POST, "/api/v3/admin/tho/promote/\(promoteTarget)")
			XCTAssertEqual(promoteTHOByMod, .forbidden, "moderator must not promote to tho")

			// Special accounts are off limits to everyone, and the refusal is a 403.
			let special = try await User.query(on: app.db).filter(\.$username, .equal, "THO").first()
			let specialID = try XCTUnwrap(special).requireID()
			let demoteSpecial = try await status(admin, .POST, "/api/v3/admin/user/demote/\(specialID)")
			XCTAssertEqual(demoteSpecial, .forbidden, "@THO cannot be demoted")
			let adminAccount = try await User.query(on: app.db).filter(\.$username, .equal, "admin").first()
			let adminAccountID = try XCTUnwrap(adminAccount).requireID()
			let demoteAdmin = try await status(tho, .POST, "/api/v3/admin/user/demote/\(adminAccountID)")
			XCTAssertEqual(demoteAdmin, .forbidden, "@admin cannot be demoted")

			// Role changes: unknown users 404, non-verified users can't be given roles, and changes are audit logged.
			let missing = UUID()
			let removeMissing = try await status(tt, .POST, "/api/v3/admin/userroles/karaokemanager/removerole/\(missing)")
			XCTAssertEqual(removeMissing, .notFound, "removing a role from an unknown user")
			let quarantinedID = try await makeActor(app, "rmquar", .quarantined).id
			let addQuarantined = try await status(tt, .POST, "/api/v3/admin/userroles/karaokemanager/addrole/\(quarantinedID)")
			XCTAssertEqual(addQuarantined, .badRequest, "adding a role to a quarantined user")
			let auditTarget = try await makeActor(app, "rmaudit", .verified).id
			_ = try await status(tt, .POST, "/api/v3/admin/userroles/karaokemanager/addrole/\(auditTarget)")
			_ = try await status(tt, .POST, "/api/v3/admin/userroles/karaokemanager/removerole/\(auditTarget)")
			_ = try await status(tt, .POST, "/api/v3/admin/userroles/karaokemanager/removerole/\(auditTarget)")  // Already gone: no log entry
			let logged = try await ModeratorAction.query(on: app.db).all().filter { $0.$target.id == auditTarget }
			XCTAssertEqual(
				Set(logged.map { $0.actionType }),
				[.roleAdded, .roleRemoved],
				"role changes should be logged"
			)
			XCTAssertEqual(logged.count, 2, "a no-op removal must not be logged")
		}
	}
}
