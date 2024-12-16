import Fluent
import Vapor

/// 	When the TEXT FIELDS of a `FriendlyFez` are edited, a `FriendlyFezEdit` is created to save the previous values of its text fields.
/// 	Edits that only modify other fields of a fez--start/end time, type of fez, min/max number of participants--do not cause a FriendlyFezEdit to be created.
///
/// 	This is done for accountability purposes and the data collected is intended to be viewable only by moderators.
///
/// 	- See Also: [FezModerationData](FezModerationData) the DTO for returning data moderators need to moderate fezzes. Specifically, the
/// 	sub-struct [FezEditLogData](FezEditLogData) delivers values from the `FriendlyFezEdit` .
/// 	- See Also: [CreateFriendlyFezEditSchema](CreateFriendlyFezEditSchema) the Migration for creating the FriendlyFezEdit table in the database.
final class FriendlyFezEdit: Model, @unchecked Sendable {
	static let schema = "fez_edit"

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous title of the fez.
	@Field(key: "title") var title: String

	/// The previous info string for the fez.
	@Field(key: "info") var info: String

	/// The previous location string for the fez.
	@Field(key: "location") var location: String

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The parent `FriendlyFez` that was edited..
	@Parent(key: "fez") var fez: FriendlyFez

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new FriendlyFezEdit with the current title of a `FriendlyFez`. Call on the post BEFORE editing it
	/// to save previous contents.
	///
	/// - Parameters:
	///   - forum: The Forum that will be edited.
	///   - editor: The User making the change.
	init(fez: FriendlyFez, editorID: UUID) throws {
		self.$fez.id = try fez.requireID()
		self.$fez.value = fez
		self.$editor.id = editorID
		self.title = fez.title
		self.info = fez.info
		self.location = fez.location ?? ""
	}
}

struct CreateFriendlyFezEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("fez_edit")
			.id()
			.field("title", .string, .required)
			.field("info", .string, .required)
			.field("location", .string, .required)
			.field("created_at", .datetime)
			.field("fez", .uuid, .required, .references("friendlyfez", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("fez_edit").delete()
	}
}
