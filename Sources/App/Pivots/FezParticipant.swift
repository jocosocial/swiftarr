import Fluent
import Foundation

/// A `Pivot` holding a siblings relation between `User` and `FriendlyFez`.

final class FezParticipant: Model {
	static let schema = "fez+participants"

	// MARK: Properties
	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	/// How many posts in this fez that this user has read. Used by the notification lifecycle and
	/// to scroll the post view to show the first unread message.
	@Field(key: "read_count") var readCount: Int

	/// How many posts in this fez that this user cannot see, due to mutes and blocks.
	@Field(key: "hidden_count") var hiddenCount: Int

	// MARK: Relationships
	/// The associated `User` who is a member of the fez..
	@Parent(key: "user") var user: User

	/// The associated `FriendlyFez` the user is a member of.
	@Parent(key: "friendly_fez") var fez: FriendlyFez

	// MARK: Initialization
	// Used by Fluent
	init() {}

	/// Initializes a new `FezParticipant` pivot.
	///
	/// - Parameters:
	///   - userID: The left hand `User` model.
	///   - post: The right hand `FriendlyFez` model.
	init(_ userID: UUID, _ post: FriendlyFez) throws {
		self.$user.id = userID
		self.$fez.id = try post.requireID()
		self.$fez.value = post
		self.readCount = 0
		self.hiddenCount = 0
	}
}

struct CreateFezParticipantSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("fez+participants")
			.id()
			.unique(on: "user", "friendly_fez")
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("friendly_fez", .uuid, .required, .references("friendlyfez", "id", onDelete: .cascade))
			.field("read_count", .int, .required)
			.field("hidden_count", .int, .required)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("fez+participants").delete()
	}
}
