import Vapor
import Fluent

/**
	A collection of `ForumPost`s on a single topic. Only the forum's creator or a moderator can edit a forum's title.
	Only moderators can can change a forum's `moderationStatus`.

	- See Also: [ForumData](ForumData) the DTO for returning detailed info on Forums.
	- See Also: [ForumListData](ForumListData) the DTO for returning basic info on Forums. Mostly, ForumListData does not include posts.
	- See Also: [ForumCreateData](ForumCreateData) the DTO for creating forums.
	- See Also: [CreateForumSchema](CreateForumSchema) the Migration for creating the Forum table in the database.
*/
final class Forum: Model, Searchable {
	static let schema = "forum"

	// MARK: Properties
	
	/// The forum's ID.
	@ID(key: .id) var id: UUID?
	
	/// The title of the forum.
	@Field(key: "title") var title: String
			
	/// The creation time of the last post added to this forum. Used to sort forums. Edits to posts don't count.
	@Field(key:"last_post_time") var lastPostTime: Date
	
	/// Moderators can set several statuses on forums that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus
	
	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	
	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
	
	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
	
	// MARK: Relations
	
	/// The parent `Category` of the forum.
	@Parent(key: "category_id") var category: Category
	
	/// The parent `User` who created the forum.
	@Parent(key: "creator_id") var creator: User
	
	/// The child `ForumPost`s within the forum.
	@Children(for: \.$forum) var posts: [ForumPost]
	
	/// The `ForumReaders` pivots contain read counts for each user who has read this forum thread. 
	@Siblings(through: ForumReaders.self, from: \.$forum, to: \.$user) var readers: [User]

	/// The child `ForumEdit` accountability records of the forum.
	@Children(for: \.$forum) var edits: [ForumEdit]
	
	/// If this forum is for discussing an event on the schedule, this is the event that's the topic of the forum.
	@OptionalChild(for: \.$forum) var scheduleEvent: Event?

	// MARK: Initialization
	
	// Used by Fluent
 	init() { }
 	
	/// Initializes a new Forum.
	///
	/// - Parameters:
	///   - title: The title for the forum.
	///   - categoryID: The category to which the forum belongs.
	///   - creatorID: The ID of the creator of the forum.
	///   - isLocked: Whether the forum is administratively locked.
	init(title: String, category: Category, creatorID: UUID, isLocked: Bool = false) throws {
		self.title = title
		self.$category.id = try category.requireID()
		self.$category.value = category
		self.$creator.id = creatorID
		self.lastPostTime = Date()
		self.moderationStatus = .normal
	}
}

struct CreateForumSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("forum")
				.id()
				.field("title", .string, .required)
				.field("mod_status", modStatusEnum, .required)
				.field("last_post_time", .datetime, .required)
				.field("created_at", .datetime)
				.field("updated_at", .datetime)
				.field("deleted_at", .datetime)
				.field("category_id", .uuid, .required, .references("category", "id"))
				.field("creator_id", .uuid, .required, .references("user", "id"))
				.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("forum").delete()
	}
}

