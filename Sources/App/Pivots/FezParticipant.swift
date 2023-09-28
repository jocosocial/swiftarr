import Fluent
import Foundation

/// A `Pivot` holding a siblings relation between `User` and `FriendlyGroup`.

final class GroupParticipant: Model {
	static let schema = "group+participants"

	// MARK: Properties
	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	/// How many posts in this group that this user has read. Used by the notification lifecycle and
	/// to scroll the post view to show the first unread message.
	@Field(key: "read_count") var readCount: Int

	/// How many posts in this group that this user cannot see, due to mutes and blocks.
	@Field(key: "hidden_count") var hiddenCount: Int

	// MARK: Relationships
	/// The associated `User` who is a member of the group..
	@Parent(key: "user") var user: User

	/// The associated `FriendlyGroup` the user is a member of.
	@Parent(key: "friendly_group") var group: FriendlyGroup

	// MARK: Initialization
	// Used by Fluent
	init() {}

	/// Initializes a new `GroupParticipant` pivot.
	///
	/// - Parameters:
	///   - userID: The left hand `User` model.
	///   - post: The right hand `FriendlyGroup` model.
	init(_ userID: UUID, _ post: FriendlyGroup) throws {
		self.$user.id = userID
		self.$group.id = try post.requireID()
		self.$group.value = post
		self.readCount = 0
		self.hiddenCount = 0
	}
}

struct CreateGroupParticipantSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("group+participants")
			.id()
			.unique(on: "user", "friendly_group")
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("friendly_group", .uuid, .required, .references("friendlygroup", "id", onDelete: .cascade))
			.field("read_count", .int, .required)
			.field("hidden_count", .int, .required)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("group+participants").delete()
	}
}
