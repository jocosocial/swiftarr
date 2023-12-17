import Fluent
import Foundation

/// A `Pivot` holding a sibllings relation between `User` and another `User`.

final class UserFavorite: Model {
	static let schema = "user+favorite"

	// MARK: Properties

	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	// MARK: Relations

	/// The associated `User` who likes this.
	@Parent(key: "user") var user: User

	/// The associated `Twarrt` that was liked.
	@Parent(key: "favorite") var favorite: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new TwarrtLikes pivot.
	///
	/// - Parameters:
	///   - userID: The ID of the `User` that performed the favorite action..
	///   - favorite: The ID of the `User` that was favorited..
	init(userID: UUID, favoriteUserID: UUID) throws {
		self.$user.id = userID
		self.$favorite.id = favoriteUserID
	}
}

struct CreateUserFavoriteSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("user+favorite")
			.id()
			.unique(on: "user", "favorite")
			.field("user", .uuid, .required, .references("user", "id"))
			.field("favorite", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("user+favorite").delete()
	}
}
