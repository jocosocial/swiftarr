import Foundation
import Fluent

/// A `Pivot` holding a siblings relation between a `User` and a `Forum`. The pivot tracks how many posts the user has read in the forum.

final class ForumReaders: Model {
	static let schema = "forum+readers"

// MARK: Properties
	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?
	
	/// How many posts in this forum that this user has read.
	@Field(key: "read_count") var readCount: Int
	
	/// TRUE if this forum is favorited by this user.
	@Field(key: "favorite") var isFavorite: Bool
		
// Timestamps
	
	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	
	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
	
// MARK: Relationships
	/// The associated `User` who has read the forum..
	@Parent(key: "user") var user: User

	/// The `Forum` the user has read.
	@Parent(key: "forum") var forum: Forum

// MARK: Initialization
	// Used by Fluent
 	init() { }
 	
	/// Initializes a new `ForumReaders` pivot. The pivot's readCount gets initialized to 0.
	///
	/// - Parameters:
	///   - user: The associated `User` model.
	///   - forum: The associated `Forum` model.
	init(_ userID: UUID, _ forum: Forum) throws {
		self.$user.id = userID
		self.$forum.id = try forum.requireID()
		self.$forum.value = forum
		self.readCount = 0
		self.isFavorite = false
	}
}

struct CreateForumReadersSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("forum+readers")
				.id()
				.unique(on: "user", "forum")
				.field("read_count", .int, .required)
				.field("favorite", .bool, .required)
				.field("created_at", .datetime)
				.field("updated_at", .datetime)
 				.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
  				.field("forum", .uuid, .required, .references("forum", "id", onDelete: .cascade))
				.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("forum+readers").delete()
	}
}
