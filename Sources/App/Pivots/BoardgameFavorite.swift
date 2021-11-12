import Foundation
import Fluent

/// A `Pivot` holding a sibling relation between `User` and `Boardgame`.
final class BoardgameFavorite: Model {
    static let schema = "boardgame+favorite"

    // MARK: Properties
    
    /// The ID of the pivot.
    @ID(key: .id) var id: UUID?
        
    // MARK: Relations
    
    /// The associated `User` who favorited the game.
	@Parent(key: "user") var user: User

    /// The associated `Boardgame` that was favorited.
    @Parent(key: "boardgame") var boardgame: Boardgame

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new BoardgameFavorite pivot.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - game: The right hand `Boardgame` model.
    init(_ user: User, _ game: Boardgame) throws {
        self.$user.id = try user.requireID()
        self.$user.value = user
        self.$boardgame.id = try game.requireID()
        self.$boardgame.value = game
    }
    
    init(_ userID: UUID, _ game: Boardgame) throws {
        self.$user.id = userID
        self.$boardgame.id = try game.requireID()
    }
}
