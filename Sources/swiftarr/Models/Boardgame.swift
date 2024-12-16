import Fluent
import Vapor

/// A boardgame in the Games Library.
final class Boardgame: Model, Searchable, @unchecked Sendable {
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
	@Field(key: "gameTypes") var gameTypes: [String]
	@Field(key: "categories") var categories: [String]
	@Field(key: "mechanisms") var mechanisms: [String]

	@OptionalField(key: "minPlayers") var minPlayers: Int?
	@OptionalField(key: "maxPlayers") var maxPlayers: Int?
	@OptionalField(key: "suggestedPlayers") var suggestedPlayers: Int?

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
	init() {}

	/// Initializes a new Boardgame from the JSON games file data.
	///
	/// - Parameters:
	///   - jsonGame: Game value decoded from the BoardGamesList JSON file..
	init(jsonGame: JsonGamesListGame) {
		self.gameName = jsonGame.gameName
		self.bggGameName = jsonGame.bggGameName
		self.yearPublished = jsonGame.yearPublished
		self.gameDescription = jsonGame.gameDescription
		self.gameTypes = jsonGame.gameTypes ?? []
		self.categories = jsonGame.categories ?? []
		self.mechanisms = jsonGame.mechanisms ?? []

		self.minPlayers = jsonGame.minPlayers
		self.maxPlayers = jsonGame.maxPlayers
		self.suggestedPlayers = jsonGame.suggestedPlayers

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

	/// Determines whether a game has enough information to be used by the recommendation engine.
	///
	/// BoardGameGeek's data is user-provided and is not complete for all games in their database. If a
	/// game is missing one of these fields, we can still create a reasonable score for how well the game
	/// matches a set of criteria. If it's missing a bunch of these fields, scoring the game would be meaningless.
	func canUseForRecommendations() -> Bool {
		var invalidCount = 0
		if suggestedPlayers == nil || suggestedPlayers == 0 {
			invalidCount += 1
			guard let min = minPlayers, let max = maxPlayers, min != 0, max != 0 else {
				return false
			}
		}
		if avgPlayingTime == nil || avgPlayingTime == 0 {
			invalidCount += 1
			guard let min = minPlayingTime, let max = maxPlayingTime, min != 0, max != 0 else {
				return false
			}
		}
		if avgRating == nil || avgRating == 0 {
			invalidCount += 1
		}
		if complexity == nil || complexity == 0 {
			invalidCount += 1
		}
		return invalidCount <= 1
	}

	func getSuggestedPlayers() -> Int {
		var result = suggestedPlayers ?? 0
		if result == 0 {
			result = ((minPlayers ?? 0) + (maxPlayers ?? 0) + 1) / 2
		}
		return result
	}

	func getAvgPlayingTime() -> Int {
		var result = avgPlayingTime ?? 0
		if result == 0 {
			result = ((minPlayingTime ?? 0) + (maxPlayingTime ?? 0)) / 2
		}
		return result
	}

	/// Unwraps, and gives games with no rating a low but not terrible default rating
	func getAvgRating() -> Float {
		return (avgRating ?? 0) == 0 ? 4.5 : (avgRating ?? 0)
	}

	/// Unwraps, and gives games with no complexity rating an average complexity value as a default.
	/// Ideally we'd give games with no complexity value a scoring penalty.
	func getComplexity() -> Float {
		return (complexity ?? 0) == 0 ? 3.0 : (complexity ?? 0)
	}
}

struct CreateBoardgameSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("boardgame")
			.id()
			.field("gameName", .string, .required)
			.field("bggGameName", .string)
			.field("yearPublished", .string)
			.field("gameDescription", .string)

			.field("minPlayers", .int)
			.field("maxPlayers", .int)
			.field("suggestedPlayers", .int)

			.field("minPlayingTime", .int)
			.field("maxPlayingTime", .int)
			.field("avgPlayingTime", .int)

			.field("minAge", .int)
			.field("numRatings", .int)
			.field("avgRating", .float)
			.field("complexity", .float)

			.field("donatedBy", .string)
			.field("notes", .string)
			.field("numCopies", .int, .required)

			.field("expands", .uuid, .references("boardgame", "id"))

			.field("created_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("boardgame").delete()
	}
}

struct BoardgameSchemaAdditions1: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("boardgame")
				.field("gameTypes", .array(of: .string), .required, .sql(.default("{}")))		// Or perhaps '.default("array[]::varchar[]")'
				.field("categories", .array(of: .string), .required, .sql(.default("{}")))
				.field("mechanisms", .array(of: .string), .required,  .sql(.default("{}")))
				.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("boardgame")
				.deleteField("gameTypes")
				.deleteField("categories")
				.deleteField("mechanisms")
				.update()
	}
}
