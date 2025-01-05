import Fluent
import PostgresNIO
import Vapor

/// Methods for accessing the list of boardgames available in the onboard Games Library.
struct BoardgameController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/boardgame endpoints
		let boardgameRoutes = app.grouped("api", "v3", "boardgames")

		let flexAuthGroup = boardgameRoutes.flexRoutes(feature: .gameslist)
		flexAuthGroup.get("", use: getBoardgames)
		flexAuthGroup.get(boardgameIDParam, use: getBoardgame)
		flexAuthGroup.get("expansions", boardgameIDParam, use: getExpansions)
		flexAuthGroup.post("recommend", use: recommendGames)

		let tokenAuthGroup = boardgameRoutes.tokenRoutes(feature: .gameslist)
		tokenAuthGroup.post(boardgameIDParam, "favorite", use: addFavorite)
		tokenAuthGroup.post(boardgameIDParam, "favorite", "remove", use: removeFavorite)
		tokenAuthGroup.delete(boardgameIDParam, "favorite", use: removeFavorite)

		let adminAuthGroup = boardgameRoutes.tokenRoutes(feature: .gameslist, minAccess: .admin)
		adminAuthGroup.post("reload", use: reloadBoardGamesData)
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
	/// - Returns: `BoardgameResponseData`
	func getBoardgames(_ req: Request) async throws -> BoardgameResponseData {
		struct GameQueryOptions: Decodable {
			var search: String?
			var favorite: String?
			var start: Int?
			var limit: Int?
		}
		let user = req.auth.get(UserCacheData.self)
		let filters = try req.query.decode(GameQueryOptions.self)
		let start = filters.start ?? 0
		let limit = (filters.limit ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = Boardgame.query(on: req.db).with(\.$expansions)
		if let search = filters.search {
			query.fullTextFilter(\.$gameName, search)
		}
		if let fav = filters.favorite, fav.lowercased() == "true", let user = user {
			query.join(BoardgameFavorite.self, on: \Boardgame.$id == \BoardgameFavorite.$boardgame.$id)
				.filter(BoardgameFavorite.self, \.$user.$id == user.userID)
		}
		let totalGames = try await query.copy().count()
		let games = try await query.sort(\.$gameName, .ascending).range(start..<(start + limit)).all()
		let gamesArray = try await buildBoardgameData(for: user, games: games, on: req.db)
		return BoardgameResponseData(gameArray: gamesArray, paginator: Paginator(total: totalGames, start: start, limit: limit))
	}

	/// `GET /api/v3/boardgames/:boardgameID
	///
	/// Gets a single boardgame referenced by ID. Can be called while not logged in; if logged in favorite information is returned.
	///
	/// - Parameter boardgameID: in URL path
	/// - Returns: `BoardgameData`
	func getBoardgame(_ req: Request) async throws -> BoardgameData {
		let user = req.auth.get(UserCacheData.self)
		let game = try await Boardgame.findFromParameter(boardgameIDParam, on: req) { $0.with(\.$expansions) }
		let gamesArray = try await buildBoardgameData(for: user, games: [game], on: req.db)
		return gamesArray[0]
	}

	/// `GET /api/v3/boardgames/expansions/:boardgameID`
	///
	/// Given a boardgameID for either a base game or an expansion, returns the base game and all expansions.
	///
	/// - Parameter boardgameID: in URL path
	/// - Throws: 400 error if the event was not favorited.
	/// - Returns: An array of `BoardgameData`. First item is the base game, other items are expansions.
	func getExpansions(_ req: Request) async throws -> BoardgameResponseData {
		let user = req.auth.get(UserCacheData.self)
		let targetGame = try await Boardgame.findFromParameter(boardgameIDParam, on: req) { $0.with(\.$expansions) }
		let basegameID = try targetGame.$expands.id ?? targetGame.requireID()
		let games = try await Boardgame.query(on: req.db).with(\.$expansions)
			.group(.or) { group in
				group.filter(\.$id == basegameID).filter(\.$expands.$id == basegameID)
			}
			.all()
		// Oddly, the list for the games library has at least one expansion for a game not in the library.
		var baseGameFirst = games
		if let baseGameIndex = baseGameFirst.firstIndex(where: { $0.expands == nil }) {
			let baseGame = baseGameFirst.remove(at: baseGameIndex)
			baseGameFirst.insert(baseGame, at: 0)
		}
		let gamesArray = try await buildBoardgameData(for: user, games: games, on: req.db)
		return BoardgameResponseData(gameArray: gamesArray, paginator: Paginator(total: gamesArray.count, start: 0, limit: 50))
	}

	/// `POST /api/v3/boardgames/:boardgameID/favorite`
	///
	/// Add the specified `Boardgame` to the user's favorite boardgame list. Must be logged in
	///
	/// - Parameter boardgameID: in URL path
	/// - Returns: 201 Created on success; 200 OK if already favorited.
	func addFavorite(_ req: Request) async throws -> HTTPStatus {
		do {
			let user = try req.auth.require(UserCacheData.self)
			let boardgame = try await Boardgame.findFromParameter(boardgameIDParam, on: req)
			let fav = try BoardgameFavorite(user.userID, boardgame)
			try await fav.save(on: req.db)
			return .created
		}
		catch let sqlError as PostgresError {
			if sqlError.code == .uniqueViolation {
				return .ok
			}
			throw sqlError
		}
	}

	/// `POST /api/v3/boardgames/:boardgameID/favorite/remove`
	/// `DELETE /api/v3/boardgames/:boardgameID/favorite`
	///
	/// Remove the specified `Boardgame` from the user's boardgame favorite list.
	///
	/// - Parameter boardgameID: in URL path
	/// - Returns: 204 No Content on success; 200 OK if already not a favorite.
	func removeFavorite(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let boardgameID = req.parameters.get(boardgameIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Could not make UUID out of boardgame parameter")
		}
		guard
			let pivot = try await BoardgameFavorite.query(on: req.db).filter(\.$user.$id == user.userID)
				.filter(\.$boardgame.$id == boardgameID).first()
		else {
			return .ok
		}
		try await pivot.delete(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/boardgames/recommend`
	///
	/// Returns an array of boardgames in a structure designed to support pagination. The returned array of board games will be sorted
	/// in decreasing order of how closely each games matches the criteria in the `BoardgameRecommendationData` JSON content.
	/// Can be called while not logged in; if logged in favorite information is returned.
	///
	/// The recommendation algorithom filters out games that don't match the given criteria, i.e. if you ask for games for 6 players, games for 1-4 players
	/// will not be returned. Then, games are assigned a score taking each games' `suggestedNumPlayers`, `avgPlayingTime`, `avgRating`,
	/// and `gameComplexity` into account.
	///
	/// **URL Query Parameters**
	///	* `?start=INT` - Offset from start of results set
	/// * `?limit=INT` - the maximum number of games to retrieve: 1-200, default is 50.
	///
	/// - Returns: `BoardgameResponseData`
	func recommendGames(_ req: Request) async throws -> BoardgameResponseData {
		let user = req.auth.get(UserCacheData.self)
		let data = try ValidatingJSONDecoder().decode(BoardgameRecommendationData.self, fromBodyOf: req)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = Boardgame.query(on: req.db).with(\.$expansions).filter(\.$minPlayers <= data.numPlayers)
			.filter(\.$maxPlayers >= data.numPlayers)
			.filter(\.$avgPlayingTime <= data.timeToPlay)
		if data.maxAge != 0 {
			query.filter(\.$minAge <= data.maxAge)
		}
		if data.minAge != 0 {
			query.filter(\.$minAge >= data.minAge)
		}
		if (data.complexity != 0) {
			query.filter(\.$complexity >= Float(data.complexity))
		}
		let games = try await query.all()
		struct GameScore {
			let game: Boardgame
			let score: Float
		}
		// In raw SQL it'd be possible to do the sort as part of the query; but the ORM layer is too restrictive for complex
		// sorts like this, going down to the SQLKit layer is a pain, and it's not *that* bad to get all the games and sort locally.
		let orderedGames =
			games.compactMap { game -> GameScore? in
				guard game.canUseForRecommendations() else {
					return nil
				}
				var score: Float = 100.0 + game.getAvgRating()
				score -= Float(abs(data.numPlayers - game.getSuggestedPlayers())) * 2.0
				score -= Float(abs(data.timeToPlay - game.getAvgPlayingTime())) / 15.0
				if data.complexity != 0 {
					score -= abs(Float(data.complexity.clamped(to: 1...5)) - game.getComplexity()) * 1.5
				}
				return GameScore(game: game, score: score)
			}
			.sorted { $0.score > $1.score }

		let orderedPageOfGames = orderedGames.enumerated()
			.compactMap { (start...(start + limit)).contains($0.0) ? $0.1.game : nil }
		let gamesArray = try await buildBoardgameData(for: user, games: orderedPageOfGames, on: req.db)
		return BoardgameResponseData(gameArray: gamesArray, paginator: Paginator(total: orderedGames.count, start: start, limit: limit))
	}

	/// `POST /api/v3/boardgames/reload`
	///
	///  Reloads the board game data from the seed file. Removes all previous entries.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK` if the settings were updated.
	func reloadBoardGamesData(_ req: Request) async throws -> HTTPStatus {
		let migrator = ImportBoardgames()
		try await migrator.revert(on: req.db)
		try await migrator.prepare(on: req.db)
		return .ok
	}

	// MARK: - Utilities

	// Builds a BoardgameData array from an array of Bardgame Model objects. Mostly, this fn figures out whether the game
	// is a favorite of the given user.
	func buildBoardgameData(for user: UserCacheData?, games: [Boardgame], on db: Database) async throws
		-> [BoardgameData]
	{
		if let user = user {
			let gameIDs = games.compactMap { $0.id }
			let favorites = try await BoardgameFavorite.query(on: db).filter(\.$boardgame.$id ~~ gameIDs)
				.filter(\.$user.$id == user.userID).all()
			let favGameIDs = Set(favorites.compactMap { $0.$boardgame.id })
			return try games.map { try BoardgameData(game: $0, isFavorite: favGameIDs.contains($0.requireID())) }
		}
		else {
			return try games.map { try BoardgameData(game: $0) }
		}
	}
}
