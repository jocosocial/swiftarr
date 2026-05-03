import XCTVapor
@testable import swiftarr

// Tests for the RCFValidatable conformances on user-facing request structs.
// These exercise the validation logic by feeding JSON through ValidatingJSONDecoder.
class UserStructValidationTests: XCTestCase {

	private let decoder = ValidatingJSONDecoder()

	private func validationErrors<T: Decodable>(_ type: T.Type, _ json: String) throws -> [String] {
		let data = json.data(using: .utf8)!
		let result = try decoder.validate(type, from: data)
		return result?.validationFailures.map { $0.errorString } ?? []
	}

	// MARK: - UserPasswordData

	func testUserPassword_Valid() throws {
		let errs = try validationErrors(
			UserPasswordData.self,
			#"{"currentPassword":"old","newPassword":"newPass1"}"#
		)
		XCTAssertEqual(errs, [])
	}

	func testUserPassword_TooShort_FlagsMin() throws {
		let errs = try validationErrors(
			UserPasswordData.self,
			#"{"currentPassword":"old","newPassword":"abc"}"#
		)
		XCTAssertTrue(errs.contains("password has a 6 character minimum"), "errs=\(errs)")
	}

	func testUserPassword_TooLong_FlagsMax() throws {
		let longPw = String(repeating: "a", count: 51)
		let errs = try validationErrors(
			UserPasswordData.self,
			#"{"currentPassword":"old","newPassword":"\#(longPw)"}"#
		)
		XCTAssertTrue(errs.contains("password has a 50 character limit"), "errs=\(errs)")
	}

	// MARK: - UserUsernameData

	func testUsername_Valid() throws {
		let errs = try validationErrors(UserUsernameData.self, #"{"username":"skyler"}"#)
		XCTAssertEqual(errs, [])
	}

	func testUsername_ValidWithSeparator() throws {
		let errs = try validationErrors(UserUsernameData.self, #"{"username":"sky.ler"}"#)
		XCTAssertEqual(errs, [])
	}

	func testUsername_TooShort() throws {
		let errs = try validationErrors(UserUsernameData.self, #"{"username":"a"}"#)
		XCTAssertTrue(errs.contains("username has a 2 character minimum"), "errs=\(errs)")
	}

	func testUsername_TooLong() throws {
		let long = String(repeating: "a", count: 51)
		let errs = try validationErrors(UserUsernameData.self, #"{"username":"\#(long)"}"#)
		XCTAssertTrue(errs.contains("username has a 50 character limit"), "errs=\(errs)")
	}

	func testUsername_InvalidCharacters() throws {
		let errs = try validationErrors(UserUsernameData.self, #"{"username":"sky ler"}"#)
		XCTAssertTrue(
			errs.contains(where: { $0.starts(with: "username can only contain alphanumeric") }),
			"errs=\(errs)"
		)
	}

	func testUsername_StartsWithSeparator() throws {
		let errs = try validationErrors(UserUsernameData.self, #"{"username":".skyler"}"#)
		XCTAssertTrue(errs.contains("username must start with a letter or number"), "errs=\(errs)")
	}

	func testUsername_EndsWithSeparator() throws {
		let errs = try validationErrors(UserUsernameData.self, #"{"username":"skyler."}"#)
		XCTAssertTrue(
			errs.contains(where: { $0.starts(with: "Username separator chars") }),
			"errs=\(errs)"
		)
	}

	// MARK: - UserVerifyData

	func testUserVerify_Valid6Char() throws {
		let errs = try validationErrors(UserVerifyData.self, #"{"verification":"abc123"}"#)
		XCTAssertEqual(errs, [])
	}

	func testUserVerify_Valid7Char() throws {
		let errs = try validationErrors(UserVerifyData.self, #"{"verification":"abc1234"}"#)
		XCTAssertEqual(errs, [])
	}

	func testUserVerify_TooShort_Fails() throws {
		let errs = try validationErrors(UserVerifyData.self, #"{"verification":"abc"}"#)
		XCTAssertEqual(errs.count, 1)
	}

	func testUserVerify_TooLong_Fails() throws {
		let errs = try validationErrors(UserVerifyData.self, #"{"verification":"abc12345"}"#)
		XCTAssertEqual(errs.count, 1)
	}

	// MARK: - UserCreateData

	private func userCreateJSON(
		username: String = "skyler",
		password: String = "newpass1",
		verification: String? = nil
	) -> String {
		var fields = [
			#""username":"\#(username)""#,
			#""password":"\#(password)""#,
		]
		if let v = verification {
			fields.append(#""verification":"\#(v)""#)
		}
		return "{" + fields.joined(separator: ",") + "}"
	}

	func testUserCreate_Valid_NoVerification() throws {
		XCTAssertEqual(try validationErrors(UserCreateData.self, userCreateJSON()), [])
	}

	func testUserCreate_Valid_WithVerification() throws {
		let json = userCreateJSON(verification: "abc123")
		XCTAssertEqual(try validationErrors(UserCreateData.self, json), [])
	}

	func testUserCreate_Valid_VerificationWithSpaces_NormalizedThenAccepted() throws {
		// "abc 123" → "abc123" after lowercased + space-strip; 6 alphanumeric → valid
		let json = userCreateJSON(verification: "abc 123")
		XCTAssertEqual(try validationErrors(UserCreateData.self, json), [])
	}

	func testUserCreate_PasswordTooShort() throws {
		let errs = try validationErrors(UserCreateData.self, userCreateJSON(password: "abc"))
		XCTAssertTrue(errs.contains("password has a 6 character minimum"), "errs=\(errs)")
	}

	func testUserCreate_BadUsername_PropagatesUsernameValidations() throws {
		let errs = try validationErrors(UserCreateData.self, userCreateJSON(username: "x"))
		XCTAssertTrue(errs.contains("username has a 2 character minimum"), "errs=\(errs)")
	}

	func testUserCreate_VerificationWrongLength_Fails() throws {
		let json = userCreateJSON(verification: "abc1234")
		let errs = try validationErrors(UserCreateData.self, json)
		XCTAssertTrue(errs.contains(where: { $0.contains("Malformed registration code") }), "errs=\(errs)")
	}

	func testUserCreate_VerificationNonAlphanumeric_Fails() throws {
		let json = userCreateJSON(verification: "abc-12")
		let errs = try validationErrors(UserCreateData.self, json)
		XCTAssertTrue(errs.contains(where: { $0.contains("Malformed registration code") }), "errs=\(errs)")
	}
}
