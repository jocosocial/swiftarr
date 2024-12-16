import Fluent
import Vapor

/// 	When a `ForumPost` is edited, a `ForumPostEdit` is created and associated with the post.
///
/// 	This is done for accountability purposes and the data collected is intended to be viewable
/// 	only by users with an access level of `.moderator` or above.
///
/// 	- See Also: [ForumPostModerationData](ForumPostModerationData) the DTO for returning data moderators need to moderate ForumPosts.
/// 	Specifically, see the [PostEditLogData](PostEditLogData) sub-struct.
/// 	- See Also: [CreateForumPostEditSchema](CreateForumPostEditSchema) the Migration for creating the ForumPostEdit table in the database.
final class ForumPostEdit: Model, @unchecked Sendable {
	static let schema = "forum_post_edit"

	// MARK: Properties

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous text of the post.
	@Field(key: "post_text") var postText: String

	/// The previous images, if any.
	@OptionalField(key: "images") var images: [String]?

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The parent `ForumPost` of the edit.
	@Parent(key: "post") var post: ForumPost

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new ForumEdit with the current contents of a post.. Call on the post BEFORE editing it
	/// to save previous contents.
	///
	/// - Parameters:
	///   - post: The ForumPost that will be edited.
	init(post: ForumPost, editorID: UUID) throws {
		self.$post.id = try post.requireID()
		self.$post.value = post
		self.$editor.id = editorID
		self.postText = post.text
		self.images = post.images
	}
}

struct CreateForumPostEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("forum_post_edit")
			.id()
			.field("post_text", .string, .required)
			.field("images", .array(of: .string))
			.field("created_at", .datetime)
			.field("post", .int, .required, .references("forumpost", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("forum_post_edit").delete()
	}
}
