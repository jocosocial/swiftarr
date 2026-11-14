import Fluent
import Testing
import XCTVapor

@testable import swiftarr

// Tests the single-use guarantee on registration codes in account recovery.
//
// A spent registration code is disabled by prefixing the stored `verification` with '*'.
// Recovery must not accept either form of a spent code, while an unspent code still works.
class AuthControllerTests: XCTestCase, SwiftarrBaseTest {

	private func makeRecoveryUser(_ app: Application, username: String, verification: String?) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			verification: verification,
			accessLevel: .verified
		)
		try await user.save(on: app.db)
		return user
	}

	private func recoveryBody(username: String, key: String) -> UserRecoveryData {
		UserRecoveryData(username: username, recoveryKey: key, newPassword: "newpassword1")
	}

	// A spent code is stored as "*code". Submitting that marked value must not recover the
	// account -- it normalizes to 7 characters, so a length-based guard alone does not catch it.
	func testRecovery_MarkedSpentCodeIsRejected() async throws {
		try await withApp { app in
			let username = "recovery-marked-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "*abc123")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "*abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest, "a spent registration code must not recover the account")
				}
			)
			try await user.delete(on: app.db)
		}
	}

	// The bare form of a spent code must stay rejected too.
	func testRecovery_BareSpentCodeIsRejected() async throws {
		try await withApp { app in
			let username = "recovery-bare-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "*abc123")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest, "a spent registration code must not recover the account")
					let error = try res.content.decode(ErrorResponse.self)
					XCTAssertEqual(error.reason, "account must be recovered using the recovery key or an account manager")
				}
			)
			try await user.delete(on: app.db)
		}
	}

	// Guards the fix against over-correcting: an unspent code must still recover the account.
	func testRecovery_UnspentCodeStillWorks() async throws {
		try await withApp { app in
			let username = "recovery-unspent-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "an unspent registration code must still recover the account")
				}
			)

			// The code is spent by that recovery, so it is marked and cannot be replayed.
			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "*abc123")
			try await user.delete(on: app.db)
		}
	}

	func testRecovery_SpacedCodeIsSpent() async throws {
		try await withApp { app in
			let username = "recovery-spaced-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abcabc")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc abc"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "a spaced registration code must recover the account")
				}
			)

			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "*abcabc")
			try await user.delete(on: app.db)
		}
	}

	func testRecovery_UppercaseSpacedCodeIsSpent() async throws {
		try await withApp { app in
			let username = "recovery-upper-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abcabc")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "ABC ABC"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "an uppercase spaced registration code must recover the account")
				}
			)

			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "*abcabc")
			try await user.delete(on: app.db)
		}
	}

	func testRecovery_NonBreakingSpaceCodeIsSpent() async throws {
		try await withApp { app in
			let username = "recovery-nbsp-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abcabc")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc\u{00A0}abc"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "a registration code with a non-breaking space must recover the account")
				}
			)

			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "*abcabc")
			try await user.delete(on: app.db)
		}
	}

	func testRecovery_SpacedSpentCodeIsRejected() async throws {
		try await withApp { app in
			let username = "recovery-spaced-spent-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "*abcabc")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc abc"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest, "a spent spaced registration code must not recover the account")
				}
			)
			try await user.delete(on: app.db)
		}
	}

	// A spent code that doesn't match the account gets the generic failure and counts as an attempt; only a caller
	// who submitted the right code learns that it was already spent.
	func testRecovery_WrongCodeOnSpentAccount_IsGenericAndCounted() async throws {
		try await withApp { app in
			let username = "recovery-spent-wrong-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "*abc123")

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "zzz999"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
					let error = try res.content.decode(ErrorResponse.self)
					XCTAssertEqual(error.reason, "no match for supplied recovery key")
				}
			)

			let attempts = await authRateLimitCount(app, .recovery(username))
			XCTAssertEqual(attempts, 1)
			try await user.delete(on: app.db)
		}
	}

	// MARK: - Recovery: username existence

	// An unknown username must fail exactly like a wrong key on a real account.
	func testRecovery_UnknownUsername_MatchesWrongKeyResponse() async throws {
		try await withApp { app in
			let username = "recovery-known-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")
			var wrongKeyReason: String?

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "not the key"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
					wrongKeyReason = try res.content.decode(ErrorResponse.self).reason
				}
			)
			for key in ["not the key", "zzz999"] {
				try await app.test(
					.POST,
					"/api/v3/auth/recovery",
					beforeRequest: { req async throws in
						try req.content.encode(recoveryBody(username: "nobody-\(UUID().uuidString.prefix(8))", key: key))
					},
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, .badRequest)
						let error = try res.content.decode(ErrorResponse.self)
						XCTAssertEqual(error.reason, wrongKeyReason, "unknown usernames must not be distinguishable")
					}
				)
			}
			try await user.delete(on: app.db)
		}
	}

	// A banned account must not reveal its ban to a caller who doesn't hold the credentials.
	func testRecovery_BannedUserWrongKey_IsGeneric() async throws {
		try await withApp { app in
			let username = "recovery-banned-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")
			user.accessLevel = .banned
			try await user.save(on: app.db)

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "not the key"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
				}
			)
			try await user.delete(on: app.db)
		}
	}

	// Correct credentials on a banned account are still refused, and the password is left unchanged.
	func testRecovery_BannedUserRightKey_IsForbidden() async throws {
		try await withApp { app in
			let username = "recovery-banned-ok-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")
			user.accessLevel = .banned
			try await user.save(on: app.db)

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden)
				}
			)

			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertTrue(try Bcrypt.verify("password1", created: reloaded?.password ?? ""))
			XCTAssertEqual(reloaded?.verification, "abc123", "a refused recovery must not spend the code")
			try await user.delete(on: app.db)
		}
	}

	// MARK: - Token revocation

	private func bootCache(_ app: Application) async throws {
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
	}

	private func makeToken(_ app: Application, for user: User) async throws -> String {
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return token.token
	}

	private func tokens(for user: User, on app: Application) async throws -> [String] {
		try await Token.query(on: app.db).filter(\.$user.$id == user.requireID()).all().map(\.token)
	}

	// Recovery must log out whoever holds the old token, and hand back a different one.
	func testRecovery_RevokesExistingToken() async throws {
		try await withApp { app in
			let username = "recovery-revoke-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")
			let oldToken = try await makeToken(app, for: user)
			try await bootCache(app)

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let tokenData = try res.content.decode(TokenStringData.self)
					XCTAssertNotEqual(tokenData.token, oldToken)
					let stored = try await tokens(for: user, on: app)
					XCTAssertEqual(stored, [tokenData.token], "only the new token may remain")
				}
			)

			var headers = HTTPHeaders()
			headers.bearerAuthorization = BearerAuthorization(token: oldToken)
			try await app.test(.GET, "/api/v3/user/whoami", headers: headers) { res async throws in
				XCTAssertEqual(res.status, .unauthorized, "the old token must stop working")
			}
			try await Token.query(on: app.db).filter(\.$user.$id == user.requireID()).delete()
			try await user.delete(on: app.db)
		}
	}

	// A password change revokes the old token and returns a new one that works.
	func testPasswordChange_RotatesToken() async throws {
		try await withApp { app in
			let username = "pwchange-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")
			let oldToken = try await makeToken(app, for: user)
			try await bootCache(app)
			var oldHeaders = HTTPHeaders()
			oldHeaders.bearerAuthorization = BearerAuthorization(token: oldToken)
			var newToken: String?

			try await app.test(
				.POST,
				"/api/v3/user/password",
				headers: oldHeaders,
				beforeRequest: { req async throws in
					try req.content.encode(UserPasswordData(currentPassword: "password1", newPassword: "newpassword1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .created)
					let tokenData = try res.content.decode(TokenStringData.self)
					XCTAssertNotEqual(tokenData.token, oldToken)
					newToken = tokenData.token
				}
			)

			try await app.test(.GET, "/api/v3/user/whoami", headers: oldHeaders) { res async throws in
				XCTAssertEqual(res.status, .unauthorized, "the old token must stop working")
			}
			var newHeaders = HTTPHeaders()
			newHeaders.bearerAuthorization = BearerAuthorization(token: try XCTUnwrap(newToken))
			try await app.test(.GET, "/api/v3/user/whoami", headers: newHeaders) { res async throws in
				XCTAssertEqual(res.status, .ok, "the new token must work")
			}
			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertTrue(try Bcrypt.verify("newpassword1", created: reloaded?.password ?? ""))
			try await Token.query(on: app.db).filter(\.$user.$id == user.requireID()).delete()
			try await user.delete(on: app.db)
		}
	}

	// MARK: - Username lookup

	private func uniqueRegCode() -> String {
		String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
	}

	private func makeLookupUser(
		_ app: Application,
		username: String,
		verification: String?,
		password: String = "password1",
		recoveryKey: String = "recoverykey",
		parentID: UUID? = nil
	) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash(password),
			recoveryKey: try Bcrypt.hash(recoveryKey),
			verification: verification,
			accessLevel: .verified
		)
		if let parentID {
			user.$parent.id = parentID
		}
		try await user.save(on: app.db)
		return user
	}

	private func lookupBody(code: String, key: String) -> UserUsernameLookupData {
		UserUsernameLookupData(registrationCode: code, recoveryKey: key)
	}

	func testUsernameLookup_PasswordMatch() async throws {
		try await withApp { app in
			let username = "lookup-pw-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: code)

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let header = try res.content.decode(UserHeader.self)
					XCTAssertEqual(header.username, username)
					XCTAssertEqual(header.userID, try user.requireID())
				}
			)

			// Lookup must not spend the registration code.
			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, code)
			try await user.delete(on: app.db)
		}
	}

	func testUsernameLookup_RecoveryKeyMatch() async throws {
		try await withApp { app in
			let username = "lookup-rk-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: code)
			let spaced = "\(code.prefix(3)) \(code.suffix(3))".uppercased()

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: spaced, key: "recovery key"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let header = try res.content.decode(UserHeader.self)
					XCTAssertEqual(header.username, username)
				}
			)
			try await user.delete(on: app.db)
		}
	}

	func testUsernameLookup_SpentCodeStillWorks() async throws {
		try await withApp { app in
			let username = "lookup-spent-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: "*" + code)

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok, "a spent registration code must still look up the username")
					let header = try res.content.decode(UserHeader.self)
					XCTAssertEqual(header.username, username)
				}
			)

			let reloaded = try await User.find(user.requireID(), on: app.db)
			XCTAssertEqual(reloaded?.verification, "*" + code)
			try await user.delete(on: app.db)
		}
	}

	func testUsernameLookup_RegistrationCodeAsBothFactors_Rejected() async throws {
		try await withApp { app in
			let username = "lookup-both-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: code)

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: code))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
					let error = try res.content.decode(ErrorResponse.self)
					XCTAssertTrue(
						error.reason.contains("cannot be a registration code"),
						"reason=\(error.reason)"
					)
				}
			)
			try await user.delete(on: app.db)
		}
	}

	func testUsernameLookup_WrongPassword_NotFound() async throws {
		try await withApp { app in
			let username = "lookup-wrong-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: code)

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "not-the-password"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
					let error = try res.content.decode(ErrorResponse.self)
					XCTAssertEqual(error.reason, "no match for supplied credentials")
				}
			)

			let attempts = await authRateLimitCount(app, .usernameLookup(code))
			XCTAssertEqual(attempts, 1)
			try await user.delete(on: app.db)
		}
	}

	func testUsernameLookup_UnknownCode_NotFound() async throws {
		try await withApp { app in
			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: uniqueRegCode(), key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest)
					let error = try res.content.decode(ErrorResponse.self)
					XCTAssertEqual(error.reason, "no match for supplied credentials")
				}
			)
		}
	}

	func testUsernameLookup_AltPasswordReturnsAlt() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8)
			let code = uniqueRegCode()
			let primary = try await makeLookupUser(
				app,
				username: "lookup-pri-\(suffix)",
				verification: code,
				password: "primarypw"
			)
			let alt = try await makeLookupUser(
				app,
				username: "lookup-alt-\(suffix)",
				verification: code,
				password: "altpasswd",
				parentID: try primary.requireID()
			)

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "altpasswd"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let header = try res.content.decode(UserHeader.self)
					XCTAssertEqual(header.username, alt.username)
					XCTAssertEqual(header.userID, try alt.requireID())
				}
			)
			try await alt.delete(on: app.db)
			try await primary.delete(on: app.db)
		}
	}

	func testUsernameLookup_RecoveryKeyReturnsPrimary() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8)
			let code = uniqueRegCode()
			let primary = try await makeLookupUser(
				app,
				username: "lookup-rkpri-\(suffix)",
				verification: code
			)
			let alt = try await makeLookupUser(
				app,
				username: "lookup-rkalt-\(suffix)",
				verification: code,
				password: "altpasswd",
				parentID: try primary.requireID()
			)

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "recovery key"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let header = try res.content.decode(UserHeader.self)
					XCTAssertEqual(header.username, primary.username)
				}
			)
			try await alt.delete(on: app.db)
			try await primary.delete(on: app.db)
		}
	}

	func testUsernameLookup_SuccessfulLookupDoesNotResetAttempts() async throws {
		try await withApp { app in
			let username = "lookup-keep-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: code)
			for _ in 0..<2 {
				try await app.test(
					.POST,
					"/api/v3/auth/username",
					beforeRequest: { req async throws in
						try req.content.encode(lookupBody(code: code, key: "not-the-password"))
					},
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, .badRequest)
					}
				)
			}

			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
				}
			)

			let attempts = await authRateLimitCount(app, .usernameLookup(code))
			XCTAssertEqual(attempts, 2, "a successful lookup must not count, or clear earlier failures")
			try await user.delete(on: app.db)
		}
	}

	func testUsernameLookup_LockoutAfterFiveFailures() async throws {
		try await withApp { app in
			let username = "lookup-lock-\(UUID().uuidString.prefix(8))"
			let code = uniqueRegCode()
			let user = try await makeLookupUser(app, username: username, verification: code)
			for _ in 0..<5 {
				try await app.test(
					.POST,
					"/api/v3/auth/username",
					beforeRequest: { req async throws in
						try req.content.encode(lookupBody(code: code, key: "not-the-password"))
					},
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, .badRequest)
					}
				)
			}

			// Even the right password is refused while the code is locked out.
			try await app.test(
				.POST,
				"/api/v3/auth/username",
				beforeRequest: { req async throws in
					try req.content.encode(lookupBody(code: code, key: "password1"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .tooManyRequests)
					XCTAssertNotNil(res.headers.first(name: "Retry-After"))
				}
			)
			try await user.delete(on: app.db)
		}
	}
}
