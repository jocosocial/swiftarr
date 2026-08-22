import Testing
import XCTVapor

@testable import swiftarr

// Staff account lookup and one-time registration-code recovery unlock (issue #520).
class AdminAccountManagementTests: XCTestCase, SwiftarrBaseTest {

	private func makeUser(
		_ app: Application,
		username: String,
		accessLevel: UserAccessLevel,
		verification: String? = nil,
		recoveryAttempts: Int = 0
	) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			verification: verification,
			accessLevel: accessLevel,
			recoveryAttempts: recoveryAttempts
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

	private func recoveryBody(username: String, key: String) -> UserRecoveryData {
		UserRecoveryData(username: username, recoveryKey: key, newPassword: "newpassword1")
	}

	private func bootCache(_ app: Application) async throws {
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
	}

	func testFindByUser_ReportsSpentRecovery() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "acctmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: staff.requireID(), role: .accountmanager).create(on: app.db)
			let target = try await makeUser(
				app,
				username: "spent-\(suffix)",
				accessLevel: .verified,
				verification: "*abc123"
			)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/admin/regcodes/findbyuser/\(try target.requireID())",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(RegistrationCodeUserData.self)
					XCTAssertTrue(data.hasUsedRegCodeForPasswordRecovery)
					XCTAssertNotNil(data.accountCreatedAt)
				}
			)
		}
	}

	func testFindByUser_ReportsUnspentRecovery() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "acctmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: staff.requireID(), role: .accountmanager).create(on: app.db)
			let target = try await makeUser(
				app,
				username: "unspent-\(suffix)",
				accessLevel: .verified,
				verification: "abc123"
			)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/admin/regcodes/findbyuser/\(try target.requireID())",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(RegistrationCodeUserData.self)
					XCTAssertFalse(data.hasUsedRegCodeForPasswordRecovery)
				}
			)
		}
	}

	func testUnlock_ForbiddenWithoutRole() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let verified = try await makeUser(app, username: "verified-\(suffix)", accessLevel: .verified)
			let target = try await makeUser(
				app,
				username: "target-\(suffix)",
				accessLevel: .verified,
				verification: "*abc123"
			)
			let verifiedToken = try await makeToken(app, for: verified)
			try await bootCache(app)

			try await app.test(
				.POST,
				"/api/v3/admin/regcodes/unlock/\(try target.requireID())",
				headers: bearer(verifiedToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden)
				}
			)
		}
	}

	func testUnlock_AllowedForAccountManager() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "acctmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: staff.requireID(), role: .accountmanager).create(on: app.db)
			let target = try await makeUser(
				app,
				username: "unlock-mgr-\(suffix)",
				accessLevel: .verified,
				verification: "*abc123"
			)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.POST,
				"/api/v3/admin/regcodes/unlock/\(try target.requireID())",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(RegistrationCodeUserData.self)
					XCTAssertFalse(data.hasUsedRegCodeForPasswordRecovery)
				}
			)

			let reloaded = try await User.find(target.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "abc123")
		}
	}

	func testUnlock_AllowedForTwitarrTeam() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "tt-\(suffix)", accessLevel: .twitarrteam)
			let target = try await makeUser(
				app,
				username: "unlock-tt-\(suffix)",
				accessLevel: .verified,
				verification: "*abc123"
			)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.POST,
				"/api/v3/admin/regcodes/unlock/\(try target.requireID())",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
				}
			)

			let reloaded = try await User.find(target.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "abc123")
		}
	}

	func testUnlock_SpentCodeRecoversAgain() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "acctmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: staff.requireID(), role: .accountmanager).create(on: app.db)
			let username = "recover-again-\(suffix)"
			let target = try await makeUser(
				app,
				username: username,
				accessLevel: .verified,
				verification: "*abc123"
			)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.POST,
				"/api/v3/admin/regcodes/unlock/\(try target.requireID())",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
				}
			)

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "an unlocked registration code must recover the account")
				}
			)

			let reloaded = try await User.find(target.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "*abc123")
		}
	}

	func testUnlock_ClearsRecoveryAttemptsLockout() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "acctmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: staff.requireID(), role: .accountmanager).create(on: app.db)
			let username = "lockout-\(suffix)"
			let target = try await makeUser(
				app,
				username: username,
				accessLevel: .verified,
				verification: "abc123",
				recoveryAttempts: 5
			)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden, "five failed recoveries must lock the account")
				}
			)

			try await app.test(
				.POST,
				"/api/v3/admin/regcodes/unlock/\(try target.requireID())",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
				}
			)

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "unlock must clear the recovery-attempts lockout")
				}
			)
		}
	}

	func testFind_SpacedCodeMatchesUnspaced() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(5).lowercased()
			let code = "t\(suffix)"
			let staff = try await makeUser(app, username: "acctmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: staff.requireID(), role: .accountmanager).create(on: app.db)
			let target = try await makeUser(
				app,
				username: "find-space-\(suffix)",
				accessLevel: .verified,
				verification: code
			)
			let record = RegistrationCode(code: code)
			record.$user.id = try target.requireID()
			try await record.save(on: app.db)
			let staffToken = try await makeToken(app, for: staff)
			try await bootCache(app)

			let spaced = "\(code.prefix(3))%20\(code.dropFirst(3))"
			try await app.test(
				.GET,
				"/api/v3/admin/regcodes/find/\(spaced)",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let headers = try res.content.decode([UserHeader].self)
					XCTAssertEqual(headers.first?.userID, try target.requireID())
				}
			)

			try await app.test(
				.GET,
				"/api/v3/admin/regcodes/find/\(code)",
				headers: bearer(staffToken),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let headers = try res.content.decode([UserHeader].self)
					XCTAssertEqual(headers.first?.userID, try target.requireID())
				}
			)
		}
	}
}
