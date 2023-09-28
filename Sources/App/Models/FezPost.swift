import Fluent
import Vapor

/// 	An individual post within a `FriendlyGroup` discussion. A GroupPost must contain
/// 	text content and may also contain image content, unless the Group is of type `GroupType.closed`,
/// 	in which case the post may not contain images.
///
/// 	- See Also: [GroupPostData](GroupPostData) the DTO for returning info on GroupPosts. GroupPostData is also a member of `GroupData`.
/// 	- See Also: [CreateGroupPostSchema](CreateGroupPostSchema) the Migration for creating the GroupPost table in the database.
final class GroupPost: Model, Searchable {
	static let schema = "groupposts"

	// MARK: Properties

	/// The post's ID.
	@ID(custom: "id") var id: Int?

	/// The text content of the post.
	@Field(key: "text") var text: String

	/// The filename of any image content of the post. GroupPosts are limited to one image, and "closed" Group types cannot have any.
	@OptionalField(key: "image") var image: String?

	/// Moderators can set several statuses on groupPosts that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// The `FriendlyGroup` to which the post belongs.
	@Parent(key: "friendly_group") var group: FriendlyGroup

	/// The post's author.
	@Parent(key: "author") var author: User

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new GroupPost.
	///
	/// - Parameters:
	///   - groupID: The ID of the post's FriendlyGroup.
	///   - authorID: The ID of the author of the post.
	///   - text: The text content of the post.
	///   - image: The filename of any image content of the post.
	init(
		group: FriendlyGroup,
		authorID: UUID,
		text: String,
		image: String?
	) throws {
		self.$group.id = try group.requireID()
		self.$group.value = group
		self.$author.id = authorID

		// Generally I'm in favor of "validate input, sanitize output" but I hate "\r\n" with the fury of a thousand suns.
		self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
		self.image = image
		self.moderationStatus = .normal
	}
}

struct CreateGroupPostSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("groupposts")
			.field("id", .int, .identifier(auto: true))
			.field("text", .string, .required)
			.field("image", .string)
			.field("mod_status", modStatusEnum, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.field("friendly_group", .uuid, .required, .references("friendlygroup", "id"))
			.field("author", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("groupposts").delete()
	}
}
