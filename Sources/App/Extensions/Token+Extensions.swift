import Vapor
import Fluent

// MARK: - BearerAuthenticatable Conformance

extension Token: ModelTokenAuthenticatable {
	/// Required key for HTTP Bearer Authorization token.
	static let valueKey = \Token.$token
	static let userKey = \Token.$user

	var isValid: Bool {
		true
	}
}

// MARK: - Methods

extension Token {
	/// Creates a new random Token.
	///
	/// - Parameter user: The `User` to be associated with this `Token`.
	/// - Parameter length: Desired length of token data, defaults to 16.
	/// - Returns: A `Token` object.
	static func generate(for user: User, length: Int = 16) throws -> Token {
		let random = [UInt8].random(count: length).base64
		return try Token(token: random, user: user)
	}
}

