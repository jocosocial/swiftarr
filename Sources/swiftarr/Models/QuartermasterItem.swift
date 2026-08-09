import Fluent
import Foundation
import Vapor

/// 	A QuartermasterItem is a single entry on the Quartermaster "have / need" board.
///
/// 	Any logged-in user can post an item they have to offer or an item they are looking for. Each entry
/// 	may optionally specify a free-text location and/or a contact user (another registered Twitarr user).
/// 	At least one of {location, contact user} must be present (validated in the controller).
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

	/// Moderators can set several statuses on items that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	// MARK: Relationships

	/// The user who created this item listing.
	@Parent(key: "owner") var owner: User

	/// An optional contact user — the person to approach about this item. Defaults to the owner
	/// in clients, but may be overridden to any real Twitarr user. When this user is deleted,
	/// the field is nulled out rather than cascading deletion to the item.
	@OptionalParent(key: "contact_user") var contactUser: User?

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
	///   - contactUserID: An optional UUID of the contact user; nil means no contact user is set.
	init(
		ownerID: UUID,
		category: QuartermasterCategory,
		itemName: String,
		itemDescription: String? = nil,
		location: String? = nil,
		contactUserID: UUID? = nil
	) {
		self.$owner.id = ownerID
		self.category = category
		self.itemName = itemName
		self.itemDescription = itemDescription
		self.location = location
		self.$contactUser.id = contactUserID
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
			.field("mod_status", modStatusEnum, .required)
			.field("owner", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("contact_user", .uuid, .references("user", "id", onDelete: .setNull))
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("quartermaster_item").delete()
	}
}
