import Fluent
import Vapor

/// 	When the TEXT FIELDS of a `FriendlyChatGroup` are edited, a `FriendlyChatGroupEdit` is created to save the previous values of its text fields.
/// 	Edits that only modify other fields of a chatgroup--start/end time, type of chatgroup, min/max number of participants--do not cause a FriendlyChatGroupEdit to be created.
///
/// 	This is done for accountability purposes and the data collected is intended to be viewable only by moderators.
///
/// 	- See Also: [ChatGroupModerationData](ChatGroupModerationData) the DTO for returning data moderators need to moderate chatgroups. Specifically, the
/// 	sub-struct [ChatGroupEditLogData](ChatGroupEditLogData) delivers values from the `FriendlyChatGroupEdit` .
/// 	- See Also: [CreateFriendlyChatGroupEditSchema](CreateFriendlyChatGroupEditSchema) the Migration for creating the FriendlyChatGroupEdit table in the database.
final class FriendlyChatGroupEdit: Model {
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

	/// The parent `FriendlyChatGroup` that was edited..
	@Parent(key: "chatgroup") var chatgroup: FriendlyChatGroup

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new FriendlyChatGroupEdit with the current title of a `FriendlyChatGroup`. Call on the post BEFORE editing it
	/// to save previous contents.
	///
	/// - Parameters:
	///   - forum: The Forum that will be edited.
	///   - editor: The User making the change.
	init(chatgroup: FriendlyChatGroup, editorID: UUID) throws {
		self.$chatGroup.id = try chatgroup.requireID()
		self.$chatGroup.value = chatgroup
		self.$editor.id = editorID
		self.title = chatgroup.title
		self.info = chatgroup.info
		self.location = chatgroup.location ?? ""
	}
}

struct CreateFriendlyChatGroupEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("chatgroup_edit")
			.id()
			.field("title", .string, .required)
			.field("info", .string, .required)
			.field("location", .string, .required)
			.field("created_at", .datetime)
			.field("chatgroup", .uuid, .required, .references("friendlychatgroup", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("chatgroup_edit").delete()
	}
}
