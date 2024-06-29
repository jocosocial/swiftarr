import Fluent
import Vapor

/// A `Migration` that imports the Games Catalog JSON file.
///
/// This file is  located in the `seeds/` subdirectory of the project.
struct ImportBoardgames: AsyncMigration {
	/// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
	/// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
	/// a parser and populates the `Event` database with the `[Event]` array returned.
	///
	/// - Requires: `schedule.ics` file in seeds subdirectory.
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		database.logger.info("Starting boardgame import")
		// get gamesFile
		let gamesFile: String
		do {
			if try Environment.detect().isRelease {
				gamesFile = "JoCoGamesCatalog.json"
			}
			else {
				gamesFile = "test-JoCoGamesCatalog.json"
			}
			let gamesFilePath = Settings.shared.seedsDirectoryPath.appendingPathComponent(gamesFile)
			guard let data = FileManager.default.contents(atPath: gamesFilePath.path) else {
				throw Abort(.internalServerError, reason: "Could not read boardgames file.")
			}
			// parse to JsonGamesListGame array
			let gamesList = try JSONDecoder().decode([JsonGamesListGame].self, from: data)
			try await gamesList.map { Boardgame(jsonGame: $0) }.create(on: database)
			for jsonGame in gamesList {
				if let expands = jsonGame.expands {
					guard let basegame = try await Boardgame.query(on: database).filter(\.$gameName == expands).first()
					else {
						database.logger.log(
							level: .notice,
							"Could not find basegame \"\(expands)\" to attach game expansion \"\(jsonGame.gameName)\""
						)
						continue
					}
					guard
						let expansion = try await Boardgame.query(on: database).filter(\.$gameName == jsonGame.gameName)
							.first()
					else {
						database.logger.log(
							level: .notice,
							"Could not attach game expansion \"\(jsonGame.gameName)\" to basegame \"\(expands)\""
						)
						continue
					}
					expansion.$expands.id = try basegame.requireID()
					try await expansion.save(on: database)
				}
			}
		}
		catch let error {
			throw Abort(.internalServerError, reason: "Failed to import games list: \(error)")
		}
	}

	/// Required by `Migration` protocol.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await Boardgame.query(on: database).delete()
	}
}

/// Structure of the JSON in the JoCoGamesCatalog file.
///
/// Similar to the structure of the Model object (Boardgame) and the Data Transfer Sruct (BoardgameData), but this
/// struct is specifically for migration.
struct JsonGamesListGame: Codable {
	var gameName: String				// JoCo Games list name for the game
	var bggGameName: String?			// In BGG's XML responses: <name primary="true">
	var yearPublished: String?			// <yearpublished>
	var gameDescription: String?		// <description>
	var gameTypes: [String]?			// <boardgamesubdomain>
	var categories: [String]?			// <boardgamecategory>	
	var mechanisms: [String]?			// <boardgamemechanic>

	var minPlayers: Int?
	var maxPlayers: Int?
	var suggestedPlayers: Int?

	var minPlayingTime: Int?
	var maxPlayingTime: Int?
	var avgPlayingTime: Int?

	var minAge: Int?
	var numRatings: Int?
	var avgRating: Float?
	var complexity: Float?

	var donatedBy: String?
	var notes: String?
	var expands: String?
	var numCopies: Int
}
