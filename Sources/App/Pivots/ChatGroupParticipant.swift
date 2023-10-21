import Fluent
import Foundation

/// A `Pivot` holding a siblings relation between `User` and `FriendlyChatGroup`.

final class ChatGroupParticipant: Model {
	static let schema = "chatgroup+participants"

	// MARK: Properties
	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	/// How many posts in this chatgroup that this user has read. Used by the notification lifecycle and
	/// to scroll the post view to show the first unread message.
	@Field(key: "read_count") var readCount: Int

	/// How many posts in this chatgroup that this user cannot see, due to mutes and blocks.
	@Field(key: "hidden_count") var hiddenCount: Int

	// MARK: Relationships
	/// The associated `User` who is a member of the chatgroup..
	@Parent(key: "user") var user: User

	/// The associated `FriendlyChatGroup` the user is a member of.
	@Parent(key: "friendly_chatgroup") var chatgroup: FriendlyChatGroup

	// MARK: Initialization
	// Used by Fluent
	init() {}

	/// Initializes a new `ChatGroupParticipant` pivot.
	///
	/// - Parameters:
	///   - userID: The left hand `User` model.
	///   - post: The right hand `FriendlyChatGroup` model.
	init(_ userID: UUID, _ post: FriendlyChatGroup) throws {
		self.$user.id = userID
		self.$chatGroup.id = try post.requireID()
		self.$chatGroup.value = post
		self.readCount = 0
		self.hiddenCount = 0
	}
}

struct CreateChatGroupParticipantSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("chatgroup+participants")
			.id()
			.unique(on: "user", "friendly_chatgroup")
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("friendly_chatgroup", .uuid, .required, .references("friendlychatgroup", "id", onDelete: .cascade))
			.field("read_count", .int, .required)
			.field("hidden_count", .int, .required)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("chatgroup+participants").delete()
	}
}
