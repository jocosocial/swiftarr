import Fluent
import Foundation
import Vapor

/// 	A QuartermasterItem is a single entry on the Quartermaster "have / need" board.
///
/// 	Any logged-in user can post an item they have to offer or an item they are looking for. Each entry
/// 	may optionally specify a free-text location, and may hide the owner's name from other users. When
/// 	the owner's name is hidden, a location is required, since it becomes the only way for other users
/// 	to identify how to find the item (validated in the controller).
///
/// 	Items are searchable, filterable by category (have/need) and by owner, and are individually
/// 	reportable to the mod queue. Moderators may quarantine or delete entries exactly as they do
/// 	for forum posts. Edits to text fields are snapshotted in `QuartermasterItemEdit` for accountability.
///
/// 	- See Also: [QuartermasterData](QuartermasterData) the DTO for returning item data.
/// 	- See Also: [QuartermasterContentData](QuartermasterContentData) the DTO for creating or editing items.
/// 	- See Also: [CreateQuartermasterItemSchema](CreateQuartermasterItemSchema) the Migration creating the table.
final class QuartermasterItem: Model, Searchable, @unchecked Sendable {
	static let schema = "quartermaster_item"

	// MARK: Properties

	/// Unique ID for this item.
	@ID(key: .id) var id: UUID?

	/// Whether the owner has this item to offer, or needs it.
	@Field(key: "category") var category: QuartermasterCategory

	/// A short name or title for the item. Required; 2–100 characters (validated in controller).
	@Field(key: "item_name") var itemName: String

	/// An optional longer description of the item. ≤2048 characters when present.
	@OptionalField(key: "item_description") var itemDescription: String?

	/// An optional free-text location where the item can be picked up / exchanged.
	/// When present: 3–100 characters (validated in the controller DTO).
	@OptionalField(key: "location") var location: String?

	/// An optional filename referencing an uploaded photo of the item. At most one image per item.
	@OptionalField(key: "image") var image: String?

	/// Moderators can set several statuses on items that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	// MARK: Relationships

	/// The user who created this item listing.
	@Parent(key: "owner") var owner: User

	/// When `true`, the owner's identity is hidden from other users viewing this item (the owner
	/// and moderators can still see it). A location is required when this is set.
	@Field(key: "hide_owner_name") var hideOwnerName: Bool

	/// The child `QuartermasterItemEdit` accountability records for this item.
	@Children(for: \.$item) var edits: [QuartermasterItemEdit]

	// MARK: Record-keeping

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	/// Soft-delete allows moderators to view deleted entries.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Initialization

	// Used by Fluent.
	init() {}

	/// Initializes a new QuartermasterItem.
	///
	/// - Parameters:
	///   - ownerID: The UUID of the user creating the listing.
	///   - category: Whether the owner has or needs the item.
	///   - itemName: A short name for the item (2–100 chars).
	///   - itemDescription: An optional longer description (≤2048 chars).
	///   - location: An optional free-text pickup/exchange location.
	///   - hideOwnerName: Whether to hide the owner's identity from other users. Defaults to `false`.
	///   - image: An optional filename referencing an already-processed uploaded photo.
	init(
		ownerID: UUID,
		category: QuartermasterCategory,
		itemName: String,
		itemDescription: String? = nil,
		location: String? = nil,
		hideOwnerName: Bool = false,
		image: String? = nil
	) {
		self.$owner.id = ownerID
		self.category = category
		self.itemName = itemName
		self.itemDescription = itemDescription
		self.location = location
		self.hideOwnerName = hideOwnerName
		self.image = image
		self.moderationStatus = .normal
	}
}

// MARK: - Reportable

/// Items can be reported to the moderator queue by any user.
/// No auto-quarantine threshold — mods must manually quarantine (same policy as FriendlyFez).
extension QuartermasterItem: Reportable {
	/// The report type for `QuartermasterItem` reports.
	var reportType: ReportType { .quartermasterItem }

	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $owner.id }

	/// No auto-quarantine for Quartermaster items.
	var autoQuarantineThreshold: Int { Int.max }
}

// MARK: - ContentFilterable

/// Items participate in mute-word and alert-word processing.
extension QuartermasterItem: ContentFilterable {
	func contentTextStrings() -> [String] {
		[itemName, itemDescription ?? "", location ?? ""]
	}
}

// MARK: - Migration

struct CreateQuartermasterItemSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("quartermaster_item")
			.id()
			.field("category", .string, .required)
			.field("item_name", .string, .required)
			.field("item_description", .string)
			.field("location", .string)
			.field("image", .string)
			.field("mod_status", modStatusEnum, .required)
			.field("owner", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("hide_owner_name", .bool, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("quartermaster_item").delete()
	}
}
