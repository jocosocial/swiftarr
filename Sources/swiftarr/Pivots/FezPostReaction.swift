import Fluent
import Foundation

/// A reaction pivot between `User` and `FezPost`.
final class FezPostReaction: Model, @unchecked Sendable {
	static let schema = "fezpost+reactions"

	@ID(key: .id) var id: UUID?
	@Field(key: "emoji") var emoji: String
	@Field(key: "createdAt") var createdAt: Date
	@Field(key: "groupOrder") var groupOrder: UUID

	@Parent(key: "user") var user: User
	@Parent(key: "fezPost") var post: FezPost

	init() {}

	init(_ userID: UUID, _ post: FezPost, emoji: String) throws {
		self.$user.id = userID
		self.$post.id = try post.requireID()
		self.$post.value = post
		self.emoji = PostReactionData.canonicalReaction(emoji)
		self.createdAt = Date()
		self.groupOrder = UUID()
	}
}

struct CreateFezPostReactionSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema(FezPostReaction.schema)
			.id()
			.unique(on: "user", "fezPost", "emoji")
			.field("emoji", .string, .required)
			// Every contributor to a chip shares its first reaction's date and group identifier, which fix the chip's position.
			.field("createdAt", .datetime, .required)
			.field("groupOrder", .uuid, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("fezPost", .int, .required, .references("fezposts", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema(FezPostReaction.schema).delete()
	}
}
