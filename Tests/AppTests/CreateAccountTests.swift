import Fluent
import XCTVapor
@testable import swiftarr

// Consent-checkbox gate on account creation (issue #610).
//
// `createAccountPostHandler` collects form validation failures and throws a 403
// `ErrorResponse`, but its own catch block re-renders `Login/createAccount` with the
// field errors embedded in the page, so a rejected submission comes back as a 200 HTML
// view, not a JSON error. These tests assert against the rendered page: the consent
// error text is present when the checkbox isn't checked and absent when it is. The
// success path past the gate (`apiQuery` -> POST /api/v3/user/create) makes a real
// HTTP call to the API server, which isn't running in tests, so the deepest in-process
// assertion is "the request got past the consent gate."
final class CreateAccountTests: XCTestCase, SwiftarrBaseTest {

	private static let consentErrorText = "You must confirm that you have read and agree to the terms of use before creating an account"
	private static let username = "consentuser"

	/// Build an `application/x-www-form-urlencoded` body for the Create Account form.
	/// Omitting `agreeToTerms` simulates an unchecked checkbox.
	private static func formBody(agreeToTerms: String?) -> ByteBuffer {
		var fields: [(String, String)] = [
			("regcode", "abc123"),
			("username", username),
			("password", "password123"),
			("passwordConfirm", "password123")
		]
		if let agreeToTerms {
			fields.append(("agreeToTerms", agreeToTerms))
		}
		let body = fields
			.map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)" }
			.joined(separator: "&")
		return ByteBuffer(string: body)
	}

	/// POST `/createAccount` and hand the rendered response to `afterResponse` for assertions.
	private func postCreateAccount(
		_ app: Application,
		agreeToTerms: String? = nil,
		afterResponse: (XCTHTTPResponse) async throws -> ()
	) async throws {
		try await app.test(
			.POST,
			"/createAccount",
			headers: ["Content-Type": "application/x-www-form-urlencoded"],
			body: Self.formBody(agreeToTerms: agreeToTerms),
			afterResponse: afterResponse
		)
	}

	private func noUserCreated(_ app: Application) async throws {
		let user = try await User.query(on: app.db)
			.filter(\.$username == Self.username)
			.first()
		XCTAssertNil(user, "no user may be created without consent")
	}

	// MARK: - Rejection

	func testCreateAccountWithoutConsentCheckbox_IsRejected() async throws {
		try await withApp { app in
			try await postCreateAccount(app) { res async throws in
				XCTAssertEqual(res.status, .ok, "rejected submissions are re-rendered as a 200 HTML view carrying the field errors")
				let html = String(buffer: res.body)
				XCTAssertTrue(html.contains(Self.consentErrorText), "the page must show the consent field error")
			}
			try await noUserCreated(app)
		}
	}

	func testCreateAccountWithEmptyConsentField_IsRejected() async throws {
		try await withApp { app in
			try await postCreateAccount(app, agreeToTerms: "") { res async throws in
				XCTAssertEqual(res.status, .ok)
				let html = String(buffer: res.body)
				XCTAssertTrue(html.contains(Self.consentErrorText), "an empty field is the same as an unchecked box")
			}
			try await noUserCreated(app)
		}
	}

	// MARK: - Gate opened

	func testCreateAccountWithConsent_PassesTheConsentGate() async throws {
		try await withApp { app in
			try await postCreateAccount(app, agreeToTerms: "true") { res async throws in
				XCTAssertEqual(res.status, .ok)
				let html = String(buffer: res.body)
				XCTAssertFalse(
					html.contains(Self.consentErrorText),
					"with the checkbox checked the request must pass the consent gate (it then fails later in apiQuery, which has no server to reach in tests)"
				)
			}
		}
	}

	// MARK: - API endpoint gate (POST /api/v3/user/create)

	// The same consent requirement is enforced by the API itself, so clients that call
	// `POST /api/v3/user/create` directly must send `agreeToTerms: true`.

	/// Build the JSON body for the API account creation endpoint.
	private static func apiCreateBody(username: String, agreeToTerms: Bool?, verification: String = "abc123") -> UserCreateData {
		UserCreateData(
			username: username,
			password: "password123",
			verification: verification,
			agreeToTerms: agreeToTerms
		)
	}

	/// POST `/api/v3/user/create` and hand the response to `afterResponse` for assertions.
	private func postUserCreate(
		_ app: Application,
		agreeToTerms: Bool?,
		username: String,
		verification: String = "abc123",
		afterResponse: (XCTHTTPResponse) async throws -> ()
	) async throws {
		try await app.test(
			.POST,
			"/api/v3/user/create",
			beforeRequest: { req async throws in
				try req.content.encode(Self.apiCreateBody(username: username, agreeToTerms: agreeToTerms, verification: verification))
			},
			afterResponse: afterResponse
		)
	}

	private func userNamed(_ username: String, on app: Application) async throws -> User? {
		try await User.query(on: app.db)
			.filter(\.$username == username)
			.first()
	}

	private func uniqueName(_ prefix: String) -> String {
		prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
	}

	func testUserCreateAPI_WithoutAgreeToTerms_IsRejected() async throws {
		try await withApp { app in
			let username = uniqueName("apiconsent")
			try await postUserCreate(app, agreeToTerms: nil, username: username) { res async throws in
				XCTAssertEqual(res.status, .badRequest, "a missing agreeToTerms field must be rejected")
			}
			let user = try await userNamed(username, on: app)
			XCTAssertNil(user, "no user may be created without consent")
		}
	}

	func testUserCreateAPI_WithAgreeToTermsFalse_IsRejected() async throws {
		try await withApp { app in
			let username = uniqueName("apiconsent")
			try await postUserCreate(app, agreeToTerms: false, username: username) { res async throws in
				XCTAssertEqual(res.status, .badRequest, "an explicit refusal must be rejected")
			}
			let user = try await userNamed(username, on: app)
			XCTAssertNil(user, "no user may be created without consent")
		}
	}

	func testUserCreateAPI_WithAgreeToTermsTrue_CreatesUser() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(5).lowercased()
			let username = uniqueName("apiconsent")
			// createHandler consumes the registration code; seed a fresh, unique one.
			let code = "t\(suffix)"
			let regCode = RegistrationCode(code: code)
			try await regCode.save(on: app.db)
			try await postUserCreate(app, agreeToTerms: true, username: username, verification: code) { res async throws in
				XCTAssertEqual(res.status, .created)
				let created = try res.content.decode(CreatedUserData.self)
				let user = try await userNamed(username, on: app)
				XCTAssertEqual(created.username, username)
				XCTAssertEqual(created.userID, user?.id)
			}
			let user = try await userNamed(username, on: app)
			XCTAssertNotNil(user, "consent plus a valid registration code must create the user")
			XCTAssertEqual(user?.verification, code, "the user must be created with the consumed registration code")
			let spentCode = try await RegistrationCode.query(on: app.db).with(\.$user).filter(\.$code == code).first()
			XCTAssertEqual(spentCode?.user?.id, user?.id, "the registration code must be linked to the new user")
		}
	}
}