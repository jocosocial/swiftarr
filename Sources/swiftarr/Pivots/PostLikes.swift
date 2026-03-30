import Fluent
import Foundation

/// A `Pivot` holding a siblings relation between `User` and `ForumPost`.

final class PostLikes: Model, @unchecked Sendable {
	static let schema = "post+likes"

	// MARK: Properties

	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	/// TRUE if this forum post is favorited by this user.
	@Field(key: "favorite") var isFavorite: Bool

	// MARK: Relationships

	/// The associated `User` who likes this.
	@Parent(key: "user") var user: User

	/// The associated `ForumPost` that was liked.
	@Parent(key: "forumPost") var post: ForumPost

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new PostLikes pivot.
	///
	/// - Parameters:
	///   - user: The left hand `User` model.
	///   - post: The right hand `ForumPost` model.
	init(_ userID: UUID, _ post: ForumPost) throws {
		self.$user.id = userID
		self.$post.id = try post.requireID()
		self.$post.value = post
		self.isFavorite = false
	}

}

struct CreatePostLikesSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("post+likes")
			.id()
			.unique(on: "user", "forumPost")
			.field("favorite", .bool, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("forumPost", .int, .required, .references("forumpost", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("post+likes").delete()
	}
}
