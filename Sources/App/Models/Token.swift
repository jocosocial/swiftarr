import Fluent
import Foundation
import Vapor

/// A `Token` model associates a randomly generated string with a `User`.
///
/// A Token is generated upon each login, and revoked by deletion upon each logout.
/// The `.token` value is used in between those events in an HTTP Bearer Authorization
/// header field to authenticate the user sending API requests. There is no
/// identifying user info in a `.token`; the association to a specific `User` is
/// done internally on the API server through this model.

final class Token: Model {
	static let schema = "token"

	// MARK: Properties

	/// The Token's ID, provisioned automatically.
	@ID(key: .id) var id: UUID?

	/// The generated token value.
	@Field(key: "token") var token: String

	/// The `User` associated to the Token.
	@Parent(key: "user") var user: User

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Initializaton

	// Used by Fluent
	init() {}

	/// Initializes a new Token.
	///
	/// - Parameters:
	///   - token: The generated token string.
	///   - user: The `User` associated to the token.
	init(token: String, user: User) throws {
		self.token = token
		self.$user.id = try user.requireID()
		self.$user.value = user
	}

	/// Initializes a new Token.
	///
	/// - Parameters:
	///   - token: The generated token string.
	///   - userID: The `User` associated to the token.
	init(token: String, userID: UUID) {
		self.token = token
		self.$user.id = userID
	}
}

struct CreateTokenSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("token")
			.id()
			.field("token", .string, .required)
			.field("created_at", .datetime)
			.field("user", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("token").delete()
	}
}
