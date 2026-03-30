import Fluent
import Foundation

/// A reaction pivot between `User` and `FezPost`.
final class FezPostReaction: Model, @unchecked Sendable {
	static let schema = "fezpost+reactions"

	@ID(key: .id) var id: UUID?
	@Field(key: "emoji") var emoji: String

	@Parent(key: "user") var user: User
	@Parent(key: "fezPost") var post: FezPost

	init() {}

	init(_ userID: UUID, _ post: FezPost, emoji: String) throws {
		self.$user.id = userID
		self.$post.id = try post.requireID()
		self.$post.value = post
		self.emoji = emoji
	}
}

struct CreateFezPostReactionSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema(FezPostReaction.schema)
			.id()
			.unique(on: "user", "fezPost", "emoji")
			.field("emoji", .string, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("fezPost", .int, .required, .references("fezposts", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema(FezPostReaction.schema).delete()
	}
}
