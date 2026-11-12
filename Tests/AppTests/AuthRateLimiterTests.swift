import Fluent
import Redis
import XCTVapor

@testable import swiftarr

// Tests AuthRateLimiter: failed-attempt limits on login, password change, recovery, and account creation.
class AuthRateLimiterTests: XCTestCase, SwiftarrBaseTest {

	// Tests lower the limits to keep request counts small; put the defaults back afterwards.
	override func tearDown() {
		Settings.shared.authRateLimitEnabled = true
		Settings.shared.authRateLimitLoginFailures = 10
		Settings.shared.authRateLimitUsernameFailures = 50
		Settings.shared.authRateLimitIPFailures = 30
		Settings.shared.authRateLimitRecoveryFailures = 5
		super.tearDown()
	}

	private func makeUser(_ app: Application, prefix: String) async throws -> User {
		let user = User(
			username: "\(prefix)-\(UUID().uuidString.prefix(8))",
			password: try Bcrypt.hash("password1", cost: 4),
			recoveryKey: try Bcrypt.hash("recoverykey", cost: 4),
			verification: nil,
			accessLevel: .verified
		)
		try await user.save(on: app.db)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return user
	}

	private func loginHeaders(_ username: String, _ password: String, ip: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: username, password: password)
		headers.add(name: .xForwardedFor, value: ip)
		return headers
	}

	private func login(
		_ app: Application,
		_ username: String,
		_ password: String,
		ip: String,
		expect status: HTTPStatus,
		file: StaticString = #filePath,
		line: UInt = #line
	) async throws {
		try await app.test(.POST, "/api/v3/auth/login", headers: loginHeaders(username, password, ip: ip)) { res async throws in
			XCTAssertEqual(res.status, status, file: file, line: line)
			if status == .tooManyRequests {
				XCTAssertNotNil(res.headers.first(name: "Retry-After"), file: file, line: line)
			}
		}
	}

	private func cleanup(_ app: Application, _ user: User) async throws {
		try await Token.query(on: app.db).filter(\.$user.$id == user.requireID()).delete()
		try await user.delete(on: app.db)
	}

	// MARK: - Login

	func testLogin_LocksUsernameFromOneIP() async throws {
		Settings.shared.authRateLimitLoginFailures = 3
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-uip")
			for _ in 0..<3 {
				try await login(app, user.username, "wrong", ip: "10.0.0.1", expect: .unauthorized)
			}
			try await login(app, user.username, "password1", ip: "10.0.0.1", expect: .tooManyRequests)
			// Another client can still log in to the account.
			try await login(app, user.username, "password1", ip: "10.0.0.2", expect: .ok)
			try await cleanup(app, user)
		}
	}

	func testLogin_SuccessesDoNotCount() async throws {
		Settings.shared.authRateLimitLoginFailures = 3
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-success")
			try await login(app, user.username, "wrong", ip: "10.0.0.3", expect: .unauthorized)
			try await login(app, user.username, "wrong", ip: "10.0.0.3", expect: .unauthorized)
			try await login(app, user.username, "password1", ip: "10.0.0.3", expect: .ok)
			try await login(app, user.username, "wrong", ip: "10.0.0.3", expect: .unauthorized)
			try await login(app, user.username, "wrong", ip: "10.0.0.3", expect: .tooManyRequests)
			try await cleanup(app, user)
		}
	}

	func testLogin_UsernameLimitAppliesAcrossIPs() async throws {
		Settings.shared.authRateLimitUsernameFailures = 3
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-user")
			for octet in 1...3 {
				try await login(app, user.username, "wrong", ip: "10.0.1.\(octet)", expect: .unauthorized)
			}
			try await login(app, user.username, "password1", ip: "10.0.1.4", expect: .tooManyRequests)
			try await cleanup(app, user)
		}
	}

	func testLogin_IPLimitAppliesAcrossUsernames() async throws {
		Settings.shared.authRateLimitIPFailures = 3
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-ip")
			for index in 1...3 {
				try await login(app, "nobody-\(index)-\(UUID().uuidString.prefix(8))", "wrong", ip: "10.0.2.1", expect: .unauthorized)
			}
			try await login(app, user.username, "password1", ip: "10.0.2.1", expect: .tooManyRequests)
			try await cleanup(app, user)
		}
	}

	func testLogin_OffSwitchDisablesLimits() async throws {
		Settings.shared.authRateLimitEnabled = false
		Settings.shared.authRateLimitLoginFailures = 1
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-off")
			for _ in 0..<3 {
				try await login(app, user.username, "wrong", ip: "10.0.3.1", expect: .unauthorized)
			}
			try await login(app, user.username, "password1", ip: "10.0.3.1", expect: .ok)
			let attempts = try await authRateLimitCount(app, .usernameAndIP(user.username, "10.0.3.1"))
			XCTAssertEqual(attempts, 0, "nothing is counted while rate limiting is off")
			try await cleanup(app, user)
		}
	}

	// MARK: - Password change

	func testPasswordChange_WrongCurrentPasswordCountsAsFailedLogin() async throws {
		Settings.shared.authRateLimitLoginFailures = 2
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-pwchange")
			let token = try Token.generate(for: user)
			try await token.save(on: app.db)
			try await app.initializeUserCache(app)
			var headers = HTTPHeaders()
			headers.bearerAuthorization = BearerAuthorization(token: token.token)
			headers.add(name: .xForwardedFor, value: "10.0.4.1")

			for (current, status) in [("wrong", HTTPStatus.badRequest), ("wrong", .badRequest), ("password1", .tooManyRequests)] {
				try await app.test(
					.POST,
					"/api/v3/user/password",
					headers: headers,
					beforeRequest: { req async throws in
						try req.content.encode(UserPasswordData(currentPassword: current, newPassword: "newpassword1"))
					},
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, status)
					}
				)
			}
			// The same limit then applies to logging in.
			try await login(app, user.username, "password1", ip: "10.0.4.1", expect: .tooManyRequests)
			try await cleanup(app, user)
		}
	}

	// MARK: - Recovery

	// An unknown username locks out exactly like a real one, so a lockout doesn't reveal whether the account exists.
	func testRecovery_UnknownUsernameLocksLikeRealOne() async throws {
		Settings.shared.authRateLimitRecoveryFailures = 2
		try await withApp { app in
			let username = "rl-ghost-\(UUID().uuidString.prefix(8))"
			let statuses: [HTTPStatus] = [.badRequest, .badRequest, .tooManyRequests]
			for status in statuses {
				try await app.test(
					.POST,
					"/api/v3/auth/recovery",
					headers: ["X-Forwarded-For": "10.0.5.1"],
					beforeRequest: { req async throws in
						try req.content.encode(
							UserRecoveryData(username: username, recoveryKey: "zzz999", newPassword: "newpassword1")
						)
					},
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, status)
					}
				)
			}
		}
	}

	// MARK: - Account creation

	func testCreate_BadRegistrationCodesCountAgainstIP() async throws {
		Settings.shared.authRateLimitIPFailures = 2
		try await withApp { app in
			let statuses: [HTTPStatus] = [.badRequest, .badRequest, .tooManyRequests]
			for status in statuses {
				let code = "q" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(5).lowercased()
				try await app.test(
					.POST,
					"/api/v3/user/create",
					headers: ["X-Forwarded-For": "10.0.6.1"],
					beforeRequest: { req async throws in
						try req.content.encode(
							UserCreateData(
								username: "rl-create-\(UUID().uuidString.prefix(8))",
								password: "password1",
								verification: code,
								agreeToTerms: true
							)
						)
					},
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, status)
					}
				)
			}
		}
	}

	// MARK: - Redis counters

	// Concurrent attempts can't all slip past the check: exactly `limit` of them are allowed.
	func testReserve_ConcurrentAttemptsCannotExceedLimit() async throws {
		try await withApp { app in
			let bucket = "test-concurrent-\(UUID().uuidString)"
			let allowed = try await withThrowingTaskGroup(of: Int.self) { group in
				for _ in 0..<20 {
					group.addTask {
						try await app.redis.reserveAuthAttempt(bucket, limit: 5, window: 60, baseLockout: 60, maxLockout: 600).wait
					}
				}
				var allowed = 0
				for try await wait in group where wait == 0 {
					allowed += 1
				}
				return allowed
			}
			XCTAssertEqual(allowed, 5)
			try await app.redis.clearAuthRateLimit(bucket)
		}
	}

	// Only the attempt that triggers a lockout reports its count, so the lockout is logged once.
	func testReserve_OnlyLockingAttemptReportsCount() async throws {
		try await withApp { app in
			let bucket = "test-lockcount-\(UUID().uuidString)"
			func reserve() async throws -> (wait: Int, lockedAtCount: Int?) {
				try await app.redis.reserveAuthAttempt(bucket, limit: 2, window: 60, baseLockout: 60, maxLockout: 600)
			}
			for _ in 0..<2 {
				let allowed = try await reserve()
				XCTAssertEqual(allowed.wait, 0)
				XCTAssertNil(allowed.lockedAtCount)
			}
			let locking = try await reserve()
			XCTAssertEqual(locking.wait, 60)
			XCTAssertEqual(locking.lockedAtCount, 3)
			let whileLocked = try await reserve()
			XCTAssertGreaterThan(whileLocked.wait, 0)
			XCTAssertNil(whileLocked.lockedAtCount, "attempts against an already locked bucket aren't reported again")
			try await app.redis.clearAuthRateLimit(bucket)
		}
	}

	func testReserve_LockoutDoublesAndCaps() async throws {
		try await withApp { app in
			let bucket = "test-doubling-\(UUID().uuidString)"
			func reserve() async throws -> Int {
				try await app.redis.reserveAuthAttempt(bucket, limit: 1, window: 60, baseLockout: 60, maxLockout: 150).wait
			}
			func expireLock() async throws {
				_ = try await app.redis.delete(RedisKey("authlimit-lock:\(bucket)")).get()
			}
			var first = try await reserve()
			XCTAssertEqual(first, 0)
			first = try await reserve()
			XCTAssertEqual(first, 60)
			try await expireLock()
			_ = try await reserve()
			let second = try await reserve()
			XCTAssertEqual(second, 120, "each lockout within a day lasts twice as long as the last")
			try await expireLock()
			_ = try await reserve()
			let third = try await reserve()
			XCTAssertEqual(third, 150, "lockouts are capped")
			try await app.redis.clearAuthRateLimit(bucket)
		}
	}

	// MARK: - Clearing lockouts

	private func makeStaffToken(_ app: Application, accessLevel: UserAccessLevel) async throws -> (User, HTTPHeaders) {
		let user = User(
			username: "rl-staff-\(UUID().uuidString.prefix(8))",
			password: try Bcrypt.hash("password1", cost: 4),
			recoveryKey: try Bcrypt.hash("recoverykey", cost: 4),
			verification: nil,
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		try await app.initializeUserCache(app)
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token.token)
		return (user, headers)
	}

	func testClearLockouts_ClearsOnlyLockedBuckets() async throws {
		Settings.shared.authRateLimitLoginFailures = 1
		try await withApp { app in
			let user = try await makeUser(app, prefix: "rl-clear")
			// Lock this username out from two IPs.
			for ip in ["10.0.7.1", "10.0.7.2"] {
				try await login(app, user.username, "wrong", ip: ip, expect: .unauthorized)
				try await login(app, user.username, "wrong", ip: ip, expect: .tooManyRequests)
			}
			let attemptsBefore = try await authRateLimitCount(app, .username(user.username))
			let (staff, staffHeaders) = try await makeStaffToken(app, accessLevel: .twitarrteam)

			try await app.test(.POST, "/api/v3/admin/authratelimits/clear", headers: staffHeaders) { res async throws in
				XCTAssertEqual(res.status, .ok)
				XCTAssertEqual(try res.content.decode(AuthRateLimitClearData.self).clearedCount, 2)
			}
			try await login(app, user.username, "password1", ip: "10.0.7.1", expect: .ok)
			// The per-username count across all IPs hadn't reached its limit, so it keeps counting.
			let attemptsAfter = try await authRateLimitCount(app, .username(user.username))
			XCTAssertEqual(attemptsAfter, attemptsBefore)
			try await cleanup(app, staff)
			try await cleanup(app, user)
		}
	}

	func testClearLockouts_RequiresTwitarrTeam() async throws {
		try await withApp { app in
			let (user, headers) = try await makeStaffToken(app, accessLevel: .moderator)
			try await app.test(.POST, "/api/v3/admin/authratelimits/clear", headers: headers) { res async throws in
				XCTAssertEqual(res.status, .forbidden)
			}
			try await cleanup(app, user)
		}
	}

	// MARK: - Client IP

	func testClientIP_UsesRightmostForwardedFor() async throws {
		try await withApp { app in
			let req = Request(application: app, on: app.eventLoopGroup.next())
			req.headers.add(name: .xForwardedFor, value: "1.2.3.4, 10.0.0.9")
			XCTAssertEqual(req.rateLimitClientIP, "10.0.0.9")
		}
	}
}
