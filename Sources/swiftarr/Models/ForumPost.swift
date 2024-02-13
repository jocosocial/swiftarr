import Fluent
import Vapor

/// 	An individual post within a `Forum`. A ForumPost must contain text content and may also contain image content.
///
/// 	Posts have a `moderationStatus` that moderators can change to perform moderation actdions.
///
/// 	When a post is edited, a `ForumPostEdit` is created to save the pre-edit state of the post.
///
/// 	- See Also: [PostData](PostData) the DTO for returning basic data on ForumPosts.
/// 	- See Also: [PostDetailData](PostDetailData) the DTO for returning extended data on ForumPosts.
/// 	- See Also: [PostContentData](PostContentData) the DTO for creating ForumPosts.
/// 	- See Also: [CreateForumPostSchema](CreateForumPostSchema) the Migration for creating the ForumPost table in the database.
final class ForumPost: Model, Searchable {
	static let schema = "forumpost"

	// MARK: Properties

	/// The post's ID. Sorting posts in a thread by ID should produce the correct ordering, but
	/// post IDs are unique through all forums, and won't be sequential in any forum.
	@ID(custom: "id") var id: Int?

	/// The text content of the post.
	@Field(key: "text") var text: String

	/// The filenames of any images for the post.
	@OptionalField(key: "images") var images: [String]?

	/// Moderators can set several statuses on forumPosts that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	/// Is the post pinned within the forum.
	@OptionalField(key: "pinned") var pinned: Bool?

	// MARK: Relations

	/// The parent `Forum` of the post.
	@Parent(key: "forum") var forum: Forum

	/// The parent `User`  who authored the post.
	@Parent(key: "author") var author: User

	/// The child `ForumPostEdit` accountability records of the post.
	@Children(for: \.$post) var edits: [ForumPostEdit]

	/// The sibling `User`s who have "liked" the post.
	@Siblings(through: PostLikes.self, from: \.$post, to: \.$user) var likes

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new ForumPost.
	///
	/// - Parameters:
	///   - forum: The post's forum.
	///   - author: The author of the post.
	///   - text: The text content of the post.
	///   - image: The filename of any image content of the post.
	init(
		forum: Forum,
		authorID: UUID,
		text: String,
		images: [String]? = nil
	) throws {
		self.$forum.id = try forum.requireID()
		self.$forum.value = forum
		self.$author.id = authorID
		// We don't do much text manipulation on input, but let's normalize line endings.
		self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
		self.images = images
		self.moderationStatus = .normal
	}
}

struct CreateForumPostSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("forumpost")
			.field("id", .int, .identifier(auto: true))
			.field("text", .string, .required)
			.field("images", .array(of: .string))
			.field("mod_status", modStatusEnum, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.field("forum", .uuid, .required, .references("forum", "id"))
			.field("author", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("forumpost").delete()
	}
}

struct UpdateForumPostPinnedMigration: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("forumpost")
			.field("pinned", .bool)
			.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("forumpost")
			.deleteField("pinned")
			.update()
	}
}