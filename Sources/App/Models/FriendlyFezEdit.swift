import Fluent
import Vapor

/// 	When the TEXT FIELDS of a `FriendlyGroup` are edited, a `FriendlyGroupEdit` is created to save the previous values of its text fields.
/// 	Edits that only modify other fields of a group--start/end time, type of group, min/max number of participants--do not cause a FriendlyGroupEdit to be created.
///
/// 	This is done for accountability purposes and the data collected is intended to be viewable only by moderators.
///
/// 	- See Also: [GroupModerationData](GroupModerationData) the DTO for returning data moderators need to moderate groups. Specifically, the
/// 	sub-struct [GroupEditLogData](GroupEditLogData) delivers values from the `FriendlyGroupEdit` .
/// 	- See Also: [CreateFriendlyGroupEditSchema](CreateFriendlyGroupEditSchema) the Migration for creating the FriendlyGroupEdit table in the database.
final class FriendlyGroupEdit: Model {
	static let schema = "group_edit"

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous title of the group.
	@Field(key: "title") var title: String

	/// The previous info string for the group.
	@Field(key: "info") var info: String

	/// The previous location string for the group.
	@Field(key: "location") var location: String

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The parent `FriendlyGroup` that was edited..
	@Parent(key: "group") var group: FriendlyGroup

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new FriendlyGroupEdit with the current title of a `FriendlyGroup`. Call on the post BEFORE editing it
	/// to save previous contents.
	///
	/// - Parameters:
	///   - forum: The Forum that will be edited.
	///   - editor: The User making the change.
	init(group: FriendlyGroup, editorID: UUID) throws {
		self.$group.id = try group.requireID()
		self.$group.value = group
		self.$editor.id = editorID
		self.title = group.title
		self.info = group.info
		self.location = group.location ?? ""
	}
}

struct CreateFriendlyGroupEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("group_edit")
			.id()
			.field("title", .string, .required)
			.field("info", .string, .required)
			.field("location", .string, .required)
			.field("created_at", .datetime)
			.field("group", .uuid, .required, .references("friendlygroup", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("group_edit").delete()
	}
}
