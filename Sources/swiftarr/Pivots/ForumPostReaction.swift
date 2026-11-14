import Fluent
import Foundation

/// A reaction pivot between `User` and `ForumPost`.
final class ForumPostReaction: Model, @unchecked Sendable {
	static let schema = "forumpost+reactions"

	@ID(key: .id) var id: UUID?
	@Field(key: "emoji") var emoji: String
	@Field(key: "createdAt") var createdAt: Date
	@Field(key: "groupOrder") var groupOrder: UUID

	@Parent(key: "user") var user: User
	@Parent(key: "forumPost") var post: ForumPost

	init() {}

	init(_ userID: UUID, _ post: ForumPost, emoji: String) throws {
		self.$user.id = userID
		self.$post.id = try post.requireID()
		self.$post.value = post
		self.emoji = PostReactionData.canonicalReaction(emoji)
		self.createdAt = Date()
		self.groupOrder = UUID()
	}
}

struct CreateForumPostReactionSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema(ForumPostReaction.schema)
			.id()
			.unique(on: "user", "forumPost", "emoji")
			.field("emoji", .string, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("forumPost", .int, .required, .references("forumpost", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema(ForumPostReaction.schema).delete()
	}
}
