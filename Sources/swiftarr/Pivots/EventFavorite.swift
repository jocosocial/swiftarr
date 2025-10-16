import Fluent
import Foundation

/// A `Pivot` holding a sibling relation between `User` and `Event`.
final class EventFavorite: Model, @unchecked Sendable {
	static let schema = "event+favorite"

	// MARK: Properties

	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?
	
	/// TRUE if the user has favorited the event. Favorited events appear on the user's DayPlanner, and the user gets
	/// notified when the events are about to start.
	@Field(key: "favorite") var favorite: Bool
	
	/// TRUE if the user has signed up to photograph the event. Only settable by members of the Shutternaut group.
	/// Works similarly to the `favorite` flag, but is independently settable, and other Shutternauts can see events
	/// a user has signed up to photograph.
	@Field(key: "photographer") var photographer: Bool

	// MARK: Relations

	/// The associated `User` who favorited the event.
	@Parent(key: "user") var user: User

	/// The associated `Event` that was favorited.
	@Parent(key: "event") var event: Event

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new EventFavorite pivot.
	///
	/// - Parameters:
	///   - user: The left hand `User` model.
	///   - game: The right hand `Boardgame` model.
	init(_ user: User, _ event: Event) throws {
		self.$user.id = try user.requireID()
		self.$user.value = user
		self.$event.id = try event.requireID()
		self.$event.value = event
		self.favorite = true
		self.photographer = false
	}

	init(_ userID: UUID, _ event: Event) throws {
		self.$user.id = userID
		self.$event.id = try event.requireID()
		self.favorite = true
		self.photographer = false
	}
}

struct CreateEventFavoriteSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("event+favorite")
			.id()
			.unique(on: "user", "event")
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("event", .uuid, .required, .references("event", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("event+favorite").delete()
	}
}

/// Migration to add the `favorite` and `photographer` fields to EventFavorite
/// Previously the existence of the record meant 'favorite', so that field defaults to true in the migration.
struct UpdateEventFavoriteSchema_Photographer: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("event+favorite")
				.field("favorite", .bool, .required, .sql(.default(true)))
				.field("photographer", .bool, .required, .sql(.default(false)))
				.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("event+favorite")
				.deleteField("favorite")
				.deleteField("photographer")
				.update()
	}
}
