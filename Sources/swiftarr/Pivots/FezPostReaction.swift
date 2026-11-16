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
		self.emoji = emoji
		self.createdAt = Date()
		self.groupOrder = UUID()
	}

	/// Takes the date and group identifier of the post's existing chip for this emoji, if there is one.
	/// Every contributor shares them, so the chip keeps its position even after its first user leaves.
	func adoptChipPosition(on db: Database) async throws {
		if let existing = try await FezPostReaction.query(on: db)
			.filter(\.$post.$id == $post.id).filter(\.$emoji == emoji).first() {
			createdAt = existing.createdAt
			groupOrder = existing.groupOrder
		}
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
