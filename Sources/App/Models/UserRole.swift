import Fluent
import Foundation
import Vapor

/// A `UserNote` is intended as a free-form test field that will appear on a `UserProfile`,
/// in which the viewing `User` can make notes about the profile's user.
///
/// It is not visible to the profile's owner nor to any other user; it is for the viewing
/// user's use only. In other words, different users viewing the same profile will each see
/// their own viewer-specific `UserNote` text.

final class UserRole: Model {
	static let schema = "user_role"

	// MARK: Properties

	/// The role's ID, provisioned automatically.
	@ID(key: .id) var id: UUID?

	/// Each UserRole object specifies a user and a role, indicating that user has that role.
	@Field(key: "role") var role: UserRoleType

	// MARK: Relations

	/// The `User` that has the role.
	@Parent(key: "user") var user: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Creates a new UserRole.
	///
	/// - Parameters:
	///   - author: The note's author.
	///   - profile: The associated `UserProfile`.
	///   - note: The text of the note.
	init(user: UUID, role: UserRoleType) {
		self.$user.id = user
		self.role = role
	}
}

struct CreateUserRoleSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("user_role")
			.id()
			.field("role", .string, .required)
			.field("user", .uuid, .required, .references("user", "id"))
			.unique(on: "role", "user")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("user_role").delete()
	}
}
