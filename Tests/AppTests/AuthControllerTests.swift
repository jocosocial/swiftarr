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
			defer { Task { try? await user.delete(on: app.db) } }

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
		}
	}

	// The bare form of a spent code must stay rejected too.
	func testRecovery_BareSpentCodeIsRejected() async throws {
		try await withApp { app in
			let username = "recovery-bare-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "*abc123")
			defer { Task { try? await user.delete(on: app.db) } }

			try await app.test(
				.POST,
				"/api/v3/auth/recovery",
				beforeRequest: { req async throws in
					try req.content.encode(recoveryBody(username: username, key: "abc123"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .badRequest, "a spent registration code must not recover the account")
				}
			)
		}
	}

	// Guards the fix against over-correcting: an unspent code must still recover the account.
	func testRecovery_UnspentCodeStillWorks() async throws {
		try await withApp { app in
			let username = "recovery-unspent-\(UUID().uuidString.prefix(8))"
			let user = try await makeRecoveryUser(app, username: username, verification: "abc123")
			defer { Task { try? await user.delete(on: app.db) } }

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
		}
	}
}
