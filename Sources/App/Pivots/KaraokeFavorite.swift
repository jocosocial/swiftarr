import Foundation
import Fluent

/// A `Pivot` holding a sibling relation between `User` and `KaraokeSong`.
final class KaraokeFavorite: Model {
	static let schema = "karaoke+favorite"

	// MARK: Properties
	
	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?
		
	// MARK: Relations
	
	/// The associated `User` who favorited the game.
	@Parent(key: "user") var user: User

	/// The associated `KaraokeSong` that was favorited.
	@Parent(key: "song") var song: KaraokeSong

	// MARK: Initialization
	
	// Used by Fluent
 	init() { }
 	
	/// Initializes a new BoardgameFavorite pivot.
	///
	/// - Parameters:
	///   - user: The left hand `User` model.
	///   - game: The right hand `Boardgame` model.
	init(_ userID: UUID, _ song: KaraokeSong) throws{
		self.$user.id = userID
		self.$song.id = try song.requireID()
	}
}

struct CreateKaraokeFavoriteSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("karaoke+favorite")
				.id()
 				.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
 				.field("song", .uuid, .required, .references("karaoke_song", "id", onDelete: .cascade))
				.create()
	}
 
	func revert(on database: Database) async throws {
		try await database.schema("karaoke+favorite").delete()
	}
}

