import Fluent
import Vapor

/// 	When the TEXT FIELDS of a `QuartermasterItem` are edited, a `QuartermasterItemEdit` is created
/// 	to save the previous values of those text fields, plus the `hideOwnerName` setting.
///
/// 	Edits that only change the category — without touching item_name, item_description, location, or
/// 	hideOwnerName — do not create a QuartermasterItemEdit. This is done for accountability purposes;
/// 	the data collected is intended to be viewable only by moderators.
///
/// 	- See Also: [QuartermasterModerationData](QuartermasterModerationData) the DTO returning data
/// 	  moderators need to review items. Specifically, [QuartermasterEditLogData](QuartermasterEditLogData)
/// 	  delivers values from the `QuartermasterItemEdit`.
/// 	- See Also: [CreateQuartermasterItemEditSchema](CreateQuartermasterItemEditSchema) the Migration
/// 	  for creating the QuartermasterItemEdit table.
final class QuartermasterItemEdit: Model, @unchecked Sendable {
	static let schema = "quartermaster_item_edit"

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous item name.
	@Field(key: "item_name") var itemName: String

	/// The previous item description (empty string when nil at edit time).
	@Field(key: "item_description") var itemDescription: String

	/// The previous location string (empty string when nil at edit time).
	@Field(key: "location") var location: String

	/// Whether the owner's name was hidden at edit time.
	@Field(key: "hide_owner_name") var hideOwnerName: Bool

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The parent `QuartermasterItem` that was edited.
	@Parent(key: "item") var item: QuartermasterItem

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent.
	init() {}

	/// Initializes a new QuartermasterItemEdit with the CURRENT text fields of the item.
	/// Call this **before** applying the edit so that the prior state is captured.
	///
	/// - Parameters:
	///   - item: The QuartermasterItem about to be edited.
	///   - editorID: The UUID of the User making the change.
	init(item: QuartermasterItem, editorID: UUID) throws {
		self.$item.id = try item.requireID()
		self.$item.value = item
		self.$editor.id = editorID
		self.itemName = item.itemName
		self.itemDescription = item.itemDescription ?? ""
		self.location = item.location ?? ""
		self.hideOwnerName = item.hideOwnerName
	}
}

struct CreateQuartermasterItemEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("quartermaster_item_edit")
			.id()
			.field("item_name", .string, .required)
			.field("item_description", .string, .required)
			.field("location", .string, .required)
			.field("hide_owner_name", .bool, .required)
			.field("created_at", .datetime)
			.field("item", .uuid, .required, .references("quartermaster_item", "id"))
			.field("editor", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("quartermaster_item_edit").delete()
	}
}
