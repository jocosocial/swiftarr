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
    init(_ user: User, _ song: KaraokeSong) throws{
        self.$user.id = try user.requireID()
        self.$user.value = user
        self.$song.id = try song.requireID()
        self.$song.value = song
    }
}
