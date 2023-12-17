import Fluent
import Vapor

/// 	When the TEXT FIELDS of a `ChatGroup` are edited, a `chatgroupEdit` is created to save the previous values of its text fields.
/// 	Edits that only modify other fields of a chatgroup--start/end time, type of chatgroup, min/max number of participants--do not cause a chatgroupEdit to be created.
///
/// 	This is done for accountability purposes and the data collected is intended to be viewable only by moderators.
///
/// 	- See Also: [ChatGroupModerationData](ChatGroupModerationData) the DTO for returning data moderators need to moderate chatgroups. Specifically, the
/// 	sub-struct [ChatGroupEditLogData](ChatGroupEditLogData) delivers values from the `chatgroupEdit` .
/// 	- See Also: [CreatechatgroupEditSchema](CreatechatgroupEditSchema) the Migration for creating the chatgroupEdit table in the database.
final class chatgroupEdit: Model {
	static let schema = "chatgroup_edit"

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous title of the chatgroup.
	@Field(key: "title") var title: String

	/// The previous info string for the chatgroup.
	@Field(key: "info") var info: String

	/// The previous location string for the chatgroup.
	@Field(key: "location") var location: String

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The parent `ChatGroup` that was edited..
	@Parent(key: "chatgroup") var chatgroup: ChatGroup

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new chatgroupEdit with the current title of a `ChatGroup`. Call on the post BEFORE editing it
	/// to save previous contents.
	///
	/// - Parameters:
	///   - forum: The Forum that will be edited.
	///   - editor: The User making the change.
	init(chatgroup: ChatGroup, editorID: UUID) throws {
		self.$chatGroup.id = try chatgroup.requireID()
		self.$chatGroup.value = chatgroup
		self.$editor.id = editorID
		self.title = chatgroup.title
		self.info = chatgroup.info
		self.location = chatgroup.location ?? ""
	}
}

struct CreatechatgroupEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("chatgroup_edit")
			.id()
			.field("title", .string, .required)
			.field("info", .string, .required)
			.field("location", .string, .required)
			.field("created_at", .datetime)
			.field("chatgroup", .uuid, .required, .references("chatgroup", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("chatgroup_edit").delete()
	}
}
