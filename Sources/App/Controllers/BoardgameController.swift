import Vapor
import Fluent

/// Methods for accessing the list of boardgames available in the onboard Games Library.
struct BoardgameController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/boardgame endpoints
		let alertRoutes = app.grouped("api", "v3", "boardgames")
	
		let flexAuthGroup = addFlexAuthGroup(to: alertRoutes)
		flexAuthGroup.get("", use: getBoardgames)
		flexAuthGroup.get(boardgameIDParam, use: getBoardgame)
		flexAuthGroup.get("expansions", boardgameIDParam, use: getExpansions)
		
		
		let tokenAuthGroup = addTokenAuthGroup(to: alertRoutes)
		tokenAuthGroup.post(boardgameIDParam, "favorite", use: addFavorite)
		tokenAuthGroup.post(boardgameIDParam, "favorite", "remove", use: removeFavorite)
		tokenAuthGroup.delete(boardgameIDParam, "favorite", use: removeFavorite)
		
		// TODO: add/remove favorites
	}
	
	/// `GET /api/v3/boardgames`
	/// 
	/// Returns an array of boardgames in a structure designed to support pagination. Can be called while not logged in; 
	/// if logged in favorite information is returned.
	/// 
	/// **URL Query Parameters**
	/// * `?search=STRING` - Only show boardgames whose title contains the given string.
	/// * `?favorite=TRUE` - Only return boardgames that have been favorited by current user. 
	///	* `?start=INT` - Offset from start of results set
	/// * `?limit=INT` - the maximum number of games to retrieve: 1-200, default is 50. 
	/// 
    /// - Returns: <doc:BoardgameResponseData>
	func getBoardgames(_ req: Request) throws -> EventLoopFuture<BoardgameResponseData> {
		struct GameQueryOptions: Decodable {
			var search: String?
			var favorite: String?
			var start: Int?
			var limit: Int?
		}
		let user = req.auth.get(User.self)
 		let filters = try req.query.decode(GameQueryOptions.self)
        let start = filters.start ?? 0
        let limit = (filters.limit ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = Boardgame.query(on: req.db)
		if let search = filters.search {
			query.filter(\.$gameName, .custom("ILIKE"), "%\(search)%")
		}
		if let fav = filters.favorite, fav.lowercased() == "true", let user = user {
			try query.join(BoardgameFavorite.self, on: \Boardgame.$id == \BoardgameFavorite.$boardgame.$id)
					.filter(BoardgameFavorite.self, \.$user.$id == user.requireID())
		}
		return query.count().flatMap { totalGames in
			return query.sort(\.$gameName, .ascending).range(start..<(start + limit)).all().throwingFlatMap { games in
				return try buildBoardgameData(for: user, games: games, on: req.db).map { gamesArray in
					return BoardgameResponseData(totalGames: totalGames, start: start, limit: limit, gameArray: gamesArray)
				}
			}
		}
	}

	/// `GET /api/v3/boardgames/:boardgameID
	/// 
	/// Gets a single boardgame referenced by ID. Can be called while not logged in; if logged in favorite information is returned.
	/// 
    /// - Parameter boardgameID: in URL path
    /// - Returns: <doc:BoardgameData>
	func getBoardgame(_ req: Request) throws -> EventLoopFuture<BoardgameData> {
		let user = req.auth.get(User.self)
		return Boardgame.findFromParameter(boardgameIDParam, on: req).throwingFlatMap { game in
			return try buildBoardgameData(for: user, games: [game], on: req.db).map { gamesArray in
				return gamesArray[0]
			}
		}
	}

	/// `GET /api/v3/boardgames/expansions/:boardgameID`
	/// 
	/// Given a boardgameID for either a base game or an expansion, returns the base game and all expansions.
	/// 
    /// - Parameter boardgameID: in URL path
    /// - Throws: 400 error if the event was not favorited.
    /// - Returns: An array of <doc:BoardgameData>. First item is the base game, other items are expansions.
	func getExpansions(_ req: Request) throws -> EventLoopFuture<[BoardgameData]> {
		let user = req.auth.get(User.self)
		return Boardgame.findFromParameter(boardgameIDParam, on: req).throwingFlatMap { targetGame in
			let basegameID = try targetGame.$expands.id ?? targetGame.requireID()
			return Boardgame.query(on: req.db).group(.or) { group in
					group.filter(\.$id == basegameID).filter(\.$expands.$id == basegameID) }.all().throwingFlatMap { games in
				// Oddly, the list for the games library has at least one expansion for a game not in the library.
				var baseGameFirst = games
				if let baseGameIndex = baseGameFirst.firstIndex(where: { $0.expands == nil }) {
					let baseGame = baseGameFirst.remove(at: baseGameIndex)
					baseGameFirst.insert(baseGame, at: 0)
				}
				return try buildBoardgameData(for: user, games: baseGameFirst, on: req.db).map { gamesArray in
					return gamesArray
				}
			}
		}
	}
	
    /// `POST /api/v3/boardgames/:boardgameID/favorite`
    ///
    /// Add the specified `Boardgame` to the user's favorite boardgame list. Must be logged in
    ///
    /// - Parameter boardgameID: in URL path
    /// - Returns: 201 Created on success.
    func addFavorite(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        return Boardgame.findFromParameter(boardgameIDParam, on: req).throwingFlatMap { boardgame in
        	user.$favoriteBoardgames.attach(boardgame, method: .ifNotExists, on: req.db).transform(to: .created)
		}
    }
    
    /// `POST /api/v3/boardgames/:boardgameID/favorite/remove`
    /// `DELETE /api/v3/boardgames/:boardgameID/favorite`
    ///
    /// Remove the specified `Boardgame` from the user's boardgame favorite list.
    ///
    /// - Parameter boardgameID: in URL path
    /// - Returns: 204 No Content on success.
    func removeFavorite(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard let boardgameID = req.parameters.get(boardgameIDParam.paramString, as: UUID.self) else {
        	throw Abort(.badRequest, reason: "Could not make UUID out of boardgame parameter")
        }
        return user.$favoriteBoardgames.$pivots.query(on: req.db).filter(\.$boardgame.$id == boardgameID).first().throwingFlatMap { pivot in
        	guard let pivot = pivot else {
        		throw Abort(.notFound, reason: "Cannot remove favorite: User has not favorited this boardgame.")
        	}
        	return pivot.delete(on: req.db).transform(to: .noContent)
        }
    }
    
// MARK: - Utilities

	// Builds a BoardgameData array from an array of Bardgame Model objects. Mostly, this fn figures out whether the game
	// is a favorite of the given user.
	func buildBoardgameData(for user: User?, games: [Boardgame], on db: Database) throws -> EventLoopFuture<[BoardgameData]> {
		if let user = user {
			let gameIDs = games.compactMap { $0.id }
			return try BoardgameFavorite.query(on: db).filter(\.$boardgame.$id ~~ gameIDs)
					.filter(\.$user.$id == user.requireID()).all().flatMapThrowing { favorites in
				let favGameIDs = Set(favorites.compactMap { $0.$boardgame.id })
				return try games.map { try BoardgameData(game: $0, isFavorite: favGameIDs.contains($0.requireID())) }
			}
		}
		else {
			let result = try games.map { try BoardgameData(game: $0) }
			return db.eventLoop.future(result)
		}
	}
}
