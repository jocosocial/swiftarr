import Vapor
import Fluent


/// A `Migration` that imports the Games Catalog JSON file.
/// 
/// This file is  located in the `seeds/` subdirectory of the project.
struct ImportBoardgames: Migration {    
    /// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
    /// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
    /// a parser and populates the `Event` database with the `[Event]` array returned.
    ///
    /// - Requires: `schedule.ics` file in seeds subdirectory.
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
    	database.logger.info("Starting boardgame import")
        // get gamesFile
        let gamesFile: String
        do {
            if (try Environment.detect().name != "heroku") {
                gamesFile = "JoCoGamesCatalog"
            } else {
                gamesFile = "test-JoCoGamesCatalog"
            }
			guard let gamesFilePath = Bundle.module.url(forResource: gamesFile, withExtension: "json", subdirectory: "seeds"),
            		let data = FileManager.default.contents(atPath: gamesFilePath.path) else {
				fatalError("Could not read boardgames file.")
            }
            // parse to JsonGamesListGame array
            let gamesList = try JSONDecoder().decode([JsonGamesListGame].self, from: data)
            let futures: [EventLoopFuture<Void>] = gamesList.map { jsonGame in
            	let modelGame = Boardgame(jsonGame: jsonGame) 
            	return modelGame.save(on: database) 
			}
 			return futures.flatten(on: database.eventLoop).flatMap {
 				var expandFutures: [EventLoopFuture<Void>] = []
 				gamesList.forEach { jsonGame in
 					if let expands = jsonGame.expands {
 						let future: EventLoopFuture<Void> = Boardgame.query(on: database).filter(\.$gameName == expands)
 								.first().flatMap { basegame in
 							guard let basegame = basegame else {
 								database.logger.log(level: .notice, 
 										"Could not find basegame \"\(expands)\" to attach game expansion \"\(jsonGame.gameName)\"")
 								return database.eventLoop.future()
 							}
 							return Boardgame.query(on: database).filter(\.$gameName == jsonGame.gameName).first()
 									.throwingFlatMap { expansion in
								guard let expansion = expansion else {
 									database.logger.log(level: .notice, 
 											"Could not attaach game expansion \"\(jsonGame.gameName)\" to basegame \"\(expands)\"")
									return database.eventLoop.future()
								}
 								expansion.$expands.id = try basegame.requireID()
 								return expansion.save(on: database)
							}
 						}
 						expandFutures.append(future)
 					}
 				}
 				return expandFutures.flatten(on: database.eventLoop).transform(to: ())
 			}
        } catch let error {
            fatalError("Failed to import games list: \(error)")
        }
    }
    
    /// Required by `Migration` protocol.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return Boardgame.query(on: database).delete()
    }
}
 
/// Structure of the JSON in the JoCoGamesCatalog file.
/// 
/// Similar to the structure of the Model object (Boardgame) and the Data Transfer Sruct (BoardgameData), but this 
/// struct is specifically for migration.
struct JsonGamesListGame: Codable {
	var gameName: String
	var bggGameName: String?
	var yearPublished: String?
	var gameDescription: String?

	var minPlayers: Int?
	var maxPlayers: Int?

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
