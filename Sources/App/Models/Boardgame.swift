import Vapor
import Fluent

/// A boardgame in the Games Library. 
final class Boardgame: Model {
	static let schema = "boardgame"
	
    // MARK: Properties
    
    /// The game's ID.
    @ID(key: .id) var id: UUID?
    
    /// The game's title.
	@Field(key: "gameName") var gameName: String
	/// How many copies the Games Library has of this game.
	@Field(key: "numCopies") var numCopies: Int
	
	/// If the game was donated (or perhaps loaned) by a cruisegoer, the person that donated it.
	@OptionalField(key: "donatedBy") var donatedBy: String?
	/// Any notes on the game, e.g.box condition, missing pieces.
	@OptionalField(key: "notes") var notes: String?

	/// The rest of these properties are pulled from BoardGameGeek's API, and may not exactly match the game in the library.
	/// Some games get re-released with slightly different versions, and the script guesses which one the Library most likely has.
	/// All these properties are optional because we may not find a match on BGG
	
	/// BoardGameGeek sometimes has a slightly different title for a game. This is the exact BGG title.
	@OptionalField(key: "bggGameName") var bggGameName: String?
	@OptionalField(key: "yearPublished") var yearPublished: String?
	@OptionalField(key: "gameDescription") var gameDescription: String?

	@OptionalField(key: "minPlayers") var minPlayers: Int?
	@OptionalField(key: "maxPlayers") var maxPlayers: Int?

	@OptionalField(key: "minPlayingTime") var minPlayingTime: Int?
	@OptionalField(key: "maxPlayingTime") var maxPlayingTime: Int?
	@OptionalField(key: "avgPlayingTime") var avgPlayingTime: Int?

	/// The recommended min age to play this game. May be based on complexity or on content.
	@OptionalField(key: "minAge") var minAge: Int?
	/// The number of BGG reviewers that have provided a rating on the game.
	@OptionalField(key: "numRatings") var numRatings: Int?
	/// The average rating by BGG game raters. Ratings range is 1...10.
	@OptionalField(key: "avgRating") var avgRating: Float?
	/// Roughly, how complex the rules are for this game. Scale is 1...5. 1 is "tic-tac-toe", 5 is "Roll 3d100 on Table 38/b to find out which sub-table to roll on"
	@OptionalField(key: "complexity") var complexity: Float?
	
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
     
	// MARK: Relations
        
    /// If this is an expansion set, the base game that it expands
    @OptionalParent(key: "expands") var expands: Boardgame?

    /// For games that have expansions, the set of expansions for this base game.
    @Children(for: \.$expands) var expansions: [Boardgame]
        
	/// The users that have favorited this game.
	@Siblings(through: BoardgameFavorite.self, from: \.$boardgame, to: \.$user) var favorites: [User]

    // MARK: Initialization
    
    /// Used by Fluent
 	init() { }
 	
    /// Initializes a new Boardgame from the JSON games file data.
    ///
    /// - Parameters:
    ///   - jsonGame: Game value decoded from the BoardGamesList JSON file..
    init(jsonGame: JsonGamesListGame) {
		self.gameName = jsonGame.gameName
		self.bggGameName = jsonGame.bggGameName
		self.yearPublished = jsonGame.yearPublished
		self.gameDescription = jsonGame.gameDescription
		
		self.minPlayers = jsonGame.minPlayers
		self.maxPlayers = jsonGame.maxPlayers
		
		self.minPlayingTime = jsonGame.minPlayingTime
		self.maxPlayingTime = jsonGame.maxPlayingTime
		self.avgPlayingTime = jsonGame.avgPlayingTime
		
		self.minAge = jsonGame.minAge
		self.numRatings = jsonGame.numRatings
		self.avgRating = jsonGame.avgRating
		self.complexity = jsonGame.complexity
		
		self.donatedBy = jsonGame.donatedBy
		self.notes = jsonGame.notes
		self.numCopies = jsonGame.numCopies
    }
}
