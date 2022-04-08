import Foundation
import Fluent

/// A `Pivot` holding a sibling relation between `User` and `Event`.
final class EventFavorite: Model {
	static let schema = "event+favorite"

	// MARK: Properties
	
	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?
		
	// MARK: Relations
	
	/// The associated `User` who favorited the game.
	@Parent(key: "user") var user: User

	/// The associated `Boardgame` that was favorited.
	@Parent(key: "event") var event: Event

	// MARK: Initialization
	
	// Used by Fluent
 	init() { }
 	
	/// Initializes a new BoardgameFavorite pivot.
	///
	/// - Parameters:
	///   - user: The left hand `User` model.
	///   - game: The right hand `Boardgame` model.
	init(_ user: User, _ event: Event) throws {
		self.$user.id = try user.requireID()
		self.$user.value = user
		self.$event.id = try event.requireID()
		self.$event.value = event
	}
	
	init(_ userID: UUID, _ event: Event) throws {
		self.$user.id = userID
		self.$event.id = try event.requireID()
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
