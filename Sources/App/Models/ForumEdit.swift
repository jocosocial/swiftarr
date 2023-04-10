import Fluent
import Vapor

/// 	When a `Forum` is edited, a `ForumEdit` is created to save the previous title text.
///
/// 	This is done for accountability purposes and the data collected is intended to be viewable
/// 	only by users with an access level of `.moderator` or above.
///
/// 	- See Also: [ForumModerationData](ForumModerationData) the DTO for returning data moderators need to moderate forums.
/// 	- See Also: [CreateForumEditSchema](CreateForumEditSchema) the Migration for creating the ForumEdit table in the database.
final class ForumEdit: Model {
	static let schema = "forum_edit"

	// MARK: Properties

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous title of the forum.
	@Field(key: "title") var title: String

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The parent `Forum` of the edit.
	@Parent(key: "forum") var forum: Forum

	/// The category the Forum was in before the edit happened, if the edit changed the category
	@OptionalParent(key: "category") var category: Category?

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new ForumEdit with the current title of a `Forum`. Call on the post BEFORE editing it
	/// to save previous contents.
	///
	/// - Parameters:
	///   - forum: The Forum that will be edited.
	///   - editor: The User making the change.
	init(forum: Forum, editorID: UUID, categoryChanged: Bool) throws {
		self.$forum.id = try forum.requireID()
		self.$forum.value = forum
		self.$category.id = categoryChanged ? forum.$category.id : nil
		self.title = forum.title
		self.$editor.id = editorID
	}
}

struct CreateForumEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("forum_edit")
			.id()
			.field("title", .string, .required)
			.field("created_at", .datetime)
			.field("forum", .uuid, .required, .references("forum", "id"))
			.field("category", .uuid, .references("category", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("forum_edit").delete()
	}
}
